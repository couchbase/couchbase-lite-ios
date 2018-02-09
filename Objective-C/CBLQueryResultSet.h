//
//  CBLQueryResultSet.h
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
@class CBLQueryResult;

/** 
 CBLQueryResultSet is a result returned from a query. The CBLQueryResultSet is
 an NSEnumerator of the CBLQueryResult objects, each of which represent
 a single row in the query result.
 */
@interface CBLQueryResultSet : NSEnumerator<CBLQueryResult*>

/**
 All unenumerated results.

 @return An array of all unenumerated Result objects.
 */
- (NSArray<CBLQueryResult*>*) allResults;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end
