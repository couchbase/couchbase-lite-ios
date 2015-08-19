//
//  CBLProgressGroup.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/20/15.
//  Copyright © 2015 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>


// Key for NSProgress userInfo dictionary
#define kCBLProgressError @"CBLError"


/** Aggregates a set of NSProgress objects. */
@interface CBLProgressGroup : NSObject

- (instancetype) init;

- (BOOL) addProgress: (NSProgress*)progress;
- (void) addProgressGroup: (CBLProgressGroup*)group;

- (void) setIndeterminate;
- (void) setTotalUnitCount: (int64_t)total;
- (void) setCompletedUnitCount: (int64_t)completed;

- (void) finished;
- (void) failedWithError: (NSError*)error;

/** If set, will be called when the last child NSProgress is canceled. */
@property (copy) void (^cancellationHandler)(void);

@property (readonly) BOOL isCanceled;

@end
