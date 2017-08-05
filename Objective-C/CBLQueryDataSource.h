//
//  CBLQueryDataSource.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
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
