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
- (id) waitForDatabaseManager: (id (^)(TD_DatabaseManager*))block;

- (void) close;

@end


/** Starts a TD_Server and registers it with TDURLProtocol so you can call it using the CouchDB-compatible REST API.
    @param serverDirectory  The top-level directory where you want the server to store databases. Will be created if it does not already exist.
    @param outError  An error will be stored here if the function returns nil.
    @return  The root URL of the REST API, or nil if the server failed to start. */
NSURL* TDStartServer(NSString* serverDirectory, NSError** outError);
