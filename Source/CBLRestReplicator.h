//
//  CBLRestReplicator.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/6/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import "CBL_Replicator.h"

@class CBLBatcher, CBLRemoteRequest, CBLRemoteSession, MYBackgroundMonitor;


/** Abstract base class for push or pull replications. */
@interface CBLRestReplicator : NSObject <CBL_Replicator>

#if DEBUG
@property (readonly) BOOL running, active; // for unit tests
#endif

@end
