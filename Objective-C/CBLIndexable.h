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

#import <CouchbaseLite/CBLIndexConfiguration.h>
#import <CouchbaseLite/CBLIndex.h>

NS_ASSUME_NONNULL_BEGIN
/** The Indexable interface defines a set of functions for managing the query indexes. */
@protocol CBLIndexable <NSObject>

/** Return all index names, or nil if an error occurred. */
- (nullable NSArray<NSString*>*) indexes: (NSError**)error;

/** Create an index with the index name and config. */
- (BOOL) createIndexWithName: (NSString*)name
                      config: (CBLIndexConfiguration*)config
                       error: (NSError**)error;

/** Create an index with the index name and index. */
- (BOOL) createIndex: (CBLIndex*)index name: (NSString*)name error: (NSError**)error;

/** Delete an index by name. */
- (BOOL) deleteIndexWithName: (NSString*)name error: (NSError**)error;

@end

NS_ASSUME_NONNULL_END
