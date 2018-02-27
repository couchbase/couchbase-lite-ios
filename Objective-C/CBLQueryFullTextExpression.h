//
//  CBLQueryFullTextExpression.h
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
 Full-text expression.
 */
@interface CBLQueryFullTextExpression : NSObject

/**
 Creates a full-text expression with the given full-text index name.

 @param name The full-text index name.
 @return The full-text expression.
 */
+ (CBLQueryFullTextExpression*) indexWithName: (NSString*)name;


/**
 Creates a full-text match expression with the given search text.

 @param query The query string.
 @return The full-text match expression.
 */
- (CBLQueryExpression*) match: (NSString*)query;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
