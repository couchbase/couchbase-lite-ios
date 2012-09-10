//
//  TDDatabaseManager.h
//  TouchDB
//
//  Created by Jens Alfke on 3/22/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class TDDatabase, TDReplicatorManager;


typedef struct TDDatabaseManagerOptions {
    bool readOnly;
    bool noReplicator;
} TDDatabaseManagerOptions;

extern const TDDatabaseManagerOptions kTDDatabaseManagerDefaultOptions;


/** Manages a directory containing TDDatabases. */
@interface TDDatabaseManager : NSObject 
{
    @private
    NSString* _dir;
    TDDatabaseManagerOptions _options;
    NSMutableDictionary* _databases;
    TDReplicatorManager* _replicatorManager;
}

+ (BOOL) isValidDatabaseName: (NSString*)name;

- (id) initWithDirectory: (NSString*)dirPath
                 options: (const TDDatabaseManagerOptions*)options
                   error: (NSError**)outError;

@property (readonly) NSString* directory;

- (TDDatabase*) databaseNamed: (NSString*)name;
- (TDDatabase*) existingDatabaseNamed: (NSString*)name;

- (BOOL) deleteDatabaseNamed: (NSString*)name;

@property (readonly) NSArray* allDatabaseNames;
@property (readonly) NSArray* allOpenDatabases;

- (void) close;

@end
