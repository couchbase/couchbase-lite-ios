//
//  CBLProgressGroup.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/20/15.
//  Copyright © 2015 Couchbase, Inc. All rights reserved.
//

#import "CBLProgressGroup.h"
#import "MYBlockUtils.h"


#define kProgressInterval 0.25


@implementation CBLProgressGroup
{
    NSMutableArray* _progresses;
    int64_t _completed, _total;
    void (^_noteProgress)();
}
@synthesize cancellationHandler=_cancellationHandler;


- (instancetype) init {
    self = [super init];
    if (self) {
        _progresses = [NSMutableArray new];
        _completed = _total = -1;
        _noteProgress = MYThrottledBlock(kProgressInterval, ^{
            [self _updateProgresses];
        });
    }
    return self;
}


- (BOOL) addProgress: (NSProgress*)progress {
    if (progress.isCancelled)
        return NO;
    if (![_progresses containsObject: progress]) {
        [_progresses addObject: progress];
        progress.completedUnitCount = _completed;
        progress.totalUnitCount = _total;

        __weak CBLProgressGroup* weakSelf = self;
        __weak NSProgress* weakProgress = progress;
        progress.cancellationHandler = ^{
            [weakSelf removeProgress: weakProgress];
        };
        progress.cancellable = YES;
    }
    return YES;
}


- (void) removeProgress: (NSProgress*)progress {
    if (!progress)
        return;
    [_progresses removeObject: progress];
    if (_progresses.count == 0) {
        void (^handler)() = _cancellationHandler;
        _cancellationHandler = nil;
        if (handler)
            handler();
    }
}


- (void) addProgressGroup: (CBLProgressGroup*)group {
    Assert(group);
    if (group != self) {
        for (NSProgress* progress in group->_progresses)
            [self addProgress: progress];
        [group->_progresses removeAllObjects];
    }
}


- (BOOL) isCanceled {
    return _progresses.count == 0;
}


- (void) _updateProgresses {
    for (NSProgress* progress in _progresses) {
        progress.totalUnitCount = _total;
        progress.completedUnitCount = _completed;
    }
}


- (void) setCompletedUnitCount: (int64_t)completed {
    completed = MIN(completed, _total-1);   // don't allow _completed to equal _total yet
    _completed = completed;
    __typeof(_noteProgress) noteProgress = _noteProgress;
    noteProgress();
}

- (void) setTotalUnitCount: (int64_t)total {
    _total = total;
    _completed = MAX(_completed, 0);
    [self _updateProgresses];
}


- (void) setIndeterminate {
    _completed = _total = -1;
    [self _updateProgresses];
}


- (void) finished {
    _completed = _total = MAX(_total, 0);
    [self _updateProgresses];
}


- (void) failedWithError: (NSError*)error {
    for (NSProgress* progress in _progresses)
        [progress setUserInfoObject: error forKey: kCBLProgressError];
}


@end
