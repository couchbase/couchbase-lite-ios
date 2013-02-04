//
//  CBLManager+Internal.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/22/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "CBLManager.h"
#import "CBLStatus.h"
@class CBL_Database, CBL_Replicator;


@interface CBLManager (Internal)

- (CBL_Database*) _databaseNamed: (NSString*)name;
- (CBL_Database*) _existingDatabaseNamed: (NSString*)name;

- (BOOL) _deleteDatabase: (CBL_Database*)db error: (NSError**)outError;

@property (readonly) NSArray* allOpenDatabases;

- (CBLStatus) validateReplicatorProperties: (NSDictionary*)properties;
- (CBL_Replicator*) replicatorWithProperties: (NSDictionary*)body
                                    status: (CBLStatus*)outStatus;

@end
