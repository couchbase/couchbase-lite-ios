//
//  CBLReplicatorChange.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/28/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLReplicatorChange.h"
#import "CBLReplicator.h"
#import "CBLReplicatorChange+Internal.h"

@implementation CBLReplicatorChange

@synthesize replicator=_replicator, status=_status;

- (instancetype) initWithReplicator:(CBLReplicator *)replicator
                             status:(CBLReplicatorStatus *)status
{
    self = [super init];
    if (self) {
        _replicator = replicator;
        _status = status;
    }
    return self;
}

@end
