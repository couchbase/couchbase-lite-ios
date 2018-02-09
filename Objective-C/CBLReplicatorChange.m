//
//  CBLReplicatorChange.m
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
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
