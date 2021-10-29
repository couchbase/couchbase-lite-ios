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

@interface CBLQueryObserver ()

@property (nonatomic, readonly) CBLQuery* query;

@end

@implementation CBLQueryObserver {
    CBLQuery* _query;
    
    CBLChangeNotifier<CBLQueryChange*>* _changeNotifier;
    
    CBLQueryResultSet* _rs;
    NSDictionary* _columnNames;
}

- (instancetype) initWithQuery: (CBLQuery*)query columnNames:(nonnull NSDictionary *)columnNames {
    NSParameterAssert(query);
    NSParameterAssert(columnNames);
    
    self = [super init];
    if (self) {
        _query = query;
        _columnNames = columnNames;
    }
    return self;
}

- (void) start {
    
}

- (void) stop {
    
}

- (CBLQuery*) query {
    return _query;
}

static void liveQueryCallback(C4QueryObserver *obs, C4Query *query, void *context) {
    CBLQueryObserver *liveQuery = (__bridge CBLQueryObserver*)context;
    dispatch_queue_t queue = [liveQuery query].database.queryQueue;
    if (!queue)
        return;
    
    dispatch_async(queue, ^{
        [liveQuery postQueryChange: obs];
    });
};

- (void) postQueryChange: (C4QueryObserver*)obs {
    CBL_LOCK(self) {
        C4Error c4error = {};
        CBLQuery* strongQuery = _query;
        
        // Note: enumerator('e') will be released in ~QueryResultContext; no need to release it
        C4QueryEnumerator* e = c4queryobs_getEnumerator(obs, true, &c4error);
        if (!e) {
            CBLLogInfo(Query, @"%@: C4QueryEnumerator returns empty (%d/%d)",
                       self, c4error.domain, c4error.code);
            return;
        }
        
        _rs = [[CBLQueryResultSet alloc] initWithQuery: strongQuery
                                            enumerator: e
                                           columnNames: _columnNames];
        
        if (!_rs) {
            CBLLogInfo(Query, @"%@: Result set returns empty", self);
            return;
        }
        
        NSError* error = nil;
        [_changeNotifier postChange: [[CBLQueryChange alloc] initWithQuery: strongQuery
                                                                   results: _rs
                                                                     error: error]];
    }
}

@end
