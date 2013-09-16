//
//  CBLQuery.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/18/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "CouchbaseLitePrivate.h"
#import "CBLView+Internal.h"
#import "CBLDatabase.h"
#import "CBL_Server.h"
#import "MYBlockUtils.h"


// Querying utilities for CBLDatabase. Defined down below.
@interface CBLDatabase (Views)
- (NSArray*) queryViewNamed: (NSString*)viewName
                    options: (CBLQueryOptions)options
               lastSequence: (SequenceNumber*)outLastSequence
                     status: (CBLStatus*)outStatus;
@end


@interface CBLQueryEnumerator ()
- (instancetype) initWithDatabase: (CBLDatabase*)db
                             rows: (NSArray*)rows
                   sequenceNumber: (SequenceNumber)sequenceNumber;
- (instancetype) initWithDatabase: (CBLDatabase*)database
                           status: (CBLStatus)status;
@property (nonatomic, readonly) CBLStatus status;
@end


@interface CBLQueryRow ()
@property (nonatomic) CBLDatabase* database;
@end


@implementation CBLQuery
{
    CBLDatabase* _database;
    CBLView* _view;              // nil for _all_docs query
    BOOL _temporaryView;
    NSUInteger _limit, _skip;
    id _startKey, _endKey;
    NSString* _startKeyDocID;
    NSString* _endKeyDocID;
    CBLStaleness _stale;
    BOOL _descending, _prefetch, _mapOnly, _includeDeleted;
    NSArray *_keys;
    NSUInteger _groupLevel;
    SInt64 _lastSequence;       // The db's lastSequence the last time -rows was called
    @protected
    CBLStatus _status;          // Result status of last query (.error property derived from this)
}


// A nil view refers to 'all documents'
- (instancetype) initWithDatabase: (CBLDatabase*)database view: (CBLView*)view {
    self = [super init];
    if (self) {
        _database = database;
        _view = view;
        _limit = kDefaultCBLQueryOptions.limit;  // this has a nonzero default (UINT_MAX)
        _mapOnly = (view.reduceBlock == nil);
    }
    return self;
}


- (instancetype) initWithDatabase: (CBLDatabase*)database mapBlock: (CBLMapBlock)mapBlock {
    CBLView* view = [database makeAnonymousView];
    if (self = [self initWithDatabase: database view: view]) {
        _temporaryView = YES;
        [view setMapBlock: mapBlock reduceBlock: nil version: @""];
    }
    return self;
}


- (instancetype) initWithQuery: (CBLQuery*)query {
    self = [self initWithDatabase: query->_database view: query->_view];
    if (self) {
        _limit = query.limit;
        _skip = query.skip;
        self.startKey = query.startKey;
        self.endKey = query.endKey;
        _descending = query.descending;
        _prefetch = query.prefetch;
        self.keys = query.keys;
        _groupLevel = query.groupLevel;
        _mapOnly = query.mapOnly;
        self.startKeyDocID = query.startKeyDocID;
        self.endKeyDocID = query.endKeyDocID;
        _stale = query.stale;
        
    }
    return self;
}


- (void) dealloc
{
    if (_temporaryView)
        [_view deleteView];
}


@synthesize  limit=_limit, skip=_skip, descending=_descending, startKey=_startKey, endKey=_endKey,
            prefetch=_prefetch, keys=_keys, groupLevel=_groupLevel, startKeyDocID=_startKeyDocID,
            endKeyDocID=_endKeyDocID, stale=_stale, mapOnly=_mapOnly,
            database=_database, includeDeleted=_includeDeleted;


- (CBLLiveQuery*) asLiveQuery {
    return [[CBLLiveQuery alloc] initWithQuery: self];
}

- (CBLQueryOptions) queryOptions {
    return (CBLQueryOptions) {
        .startKey = _startKey,
        .endKey = _endKey,
        .keys = _keys,
        .skip = (unsigned)_skip,
        .limit = (unsigned)_limit,
        .reduce = !_mapOnly,
        .reduceSpecified = YES,
        .groupLevel = (unsigned)_groupLevel,
        .descending = _descending,
        .includeDocs = _prefetch,
        .updateSeq = YES,
        .inclusiveEnd = YES,
        .includeDeletedDocs = _includeDeleted,
        .stale = _stale
    };
}


