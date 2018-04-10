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
#import "CBLLog.h"
#import "CBLQuery.h"
#import "CBLQueryChange+Internal.h"
#import "CBLQuery+Internal.h"
#import "CBLQueryResultSet+Internal.h"
#import "CBLChangeNotifier.h"


// Default value of CBLLiveQuery.updateInterval
static const NSTimeInterval kDefaultLiveQueryUpdateInterval = 0.2;

@implementation CBLLiveQuery
{
    __weak CBLQuery* _query;
    NSTimeInterval _updateInterval;
    
    BOOL _observing, _willUpdate;
    CFAbsoluteTime _lastUpdatedAt;
    CBLQueryResultSet* _rs;
    id _dbListenerToken;
    
    CBLChangeNotifier<CBLQueryChange*>* _changeNotifier;
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
    if (!_dbListenerToken) {
        CBLDatabase* db = _query.database;
        Assert(db);
        
        CBL_LOCK(db) {
            [db.liveQueries addObject:self];
        }
        
        __weak typeof(self) wSelf = self;

        _dbListenerToken = [db addChangeListener: ^(CBLDatabaseChange *change) {
            [wSelf databaseChanged: change];
        }];
    }
    _observing = YES;
    
    CBL_LOCK(self) {
        _rs = nil;
        _willUpdate = NO;
        [self updateAfter:0.0];
    }
}


- (void) stop {
    if (_dbListenerToken) {
        CBLQuery* strongQuery = _query; // since we are accessing weak _query multiple times which can become nil
        CBL_LOCK(strongQuery.database) {
            [strongQuery.database.liveQueries removeObject:self];
        }
        [strongQuery.database removeChangeListenerWithToken: _dbListenerToken];
        _dbListenerToken = nil;
    }
    
    _observing = NO;
    _changeNotifier = nil;
    
    CBL_LOCK(self) {
        _willUpdate = NO; // cancels the delayed update started by -databaseChanged
        _rs = nil;
    }
}



- (void) queryParametersChanged {
    if (_dbListenerToken)
        [self start];
}


- (nullable NSString*) explain: (NSError**)error {
    return [_query explain: error];
}


- (id<CBLListenerToken>) addChangeListenerWithQueue: (nullable dispatch_queue_t)queue
                                           listener: (void (^)(CBLQueryChange*))listener
{
    if (!_observing)
        [self start];

    if (!_changeNotifier)
        _changeNotifier = [CBLChangeNotifier new];
    return [_changeNotifier addChangeListenerWithQueue: queue listener: listener];
}


- (void) removeChangeListenerWithToken: (id<CBLListenerToken>)token {
    if ([_changeNotifier removeChangeListenerWithToken: token] == 0)
        [self stop];
}


#pragma mark Private


- (void) databaseChanged: (CBLDatabaseChange*)change {
    CBL_LOCK(self) {
        if (_willUpdate)
            return;  // Already a pending update scheduled
    }
    
    // Use double the update interval if this is a remote change (coming from a pull replication):
    NSTimeInterval updateInterval = _updateInterval;
    if (change.isExternal)
        updateInterval *= 2;

    // Schedule an update, respecting the updateInterval:
    NSTimeInterval updateDelay = (_lastUpdatedAt + updateInterval) - CFAbsoluteTimeGetCurrent();
    updateDelay = MAX(0, MIN(_updateInterval, updateDelay));
    [self updateAfter: updateDelay];
}


- (void) updateAfter: (NSTimeInterval)updateDelay {
    CBL_LOCK(self) {
        if (_willUpdate)
            return;  // Already a pending update scheduled
        _willUpdate = YES;
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(updateDelay * NSEC_PER_SEC)),
                       _query.database.queryQueue, ^{
            CBL_LOCK(self) {
                if (_willUpdate)
                    [self update];
            }
        });
    }
}


- (void) update {
    CBLQuery* strongQuery = _query;
    CBLLog(Query, @"%@: Querying...", self);
    NSError *error;
    CBLQueryResultSet* oldRs = _rs;
    CBLQueryResultSet* newRs;
    if (oldRs == nil)
        newRs = (CBLQueryResultSet*) [strongQuery execute: &error];
    else
        newRs = [oldRs refresh: &error];

    _willUpdate = false;
    _lastUpdatedAt = CFAbsoluteTimeGetCurrent();
    
    BOOL changed = YES;
    if (newRs) {
        if (oldRs)
            CBLLog(Query, @"%@: Changed!", self);
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


@end
