//
//  CBLDatabaseEndpoint.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/9/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLEndpoint.h"
@class CBLDatabase;


/**
 Database based replication target endpoint.
 */
@interface CBLDatabaseEndpoint : NSObject <CBLEndpoint>

/** The database object. */
@property (readonly, nonatomic) CBLDatabase* database;

/**
 Initializes with the database object.

 @param database The database object.
 @return The CBLDatabaseEndpoint object.
 */
- (instancetype) initWithDatabase: (CBLDatabase*)database;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end