- (CBLQueryEnumerator*) rows {
    NSArray* rows = [_database queryViewNamed: _view.name
                                      options: self.queryOptions
                                 lastSequence: &_lastSequence
                                       status: &_status];
    return [[CBLQueryEnumerator alloc] initWithDatabase: _database
                                                   rows: rows
                                         sequenceNumber: _lastSequence];
}


- (void) runAsync: (void (^)(CBLQueryEnumerator*))onComplete {
    LogTo(Query, @"%@: Async query %@/%@...", self, _database.name, (_view.name ?: @"_all_docs"));
    NSThread *callingThread = [NSThread currentThread];
    NSString* viewName = _view.name;
    CBLQueryOptions options = self.queryOptions;
    
    [_database.manager asyncTellDatabaseNamed: _database.name to: ^(CBLDatabase *bgdb) {
        // On the background server thread, run the query:
        CBLStatus status;
        SequenceNumber lastSequence;
        NSArray* rows = [bgdb queryViewNamed: viewName
                                     options: options
                                lastSequence: &lastSequence
                                      status: &status];
        MYOnThread(callingThread, ^{
            // Back on original thread, call the onComplete block:
            LogTo(Query, @"%@: ...async query finished (%u rows)", self, (unsigned)rows.count);
            if (CBLStatusIsError(status)) {
                onComplete([[CBLQueryEnumerator alloc] initWithDatabase: _database
                                                                 status: status]);
            } else {
                onComplete([[CBLQueryEnumerator alloc] initWithDatabase: _database
                                                                   rows: rows
                                                         sequenceNumber: lastSequence]);
            }
        });
    }];
}


- (NSError*) error {
    return CBLStatusIsError(_status) ? CBLStatusToNSError(_status, nil) : nil;
}


- (CBLQueryEnumerator*) rowsIfChanged {
    if (_database.lastSequenceNumber == _lastSequence)
        return nil;
    return self.rows;
}


@end




@implementation CBLLiveQuery
{
    BOOL _observing, _willUpdate;
    CBLQueryEnumerator* _rows;
}


- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}


- (void) start {
    if (!_observing) {
        _observing = YES;
        [[NSNotificationCenter defaultCenter] addObserver: self 
                                                 selector: @selector(databaseChanged)
                                                     name: kCBLDatabaseChangeNotification 
                                                   object: self.database];
        [self update];
    }
}


- (void) stop {
    if (_observing) {
        _observing = NO;
        [[NSNotificationCenter defaultCenter] removeObserver: self
                                                        name: kCBLDatabaseChangeNotification
                                                      object: self.database];
    }
    if (_willUpdate) {
        _willUpdate = NO;
        [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(update)
                                                   object: nil];
    }
}


- (CBLQueryEnumerator*) rows {
    [self start];
    // Have to return a copy because the enumeration has to start at item #0 every time
    return [_rows copy];
}


- (void) addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath
             options:(NSKeyValueObservingOptions)options context:(void *)context
{
    [self start];
    [super addObserver: observer forKeyPath: keyPath options: options context: context];
}


- (void) setRows:(CBLQueryEnumerator *)rows {
    _rows = rows;
}


- (void) databaseChanged {
    if (!_willUpdate) {
        _willUpdate = YES;
        [self performSelector: @selector(update) withObject: nil afterDelay: 0.0];
    }
}


- (void) update {
    _willUpdate = NO;
    [self runAsync: ^(CBLQueryEnumerator *rows) {
        _status = rows.status;
        if (CBLStatusIsError(_status)) {
            Warn(@"%@: Error updating rows: %d", self, _status);
        } else if(![rows isEqual: _rows]) {
            LogTo(Query, @"%@: ...Rows changed! (now %lu)", self, (unsigned long)rows.count);
            self.rows = rows;   // Triggers KVO notification
        }
    }];
}


- (BOOL) waitForRows {
    [self start];
    while (!_rows && !CBLStatusIsError(_status)) {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                      beforeDate: [NSDate distantFuture]]) {
            Warn(@"CBLQuery waitForRows: Runloop stopped");
            break;
        }
    }
    return _rows != nil;
}


@end




