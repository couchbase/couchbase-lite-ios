//
//  CBL_DatabaseManager.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/22/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLStatus.h"
#import "CBLManager.h"
@class CBL_Database, CBL_Replicator;

#ifndef CBL_DatabaseManager
#define CBL_DatabaseManager CBLManager  // class name CBL_DatabaseManager is being phased out
#endif


@interface CBL_DatabaseManager (Internal)

- (CBL_Database*) _databaseNamed: (NSString*)name;
- (CBL_Database*) _existingDatabaseNamed: (NSString*)name;

- (BOOL) _deleteDatabase: (CBL_Database*)db error: (NSError**)outError;

@property (readonly) NSArray* allOpenDatabases;

- (CBLStatus) validateReplicatorProperties: (NSDictionary*)properties;
- (CBL_Replicator*) replicatorWithProperties: (NSDictionary*)body
                                    status: (CBLStatus*)outStatus;

@end
