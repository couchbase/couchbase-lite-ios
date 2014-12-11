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


// Default value of CBLLiveQuery.updateInterval
#define kDefaultLiveQueryUpdateInterval 0.5


static NSString* keyPathForQueryRow(NSString* keyPath);


// Querying utilities for CBLDatabase. Defined down below.
@interface CBLDatabase (Views)
- (NSArray*) queryViewNamed: (NSString*)viewName
                    options: (CBLQueryOptions*)options
               lastSequence: (SequenceNumber*)outLastSequence
                     status: (CBLStatus*)outStatus;
@end


@interface CBLQueryEnumerator ()
- (instancetype) initWithDatabase: (CBLDatabase*)db
                             rows: (NSArray*)rows
                   sequenceNumber: (SequenceNumber)sequenceNumber;
@end



@implementation CBLQuery
{
    CBLDatabase* _database;
    BOOL _temporaryView;
    NSUInteger _limit, _skip;
    id _startKey, _endKey;
    NSString* _startKeyDocID;
    NSString* _endKeyDocID;
    CBLIndexUpdateMode _indexUpdateMode;
    BOOL _descending, _inclusiveStart, _inclusiveEnd, _prefetch, _mapOnly;
    CBLAllDocsMode _allDocsMode;
    NSArray *_keys;
    NSUInteger _prefixMatchLevel, _groupLevel;

    @protected
    CBLView* _view;              // nil for _all_docs query
}


// A nil view refers to 'all documents'
- (instancetype) initWithDatabase: (CBLDatabase*)database view: (CBLView*)view {
    self = [super init];
    if (self) {
        _database = database;
        _view = view;
        _inclusiveStart = _inclusiveEnd = YES;
        _limit = kCBLQueryOptionsDefaultLimit;
        _fullTextRanking = YES;
        _mapOnly = (view.reduceBlock == nil);
    }
    return self;
}


- (instancetype) initWithDatabase: (CBLDatabase*)database mapBlock: (CBLMapBlock)mapBlock {
    CBLView* view = [database makeAnonymousView];
    if (self = [self initWithDatabase: database view: view]) {
        _temporaryView = YES;
        _inclusiveStart = _inclusiveEnd = YES;
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
        _inclusiveStart = query.inclusiveStart;
        _inclusiveEnd = query.inclusiveEnd;
        _prefixMatchLevel = query.prefixMatchLevel;
        _descending = query.descending;
        _prefetch = query.prefetch;
        self.keys = query.keys;
        self.sortDescriptors = query.sortDescriptors;
        self.postFilter = query.postFilter;
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
            database=_database, allDocsMode=_allDocsMode, sortDescriptors=_sortDescriptors,
            inclusiveStart=_inclusiveStart, inclusiveEnd=_inclusiveEnd, postFilter=_postFilter,
            prefixMatchLevel=_prefixMatchLevel;


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
    options.filter = _postFilter;
    return options;
}


- (CBLQueryEnumerator*) run: (NSError**)outError {
    CBLStatus status;
    SInt64 lastSequence;
    NSArray* rows = [_database queryViewNamed: _view.name
                                      options: self.queryOptions
                                 lastSequence: &lastSequence
                                       status: &status];
    if (!rows) {
        if (outError)
            *outError = CBLStatusToNSError(status, nil);
        return nil;
    }
    CBLQueryEnumerator* result = [[CBLQueryEnumerator alloc] initWithDatabase: _database
                                                                         rows: rows
                                                               sequenceNumber: lastSequence];
    if (_sortDescriptors)
        [result sortUsingDescriptors: _sortDescriptors];
    return result;
}


- (void) runAsync: (void (^)(CBLQueryEnumerator*, NSError*))onComplete {
    LogTo(Query, @"%@: Async query %@/%@...", self, _database.name, (_view.name ?: @"_all_docs"));
    NSString* viewName = _view.name;
    CBLQueryOptions *options = self.queryOptions;
    
    [_database.manager backgroundTellDatabaseNamed: _database.name to: ^(CBLDatabase *bgdb) {
        // On the background server thread, run the query:
        CBLStatus status;
        SequenceNumber lastSequence;
        NSArray* rows = [bgdb queryViewNamed: viewName
                                     options: options
                                lastSequence: &lastSequence
                                      status: &status];
        LogTo(QueryVerbose, @"%@: Async query done, messaging main thread...", self);
        [_database doAsync:^{
            // Back on original thread, call the onComplete block:
            LogTo(Query, @"%@: ...async query finished (%u rows)", self, (unsigned)rows.count);
            NSError* error = nil;
            CBLQueryEnumerator* e = nil;
            if (CBLStatusIsError(status))
                error = CBLStatusToNSError(status, nil);
            else {
                e = [[CBLQueryEnumerator alloc] initWithDatabase: _database
                                                            rows: rows
                                                  sequenceNumber: lastSequence];
                if (_sortDescriptors)
                    [e sortUsingDescriptors: _sortDescriptors];
            }
            onComplete(e, error);
        }];
    }];
}


@end




@implementation CBLLiveQuery
{
    BOOL _observing, _willUpdate, _updateAgain;
    SequenceNumber _lastSequence, _isUpdatingAtSequence;
    CFAbsoluteTime _lastUpdatedAt;
    CBLQueryEnumerator* _rows;
}


@synthesize lastError=_lastError, updateInterval=_updateInterval;


- (instancetype) initWithDatabase: (CBLDatabase*)database view: (CBLView*)view {
    self = [super initWithDatabase: database view: view];
    if (self) {
        _updateInterval = kDefaultLiveQueryUpdateInterval;
    }
    return self;
}


- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}


