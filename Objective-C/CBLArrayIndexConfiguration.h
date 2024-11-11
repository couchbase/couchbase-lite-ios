//
//  CBLArrayIndexConfiguration.h
//  CouchbaseLite
//
//  Copyright (c) 2024 Couchbase, Inc All rights reserved.
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
 Configuration for indexing property values within nested arrays in documents, 
 intended for use with the UNNEST query.
 */

@interface CBLArrayIndexConfiguration : CBLIndexConfiguration

/**
 Path to the array, which can be nested.
 */

@property (nonatomic, readonly) NSString* path;

/**
 The expressions representing the values within the array to be indexed.
 */

@property (nonatomic, readonly, nullable) NSArray<NSString*>* expressions;

/**
 Initializes the configuration with paths to the nested array
 and the optional expressions for the values within the arrays to be indexed.
 @param path Path to the array, which can be nested to be indexed.
 @note Use "[]" to represent a property that is an array of each nested
 array level. For a single array or the last level array, the "[]" is optional.
 
 For instance, use "contacts[].phones" to specify an array of phones within
 each contact.
 @param expressions An optional array of strings, where each string
 represents an expression defining the values within the array
 to be indexed. If the array specified by the path contains
 scalar values, this parameter can be null.
 
 @return The CBLArrayIndexConfiguration object.
 */

- (instancetype) initWithPath: (NSString*)path
                  expressions: (nullable NSArray<NSString*>*)expressions;

@end

NS_ASSUME_NONNULL_END
