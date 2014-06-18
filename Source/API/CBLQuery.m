//
//  CBLQuery.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/18/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CouchbaseLitePrivate.h"
#import "CBLQuery+FullTextSearch.h"
#import "CBLView+Internal.h"
#import "CBLDatabase.h"
#import "CBL_Server.h"
#import "CBLMisc.h"
#import "MYBlockUtils.h"


// Querying utilities for CBLDatabase. Defined down below.
@interface CBLDatabase (Views)
- (CBLQueryIteratorBlock) queryViewNamed: (NSString*)viewName
                                 options: (CBLQueryOptions*)options
                          ifChangedSince: (SequenceNumber)ifChangedSince
                            lastSequence: (SequenceNumber*)outLastSequence
                                  status: (CBLStatus*)outStatus;
@end


@interface CBLQueryEnumerator ()
- (instancetype) initWithDatabase: (CBLDatabase*)database
                             view: (CBLView*)view
                   sequenceNumber: (SequenceNumber)sequenceNumber
                         iterator: (CBLQueryIteratorBlock)iterator;
- (instancetype) initWithDatabase: (CBLDatabase*)database
                             view: (CBLView*)view
                   sequenceNumber: (SequenceNumber)sequenceNumber
                             rows: (NSArray*)rows;
@end


@interface CBLQueryRow ()
@property (readwrite, nonatomic) CBLDatabase* database;
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
    CBLIndexUpdateMode _indexUpdateMode;
    BOOL _descending, _prefetch, _mapOnly;
    CBLAllDocsMode _allDocsMode;
    NSArray *_keys;
    NSUInteger _groupLevel;
    SInt64 _lastSequence;       // The db's lastSequence the last time -rows was called
}


