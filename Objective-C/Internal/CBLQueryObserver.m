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
#import "CBLContextManager.h"
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
    C4QueryObserver* _c4obs;
    CBLChangeListenerToken<CBLQueryChange*>* _token;
    void* _context;
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
        
        _context = [[CBLContextManager shared] registerObject: self];
        _c4obs = c4queryobs_create(query.c4query, liveQueryCallback, _context); // c4queryobs_create is thread-safe.
        
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
        Assert(_c4obs, @"QueryObserver cannot be restarted.");
        [_query.database safeBlock: ^{
            c4queryobs_setEnabled(_c4obs, true);
        }];
    }
}

- (CBLQuery*) query {
    CBL_LOCK(self) {
        return _query;
    }
}

- (void) stop {
    CBL_LOCK(self) {
        if ([self isStopped]) { return; }
        
        [_query.database safeBlock: ^{
            c4queryobs_setEnabled(_c4obs, false);
            c4queryobs_free(_c4obs);
            [_query.database removeActiveStoppable: self];
        }];
        
        [[CBLContextManager shared] unregisterObjectForPointer: _context];
        _context = nil;
        
        _c4obs = nil;
        _query = nil; // Break circular reference cycle
        _token = nil; // Break circular reference cycle
    }
}

// Must call under self lock
- (BOOL) isStopped {
    return _c4obs == nil;
}

#ifdef DEBUG

static NSTimeInterval sC4QueryObserverCallbackDelayInterval = 0;

+ (void) setC4QueryObserverCallbackDelayInterval: (NSTimeInterval)delay {
    sC4QueryObserverCallbackDelayInterval = delay;
}

#endif

#pragma mark - Private

static void liveQueryCallback(C4QueryObserver *c4obs, C4Query *c4query, void *context) {
#ifdef DEBUG
    if (sC4QueryObserverCallbackDelayInterval > 0) {
        [NSThread sleepForTimeInterval: sC4QueryObserverCallbackDelayInterval];
    }
#endif
    
    // Get and retain object:
    id obj = [[CBLContextManager shared] objectForPointer: context];
    CBLQueryObserver* obs = $castIf(CBLQueryObserver, obj);
    
    // Validate:
    if (!obs || obs->_c4obs != c4obs) {
        CBLLogVerbose(Query, @"Query observer context was already released, ignore observer callback");
        return;
    }
    
    // Check stopped:
    CBLQuery* query = obs.query;
    if (!query) {
        CBLLogVerbose(Query, @"%@: Query observer was already stopped, ignore observer callback", obs);
        return;
    }
    
    // MUST get the enumerator inside the callback as the c4obs could be deleted after the callback if called.
    __block C4QueryEnumerator* enumerator = NULL;
    __block C4Error c4error = {};
    
    [query.database safeBlock: ^{
        enumerator = c4queryobs_getEnumerator(c4obs, true, &c4error);
    }];
    
    if (!enumerator) {
        CBLLogVerbose(Query, @"%@: Ignore an empty result (%d/%d)", obs, c4error.domain, c4error.code);
        return;
    }
    
    dispatch_async(query.database.queryQueue, ^{
        [obs postQueryChange: enumerator];
    });
};

- (void) postQueryChange: (C4QueryEnumerator*)enumerator {
    CBLChangeListenerToken<CBLQueryChange*>* token;
    CBLQuery* query;
    CBL_LOCK(self) {
        if ([self isStopped]) {
            c4queryenum_release( enumerator);
            CBLLogVerbose(Query, @"%@: Query observer was already stopped, skip notification", self);
            return;
        }
        token = _token;
        query = _query;
    }
    
    CBLQueryResultSet* rs = [[CBLQueryResultSet alloc] initWithQuery: query
                                                          enumerator: enumerator
                                                         columnNames: _columnNames];
    [token postChange: [[CBLQueryChange alloc] initWithQuery: query results: rs error: nil]];
}

@end
