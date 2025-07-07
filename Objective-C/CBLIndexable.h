//
//  CBLIndexable.h
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

#import <Foundation/Foundation.h>

@class CBLIndex;
@class CBLIndexConfiguration;
@class CBLQueryIndex;

NS_ASSUME_NONNULL_BEGIN

/** The Indexable interface defines a set of functions for managing the query indexes. */
@protocol CBLIndexable <NSObject>

/**
 Get the names of all indexes of the collection.
 
 @param error On return, the error if any.
 @return Names of all indexes of the collection or nil if no indexes exist.
 */
- (nullable NSArray<NSString*>*) indexes: (NSError**)error;

/**
 Create an index with the index name and config.
 
 @param name The index name.
 @param config The index configuration.
 @param error On return, the error if any.
 @return True if index is created successfully, otherwise false.
 */
- (BOOL) createIndexWithName: (NSString*)name
                      config: (CBLIndexConfiguration*)config
                       error: (NSError**)error;

/**
 Create an index with the index name and index.
 
 @param index The index instance.
 @param name The index name.
 @param error On return, the error if any.
 @return True if index is created successfully, otherwise false.
 @note To be used with Index Builder
 */
- (BOOL) createIndex: (CBLIndex*)index name: (NSString*)name error: (NSError**)error;

/**
 Delete an index by name.
 
 @param name The index name.
 @param error On return, the error if any.
 @return True if index is deleted successfully, otherwise false.
 */
- (BOOL) deleteIndexWithName: (NSString*)name error: (NSError**)error;

/**
 Get an index object by name.
 
 @param name The index name.
 @param error On return, the error if any.
 @return The index object or nil.
 */
- (nullable CBLQueryIndex*) indexWithName: (NSString*)name
                                    error: (NSError**)error NS_SWIFT_NOTHROW;

@end

NS_ASSUME_NONNULL_END
