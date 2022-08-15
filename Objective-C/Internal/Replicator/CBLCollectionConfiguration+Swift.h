//
//  CBLCollectionConfiguration+Swift.h
//  CouchbaseLite
//
//  Copyright (c) 2022 Couchbase, Inc All rights reserved.
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

#import "CBLCollectionConfiguration.h"
#import "CBLConflictResolver.h"
#import "CBLConflictResolverBridge.h"

NS_ASSUME_NONNULL_BEGIN

typedef CBLDocument* __nullable (^CBLConflictResolverBlock)(CBLConflict*);

/**
 * As CBLConflictResolver definition will not be exposed to CBL Swift Public API,
 * defining a bridging resolver class in Swift could cause the Swift editor to crash.
 * The solution here is allow Swift CollectionConfiguration to set the conflict resolver
 * using a resolver block and CBLCollectionConfiguration will create an internal bridging
 * conflict resolver that will call into the resolver block to get the result.
 */
@interface CBLCollectionConfiguration (Swift)

- (void) setConflictResolverUsingBlock: (_Nullable CBLConflictResolverBlock)block;

@end

NS_ASSUME_NONNULL_END
