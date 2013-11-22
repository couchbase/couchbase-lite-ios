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
    CBLUpdateIndexMode _updateIndex;
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
        _limit = kDefaultCBLQueryOptions.limit;  // this has a nonzero default (UINT_MAX)
        _fullTextRanking = kDefaultCBLQueryOptions.fullTextRanking; // defaults to YES
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
        _updateIndex = query.updateIndex;
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
            endKeyDocID=_endKeyDocID, updateIndex=_updateIndex, mapOnly=_mapOnly,
            database=_database, allDocsMode=_allDocsMode;


- (CBLLiveQuery*) asLiveQuery {
    return [[CBLLiveQuery alloc] initWithQuery: self];
}

- (CBLQueryOptions) queryOptions {
    return (CBLQueryOptions) {
        .startKey = _startKey,
        .endKey = _endKey,
        .keys = _keys,
        .fullTextQuery = _fullTextQuery,
        .fullTextSnippets = _fullTextSnippets,
        .fullTextRanking = _fullTextRanking,
        .bbox = (_isGeoQuery ? &_boundingBox : NULL),
        .skip = (unsigned)_skip,
        .limit = (unsigned)_limit,
        .reduce = !_mapOnly,
        .reduceSpecified = YES,
        .groupLevel = (unsigned)_groupLevel,
        .descending = _descending,
        .includeDocs = _prefetch,
        .updateSeq = YES,
        .inclusiveEnd = YES,
        .allDocsMode = _allDocsMode,
        .stale = _updateIndex
    };
}


- (CBLQueryEnumerator*) rows: (NSError**)outError {
    CBLStatus status;
    NSArray* rows = [_database queryViewNamed: _view.name
                                      options: self.queryOptions
                                 lastSequence: &_lastSequence
                                       status: &status];
    if (!rows) {
        if (outError)
            *outError = CBLStatusToNSError(status, nil);
        return nil;
    }
    return [[CBLQueryEnumerator alloc] initWithDatabase: _database
                                                   rows: rows
                                         sequenceNumber: _lastSequence];
}


- (void) runAsync: (void (^)(CBLQueryEnumerator*, NSError*))onComplete {
    LogTo(Query, @"%@: Async query %@/%@...", self, _database.name, (_view.name ?: @"_all_docs"));
    NSThread *callingThread = [NSThread currentThread];
    NSString* viewName = _view.name;
    CBLQueryOptions options = self.queryOptions;
    
    [_database.manager backgroundTellDatabaseNamed: _database.name to: ^(CBLDatabase *bgdb) {
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
            NSError* error = nil;
            CBLQueryEnumerator* e = nil;
            if (CBLStatusIsError(status))
                error = CBLStatusToNSError(status, nil);
            else
                e = [[CBLQueryEnumerator alloc] initWithDatabase: _database
                                                            rows: rows
                                                  sequenceNumber: lastSequence];
            onComplete(e, error);
        });
    }];
}


#ifdef CBL_DEPRECATED
@synthesize error=_deprecatedError;
- (BOOL) includeDeleted {
    return _allDocsMode == kCBLIncludeDeleted;
}
- (void) setIncludeDeleted:(BOOL)includeDeleted {
    _allDocsMode = includeDeleted ? kCBLIncludeDeleted : kCBLAllDocs;
}
- (CBLUpdateIndexMode) stale {return self.updateIndex;}
- (void) setStale:(CBLUpdateIndexMode)stale {self.updateIndex = stale;}
- (CBLQueryEnumerator*) rows {
    NSError* error;
    CBLQueryEnumerator* result = [self rows: &error];
    _deprecatedError = error;
    return result;
}
- (CBLQueryEnumerator*) rowsIfChanged {
    if (_database.lastSequenceNumber == _lastSequence)
        return nil;
    return [self rows: nil];
}
#endif


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


- (CBLQueryEnumerator*) rows: (NSError**)outError {
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
    [self runAsync: ^(CBLQueryEnumerator *rows, NSError* error) {
        _lastError = error;
        if (error) {
            Warn(@"%@: Error updating rows: %@", self, error);
        } else if(![rows isEqual: _rows]) {
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
    NSArray* _rows;
    NSUInteger _nextRow;
    UInt64 _sequenceNumber;
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

        // Fill in the rows' database reference now
        for (CBLQueryRow* row in _rows)
            row.database = database;
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


- (void) reset {
    _nextRow = 0;
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


- (BOOL) stale {
    return (SequenceNumber)_sequenceNumber < _database.lastSequenceNumber;
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
    return [NSString stringWithFormat: @"%@[key=%@; value=%@; id=%@]",
            [self class],
            [CBLJSON stringWithJSONObject: self.key options: CBLJSONWritingAllowFragments error: nil],
            [CBLJSON stringWithJSONObject: self.value options: CBLJSONWritingAllowFragments error: nil],
            self.documentID];
}


#ifdef CBL_DEPRECATED
- (UInt64) localSequence {return _sequence;}
#endif


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
            if (options.stale == kCBLUpdateIndexBefore || lastSequence <= 0) {
                status = [view updateIndex];
                if (CBLStatusIsError(status)) {
                    Warn(@"Failed to update view index: %d", status);
                    break;
                }
                lastSequence = view.lastSequenceIndexed;
            } else if (options.stale == kCBLUpdateIndexAfter &&
                       lastSequence < self.lastSequenceNumber) {
                [self doAsync: ^{
                    [view updateIndex];
                }];
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
