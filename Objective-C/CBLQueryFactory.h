//
//  CBLQueryFactory.h
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

@class CBLQuery;

NS_ASSUME_NONNULL_BEGIN

/** The QueryFactory interface defines a function for creating a query from the given SQL string. */
@protocol CBLQueryFactory <NSObject>

/**
 Create a query object from an SQL string.
 
 @param query Query expression
 @param error On return, the error if any., the given query string is invalid(e.g., syntax error).
 @return query created using the given expression string, or nil if an error occurred.
 */
- (nullable CBLQuery*) createQuery: (NSString*)query error: (NSError**)error;

@end

NS_ASSUME_NONNULL_END
