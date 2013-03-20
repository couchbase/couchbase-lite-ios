//
//  CBL_Server.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 11/30/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "CBLManager+Internal.h"


/** Thread-safe top-level interface to CouchbaseLite API.
    A CBL_Server owns a background thread on which it runs a CBLManager and all related tasks.
    The database objects can only be called by queueing blocks that will run on the background thread. */
@interface CBL_Server : NSObject
{
    @private
    CBLManager* _manager;
    NSThread* _serverThread;
    BOOL _stopRunLoop;
}

- (instancetype) initWithManager: (CBLManager*)newManager;

@property (readonly) NSString* directory;

- (void) queue: (void(^)())block;
- (void) tellDatabaseManager: (void (^)(CBLManager*))block;
- (void) tellDatabaseNamed: (NSString*)dbName to: (void (^)(CBLDatabase*))block;
- (id) waitForDatabaseNamed: (NSString*)dbName to: (id (^)(CBLDatabase*))block;

- (void) close;

@end
