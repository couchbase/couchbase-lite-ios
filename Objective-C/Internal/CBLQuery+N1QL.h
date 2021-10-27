//
//  CBLQuery+N1QL.h
//  CouchbaseLite
//
//  Copyright (c) 2021 Couchbase, Inc All rights reserved.
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

#import "CBLQuery.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLQuery ()

/**
 Encoded representation of the query. Can be used to re-create the query by calling
 -initWithDatabase:expressions:.
 */
@property (nonatomic, readonly) NSString* expressions;


/**
 Creates a query, given the N1QL string, as from the
 expression property.
 @param database  The database to query.
 @param expressions  String representing the query expression.
 */
- (nullable instancetype) initWithDatabase: (CBLDatabase*)database
                               expressions: (NSString*)expressions
                                     error: (NSError**)error NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