- (void) start {
    if (!_observing) {
        _observing = YES;
        [[NSNotificationCenter defaultCenter] addObserver: self 
                                                 selector: @selector(databaseChanged:)
                                                     name: kCBLDatabaseChangeNotification 
                                                   object: self.database];
        
        //view can be null for _all_docs query
        if (_view) {
            [[NSNotificationCenter defaultCenter] addObserver: self
                                                     selector: @selector(viewChanged:)
                                                         name: kCBLViewChangeNotification
                                                       object: _view];
        }
        [self update];
    }
}


- (void) stop {
    if (_observing) {
        _observing = NO;
        [[NSNotificationCenter defaultCenter] removeObserver: self];
    }
    _willUpdate = NO; // cancels the delayed update started by -databaseChanged
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


- (void) databaseChanged: (NSNotification*)n {
    if (_willUpdate)
        return;

    // Use double the update interval if this is a remote change (coming from a pull replication):
    NSTimeInterval updateInterval = _updateInterval * 2;
    for (CBLDatabaseChange* change in n.userInfo[@"changes"]) {
        if (change.source == nil) {
            updateInterval /= 2;
            break;
        }
    }

    // Schedule an update, respecting the updateInterval:
    _willUpdate = YES;
    NSTimeInterval updateDelay = (_lastUpdatedAt + updateInterval) - CFAbsoluteTimeGetCurrent();
    updateDelay = MAX(0, MIN(_updateInterval, updateDelay));
    LogTo(Query, @"%@: Will update after %g sec...", self, updateDelay);
    [self.database doAsyncAfterDelay: updateDelay block: ^{
        if (_willUpdate)
            [self update];
    }];
}


- (void) viewChanged: (NSNotification*)n {
    _lastSequence = 0;  // force an update even though the db's lastSequence hasn't changed
    [self update];
}


- (void) update {
    SequenceNumber lastSequence = self.database.lastSequenceNumber;
    if (_rows && _lastSequence >= lastSequence) {
        return; // db hasn't changed since last query
    }
    if (_isUpdatingAtSequence > 0) {
        // Update already in progress; only schedule another one if db has changed since
        if (_isUpdatingAtSequence < lastSequence) {
            _isUpdatingAtSequence = lastSequence;
            _updateAgain = YES;
        }
        return;
    }

    _willUpdate = NO;
    _updateAgain = NO;
    _isUpdatingAtSequence = lastSequence;
    _lastUpdatedAt = CFAbsoluteTimeGetCurrent();
    [self runAsync: ^(CBLQueryEnumerator *rows, NSError* error) {
        // Async update finished:
        _isUpdatingAtSequence = 0;
        _lastError = error;
        if (error) {
            Warn(@"%@: Error updating rows: %@", self, error);
        } else {
            _lastSequence = (SequenceNumber)rows.sequenceNumber;
            if (![rows isEqual: _rows]) {
                LogTo(Query, @"%@: ...Rows changed! (now %lu)", self, (unsigned long)rows.count);
                self.rows = rows;   // Triggers KVO notification
            }
        }
        if (_updateAgain)
            [self update];
    }];
}


- (BOOL) waitForRows {
    [self start];
    return [self.database waitFor: ^BOOL { return _rows != nil || _lastError != nil; }]
        && _rows != nil;
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


- (void) sortUsingDescriptors: (NSArray*)sortDescriptors {
    // First make the key-paths relative to each row's value unless they start from a root key:
    sortDescriptors = [sortDescriptors my_map: ^id(id descOrString) {
        NSSortDescriptor* desc = [[self class] asNSSortDescriptor: descOrString];
        NSString* keyPath = desc.key;
        NSString* newKeyPath = keyPathForQueryRow(keyPath);
        Assert(newKeyPath, @"Invalid CBLQueryRow key path \"%@\"", keyPath);
        if (newKeyPath == keyPath)
            return desc;
        else if (desc.comparator)
            return [[NSSortDescriptor alloc] initWithKey: newKeyPath
                                               ascending: desc.ascending
                                              comparator: desc.comparator];
        else
            return [[NSSortDescriptor alloc] initWithKey: newKeyPath
                                               ascending: desc.ascending
                                                selector: desc.selector];
    }];

    // Now the sorting is trivial:
    _rows = [_rows sortedArrayUsingDescriptors: sortDescriptors];
}


+ (NSSortDescriptor*) asNSSortDescriptor: (id)desc {
    if ([desc isKindOfClass: [NSString class]]) {
        BOOL ascending = ![desc hasPrefix: @"-"];
        if (!ascending)
            desc = [desc substringFromIndex: 1];
        desc = [NSSortDescriptor sortDescriptorWithKey: desc ascending: ascending];
    }
    return desc;
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


static inline BOOL isNonMagicValue(id value) {
    return value && !([value isKindOfClass: [NSData class]] && CBLValueIsEntireDoc(value));
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
        if (isNonMagicValue(_value) || isNonMagicValue(other->_value))
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
            if (CBLValueIsEntireDoc(value)) {
                // Value is a placeholder ("*") denoting that the map function emitted "doc" as
                // the value. So load the body of the revision now:
                Assert(_database);
                Assert(_sequence);
                CBLStatus status;
                CBL_Revision* rev = [_database getDocumentWithID: _sourceDocID
                                                        sequence: _sequence
                                                          status: &status];
                if (!rev)
                    Warn(@"%@: Couldn't load doc for row value: status %d", self, status);
                value = rev.properties;
            } else {
                value = fromJSON(value);
            }
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


// Custom key & value indexing properties. These are used by the extended "key[0]" / "value[2]"
// key-path syntax (see keyPathForQueryRow(), below.) They're also useful when creating Cocoa
// bindings to query rows, on Mac OS X.

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

- (id) valueAtIndex: (NSUInteger)index {
    id value = self.value;
    if ([value isKindOfClass:[NSArray class]])
        return (index < [value count]) ? value[index] : nil;
    else
        return (index == 0) ? value : nil;
}

- (id) value0                         {return [self valueAtIndex: 0];}
- (id) value1                         {return [self valueAtIndex: 1];}
- (id) value2                         {return [self valueAtIndex: 2];}
- (id) value3                         {return [self valueAtIndex: 3];}


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
    NSString* valueStr = @"nil";
    if (self.value)
        valueStr = [CBLJSON stringWithJSONObject: self.value
                                         options: CBLJSONWritingAllowFragments error: nil];
    return [NSString stringWithFormat: @"%@[key=%@; value=%@; id=%@]",
            [self class],
            [CBLJSON stringWithJSONObject: self.key options: CBLJSONWritingAllowFragments error: nil],
            valueStr,
            self.documentID];
}


@end




@implementation CBLDatabase (Views)

- (NSArray*) queryViewNamed: (NSString*)viewName
                    options: (CBLQueryOptions*)options
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
            rows = [view _queryWithOptions: options status: &status];
        } else {
            // nil view means query _all_docs
            rows = [self getAllDocs: options];
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



// Tweaks a key-path for use with a CBLQueryRow. The "key" and "value" properties can be
// indexed as arrays using a syntax like "key[0]". (Yes, this is a hack.)
static NSString* keyPathForQueryRow(NSString* keyPath) {
    NSRange bracket = [keyPath rangeOfString: @"["];
    if (bracket.length == 0)
        return keyPath;
    if (![keyPath hasPrefix: @"key["] && ![keyPath hasPrefix: @"value["])
        return nil;
    NSUInteger indexPos = NSMaxRange(bracket);
    if (keyPath.length < indexPos+2 || [keyPath characterAtIndex: indexPos+1] != ']')
        return nil;
    unichar ch = [keyPath characterAtIndex: indexPos];
    if (!isdigit(ch))
        return nil;
    // Delete the brackets, e.g. turning "value[1]" into "value1". CBLQueryRow
    // just so happens to have custom properties key0..key3 and value0..value3.
    NSMutableString* newKey = [keyPath mutableCopy];
    [newKey deleteCharactersInRange: NSMakeRange(indexPos+1, 1)]; // delete ']'
    [newKey deleteCharactersInRange: NSMakeRange(indexPos-1, 1)]; // delete '['
    return newKey;
}


TestCase(CBLQuery_KeyPathForQueryRow) {
    AssertEqual(keyPathForQueryRow(@"value"),           @"value");
    AssertEqual(keyPathForQueryRow(@"value.foo"),       @"value.foo");
    AssertEqual(keyPathForQueryRow(@"value[0]"),        @"value0");
    AssertEqual(keyPathForQueryRow(@"key[3].foo"),      @"key3.foo");
    AssertEqual(keyPathForQueryRow(@"value[0].foo"),    @"value0.foo");
    AssertEqual(keyPathForQueryRow(@"[2]"),             nil);
    AssertEqual(keyPathForQueryRow(@"sequence[2]"),     nil);
    AssertEqual(keyPathForQueryRow(@"value.addresses[2]"),nil);
    AssertEqual(keyPathForQueryRow(@"value["),          nil);
    AssertEqual(keyPathForQueryRow(@"value[0"),         nil);
    AssertEqual(keyPathForQueryRow(@"value[0"),         nil);
    AssertEqual(keyPathForQueryRow(@"value[0}"),        nil);
    AssertEqual(keyPathForQueryRow(@"value[d]"),        nil);
}
