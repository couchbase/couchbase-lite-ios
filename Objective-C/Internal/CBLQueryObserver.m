//
//  CBLQueryObserver.m
//  CouchbaseLite
//
//  Copyright (c) 2021 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//
#import "CBLQueryObserver.h"
#import "c4.h"
#import "CBLChangeNotifier.h"
#import "CBLQueryChange+Internal.h"
#import "CBLQuery+Internal.h"
#import "CBLQueryResultSet+Internal.h"

@interface CBLQueryObserver () <CBLStoppable>

/** The query object will be set to nil when the replicator is stopped to break the circular retain references.  */
@property (nonatomic, readonly, nullable) CBLQuery* query;

@end

@implementation CBLQueryObserver {
    CBLQuery* _query;
    NSDictionary* _columnNames;
    C4QueryObserver* _obs;
    CBLChangeListenerToken<CBLQueryChange*>* _token;
}

#pragma mark - Constructor

- (instancetype) initWithQuery: (CBLQuery*)query
                   columnNames: (NSDictionary*)columnNames
                         token: (CBLChangeListenerToken<CBLQueryChange*>*)token {
    NSParameterAssert(query);
    NSParameterAssert(columnNames);
    NSParameterAssert(token);
    
    self = [super init];
    if (self) {
        _query = query;
        _columnNames = columnNames;
        _token = token;
        
        // https://github.com/couchbase/couchbase-lite-core/wiki/Thread-Safety
        // c4queryobs_create is thread-safe.
        _obs = c4queryobs_create(query.c4query, liveQueryCallback, (__bridge void *)self);
        
        [query.database addActiveStoppable: self];
    }
    return self;
}

- (void) dealloc {
    [self stop];
}

#pragma mark - Methods

- (void) start {
    CBL_LOCK(self) {
        Assert(_query, @"QueryObserver cannot be restarted.");
        [_query.database safeBlock: ^{
            c4queryobs_setEnabled(_obs, true);
        }];
    }
}

#pragma mark - Internal

- (CBLQuery*) query {
    CBL_LOCK(self) {
        return _query;
    }
}

- (void) stop {
    CBL_LOCK(self) {
        if (!_query) {
            return;
        }
        
        [_query.database safeBlock: ^{
            c4queryobs_setEnabled(_obs, false);
            c4queryobs_free(_obs);
            _obs = nil;
            [_query.database removeActiveStoppable: self];
        }];
        
        _query = nil; // Break circular reference cycle
        _token = nil; // Break circular reference cycle
    }
}

#pragma mark - Private

static void liveQueryCallback(C4QueryObserver *obs, C4Query *c4query, void *context) {
    CBLQueryObserver* queryObs = (__bridge CBLQueryObserver*)context;
    CBLQuery* query = queryObs.query;
    if (!query) {
        return;
    }
    
    dispatch_async(query.database.queryQueue, ^{
        [queryObs postQueryChange: obs];
    });
};

- (void) postQueryChange: (C4QueryObserver*)obs {
    CBL_LOCK(self) {
        if (!_query) {
            return;
        }
        
        // Note: enumerator('result') will be released in ~QueryResultContext; no need to release it
        __block C4Error c4error = {};
        __block C4QueryEnumerator* result = NULL;
        [_query.database safeBlock: ^{
            result = c4queryobs_getEnumerator(obs, true, &c4error);
        }];
        
        if (!result) {
            CBLLogVerbose(Query, @"%@: Ignore an empty result (%d/%d)", self, c4error.domain, c4error.code);
            return;
        }
        
        CBLQueryResultSet* rs = [[CBLQueryResultSet alloc] initWithQuery: _query enumerator: result columnNames: _columnNames];
        [_token postChange: [[CBLQueryChange alloc] initWithQuery: _query results: rs error: nil]];
    }
}

@end
