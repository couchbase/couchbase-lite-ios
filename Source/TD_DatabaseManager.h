//
//  TD_DatabaseManager.h
//  TouchDB
//
//  Created by Jens Alfke on 3/22/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TDStatus.h"
@class TD_Database, TDReplicator, TDReplicatorManager;


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

- (id) initWithDirectory: (NSString*)dirPath
                 options: (const TD_DatabaseManagerOptions*)options
                   error: (NSError**)outError;

@property (readonly) NSString* directory;

- (TD_Database*) databaseNamed: (NSString*)name;
- (TD_Database*) existingDatabaseNamed: (NSString*)name;

- (BOOL) deleteDatabaseNamed: (NSString*)name;

@property (readonly) NSArray* allDatabaseNames;
@property (readonly) NSArray* allOpenDatabases;

- (void) close;

- (TDStatus) validateReplicatorProperties: (NSDictionary*)properties;
- (TDReplicator*) replicatorWithProperties: (NSDictionary*)body
                                    status: (TDStatus*)outStatus;

@end
