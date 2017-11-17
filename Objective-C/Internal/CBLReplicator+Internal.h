//
//  CBLReplicator+Internal.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 4/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLReplicator.h"
#import "CBLReplicatorConfiguration.h"
#import "c4.h"
@class MYBackgroundMonitor;

NS_ASSUME_NONNULL_BEGIN


@interface CBLReplicatorConfiguration ()
@property (readonly, nonatomic) NSDictionary* effectiveOptions;
@property (nonatomic) NSTimeInterval checkpointInterval;
@end


@interface CBLReplicator () {
    BOOL _deepBackground;
    BOOL _filesystemUnavailable;
}

@property (nonatomic, readonly) dispatch_queue_t dispatchQueue;
@property (atomic) CBLReplicatorStatus* status;
@property (nonatomic) MYBackgroundMonitor* bgMonitor;
@property (nonatomic, readonly) BOOL isActive;
@property (nonatomic) BOOL suspended;
@end

NS_ASSUME_NONNULL_END
