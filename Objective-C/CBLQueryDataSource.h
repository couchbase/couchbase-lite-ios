//
//  CBLQueryDataSource.h
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
@class CBLQueryDatabase, CBLDatabase;


NS_ASSUME_NONNULL_BEGIN

/** 
 A query data source. used for specifiying the data source for your query.
 The current data source supported is the database.
 */
@interface CBLQueryDataSource : NSObject

/** 
 Create a database data source.
 
 @param database The database used as the data source as the query.
 @return The CBLQueryDatabase instance.
 */
+ (instancetype) database: (CBLDatabase*)database;

/** 
 Create a database data source with the given alias name.
 
 @param database The database used as the data source as the query.
 @alias The alias name of the data source.
 @return The CBLQueryDatabase instance.
 */
+ (instancetype) database: (CBLDatabase*)database as: (nullable NSString*)alias;

/** Not available. */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
