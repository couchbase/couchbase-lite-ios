//
//  CBLLiveQuery.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/15/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLLiveQuery+Internal.h"
#import "CBLLiveQueryChange+Internal.h"
#import "CBLChangeListener.h"
#import "CBLQuery+Internal.h"
#import "CBLQueryResultSet+Internal.h"
#import "CBLLog.h"


// Default value of CBLLiveQuery.updateInterval
static const NSTimeInterval kDefaultLiveQueryUpdateInterval = 0.2;

@implementation CBLLiveQuery
{
    CBLQuery* _query;
    NSTimeInterval _updateInterval;
    
    bool _observing, _willUpdate;
    CFAbsoluteTime _lastUpdatedAt;
    CBLQueryResultSet* _rs;
    id _dbChangeListener;
    
    NSMutableSet* _changeListeners;
}


- (instancetype) initWithQuery: (CBLQuery*)query {
    self = [super init];
    if (self) {
        _query = [query copy];
        
        // Note: We could make the updateInternal property public in the future
        _updateInterval = kDefaultLiveQueryUpdateInterval;
    }
    return self;
}


- (void) dealloc {
    [self stop];
}


- (CBLQueryParameters*) parameters {
    return _query.parameters;
}


- (void) start {
    if (!_dbChangeListener) {
        CBLDatabase* database = _query.database;
        Assert(database);
        
        __weak typeof(self) wSelf = self;
        _dbChangeListener = [database addChangeListener:^(CBLDatabaseChange *change) {
            [wSelf databaseChanged: change];
        }];
    }
    _rs = nil;
    [self update];
}


- (void) stop {
    if (_dbChangeListener) {
        [_query.database removeChangeListener: _dbChangeListener];
        _dbChangeListener = nil;
    }
    _willUpdate = NO; // cancels the delayed update started by -databaseChanged
}


- (nullable NSString*) explain: (NSError**)error {
    return [_query explain: error];
}


- (id<NSObject>) addChangeListener: (void (^)(CBLLiveQueryChange*))block {
    if (!_changeListeners) {
        _changeListeners = [NSMutableSet set];
    }
    
    CBLChangeListener* listener = [[CBLChangeListener alloc] initWithBlock: block];
    [_changeListeners addObject: listener];
    return listener;
}


- (void) removeChangeListener: (id<NSObject>)listener {
    [_changeListeners removeObject: listener];
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
    CBLLog(Query, @"%@: Querying...", self);
    NSError *error;
    CBLQueryResultSet* oldRs = _rs;
    CBLQueryResultSet* newRs;
    if (oldRs == nil)
        newRs = (CBLQueryResultSet*) [_query run: &error];
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
        [self notifyChange: [[CBLLiveQueryChange alloc] initWithQuery: self
                                                                 rows: newRs error: error]];
}


- (void) notifyChange: (CBLLiveQueryChange*)change {
    for (CBLChangeListener* listener in _changeListeners) {
        void (^block)(CBLLiveQueryChange*) = listener.block;
        block(change);
    }
}


@end
