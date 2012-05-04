//
//  TDServer.h
//  TouchDB
//
//  Created by Jens Alfke on 11/30/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class TDDatabase, TDDatabaseManager;


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

@property (readonly) NSString* directory;

- (void) queue: (void(^)())block;
- (void) tellDatabaseManager: (void (^)(TDDatabaseManager*))block;
- (void) tellDatabaseNamed: (NSString*)dbName to: (void (^)(TDDatabase*))block;

- (void) close;

@end
