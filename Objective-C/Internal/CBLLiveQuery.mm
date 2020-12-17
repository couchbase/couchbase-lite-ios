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

typedef enum {
    kCBLLiveQueryStatusNoUpdate = 0,    // up to date, nothing to update
    kCBLLiveQueryStatusUpdating,        // in the middle of an update
    kCBLLiveQueryStatusWillUpdate,      // is waiting to be updated
} CBLLiveQueryUpdateStatus;

typedef enum {
    kCBLLiveQueryStateStopped = 0,
    kCBLLiveQueryStateStopping,
    kCBLLiveQueryStateObserving,
} CBLLiveQueryState;

// Default value of CBLLiveQuery.updateInterval
static const NSTimeInterval kDefaultLiveQueryUpdateInterval = 0.2;

@implementation CBLLiveQuery
{
    __weak CBLQuery* _query;
    NSTimeInterval _updateInterval;
    
    CFAbsoluteTime _lastUpdatedAt;
    CBLQueryResultSet* _rs;
    id _dbListenerToken;
    
    CBLChangeNotifier<CBLQueryChange*>* _changeNotifier;
    
    CBLLiveQueryUpdateStatus _updateStatus;
    CBLLiveQueryState _state;
}

- (instancetype) initWithQuery: (CBLQuery*)query {
    self = [super init];
    if (self) {
        _query = query;
        // Note: We could make the updateInternal property public in the future
        _updateInterval = kDefaultLiveQueryUpdateInterval;
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

- (void) start {
    CBL_LOCK(self) {
        if (!_dbListenerToken) {
            CBLDatabase* db = _query.database;
            Assert(db);
            
            [db addActiveStoppable: self];
            
            __weak CBLLiveQuery* wSelf = self;
            _dbListenerToken = [db addChangeListener: ^(CBLDatabaseChange *change) {
                [wSelf databaseChanged: change];
            }];
        }
        
        _rs = nil;
        _updateStatus = kCBLLiveQueryStatusNoUpdate;
        _state = kCBLLiveQueryStateObserving;
        
        [self updateAfter:0.0];
    }
}

- (void) stop {
    CBL_LOCK(self) {
        if (_state != kCBLLiveQueryStateObserving)
            return;
        
        // Since we are accessing weak _query multiple times which can become nil.
        CBLQuery* strongQuery = _query;
        if (_dbListenerToken) {
            [strongQuery.database removeChangeListenerWithToken: _dbListenerToken];
            _dbListenerToken = nil;
        }
        
        _changeNotifier = nil;
        _rs = nil;
        
        // cancels the delayed update started by -databaseChanged as well.
        if (_updateStatus != kCBLLiveQueryStatusUpdating)
            [self stopped];
        else
            _state = kCBLLiveQueryStateStopping;
    }
}

// Called under self lock.
- (void) stopped {
    // Since we are accessing weak _query multiple times which can become nil.
    CBLQuery* strongQuery = _query;
    [strongQuery.database removeActiveStoppable: self];
    
    _state = kCBLLiveQueryStateStopped;
}

- (void) queryParametersChanged {
    CBL_LOCK(self) {
        if (_dbListenerToken)
            [self start];
    }
}

- (nullable NSString*) explain: (NSError**)error {
    return [_query explain: error];
}

- (id<CBLListenerToken>) addChangeListenerWithQueue: (nullable dispatch_queue_t)queue
                                           listener: (void (^)(CBLQueryChange*))listener
{
    CBL_LOCK(self) {
        if (_state != kCBLLiveQueryStateObserving)
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

#pragma mark Private

- (void) databaseChanged: (CBLDatabaseChange*)change {
    CBL_LOCK(self) {
        if (_updateStatus == kCBLLiveQueryStatusWillUpdate)
            return;  // Already a pending update scheduled
        
        // Use double the update interval if this is a remote change (coming from a pull replication):
        NSTimeInterval updateInterval = _updateInterval;
        if (change.isExternal)
            updateInterval *= 2;
        
        // Schedule an update, respecting the updateInterval:
        NSTimeInterval updateDelay = (_lastUpdatedAt + updateInterval) - CFAbsoluteTimeGetCurrent();
        updateDelay = MAX(0, MIN(_updateInterval, updateDelay));
        [self updateAfter: updateDelay];
    }
}

- (void) updateAfter: (NSTimeInterval)updateDelay {
    if (_updateStatus == kCBLLiveQueryStatusWillUpdate)
        return;  // Already a pending update scheduled
    _updateStatus = kCBLLiveQueryStatusWillUpdate;
    
    __strong CBLQuery* query = _query;
    dispatch_queue_t queue = query.database.queryQueue;
    if (!queue)
        return;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(updateDelay * NSEC_PER_SEC)),
                   queue, ^{
                       [self update];
                   });
}

- (void) update {
    CBL_LOCK(self) {
        if (_updateStatus != kCBLLiveQueryStatusWillUpdate)
            return;
        _updateStatus = kCBLLiveQueryStatusUpdating;
    }
    
    CBLQuery* strongQuery = _query;
    CBLLogInfo(Query, @"%@: Querying...", self);
    NSError *error;
    CBLQueryResultSet* oldRs = _rs;
    CBLQueryResultSet* newRs;
    if (oldRs == nil)
        newRs = (CBLQueryResultSet*) [strongQuery execute: &error];
    else
        newRs = [oldRs refresh: &error];

    CBL_LOCK(self) {
        _updateStatus = kCBLLiveQueryStatusNoUpdate;
        
        if(_state == kCBLLiveQueryStateStopping) {
            [self stopped];
            return;
        }
        
        _lastUpdatedAt = CFAbsoluteTimeGetCurrent();
        BOOL changed = YES;
        if (newRs) {
            if (oldRs)
                CBLLogInfo(Query, @"%@: Changed!", self);
            _rs = newRs;
        } else if (error != nil) {
            CBLWarnError(Query, @"%@: Update failed: %@", self, error.localizedDescription);
        } else {
            changed = NO;
            CBLLogVerbose(Query, @"%@: ...no change", self);
        }
        
        if (changed) {
            [_changeNotifier postChange: [[CBLQueryChange alloc] initWithQuery: strongQuery
                                                                       results: newRs
                                                                         error: error]];
        }
    }
}

@end
