//
//  TDServer.h
//  TouchDB
//
//  Created by Jens Alfke on 11/30/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class TDDatabase;


/** Manages a directory containing TDDatabases. */
@interface TDServer : NSObject
{
    @private
    NSString* _dir;
    NSMutableDictionary* _databases;
}

- (id) initWithDirectory: (NSString*)dirPath error: (NSError**)outError;

@property (readonly) NSString* directory;

- (TDDatabase*) databaseNamed: (NSString*)name;
- (TDDatabase*) existingDatabaseNamed: (NSString*)name;

- (BOOL) deleteDatabaseNamed: (NSString*)name;

@property (readonly) NSArray* allDatabaseNames;
@property (readonly) NSArray* allOpenDatabases;

- (void) close;

@end
