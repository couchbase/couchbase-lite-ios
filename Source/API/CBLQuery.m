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
#import "CBL_ViewStorage.h"
#import "CBLDatabase.h"
#import "CBL_Server.h"
#import "CBLMisc.h"
#import "MYBlockUtils.h"


// Default value of CBLLiveQuery.updateInterval
#define kDefaultLiveQueryUpdateInterval 0.5


// Querying utilities for CBLDatabase. Defined down below.
@interface CBLDatabase (Views)
- (CBLQueryIteratorBlock) queryViewNamed: (NSString*)viewName
                                 options: (CBLQueryOptions*)options
                          ifChangedSince: (SequenceNumber)ifChangedSince
                            lastSequence: (SequenceNumber*)outLastSequence
                                  status: (CBLStatus*)outStatus;
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
    Assert(database);
    self = [super init];
    if (self) {
        _database = database;
        _view = view;
        _inclusiveStart = _inclusiveEnd = YES;
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
    if (_prefixMatchLevel)
        [desc appendFormat: @", prefixMatchLevel=%lu", (unsigned long)_prefixMatchLevel];
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
    options.startKey = _startKey;
    options.endKey = _endKey;
    options.startKeyDocID = _startKeyDocID;
    options.endKeyDocID = _endKeyDocID;
    options->inclusiveStart = _inclusiveStart;
    options->inclusiveEnd = _inclusiveEnd;
    options->prefixMatchLevel = (unsigned)_prefixMatchLevel;
    options.keys = _keys;
    options.fullTextQuery = _fullTextQuery;
    options->fullTextSnippets = _fullTextSnippets;
    options->fullTextRanking = _fullTextRanking;
    options->bbox = (_isGeoQuery ? &_boundingBox : NULL);
    options->skip = (unsigned)_skip;
    options->limit = (unsigned)_limit;
    options->reduce = !_mapOnly;
    options->reduceSpecified = YES;
    options->groupLevel = (unsigned)_groupLevel;
    options->descending = _descending;
    options->includeDocs = _prefetch;
    options->updateSeq = YES;
    options->allDocsMode = _allDocsMode;
    options->indexUpdateMode = _indexUpdateMode;
    options->indexUpdateMode = _indexUpdateMode;

    NSPredicate* postFilter = _postFilter;
    if (postFilter) {
        CBLDatabase* database = _database;
        options.filter = ^(CBLQueryRow* row) {
            row.database = database;    //FIX: What if this is called on another thread??
            BOOL result = [postFilter evaluateWithObject: row];
            [row _clearDatabase];
            return result;
        };
    }
    return options;
}


- (CBLQueryEnumerator*) run: (NSError**)outError {
    CBLStatus status;
    LogTo(Query, @"%@: running...", self);
    SequenceNumber lastSequence;
    CBLQueryIteratorBlock iterator = [_database queryViewNamed: _view.name
                                                       options: self.queryOptions
                                                ifChangedSince: 0
                                                  lastSequence: &lastSequence
                                                        status: &status];
    if (!iterator) {
        if (outError)
            *outError = CBLStatusToNSError(status, nil);
        return nil;
    }
    CBLQueryEnumerator* result = [[CBLQueryEnumerator alloc] initWithDatabase: _database
                                                                         view: _view
                                                               sequenceNumber: lastSequence
                                                                     iterator: iterator];
    if (_sortDescriptors)
        [result sortUsingDescriptors: _sortDescriptors];
    return result;
}


- (void) runAsync: (void (^)(CBLQueryEnumerator*, NSError*))onComplete {
    [self runAsyncIfChangedSince: 0 onComplete: onComplete];
}

- (void) runAsyncIfChangedSince: (SequenceNumber)ifChangedSince
                     onComplete: (void (^)(CBLQueryEnumerator*, NSError*))onComplete
{
    LogTo(Query, @"%@: Async query %@/%@...", self, _database.name, (_view.name ?: @"_all_docs"));
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

        [_database doAsync: ^{
            // Back on original thread, call the onComplete block:
            LogTo(Query, @"%@: ...async query finished (%u rows, status %d)",
                  self, (unsigned)rows.count, status);
            NSError* error = nil;
            CBLQueryEnumerator* e = nil;
            if (rows) {
                // Associate the query rows with this view, not the background-thread one:
                for (CBLQueryRow* row in rows)
                    [row moveToView: _view];
                e = [[CBLQueryEnumerator alloc] initWithDatabase: _database
                                                            view: _view
                                                  sequenceNumber: lastSequence
                                                            rows: rows];
                if (_sortDescriptors)
                    [e sortUsingDescriptors: _sortDescriptors];
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
    _willUpdate = NO;

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

    _updateAgain = NO;
    _isUpdatingAtSequence = lastSequence;
    _lastUpdatedAt = CFAbsoluteTimeGetCurrent();

    // Reset sequence number in the current result's sequence number when
    // forcing the query to re-run as setting _lastSequence to zero.
    SequenceNumber curRowsSeq = _lastSequence != 0 ? _rows.sequenceNumber : 0;
    [self runAsyncIfChangedSince: curRowsSeq
                      onComplete: ^(CBLQueryEnumerator *rows, NSError* error) {
        // Async update finished:
        _isUpdatingAtSequence = 0;
        _lastError = error;
        if (error) {
            Warn(@"%@: Error updating rows: %@", self, error);
        } else {
            _lastSequence = (SequenceNumber)rows.sequenceNumber;
            if(rows && ![rows isEqual: _rows]) {
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

 
- (void) queryOptionsChanged {
    [self viewChanged: nil];
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
    SequenceNumber lastIndexedSequence = 0, lastChangedSequence = 0;
    do {
        if (viewName) {
            CBLView* view = [self viewNamed: viewName];
            if (!view) {
                status = kCBLStatusNotFound;
                break;
            }
            lastIndexedSequence = view.lastSequenceIndexed;
            if (options->indexUpdateMode == kCBLUpdateIndexBefore || lastIndexedSequence <= 0) {
                status = [view updateIndex];
                if (CBLStatusIsError(status)) {
                    Warn(@"Failed to update view index: %d", status);
                    break;
                }
                lastIndexedSequence = view.lastSequenceIndexed;
            } else if (options->indexUpdateMode == kCBLUpdateIndexAfter &&
                       lastIndexedSequence < self.lastSequenceNumber) {
                [self doAsync: ^{
                    [view updateIndex];
                }];
            }
            lastChangedSequence = view.lastSequenceChangedAt;
            iterator = [view _queryWithOptions: options status: &status];
        } else {
            // nil view means query _all_docs
            iterator = [self getAllDocs: options status: &status];
            lastIndexedSequence = lastChangedSequence = self.lastSequenceNumber;
        }
        if (lastChangedSequence <= ifChangedSince) {
            status = 304;
            break;
        }
    } while(false); // just to allow 'break' within the block

    if (outLastSequence)
        *outLastSequence = lastIndexedSequence;
    if (outStatus)
        *outStatus = status;
    return iterator;
}

@end
