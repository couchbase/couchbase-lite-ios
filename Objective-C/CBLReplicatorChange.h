//
//  CBLReplicatorChange.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/28/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLReplicator;
@class CBLReplicatorStatus;

/** Replicator status change details. */
@interface CBLReplicatorChange : NSObject

/** The replicator. */
@property (nonatomic, readonly) CBLReplicator* replicator;

/** The changed status. */
@property (nonatomic, readonly) CBLReplicatorStatus* status;

@end
