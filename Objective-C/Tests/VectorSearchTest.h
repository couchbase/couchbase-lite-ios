//
//  VectorIndexTest.h
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

#import "CBLTestCase.h"

#ifdef COUCHBASE_ENTERPRISE

NS_ASSUME_NONNULL_BEGIN

#define kWordsDatabaseName @"words_db"

#define kWordsCollectionName @"words"

#define kExtWordsCollectionName @"extwords"

#define kWordsIndexName @"words_index"

#define kWordPredictiveModelName @"WordEmbedding"

#define VECTOR_INDEX_CONFIG(E, D, C) [[CBLVectorIndexConfiguration alloc] initWithExpression: (E) dimensions: (D) centroids: (C)]

@interface VectorSearchTest : CBLTestCase

@property (nonatomic, readonly) CBLDatabase* wordDB;

@property (nonatomic, readonly) CBLCollection* wordsCollection;

@property (nonatomic, readonly) CBLCollection* extWordsCollection;

- (void) createVectorIndexInCollection: (CBLCollection*)collection
                                  name: (NSString*)name
                                config: (CBLVectorIndexConfiguration*)config;

- (void) createWordsIndexWithConfig: (CBLVectorIndexConfiguration*)config;

- (void) deleteWordsIndex;

- (NSString*) wordsQueryStringWithLimit: (nullable NSNumber*)limit
                              andClause: (nullable NSString*)andClause;

- (CBLQueryResultSet*) executeWordsQueryWithLimit: (nullable NSNumber*)limit
                                        andClause: (nullable NSString*)andClause
                                    checkTraining: (BOOL) checkTraining;

- (CBLQueryResultSet*) executeWordsQueryWithLimit: (nullable NSNumber*)limit;

- (CBLQueryResultSet*) executeWordsQueryNoTrainingCheckWithLimit: (nullable NSNumber*)limit;

- (NSDictionary<NSString*, NSString*>*) toDocIDWordMap: (CBLQueryResultSet*)resultSet;

@end

NS_ASSUME_NONNULL_END

#endif
