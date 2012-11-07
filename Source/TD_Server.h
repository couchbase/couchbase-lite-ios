//
//  TD_Server.h
//  TouchDB
//
//  Created by Jens Alfke on 11/30/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TD_DatabaseManager.h"


/** Thread-safe top-level interface to TouchDB API.
    A TD_Server owns a background thread on which it runs a TD_DatabaseManager and all related tasks.
    The database objects can only be called by queueing blocks that will run on the background thread. */
@interface TD_Server : NSObject
{
    @private
    TD_DatabaseManager* _manager;
    NSThread* _serverThread;
    BOOL _stopRunLoop;
}

- (id) initWithDirectory: (NSString*)dirPath error: (NSError**)outError;

- (id) initWithDirectory: (NSString*)dirPath
                 options: (const TD_DatabaseManagerOptions*)options
                   error: (NSError**)outError;

@property (readonly) NSString* directory;

- (void) queue: (void(^)())block;
- (void) tellDatabaseManager: (void (^)(TD_DatabaseManager*))block;
- (void) tellDatabaseNamed: (NSString*)dbName to: (void (^)(TD_Database*))block;
- (id) waitForDatabaseNamed: (NSString*)dbName to: (id (^)(TD_Database*))block;

- (void) close;

@end
