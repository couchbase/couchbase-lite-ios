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

@property (readonly, nullable) CBLQuery* query;

@end

@implementation CBLQueryObserver {
    CBLQuery* _query;
    NSDictionary* _columnNames;
    C4QueryObserver* _obs;
    CBLChangeNotifier* _listenerToken;
}

#pragma mark - Constructor

- (instancetype) initWithQuery: (CBLQuery*)query
                   columnNames: (NSDictionary *)columnNames
                         token: (id<CBLListenerToken>)token {
    NSParameterAssert(query);
    NSParameterAssert(columnNames);
    NSParameterAssert(token);
    
    self = [super init];
    if (self) {
        _query = query;
        _columnNames = columnNames;
        _listenerToken = token;
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
        if (!_obs) {
            return;
        }
        
        [_query.database safeBlock: ^{
            c4queryobs_setEnabled(_obs, true);
        }];
    }
}

- (void) stop {
    CBL_LOCK(self) {
        if (!_obs)
            return;
        
        [_query.database safeBlock: ^{
            c4queryobs_setEnabled(_obs, false);
            c4queryobs_free(_obs);
        }];
        
        _obs = nil;
        _listenerToken = nil;
        
        [_query.database removeActiveStoppable: self];
        
        // NOTE: When database closes, the observer will be stopped without removing
        // the listener token, which also holds this observer instance, from the query.
        // Nulling the _query to ensure to break the circular retain cycle with the query.
        _query = nil;
    }
}

#pragma mark - Internal

- (CBLQuery*) query {
    CBL_LOCK(self) {
        return _query;
    }
}

- (NSString*) description {
    return [NSString stringWithFormat:@"%@[%@:%@]%@", self.class, [_query description], _obs, [_listenerToken description]];
}

#pragma mark - Private

static void liveQueryCallback(C4QueryObserver *obs, C4Query *query, void *context) {
    CBLQueryObserver *queryObs = (__bridge CBLQueryObserver*)context;
    dispatch_queue_t queue = [queryObs query].database.queryQueue;
    if (!queue)
        return;
    
    dispatch_async(queue, ^{
        [queryObs postQueryChange: obs];
    });
};

- (void) postQueryChange: (C4QueryObserver*)obs {
    CBL_LOCK(self) {
        if (!_obs)
            return;
        
        // Note: enumerator('e') will be released in ~QueryResultContext; no need to release it
        __block C4Error c4error = {};
        __block C4QueryEnumerator* e;
        [_query.database safeBlock: ^{
            e = c4queryobs_getEnumerator(obs, true, &c4error);
        }];
        
        if (!e) {
            CBLLogInfo(Query, @"%@: C4QueryEnumerator returns empty (%d/%d)",
                       self, c4error.domain, c4error.code);
            return;
        }
        
        CBLQueryResultSet *rs = [[CBLQueryResultSet alloc] initWithQuery: self.query
                                                              enumerator: e
                                                             columnNames: _columnNames];
        
        if (!rs) {
            CBLLogInfo(Query, @"%@: Result set returns empty", self);
            return;
        }
        
        NSError* error = nil;
        [_listenerToken postChange: [[CBLQueryChange alloc] initWithQuery: self.query
                                                                  results: rs
                                                                    error: error]];
    }
}

@end
