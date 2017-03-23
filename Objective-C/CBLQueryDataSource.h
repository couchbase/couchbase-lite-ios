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

/** A query data source. used for specifiying the data source for your query. 
 The current data source supported is the database. */
@interface CBLQueryDataSource : NSObject

/** Create a database data source. */
+ (CBLQueryDatabase*) database: (CBLDatabase*)database;

/** Not available. */
- (instancetype) init NS_UNAVAILABLE;

@end

/** A database data source. You could also create an alias data source by calling 
 the -as: method with a given alias name. */
@interface CBLQueryDatabase : CBLQueryDataSource

/** Create an alias data source. */
- (CBLQueryDataSource*) as: (NSString*)as;

/** Not available. */
- (instancetype) init NS_UNAVAILABLE;

@end


NS_ASSUME_NONNULL_END


