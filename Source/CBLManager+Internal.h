//
//  CBLManager+Internal.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/22/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import "CBLManager.h"
#import "CBLStatus.h"
@class CBLDatabase, CBL_Replicator, CBL_Shared;


@interface CBLManager ()


@property (copy, nonatomic) NSString* storageType;      // @"SQLite" (default) or @"ForestDB"

- (NSString*) nameOfDatabaseAtPath: (NSString*)path;

- (NSString*) pathForDatabaseNamed: (NSString*)name;

- (CBLDatabase*) _databaseNamed: (NSString*)name
                      mustExist: (BOOL)mustExist
                          error: (NSError**)outError;

- (void) _forgetDatabase: (CBLDatabase*)db;

@property (readonly) NSArray* allOpenDatabases;

@property (readonly) CBL_Shared* shared;

- (CBLStatus) validateReplicatorProperties: (NSDictionary*)properties;

/** Creates a new CBL_Replicator, or returns an existing active one if it has the same properties. */
- (CBL_Replicator*) replicatorWithProperties: (NSDictionary*)body
                                    status: (CBLStatus*)outStatus;

@end
