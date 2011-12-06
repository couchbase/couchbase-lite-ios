//
//  ToyPuller.h
//  ToyCouch
//
//  Created by Jens Alfke on 12/2/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "ToyReplicator.h"


/** Replicator that pulls from a remote CouchDB. */
@interface ToyPuller : ToyReplicator
{
    @private
    CouchChangeTracker* _changeTracker;
}

@end