@implementation CBLQueryEnumerator
{
    CBLDatabase* _database;
    NSArray* _rows;
    NSUInteger _nextRow;
    UInt64 _sequenceNumber;
    CBLStatus _status;
}


@synthesize sequenceNumber=_sequenceNumber;


- (instancetype) initWithDatabase: (CBLDatabase*)database
                             rows: (NSArray*)rows
                   sequenceNumber: (SequenceNumber)sequenceNumber
{
    NSParameterAssert(database);
    self = [super init];
    if (self ) {
        if (!rows)
            return nil;
        _database = database;
        _rows = [rows copy];
        _sequenceNumber = sequenceNumber;
        _status = kCBLStatusOK;

        // Fill in the rows' database reference now
        for (CBLQueryRow* row in _rows)
            row.database = database;
    }
    return self;
}

- (instancetype) initWithDatabase: (CBLDatabase*)database
                           status: (CBLStatus)status
{
    NSParameterAssert(database);
    self = [super init];
    if (self ) {
        _status = status;
    }
    return self;
}


- (id) copyWithZone: (NSZone*)zone {
    return [[[self class] alloc] initWithDatabase: _database
                                             rows: _rows
                                   sequenceNumber: _sequenceNumber];
}


- (BOOL) isEqual:(id)object {
    if (object == self)
        return YES;
    if (![object isKindOfClass: [CBLQueryEnumerator class]])
        return NO;
    CBLQueryEnumerator* otherEnum = object;
    return [otherEnum->_rows isEqual: _rows];
}


- (NSUInteger) count {
    return _rows.count;
}


- (CBLQueryRow*) rowAtIndex: (NSUInteger)index {
    return _rows[index];
}


- (CBLQueryRow*) nextRow {
    if (_nextRow >= _rows.count)
        return nil;
    return [self rowAtIndex:_nextRow++];
}


- (id) nextObject {
    return [self nextRow];
}


@synthesize status=_status;


- (NSError*) error {
    return CBLStatusIsError(_status) ? CBLStatusToNSError(_status, nil) : nil;
}


@end




static id fromJSON( NSData* json ) {
    if (!json)
        return nil;
    return [CBLJSON JSONObjectWithData: json
                               options: CBLJSONReadingAllowFragments
                                 error: NULL];
}




@implementation CBLQueryRow
{
    CBLDatabase* _database;
    id _key, _value;            // Usually starts as JSON NSData; parsed on demand
    id _geo;                    // Constructed from the result data, never parsed.
    __weak id _parsedKey, _parsedValue;
    UInt64 _sequence;
    NSString* _sourceDocID;
    NSDictionary* _documentProperties;
}


@synthesize documentProperties=_documentProperties, sourceDocumentID=_sourceDocID,
            database=_database, localSequence=_sequence;


- (instancetype) initWithDocID: (NSString*)docID
                      sequence: (SequenceNumber)sequence
                           key: (id)key
                         value: (id)value
                         geo: (id)geo
                 docProperties: (NSDictionary*)docProperties
{
    self = [super init];
    if (self) {
        // Don't initialize _database yet. I might be instantiated on a background thread (if the
        // query is async) which has a different CBLDatabase instance than the original caller.
        // Instead, the database property will be filled in when I'm added to a CBLQueryEnumerator.
        _sourceDocID = [docID copy];
        _sequence = sequence;
        _key = [key copy];
        _value = [value copy];
        _geo = [geo copy];
        _documentProperties = [docProperties copy];
    }
    return self;
}


- (BOOL) isEqual:(id)object {
    if (object == self)
        return YES;
    if (![object isKindOfClass: [CBLQueryRow class]])
        return NO;
    CBLQueryRow* other = object;
    return _database == other->_database
        && $equal(_key, other->_key) && $equal(_value, other->_value)
        && $equal(_geo, other->_geo)
        && $equal(_sourceDocID, other->_sourceDocID)
        && $equal(_documentProperties, other->_documentProperties);
}


- (id) key {
    id key = _parsedKey;
    if (!key) {
        key = _key;
        if ([key isKindOfClass: [NSData class]]) {  // _key may start out as unparsed JSON data
            key = fromJSON(_key);
            _parsedKey = key;
        }
    }
    return key;
}

