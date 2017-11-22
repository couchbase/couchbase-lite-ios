//
//  CBLLiveQuery.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/15/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLLiveQuery.h"
#import "CBLChangeListenerToken.h"
#import "CBLLog.h"
#import "CBLQuery.h"
#import "CBLQueryChange+Internal.h"
#import "CBLQuery+Internal.h"
#import "CBLQueryResultSet+Internal.h"


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
    
    NSMutableSet* _listenerTokens;
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
        
        __weak typeof(self) wSelf = self;
        _dbListenerToken = [db addChangeListener: ^(CBLDatabaseChange *change) {
            [wSelf databaseChanged: change];
        }];
    }
    _observing = YES;
    _rs = nil;
    [self update];
}


- (void) stop {
    if (_dbListenerToken) {
        [_query.database removeChangeListenerWithToken: _dbListenerToken];
        _dbListenerToken = nil;
    }
    _willUpdate = NO; // cancels the delayed update started by -databaseChanged
    _observing = NO;
}


- (nullable NSString*) explain: (NSError**)error {
    return [_query explain: error];
}


- (id<CBLListenerToken>) addChangeListenerWithQueue: (nullable dispatch_queue_t)queue
                                           listener: (void (^)(CBLQueryChange*))listener
{
    if (!_listenerTokens) {
        _listenerTokens = [NSMutableSet set];
    }
    
    id token = [[CBLChangeListenerToken alloc] initWithListener: listener
                                                          queue: queue];
    [_listenerTokens addObject: token];
    
    if (!_observing)
        [self start];
    
    return token;
}


- (void) removeChangeListenerWithToken: (id<NSObject>)listener {
    [_listenerTokens removeObject: listener];
}


#pragma mark Private


- (void) databaseChanged: (CBLDatabaseChange*)change {
    if (_willUpdate)
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


- (void) updateAfter: (NSTimeInterval)updateDelay {
    if (_willUpdate)
        return;  // Already a pending update scheduled
    _willUpdate = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(updateDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{        //FIX: Use a different queue
        if (_willUpdate)
            [self update];
    });
}


- (void) update {
    //TODO: Make this asynchronous (as in 1.x)
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
    
    if (changed)
        [self notifyChange: [[CBLQueryChange alloc] initWithQuery: strongQuery
                                                             rows: newRs
                                                            error: error]];
}


- (void) notifyChange: (CBLQueryChange*)change {
    for (CBLChangeListenerToken* token in _listenerTokens) {
        void (^listener)(CBLQueryChange*) = token.listener;
        dispatch_async(token.queue, ^{
            listener(change);
        });
    }
}


@end
