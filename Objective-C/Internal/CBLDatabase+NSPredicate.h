//
//  CBLDatabase+NSPredicate.h
//  CBL ObjC
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
#import "CBLDatabase.h"
@class CBLPredicateQuery;

NS_ASSUME_NONNULL_BEGIN

@interface CBLDatabase ()

/**
 Compiles a database query, from any of several input formats.
 Once compiled, the query can be run many times with different parameter values.
 The rows will be sorted by ascending document ID, and no custom values are returned.
 
 @param where The query specification. This can be an NSPredicate, or an NSString (interpreted
 as an NSPredicate format string), or nil to return all documents.
 @return The CBLQuery.
 */
- (CBLPredicateQuery*) createQueryWhere: (nullable id)where;

@end

NS_ASSUME_NONNULL_END