- (id) value {
    id value = _parsedValue;
    if (!value) {
        value = _value;
        if ([value isKindOfClass: [NSData class]]) {   // _value may start out as unparsed JSON data
            value = fromJSON(_value);
            _parsedValue = value;
        }
    }
    return value;
}

- (id) geo {
    return _geo;
}


- (NSString*) documentID {
    // _documentProperties may have been 'redirected' from a different document
    return _documentProperties[@"_id"] ?: _sourceDocID;
}


- (NSString*) documentRevision {
    // Get the revision id from either the embedded document contents,
    // or the '_rev' or 'rev' value key:
    NSString* rev = _documentProperties[@"_rev"];
    if (!rev) {
        id value = self.value;
        if ([value isKindOfClass: [NSDictionary class]]) {      // $castIf would log a warning
            rev = value[@"_rev"];
            if (!rev)
                rev = value[@"rev"];
        }
    }
    
    if (![rev isKindOfClass: [NSString class]])                 // $castIf would log a warning
        rev = nil;
    return rev;
}


- (id) keyAtIndex: (NSUInteger)index {
    id key = self.key;
    if ([key isKindOfClass:[NSArray class]])
        return (index < [key count]) ? key[index] : nil;
    else
        return (index == 0) ? key : nil;
}

- (id) key0                         {return [self keyAtIndex: 0];}
- (id) key1                         {return [self keyAtIndex: 1];}
- (id) key2                         {return [self keyAtIndex: 2];}
- (id) key3                         {return [self keyAtIndex: 3];}


- (CBLDocument*) document {
    NSString* docID = self.documentID;
    if (!docID)
        return nil;
    CBLDocument* doc = [_database documentWithID: docID];
    [doc loadCurrentRevisionFrom: self];
    return doc;
}


// This is used by the router
- (NSDictionary*) asJSONDictionary {
    if (_value || _sourceDocID) {
        if (_geo)
            return $dict({@"key", self.key}, {@"value", self.value}, {@"id", _sourceDocID}, {@"geo", self.geo},
                         {@"doc", _documentProperties});
        return $dict({@"key", self.key}, {@"value", self.value}, {@"id", _sourceDocID},
                     {@"doc", _documentProperties});
    }
    else
        return $dict({@"key", self.key}, {@"error", @"not_found"});

}


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[key=%@; value=%@; id=%@]",
            [self class],
            [CBLJSON stringWithJSONObject: self.key options: CBLJSONWritingAllowFragments error: nil],
            [CBLJSON stringWithJSONObject: self.value options: CBLJSONWritingAllowFragments error: nil],
            self.documentID];
}


@end




@implementation CBLDatabase (Views)

- (NSArray*) queryViewNamed: (NSString*)viewName
                    options: (CBLQueryOptions)options
               lastSequence: (SequenceNumber*)outLastSequence
                     status: (CBLStatus*)outStatus
{
    CBLStatus status;
    NSArray* rows = nil;
    SequenceNumber lastSequence = 0;
    do {
        if (viewName) {
            CBLView* view = [self viewNamed: viewName];
            if (!view) {
                status = kCBLStatusNotFound;
                break;
            }
            lastSequence = view.lastSequenceIndexed;
            if (options.stale == kCBLStaleNever || lastSequence <= 0) {
                status = [view updateIndex];
                if (CBLStatusIsError(status)) {
                    Warn(@"Failed to update view index: %d", status);
                    break;
                }
                lastSequence = view.lastSequenceIndexed;
            } else if (options.stale == kCBLStaleUpdateAfter &&
                       lastSequence < self.lastSequenceNumber) {
                [view performSelector: @selector(updateIndex) withObject: nil afterDelay: 0];
            }
            rows = [view _queryWithOptions: &options status: &status];
        } else {
            // nil view means query _all_docs
            rows = [self getAllDocs: &options];
            status = rows ? kCBLStatusOK :self.lastDbError; //FIX: getALlDocs should return status
            lastSequence = self.lastSequenceNumber;
        }
    } while(false); // just to allow 'break' within the block

    if (outLastSequence)
        *outLastSequence = lastSequence;
    if (outStatus)
        *outStatus = status;
    return rows;
}


@end
