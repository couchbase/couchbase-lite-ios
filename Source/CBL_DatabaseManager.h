//
//  CBL_DatabaseManager.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/22/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLStatus.h"
@class CBL_Database, CBL_Replicator, CBL_ReplicatorManager;


typedef struct CBL_DatabaseManagerOptions {
    bool readOnly;
    bool noReplicator;
} CBL_DatabaseManagerOptions;

extern const CBL_DatabaseManagerOptions kCBL_DatabaseManagerDefaultOptions;


/** Manages a directory containing CBL_Databases. */
@interface CBL_DatabaseManager : NSObject 
{
    @private
    NSString* _dir;
    CBL_DatabaseManagerOptions _options;
    NSMutableDictionary* _databases;
    CBL_ReplicatorManager* _replicatorManager;
}

+ (BOOL) isValidDatabaseName: (NSString*)name;

+ (NSString*) defaultDirectory;

- (id) initWithDirectory: (NSString*)dirPath
                 options: (const CBL_DatabaseManagerOptions*)options
                   error: (NSError**)outError;

@property (readonly) NSString* directory;

- (CBL_Database*) databaseNamed: (NSString*)name;
- (CBL_Database*) existingDatabaseNamed: (NSString*)name;

- (BOOL) deleteDatabase: (CBL_Database*)db error: (NSError**)outError;

@property (readonly) NSArray* allDatabaseNames;
@property (readonly) NSArray* allOpenDatabases;

- (void) close;

- (CBLStatus) validateReplicatorProperties: (NSDictionary*)properties;
- (CBL_Replicator*) replicatorWithProperties: (NSDictionary*)body
                                    status: (CBLStatus*)outStatus;

@end
