//
//  CBLQueryLimit.h
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
@class CBLQueryExpression;

NS_ASSUME_NONNULL_BEGIN

/** 
 A CBLQueryLimit represents a query LIMIT clause used for constrainting the number of results
 returned by a query.
 */
@interface CBLQueryLimit : NSObject

/**
  Create a LIMIT component to limit the number of results to not more than the given limit value.
 */
+ (CBLQueryLimit*) limit: (CBLQueryExpression*)expression;

/** 
 Create a LIMIT component to skip the returned results for the given offset position
 and to limit the number of results to not more than the given limit value.
 */
+ (CBLQueryLimit*) limit: (CBLQueryExpression*)expression offset: (nullable CBLQueryExpression*)expression;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
