//
//  CBLReplicatorConfiguration+Swift.m
//  CouchbaseLite
//
//  Copyright (c) 2019 Couchbase, Inc All rights reserved.
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

#import "CBLReplicatorConfiguration+Swift.h"
#import "CBLConflictResolverBridge.h"

@implementation CBLReplicatorConfiguration (Swift)

- (void) setConflictResolverUsingBlock: (CBLConflictResolverBlock)block {
// TODO: Remove https://issues.couchbase.com/browse/CBL-3206
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

    if (block)
        self.conflictResolver = [[CBLConflictResolverBridge alloc] initWithResolverBlock: block];
    else
        self.conflictResolver = nil;
#pragma clang diagnostic pop
}

@end
