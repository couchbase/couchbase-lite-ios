//
//  CBLReplicatorStatus+Internal.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/1/25.
//  Copyright © 2025 Couchbase. All rights reserved.
//

#import "CBLReplicatorStatus.h"
#import "c4ReplicatorTypes.h"

@interface CBLReplicatorStatus ()
- (instancetype) initWithStatus: (C4ReplicatorStatus)c4Status;
@end
