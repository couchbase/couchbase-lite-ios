//
//  CBLReplication+Internal.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 4/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLReplication.h"


extern C4LogDomain kCBLSyncLogDomain;


@interface CBLReplication ()

// Used by Swift bridge
@property (strong, nonatomic) id<CBLReplicationDelegate> delegateBridge;

@end
