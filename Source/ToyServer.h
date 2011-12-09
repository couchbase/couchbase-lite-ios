//
//  ToyServer.h
//  ToyCouch
//
//  Created by Jens Alfke on 11/30/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class ToyDB;


/** Manages a directory containing ToyDBs. */
@interface ToyServer : NSObject
{
    @private
    NSString* _dir;
    NSMutableDictionary* _databases;
}

- (id) initWithDirectory: (NSString*)dirPath error: (NSError**)outError;

@property (readonly) NSString* directory;

- (ToyDB*) databaseNamed: (NSString*)name;

- (BOOL) deleteDatabaseNamed: (NSString*)name;

@property (readonly) NSArray* allDatabaseNames;

- (void) close;

#if DEBUG
+ (ToyServer*) createEmptyAtPath: (NSString*)path;  // for testing
#endif

@end
