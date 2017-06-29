//
//  CBLReplicatorChange+Internal.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/28/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLReplicatorChange.h"
@class CBLReplicator;
@class CBLReplicatorStatus;

NS_ASSUME_NONNULL_BEGIN

@interface CBLReplicatorChange ()

- (instancetype) initWithReplicator: (CBLReplicator*)replicator
                             status: (CBLReplicatorStatus*)status;

@end

NS_ASSUME_NONNULL_END

