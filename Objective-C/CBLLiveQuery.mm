//
//  CBLLiveQuery.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/15/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLLiveQuery.h"
#import "CBLQuery+Internal.h"
#import "CBLQueryEnumerator.h"
#import "CBLLog.h"
#import "c4.h"


// Default value of CBLLiveQuery.updateInterval
static const NSTimeInterval kDefaultLiveQueryUpdateInterval = 0.2;


@interface CBLLiveQuery ()
@property (readwrite, nullable, nonatomic) NSArray* rows;
@property (readwrite, nullable, nonatomic) NSError* lastError;
@end


@implementation CBLLiveQuery
{
    bool _observing, _willUpdate, _forceReload;
    NSUInteger _observerCount;
    CFAbsoluteTime _lastUpdatedAt;
    CBLQueryEnumerator* _enum;
    NSArray* _rows;
}


@synthesize lastError=_lastError, updateInterval=_updateInterval;


- (instancetype) initWithSelect: (CBLQuerySelect*)select
                       distinct: (BOOL)distinct
                           from: (CBLQueryDataSource*)from
                          where: (CBLQueryExpression*)where
                        orderBy: (CBLQueryOrderBy*)orderBy
{
    self = [super initWithSelect: select distinct: distinct from: from where: where orderBy: orderBy];
    if (self) {
        _updateInterval = kDefaultLiveQueryUpdateInterval;
    }
    return self;
}


- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}


- (void) start {
    if (!_observing) {
        _observing = YES;
        [[NSNotificationCenter defaultCenter] addObserver: self 
                                                 selector: @selector(databaseChanged:)
                                                     name: kCBLDatabaseChangeNotification 
                                                   object: self.database];
        [self update];
    }
}


- (void) stop {
    if (_observing) {
        _observing = NO;
        [[NSNotificationCenter defaultCenter] removeObserver: self];
    }
    _willUpdate = NO; // cancels the delayed update started by -databaseChanged
}


- (NSArray*) rows {
    [self start];
    return _rows;
}


- (void) setRows:(NSArray*)rows {
    _rows = rows;
}


- (void) addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath
             options:(NSKeyValueObservingOptions)options context:(void *)context
{
    if ([keyPath isEqualToString: @"rows"]) {
        if (++_observerCount == 1)
            [self start];
    }
    [super addObserver: observer forKeyPath: keyPath options: options context: context];
}


- (void) removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath {
    if ([keyPath isEqualToString: @"rows"]) {
        if (--_observerCount == 0)
            [self stop];
    }
    [super removeObserver: observer forKeyPath: keyPath];
}


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
    if (oldEnum == nil || _forceReload)
        newEnum = (CBLQueryEnumerator*) [self run: &error];
    else
        newEnum = [oldEnum refresh: &error];

    _willUpdate = _forceReload = false;
    _lastUpdatedAt = CFAbsoluteTimeGetCurrent();

    if (newEnum) {
        if (oldEnum)
            CBLLog(Query, @"%@: Changed!", self);
        _enum = newEnum;
        self.rows = newEnum.allObjects;     // triggers KVO
        error = nil;
    } else if (error == nil) {
        CBLLogVerbose(Query, @"%@: ...no change", self);
    } else {
        CBLWarnError(Query, @"%@: Update failed: %@", self, error.localizedDescription);
    }

    if (error || _lastError)
        self.lastError = error;             // triggers KVO
}


@end
