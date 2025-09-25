//
//  CBLCollectionConfiguration+Internal.h
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

#pragma once
#import "CBLCollectionConfiguration.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLCollectionConfiguration ()

- (instancetype) initWithConfig: (CBLCollectionConfiguration*)config;

- (NSDictionary*) effectiveOptions;

/**
 Creates an array of `CBLCollectionConfiguration` objects from the given collections with the same configuration closure.

 This is a convenience method for configuring multiple collections with the same configurations.
 If custom configurations are needed, construct `CBLCollectionConfiguration` objects
 directly instead.
       
 @param collections The collections to replicate.
 @param config A block to configure all `CBLCollectionConfiguration` object.
 @return An array of CBLCollectionConfiguration objects for the given collections.
 */
+ (NSArray<CBLCollectionConfiguration*>*) fromCollections: (NSArray<CBLCollection*>*)collections
                                                   config: (void (^)(CBLCollectionConfiguration* config))config;

@end

NS_ASSUME_NONNULL_END
