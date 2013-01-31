//
//  CBL_Server.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 11/30/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "CBL_DatabaseManager.h"


/** Thread-safe top-level interface to CouchbaseLite API.
    A CBL_Server owns a background thread on which it runs a CBL_DatabaseManager and all related tasks.
    The database objects can only be called by queueing blocks that will run on the background thread. */
@interface CBL_Server : NSObject
{
    @private
    CBL_DatabaseManager* _manager;
    NSThread* _serverThread;
    BOOL _stopRunLoop;
}

- (id) initWithDirectory: (NSString*)dirPath error: (NSError**)outError;

- (id) initWithDirectory: (NSString*)dirPath
                 options: (const CBL_DatabaseManagerOptions*)options
                   error: (NSError**)outError;

@property (readonly) NSString* directory;

- (void) queue: (void(^)())block;
- (void) tellDatabaseManager: (void (^)(CBL_DatabaseManager*))block;
- (void) tellDatabaseNamed: (NSString*)dbName to: (void (^)(CBL_Database*))block;
- (id) waitForDatabaseNamed: (NSString*)dbName to: (id (^)(CBL_Database*))block;

- (void) close;

@end
