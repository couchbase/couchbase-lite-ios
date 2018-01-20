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

NS_ASSUME_NONNULL_BEGIN


@interface CBLReplicatorConfiguration ()
@property (readonly, nonatomic) NSDictionary* effectiveOptions;
@property (nonatomic) NSTimeInterval checkpointInterval;
@property (nonatomic) NSTimeInterval heartbeatInterval;
@end


@interface CBLReplicator ()

@end

NS_ASSUME_NONNULL_END
