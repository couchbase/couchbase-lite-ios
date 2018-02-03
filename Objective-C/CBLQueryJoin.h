//
//  CBLQueryJoin.h
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
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
@class CBLQueryDataSource, CBLQueryExpression;

NS_ASSUME_NONNULL_BEGIN

/**
 A CBLQueryJoin represents the JOIN clause in the query statement.
 */
@interface CBLQueryJoin : NSObject

/** 
 Create a JOIN (same as INNER JOIN) component with the given data source and the on expression. 
 */
+ (instancetype) join: (CBLQueryDataSource*)dataSource on: (nullable CBLQueryExpression*)expression;

/** 
 Create a LEFT JOIN (same as LEFT OUTER JOIN) component with the given data source 
 and the on expression. 
 */
+ (instancetype) leftJoin: (CBLQueryDataSource*)dataSource on: (nullable CBLQueryExpression*)expression;

/** 
 Create a LEFT OUTER JOIN component with the given data source and the on expression.
 */
+ (instancetype) leftOuterJoin: (CBLQueryDataSource*)dataSource on: (nullable CBLQueryExpression*)expression;

/** 
 Create an INNER JOIN component with the given data source and the on expression. 
 */
+ (instancetype) innerJoin: (CBLQueryDataSource*)dataSource on: (nullable CBLQueryExpression*)expression;

/** 
 Create a CROSS JOIN component with the given data source and the on expression. 
 */
+ (instancetype) crossJoin: (CBLQueryDataSource*)dataSource;

/** Not available. */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
