//
//  TDDatabaseManager.h
//  TouchDB
//
//  Created by Jens Alfke on 3/22/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class TDDatabase, TDReplicatorManager;


/** Manages a directory containing TDDatabases. */
@interface TDDatabaseManager : NSObject 
{
    @private
    NSString* _dir;
    BOOL _readOnly;
    NSMutableDictionary* _databases;
    TDReplicatorManager* _replicatorManager;
}

+ (BOOL) isValidDatabaseName: (NSString*)name;

- (id) initWithDirectory: (NSString*)dirPath error: (NSError**)outError;

@property (readonly) NSString* directory;

@property (nonatomic) BOOL readOnly;

- (TDDatabase*) databaseNamed: (NSString*)name;
- (TDDatabase*) existingDatabaseNamed: (NSString*)name;

- (BOOL) deleteDatabaseNamed: (NSString*)name;

@property (readonly) NSArray* allDatabaseNames;
@property (readonly) NSArray* allOpenDatabases;

- (void) close;

@end
