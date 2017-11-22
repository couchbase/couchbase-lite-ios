//
//  CBLChangeListenerToken.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/22/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLListenerToken.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLChangeListenerToken : NSObject <CBLListenerToken>

/**
 The listener block for posting changes.
 */
@property (nonatomic, readonly, copy) id listener;

/**
 The dispatch queue to post changes onto.
 */
@property (nonatomic, readonly) dispatch_queue_t queue;

/**
 Initialize with the given listener block and the dispatch queue.
 Without specifying the dispatch queue, the main queue will be used.

 @param listener The listener block.
 @param queue The dispatch queue.
 @return The CBLChangeListenerToken object.
 */
- (instancetype) initWithListener: (id)listener
                            queue: (nullable dispatch_queue_t)queue;

@end

NS_ASSUME_NONNULL_END
