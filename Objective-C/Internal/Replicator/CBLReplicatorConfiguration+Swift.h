//
//  CBLReplicatorConfiguration+Swift.h
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

#import "CBLReplicatorConfiguration.h"
#import "CBLConflictResolver.h"


NS_ASSUME_NONNULL_BEGIN

typedef CBLDocument* __nullable (^CBLConflictResolverBlock)(CBLConflict*);

/**
 * As CBLConflictResolver definition will not be exposed to CBL Swift Public API,
 * defining a bridging resolver class in Swift could cause the Swift editor to crash.
 * The solution here is allow Swift ReplicatorConfiguration to set the conflict resolver
 * using a resolver block and CBLReplicatorConfiguration will create an internal bridging
 * conflict resolver that will call into the resolver block to get the result.
 */
@interface CBLReplicatorConfiguration (Swift)

- (void) setConflictResolverUsingBlock: (_Nullable CBLConflictResolverBlock)block;

@end

/**
 * Bridging Conflict Resolver for CBL Swift
 */
@interface CBLConflictResolverBridge: NSObject<CBLConflictResolver>

// set this resolver, which will be used while resolving the conflict
- (instancetype) initWithResolverBlock: (CBLConflictResolverBlock)resolver;

- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
