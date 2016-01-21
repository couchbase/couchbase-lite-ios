//
//  CBLManager+Internal.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/22/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import "CBLManager.h"
#import "CBLStatus.h"
@class CBLDatabase, CBL_Shared, CBL_ReplicatorSettings, CBLSymmetricKey;
@protocol CBL_Replicator;


@interface CBLManager ()

@property (copy, nonatomic) NSString* replicatorClassName;  // defaults to "CBLRestReplicator"
@property (readonly) Class replicatorClass;


- (NSString*) nameOfDatabaseAtPath: (NSString*)path;

- (NSString*) pathForDatabaseNamed: (NSString*)name;

- (CBLDatabase*) _databaseNamed: (NSString*)name
                      mustExist: (BOOL)mustExist
                          error: (NSError**)outError;

- (void) _forgetDatabase: (CBLDatabase*)db;

- (CBLDatabaseOptions*) defaultOptionsForDatabaseNamed: (NSString*)name;

- (BOOL) _closeDatabaseNamed: (NSString*)name
                       error: (NSError**)outError;

@property (readonly) NSArray* allOpenDatabases;

@property (readonly) CBL_Shared* shared;

- (CBLStatus) validateReplicatorProperties: (NSDictionary*)properties;

/** Creates a new CBL_Replicator, or returns an existing active one if it has the same properties. */
- (id<CBL_Replicator>) replicatorWithProperties: (NSDictionary*)body
                                    status: (CBLStatus*)outStatus;

/** Get a replicator settings from a given property. */
- (CBL_ReplicatorSettings*) replicatorSettingsWithProperties: (NSDictionary*)body
                                                  toDatabase: (CBLDatabase**)outDatabase // may be NULL
                                                      status: (CBLStatus*)outStatus;

@end
