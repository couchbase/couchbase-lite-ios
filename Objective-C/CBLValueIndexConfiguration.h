//
//  CBLValueIndexConfiguration.h
//  CouchbaseLite
//
//  Copyright (c) 2025 Couchbase, Inc All rights reserved.
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

#import <Foundation/Foundation.h>
#import <CouchbaseLite/CBLIndexConfiguration.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Configuration for creating value indexes.
 */
@interface CBLValueIndexConfiguration : CBLIndexConfiguration

/**
 A predicate expression defining conditions for indexing documents.
 Only documents satisfying the predicate are included, enabling partial indexes.
 */
@property (nonatomic, readonly, nullable) NSString* where;

/**
 Initializes a value index by using an array of expression strings.
 @param expressions The array of expression strings.
 @return The value index configuration object.
 */
- (instancetype) initWithExpression: (NSArray<NSString*>*)expressions;

/**
 Initializes a value index with an array of expression strings and an optional where clause for a partial index.
 @param expressions The array of expression strings.
 @param where Optional where clause for partial indexing.
 @return The value index configuration object.
 */
- (instancetype) initWithExpression: (NSArray<NSString*>*)expressions
                              where: (nullable NSString*)where;

@end

NS_ASSUME_NONNULL_END
