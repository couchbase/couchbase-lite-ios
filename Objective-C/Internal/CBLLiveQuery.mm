//
//  CBLLiveQuery.mm
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
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

#import "CBLLiveQuery.h"
#import "CBLQuery.h"
#import "CBLQueryChange+Internal.h"
#import "CBLQuery+Internal.h"
#import "CBLQueryResultSet+Internal.h"
#import "CBLChangeNotifier.h"
#import "CBLStoppable.h"

#pragma mark -
@interface CBLLiveQuery () <CBLStoppable>
@end

#pragma mark -

@implementation CBLLiveQuery
{
    __weak CBLQuery* _query;
    CBLQueryResultSet* _rs;
    
    CBLChangeNotifier<CBLQueryChange*>* _changeNotifier;
    
    C4QueryObserver* _obs;
    NSDictionary* _columnNames;
}

- (instancetype) initWithQuery: (CBLQuery*)query columnNames: (NSDictionary*)columnNames {
    NSParameterAssert(query);
    NSParameterAssert(columnNames);
    
    self = [super init];
    if (self) {
        _query = query;
        _columnNames = columnNames;
    }
    return self;
}

- (void) dealloc {
    [self stop];
}

- (NSString*) description {
    return [NSString stringWithFormat:@"%@[%@]", self.class, [_query description]];
}

- (CBLQueryParameters*) parameters {
    return _query.parameters;
}

- (CBLQuery*) query {
    return _query;
}

static void liveQueryCallback(C4QueryObserver *obs, C4Query *query, void *context) {
    CBLLiveQuery *liveQuery = (__bridge CBLLiveQuery*)context;
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
        C4QueryEnumerator* e = c4queryobs_getEnumerator(obs, true, &c4error);
        if (!e) {
            CBLLogInfo(Query, @"%@: C4QueryEnumerator returns empty (%d/%d)",
                       self, c4error.domain, c4error.code);
            return;
        }
        _rs = [[CBLQueryResultSet alloc] initWithQuery: strongQuery
                                            enumerator: e
                                           columnNames: _columnNames];
        c4queryenum_release(e);
        
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

- (void) start {
    CBL_LOCK(self) {
        CBLQuery* strongQuery = _query;
        if (!_obs) {
            Assert(strongQuery.c4query);
            
            CBLDatabase* db = strongQuery.database;
            Assert(db);
            
            [db addActiveStoppable: self];
            
            _obs = c4queryobs_create(strongQuery.c4query, liveQueryCallback, (__bridge void *)self);
            c4queryobs_setEnabled(_obs, true);
            _rs = nil;
        }
    }
}

- (void) stop {
    CBL_LOCK(self) {
        if (_obs) {
            c4queryobs_free(_obs);
            _obs = nil;
        }
        
        _changeNotifier = nil;
        _rs = nil;
        
        [_query.database removeActiveStoppable: self];
    }
}

- (nullable NSString*) explain: (NSError**)error {
    return [_query explain: error];
}

- (id<CBLListenerToken>) addChangeListenerWithQueue: (nullable dispatch_queue_t)queue
                                           listener: (void (^)(CBLQueryChange*))listener
{
    CBL_LOCK(self) {
        [self start];
        
        if (!_changeNotifier)
            _changeNotifier = [CBLChangeNotifier new];
        return [_changeNotifier addChangeListenerWithQueue: queue listener: listener];
    }
}

- (void) removeChangeListenerWithToken: (id<CBLListenerToken>)token {
    CBL_LOCK(self) {
        if ([_changeNotifier removeChangeListenerWithToken: token] == 0)
            [self stop];
    }
}

@end
