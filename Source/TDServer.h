//
//  TDServer.h
//  TouchDB
//
//  Created by Jens Alfke on 11/30/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TDDatabaseManager.h"


/** Thread-safe top-level interface to TouchDB API.
    A TDServer owns a background thread on which it runs a TDDatabaseManager and all related tasks.
    The database objects can only be called by queueing blocks that will run on the background thread. */
@interface TDServer : NSObject
{
    @private
    TDDatabaseManager* _manager;
    NSThread* _serverThread;
    BOOL _stopRunLoop;
}

- (id) initWithDirectory: (NSString*)dirPath error: (NSError**)outError;

- (id) initWithDirectory: (NSString*)dirPath
                 options: (const TDDatabaseManagerOptions*)options
                   error: (NSError**)outError;

@property (readonly) NSString* directory;

- (void) queue: (void(^)())block;
- (void) tellDatabaseManager: (void (^)(TDDatabaseManager*))block;
- (void) tellDatabaseNamed: (NSString*)dbName to: (void (^)(TDDatabase*))block;

- (void) close;

@end


/** Starts a TDServer and registers it with TDURLProtocol so you can call it using the CouchDB-compatible REST API.
    @param serverDirectory  The top-level directory where you want the server to store databases. Will be created if it does not already exist.
    @param outError  An error will be stored here if the function returns nil.
    @return  The root URL of the REST API, or nil if the server failed to start. */
NSURL* TDStartServer(NSString* serverDirectory, NSError** outError);
