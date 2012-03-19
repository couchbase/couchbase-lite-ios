//
//  TDServer.h
//  TouchDB
//
//  Created by Jens Alfke on 11/30/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class TDDatabase, TDReplicatorManager;


/** Manages a directory containing TDDatabases. */
@interface TDServer : NSObject
{
    @private
    NSString* _dir;
    NSMutableDictionary* _databases;
    TDReplicatorManager* _replicatorManager;
    NSOperationQueue* _dispatchQueue;
}

+ (BOOL) isValidDatabaseName: (NSString*)name;

- (id) initWithDirectory: (NSString*)dirPath error: (NSError**)outError;

@property (readonly) NSString* directory;

- (TDDatabase*) databaseNamed: (NSString*)name;
- (TDDatabase*) existingDatabaseNamed: (NSString*)name;

- (BOOL) deleteDatabaseNamed: (NSString*)name;

@property (readonly) NSArray* allDatabaseNames;
@property (readonly) NSArray* allOpenDatabases;

- (void) close;

- (void) queue: (void(^)())block;
- (void) tellDatabaseNamed: (NSString*)dbName to: (void (^)(TDDatabase*))block;

@end