// A nil view refers to 'all documents'
- (instancetype) initWithDatabase: (CBLDatabase*)database view: (CBLView*)view {
    self = [super init];
    if (self) {
        _database = database;
        _view = view;
        _limit = UINT_MAX;
        _fullTextRanking = YES;
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
        if (query->_isGeoQuery) {
            _isGeoQuery = YES;
            _boundingBox = query->_boundingBox;
        }
        _groupLevel = query.groupLevel;
        _mapOnly = query.mapOnly;
        self.startKeyDocID = query.startKeyDocID;
        self.endKeyDocID = query.endKeyDocID;
        _indexUpdateMode = query.indexUpdateMode;
        _fullTextQuery = query.fullTextQuery;
        _fullTextRanking = query.fullTextRanking;
        _fullTextSnippets = query.fullTextSnippets;
        _allDocsMode = query.allDocsMode;
        
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
            endKeyDocID=_endKeyDocID, indexUpdateMode=_indexUpdateMode, mapOnly=_mapOnly,
            database=_database, allDocsMode=_allDocsMode;

- (NSString*) description {
    NSMutableString *desc = [NSMutableString stringWithFormat: @"%@[%@",
                             [self class], (_view ? _view.name : @"AllDocs")];
#if DEBUG
    if (_startKey)
        [desc appendFormat: @", start=%@", CBLJSONString(_startKey)];
    if (_endKey)
        [desc appendFormat: @", end=%@", CBLJSONString(_endKey)];
    if (_keys)
        [desc appendFormat: @", keys=[..%lu keys...]", (unsigned long)_keys.count];
    if (_skip)
        [desc appendFormat: @", skip=%lu", (unsigned long)_skip];
    if (_descending)
        [desc appendFormat: @", descending"];
    if (_limit != UINT_MAX)
        [desc appendFormat: @", limit=%lu", (unsigned long)_limit];
    if (_groupLevel)
        [desc appendFormat: @", groupLevel=%lu", (unsigned long)_groupLevel];
    if (_mapOnly)
        [desc appendFormat: @", mapOnly=YES"];
    if (_allDocsMode)
        [desc appendFormat: @", allDocsMode=%d", _allDocsMode];
#endif
    [desc appendString: @"]"];
    return desc;
}



- (CBLLiveQuery*) asLiveQuery {
    return [[CBLLiveQuery alloc] initWithQuery: self];
}

- (CBLQueryOptions*) queryOptions {
    CBLQueryOptions* options = [CBLQueryOptions new];
    options.startKey = _startKey,
    options.endKey = _endKey,
    options.startKeyDocID = _startKeyDocID,
    options.endKeyDocID = _endKeyDocID,
    options.keys = _keys,
    options.fullTextQuery = _fullTextQuery,
    options->fullTextSnippets = _fullTextSnippets,
    options->fullTextRanking = _fullTextRanking,
    options->bbox = (_isGeoQuery ? &_boundingBox : NULL),
    options->skip = (unsigned)_skip,
    options->limit = (unsigned)_limit,
    options->reduce = !_mapOnly,
    options->reduceSpecified = YES,
    options->groupLevel = (unsigned)_groupLevel,
    options->descending = _descending,
    options->includeDocs = _prefetch,
    options->updateSeq = YES,
    options->inclusiveEnd = YES,
    options->allDocsMode = _allDocsMode,
    options->indexUpdateMode = _indexUpdateMode;
    return options;
}


- (CBLQueryEnumerator*) run: (NSError**)outError {
    CBLStatus status;
    LogTo(Query, @"%@: running...", self);
    CBLQueryIteratorBlock iterator = [_database queryViewNamed: _view.name
                                                       options: self.queryOptions
                                                ifChangedSince: 0
                                                  lastSequence: &_lastSequence
                                                        status: &status];
    if (!iterator) {
        if (outError)
            *outError = CBLStatusToNSError(status, nil);
        return nil;
    }
    return [[CBLQueryEnumerator alloc] initWithDatabase: _database
                                                   view: _view
                                         sequenceNumber: _lastSequence
                                               iterator: iterator];
}


- (void) runAsync: (void (^)(CBLQueryEnumerator*, NSError*))onComplete {
    [self runAsyncIfChangedSince: 0 onComplete: onComplete];
}

- (void) runAsyncIfChangedSince: (SequenceNumber)ifChangedSince
                     onComplete: (void (^)(CBLQueryEnumerator*, NSError*))onComplete
{
    LogTo(Query, @"%@: Async query...", self);
    NSString* viewName = _view.name;
    CBLQueryOptions *options = self.queryOptions;
    
    [_database.manager backgroundTellDatabaseNamed: _database.name to: ^(CBLDatabase *bgdb) {
        // On the background server thread, run the query:
        CBLStatus status;
        SequenceNumber lastSequence;
        CBLQueryIteratorBlock iterator = [bgdb queryViewNamed: viewName
                                                      options: options
                                               ifChangedSince: ifChangedSince
                                                 lastSequence: &lastSequence
                                                       status: &status];
        NSMutableArray* rows = nil;
        if (iterator) {
            // The iterator came from a background thread, so we shouldn't call it on the
            // original thread. Instead, copy all the rows into an array:
            rows = $marray();
            while (true) {
                CBLQueryRow* row = iterator();
                if (!row)
                    break;
                [rows addObject: row];
            }
        }

        [_database.manager doAsync: ^{
            // Back on original thread, call the onComplete block:
            LogTo(Query, @"%@: ...async query finished (%u rows, status %d)",
                  self, (unsigned)rows.count, status);
            NSError* error = nil;
            CBLQueryEnumerator* e = nil;
            if (rows) {
                for (CBLQueryRow* row in rows)
                    row.database = _database;
                e = [[CBLQueryEnumerator alloc] initWithDatabase: _database
                                                            view: _view
                                                  sequenceNumber: lastSequence
                                                            rows: rows];
            } else if (CBLStatusIsError(status)) {
                error = CBLStatusToNSError(status, nil);
            }
            onComplete(e, error);
        }];
    }];
}


@end




@implementation CBLLiveQuery
{
    BOOL _observing, _willUpdate;
    CBLQueryEnumerator* _rows;
}


@synthesize lastError=_lastError;


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


- (CBLQueryEnumerator*) run: (NSError**)outError {
    if ([self waitForRows]) {
        return self.rows;
    } else {
        if (outError)
            *outError = self.lastError;
        return nil;
    }
}


- (CBLQueryEnumerator*) rows {
    [self start];
    // Have to return a copy because the enumeration has to start at item #0 every time
    return [_rows copy];
}


- (void) setRows:(CBLQueryEnumerator *)rows {
    _rows = rows;
}


- (void) addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath
             options:(NSKeyValueObservingOptions)options context:(void *)context
{
    [self start];
    [super addObserver: observer forKeyPath: keyPath options: options context: context];
}


- (void) databaseChanged {
    if (!_willUpdate) {
        _willUpdate = YES;
        [self.database doAsync: ^{
            [self update];
        }];
    }
}


- (void) update {
    _willUpdate = NO;
    [self runAsyncIfChangedSince: _rows.sequenceNumber
                      onComplete: ^(CBLQueryEnumerator *rows, NSError* error) {
        _lastError = error;
        if (error) {
            Warn(@"%@: Error updating rows: %@", self, error);
        } else if(rows && ![rows isEqual: _rows]) {
            LogTo(Query, @"%@: ...Rows changed! (now %lu)", self, (unsigned long)rows.count);
            self.rows = rows;   // Triggers KVO notification
        }
    }];
}


- (BOOL) waitForRows {
    [self start];
    while (!_rows && !_lastError) {
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
    CBLView* _view; // nil if this is an all-docs query
    NSArray* _rows;
    NSUInteger _nextRow;
    UInt64 _sequenceNumber;
    CBLQueryIteratorBlock _iterator;
    BOOL _usingIterator;
}


@synthesize sequenceNumber=_sequenceNumber;


- (instancetype) initWithDatabase: (CBLDatabase*)database
                             view: (CBLView*)view
                   sequenceNumber: (SequenceNumber)sequenceNumber
                         iterator: (CBLQueryIteratorBlock)iterator
{
    NSParameterAssert(database);
    self = [super init];
    if (self ) {
        _database = database;
        _view = view;
        _sequenceNumber = sequenceNumber;
        _iterator = iterator;
    }
    return self;
}

- (instancetype) initWithDatabase: (CBLDatabase*)database
                             view: (CBLView*)view
                   sequenceNumber: (SequenceNumber)sequenceNumber
                             rows: (NSArray*)rows
{
    NSParameterAssert(database);
    self = [super init];
    if (self ) {
        _database = database;
        _view = view;
        _sequenceNumber = sequenceNumber;
        _rows = rows;
    }
    return self;
}

- (id) copyWithZone: (NSZone*)zone {
    return [[[self class] alloc] initWithDatabase: _database
                                             view: _view
                                   sequenceNumber: _sequenceNumber
                                             rows: self.allObjects];
}


- (BOOL) isEqual:(id)object {
    if (object == self)
        return YES;
    if (![object isKindOfClass: [CBLQueryEnumerator class]])
        return NO;
    return [[object allObjects] isEqual: self.allObjects];
}


- (BOOL) stale {
    // Check whether the result-set's sequence number is up to date with either the db or the view:
    SequenceNumber dbSequence = _database.lastSequenceNumber;
    if ((SequenceNumber)_sequenceNumber == dbSequence)
        return NO;
    if (_view && _view.lastSequenceIndexed == dbSequence
              && _view.lastSequenceChangedAt == (SequenceNumber)_sequenceNumber)
        return NO;
    return YES;
}


- (CBLQueryRow*) nextRow {
    if (_rows) {
        // Using array:
        if (_nextRow >= _rows.count)
            return nil;
        return [self rowAtIndex:_nextRow++];

    } else {
        // Using iterator:
        _usingIterator = YES;
        if (!_iterator)
            return nil;
        CBLQueryRow* row = _iterator();
        if (row)
            row.database = _database;
        else
            _iterator = nil;
        return row;
    }
}


- (id) nextObject {
    return [self nextRow];
}


- (NSArray*) allObjects {
    if (!_rows) {
        Assert(!_usingIterator, @"Enumerator is not at start");
        _rows = [super allObjects];
        _usingIterator = NO;
    }
    return _rows;
}


- (NSUInteger) count {
    return self.allObjects.count;
}


- (CBLQueryRow*) rowAtIndex: (NSUInteger)index {
    return self.allObjects[index];
}


- (void) reset {
    Assert(!_usingIterator, @"Enumerator is not at start");
    _nextRow = 0;
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
    id _key, _value;            // Usually starts as JSON NSData; parsed on demand
    __weak id _parsedKey, _parsedValue;
    UInt64 _sequence;
    NSString* _sourceDocID;
    NSDictionary* _documentProperties;
    @protected
    CBLDatabase* _database;
}


@synthesize documentProperties=_documentProperties, sourceDocumentID=_sourceDocID,
            database=_database, sequenceNumber=_sequence;


- (instancetype) initWithDocID: (NSString*)docID
                      sequence: (SequenceNumber)sequence
                           key: (id)key
                         value: (id)value
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
        _documentProperties = [docProperties copy];
    }
    return self;
}


// This is used implicitly by -[CBLLiveQuery update] to decide whether the query result has changed
// enough to notify the client. So it's important that it not give false positives, else the app
// won't get notified of changes.
- (BOOL) isEqual:(id)object {
    if (object == self)
        return YES;
    if (![object isKindOfClass: [CBLQueryRow class]])
        return NO;
    CBLQueryRow* other = object;
    if (_database == other->_database
            && $equal(_key, other->_key)
            && $equal(_sourceDocID, other->_sourceDocID)
            && $equal(_documentProperties, other->_documentProperties)) {
        // If values were emitted, compare them. Otherwise we have nothing to go on so check
        // if _anything_ about the doc has changed (i.e. the sequences are different.)
        if (_value || other->_value)
            return  $equal(_value, other->_value);
        else
            return _sequence == other->_sequence;
    }
    return NO;
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


- (NSString*) documentID {
    // _documentProperties may have been 'redirected' from a different document
    return _documentProperties.cbl_id ?: _sourceDocID;
}


- (NSString*) documentRevisionID {
    // Get the revision id from either the embedded document contents,
    // or the '_rev' or 'rev' value key:
    NSString* rev = _documentProperties.cbl_rev;
    if (!rev) {
        NSDictionary* value = $castIf(NSDictionary, self.value);
        rev = value.cbl_rev;
        if (value && !rev)
            rev = value[@"rev"];
    }
    return $castIf(NSString, rev);
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


- (NSArray*) conflictingRevisions {
    // The "_conflicts" value property is added when the query's allDocsMode==kCBLShowConflicts;
    // see -[CBLDatabase getAllDocs:] in CBLDatabase+Internal.m.
    CBLDocument* doc = [_database documentWithID: self.sourceDocumentID];
    NSDictionary* value = $castIf(NSDictionary, self.value);
    NSArray* conflicts = $castIf(NSArray, value[@"_conflicts"]);
    return [conflicts my_map: ^id(id obj) {
        NSString* revID = $castIf(NSString, obj);
        return revID ? [doc revisionWithID: revID] : nil;
    }];
}


// This is used by the router
- (NSDictionary*) asJSONDictionary {
    if (_value || _sourceDocID) {
        return $dict({@"key", self.key},
                     {@"value", self.value},
                     {@"id", _sourceDocID},
                     {@"doc", _documentProperties});
    } else {
        return $dict({@"key", self.key}, {@"error", @"not_found"});
    }

}


- (NSString*) description {
    NSString* valueStr = @"<none>";
    if (self.value)
        valueStr = [CBLJSON stringWithJSONObject: self.value options: CBLJSONWritingAllowFragments error: nil];
    return [NSString stringWithFormat: @"%@[key=%@; value=%@; id=%@]",
            [self class],
            [CBLJSON stringWithJSONObject: self.key options: CBLJSONWritingAllowFragments error: nil],
            valueStr,
            self.documentID];
}


@end




@implementation CBLDatabase (Views)

- (CBLQueryIteratorBlock) queryViewNamed: (NSString*)viewName
                                 options: (CBLQueryOptions*)options
                          ifChangedSince: (SequenceNumber)ifChangedSince
                            lastSequence: (SequenceNumber*)outLastSequence
                                  status: (CBLStatus*)outStatus
{
    CBLStatus status;
    CBLQueryIteratorBlock iterator = nil;
    SequenceNumber lastSequence = 0;
    do {
        if (viewName) {
            CBLView* view = [self viewNamed: viewName];
            if (!view) {
                status = kCBLStatusNotFound;
                break;
            }
            lastSequence = view.lastSequenceIndexed;
            if (options->indexUpdateMode == kCBLUpdateIndexBefore || lastSequence <= 0) {
                status = [view updateIndex];
                if (CBLStatusIsError(status)) {
                    Warn(@"Failed to update view index: %d", status);
                    break;
                }
                lastSequence = view.lastSequenceIndexed;
            } else if (options->indexUpdateMode == kCBLUpdateIndexAfter &&
                       lastSequence < self.lastSequenceNumber) {
                [self doAsync: ^{
                    [view updateIndex];
                }];
            }
            if (view.lastSequenceChangedAt <= ifChangedSince) {
                status = 304;
                break;
            }
            iterator = [view _queryWithOptions: options status: &status];
        } else {
            // nil view means query _all_docs
            iterator = [self getAllDocs: options status: &status];
            lastSequence = self.lastSequenceNumber;
        }
    } while(false); // just to allow 'break' within the block

    if (outLastSequence)
        *outLastSequence = lastSequence;
    if (outStatus)
        *outStatus = status;
    return iterator;
}

@end
