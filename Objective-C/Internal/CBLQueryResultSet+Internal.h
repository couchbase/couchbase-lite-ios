//
//  CBLQueryResultSet+Internal.h
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

#import "CBLQueryResultSet.h"
#import "c4.h"
@class CBLDatabase, CBLQuery;

NS_ASSUME_NONNULL_BEGIN

@interface CBLQueryResultSet ()

- (instancetype) initWithQuery: (CBLQuery*)query
                       c4Query: (C4Query*)c4Query
                    enumerator: (C4QueryEnumerator*)e
                   columnNames: (NSDictionary*)columnNames;

@property (nonatomic, readonly) CBLDatabase* database;
@property (nonatomic, readonly) C4Query* c4Query;
@property (nonatomic, readonly) NSDictionary* columnNames;

- (id) objectAtIndex: (NSUInteger)index;

// If query results have changed, returns a new enumerator, else nil.
- (nullable CBLQueryResultSet*) refresh: (NSError**)outError;

@end

NS_ASSUME_NONNULL_END
