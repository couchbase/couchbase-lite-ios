//
//  CBL_Server.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 11/30/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBL_Server.h"
#import "CBL_Database.h"
#import "CBL_ReplicatorManager.h"
#import "CBLMisc.h"
#import "CBL_DatabaseManager.h"
#import "CBLInternal.h"
#import "CBL_URLProtocol.h"
#import "MYBlockUtils.h"


@implementation CBL_Server


#if DEBUG
+ (CBL_Server*) createEmptyAtPath: (NSString*)path {
    [[NSFileManager defaultManager] removeItemAtPath: path error: NULL];
    NSError* error;
    CBL_Server* server = [[self alloc] initWithDirectory: path error: &error];
    Assert(server, @"Failed to create server at %@: %@", path, error);
    AssertEqual(server.directory, path);
    return server;
}

+ (CBL_Server*) createEmptyAtTemporaryPath: (NSString*)name {
    return [self createEmptyAtPath: [NSTemporaryDirectory() stringByAppendingPathComponent: name]];
}
#endif


- (id) initWithDirectory: (NSString*)dirPath
                 options: (const CBL_DatabaseManagerOptions*)options
                   error: (NSError**)outError
{
    if (outError) *outError = nil;
    self = [super init];
    if (self) {
        _manager = [[CBL_DatabaseManager alloc] initWithDirectory: dirPath
                                                        options: options
                                                          error: outError];
        if (!_manager) {
            return nil;
        }
        
        _serverThread = [[NSThread alloc] initWithTarget: self
                                                selector: @selector(runServerThread)
                                                  object: nil];
        LogTo(CBL_Server, @"Starting server thread %@ ...", _serverThread);
        [_serverThread start];

        // Don't start the replicator immediately; instead, give the app a chance to install
        // filter and validation functions, otherwise persistent replications may behave
        // incorrectly. The delayed-perform means the replicator won't start until after
        // the caller (and its caller, etc.) returns back to the runloop.
        MYAfterDelay(0.0, ^{
            if (_serverThread) {
                [self queue: ^{
                    [_manager replicatorManager];
                }];
            }
        });
    }
    return self;
}

- (id) initWithDirectory: (NSString*)dirPath error: (NSError**)outError {
    return [self initWithDirectory: dirPath options: NULL error: outError];
}


- (void)dealloc
{
    LogTo(CBL_Server, @"DEALLOC");
    if (_serverThread) Warn(@"%@ dealloced with _serverThread still set: %@", self, _serverThread);
}


- (void) close {
    if (_serverThread) {
        [self waitForDatabaseManager:^id(CBL_DatabaseManager* mgr) {
            LogTo(CBL_Server, @"Stopping server thread...");

            Class tdURLProtocol = NSClassFromString(@"CBL_URLProtocol");
            if (tdURLProtocol)
                [tdURLProtocol unregisterServer: self];
            [_manager close];
            _manager = nil;
            _stopRunLoop = YES;
            return nil;
        }];
        _serverThread = nil;
    }
}


- (NSString*) directory {
    return _manager.directory;
}


- (void) runServerThread {
    @autoreleasepool {
        LogTo(CBL_Server, @"Server thread starting...");

        [[NSThread currentThread] setName:@"CouchbaseLite"];
        
#ifndef GNUSTEP
        // Add a no-op source so the runloop won't stop on its own:
        CFRunLoopSourceContext context = {};  // all zeros
        CFRunLoopSourceRef source = CFRunLoopSourceCreate(NULL, 0, &context);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
        CFRelease(source);
#endif

        // Now run:
        while (!_stopRunLoop && [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                                         beforeDate: [NSDate distantFuture]])
            ;
        
        LogTo(CBL_Server, @"Server thread exiting");

        // Clean up; this has to be done on the server thread, not in the -close method.
        [_manager close];
    }
}


- (void) queue: (void(^)())block {
    Assert(_serverThread, @"-queue: called after -close");
    MYOnThread(_serverThread, block);
}


- (void) tellDatabaseNamed: (NSString*)dbName to: (void (^)(CBL_Database*))block {
    [self queue: ^{ block([_manager databaseNamed: dbName]); }];
}


- (void) tellDatabaseManager: (void (^)(CBL_DatabaseManager*))block {
    [self queue: ^{ block(_manager); }];
}


- (id) waitForDatabaseNamed: (NSString*)dbName to: (id (^)(CBL_Database*))block {
    __block id result = nil;
    NSConditionLock* lock = [[NSConditionLock alloc] initWithCondition: 0];
    [self queue: ^{
        [lock lockWhenCondition: 0];
        @try {
            CBL_Database* db = [_manager databaseNamed: dbName];
            result = block(db);
        } @finally {
            [lock unlockWithCondition: 1];
        }
    }];
    [lock lockWhenCondition: 1];  // wait till block finishes
    return result;
}


- (id) waitForDatabaseManager: (id (^)(CBL_DatabaseManager*))block {
    __block id result = nil;
    NSConditionLock* lock = [[NSConditionLock alloc] initWithCondition: 0];
    [self queue: ^{
        [lock lockWhenCondition: 0];
        @try {
            result = block(_manager);
        } @finally {
            [lock unlockWithCondition: 1];
        }
    }];
    [lock lockWhenCondition: 1];  // wait till block finishes
    [lock unlock];
    return result;
}


@end




TestCase(CBL_Server) {
    RequireTestCase(CBL_DatabaseManager);
}
