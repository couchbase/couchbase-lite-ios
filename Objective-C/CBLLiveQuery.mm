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
#import "CBLQueryEnumerator.h"
#import "CBLLog.h"


// Default value of CBLLiveQuery.updateInterval
static const NSTimeInterval kDefaultLiveQueryUpdateInterval = 0.2;

@implementation CBLLiveQuery
{
    CBLQuery* _query;
    NSTimeInterval _updateInterval;
    
    bool _observing, _willUpdate;
    CFAbsoluteTime _lastUpdatedAt;
    CBLQueryEnumerator* _enum;
    
    NSMutableSet* _changeListeners;
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
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}


- (void) run {
    if (!_observing) {
        _observing = YES;
        [[NSNotificationCenter defaultCenter] addObserver: self 
                                                 selector: @selector(databaseChanged:)
                                                     name: kCBLDatabaseChangeNotification 
                                                   object: _query.database];
    }
    _enum = nil;
    [self update];
}


- (void) stop {
    if (_observing) {
        _observing = NO;
        [[NSNotificationCenter defaultCenter] removeObserver: self];
    }
    _willUpdate = NO; // cancels the delayed update started by -databaseChanged
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


- (void) databaseChanged: (NSNotification*)n {
    if (_willUpdate)
        return;  // Already a pending update scheduled

    // Use double the update interval if this is a remote change (coming from a pull replication):
    NSTimeInterval updateInterval = _updateInterval;
    
    CBLDatabaseChange* change = n.userInfo[kCBLDatabaseChangesUserInfoKey];
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
    CBLQueryEnumerator* oldEnum = _enum;
    CBLQueryEnumerator* newEnum;
    if (oldEnum == nil)
        newEnum = (CBLQueryEnumerator*) [_query run: &error];
    else
        newEnum = [oldEnum refresh: &error];

    _willUpdate = false;
    _lastUpdatedAt = CFAbsoluteTimeGetCurrent();
    
    BOOL changed = YES;
    if (newEnum) {
        if (oldEnum)
            CBLLog(Query, @"%@: Changed!", self);
        _enum = newEnum;
    } else if (error != nil) {
        CBLWarnError(Query, @"%@: Update failed: %@", self, error.localizedDescription);
    } else {
        changed = NO;
        CBLLogVerbose(Query, @"%@: ...no change", self);
    }
    
    if (changed)
        [self notifyChange: [[CBLLiveQueryChange alloc] initWithQuery: self
                                                                 rows: newEnum error: error]];
}


- (void) notifyChange: (CBLLiveQueryChange*)change {
    for (CBLChangeListener* listener in _changeListeners) {
        void (^block)(CBLLiveQueryChange*) = listener.block;
        block(change);
    }
}


@end
