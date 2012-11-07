//
//  TD_DatabaseManager.h
//  TouchDB
//
//  Created by Jens Alfke on 3/22/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class TD_Database, TDReplicatorManager;


typedef struct TD_DatabaseManagerOptions {
    bool readOnly;
    bool noReplicator;
} TD_DatabaseManagerOptions;

extern const TD_DatabaseManagerOptions kTD_DatabaseManagerDefaultOptions;


/** Manages a directory containing TD_Databases. */
@interface TD_DatabaseManager : NSObject 
{
    @private
    NSString* _dir;
    TD_DatabaseManagerOptions _options;
    NSMutableDictionary* _databases;
    TDReplicatorManager* _replicatorManager;
}

+ (BOOL) isValidDatabaseName: (NSString*)name;

+ (NSString*) defaultDirectory;

- (id) initWithDirectory: (NSString*)dirPath
                 options: (const TD_DatabaseManagerOptions*)options
                   error: (NSError**)outError;

@property (readonly) NSString* directory;

- (TD_Database*) databaseNamed: (NSString*)name;
- (TD_Database*) existingDatabaseNamed: (NSString*)name;

- (BOOL) deleteDatabase: (TD_Database*)db error: (NSError**)outError;

@property (readonly) NSArray* allDatabaseNames;
@property (readonly) NSArray* allOpenDatabases;

- (void) close;

@end
