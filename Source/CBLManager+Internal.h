//
//  CBLManager+Internal.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/22/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "CBLManager.h"
#import "CBLStatus.h"
@class CBLDatabase, CBL_Replicator, CBL_Shared;


@interface CBLManager (Internal)

- (CBLDatabase*) _databaseNamed: (NSString*)name
                      mustExist: (BOOL)mustExist
                          error: (NSError**)outError;

- (void) _forgetDatabase: (CBLDatabase*)db;

@property (readonly) NSArray* allOpenDatabases;

@property (readonly) CBL_Shared* shared;

- (CBLStatus) validateReplicatorProperties: (NSDictionary*)properties;
- (CBL_Replicator*) replicatorWithProperties: (NSDictionary*)body
                                    status: (CBLStatus*)outStatus;

@end
