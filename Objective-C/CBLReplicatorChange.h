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

@interface CBLReplicatorChange : NSObject

@property (nonatomic, readonly) CBLReplicator* replicator;

@property (nonatomic, readonly) CBLReplicatorStatus* status;

@end
