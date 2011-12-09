//
//  TDPuller.h
//  TouchDB
//
//  Created by Jens Alfke on 12/2/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TDReplicator.h"


/** Replicator that pulls from a remote CouchDB. */
@interface TDPuller : TDReplicator
{
    @private
    TDChangeTracker* _changeTracker;
}

@end
