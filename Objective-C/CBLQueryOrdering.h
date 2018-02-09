//
//  CBLQueryOrdering.h
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
@class CBLQuerySortOrder, CBLQueryExpression;

NS_ASSUME_NONNULL_BEGIN

/** 
 A CBLQueryOrdering represents a single ordering component in the query ORDER BY clause. 
 */
@interface CBLQueryOrdering : NSObject

/** 
 Create a sort order instance with a given property name.
 
 @param name A propert name in key path format.
 @return A sort order instance.
 */
+ (CBLQuerySortOrder*) property: (NSString*)name;

/** 
 Create a sort order instance with a given expression.
 
 @param expression An expression instance.
 @return  A sort order instance.
 */
+ (CBLQuerySortOrder*) expression: (CBLQueryExpression*)expression;

- (instancetype) init NS_UNAVAILABLE;

@end

/** 
 CBLQuerySortOrder allows to specify the ordering direction which is an ascending or 
 a descending order
 */
@interface CBLQuerySortOrder : CBLQueryOrdering

/** 
 Create an ascending CBLQueryOrdering instance.
 
 @return An ascending CBLQueryOrdering instance.
 */
- (CBLQueryOrdering*) ascending;

/** 
 Create a descending CBLQueryOrdering instance.
 
 @return A descending CBLQueryOrdering instance.
 */
- (CBLQueryOrdering*) descending;

/** Not available. */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
