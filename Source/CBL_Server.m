//
//  CBL_Server.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 11/30/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CouchbaseLitePrivate.h"
#import "CBL_Server.h"
#import "CBLDatabase.h"
#import "CBLMisc.h"
#import "CBLManager+Internal.h"
#import "CBLInternal.h"
#import "CBL_URLProtocol.h"
#import "MYBlockUtils.h"


DefineLogDomain(Server);


@implementation CBL_Server
{
@protected
    CBLManager* _manager;
}

#if DEBUG
+ (instancetype) createEmptyAtPath: (NSString*)path {
    Assert(self != [CBL_Server class], @"CBL_Server is abstract");
    [[NSFileManager defaultManager] removeItemAtPath: path error: NULL];
    NSError* error;
    CBLManager* manager = [[CBLManager alloc] initWithDirectory: path options: nil error: &error];
    Assert(manager, @"Failed to create server at %@: %@", path, error.my_compactDescription);
    CBL_Server* server = [[self alloc] initWithManager: manager];
    return server;
}

+ (instancetype) createEmptyAtTemporaryPath: (NSString*)name {
    return [self createEmptyAtPath: [NSTemporaryDirectory() stringByAppendingPathComponent: name]];
}
#endif

- (NSDictionary*) customHTTPHeaders {
    return _manager.customHTTPHeaders;
}

- (instancetype) initWithManager: (CBLManager*)newManager {
    self = [super init];
    if (self) {
        _manager = newManager;
    }
    return self;
}

- (void) dealloc {
    LogTo(Server, @"DEALLOC");
}

- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%p]", self.class, self];
}

- (void) queue: (void(^)())block {
    AssertAbstractMethod();
}

- (id) waitForDatabaseManager: (id (^)(CBLManager*))block {
    AssertAbstractMethod();
}

- (void) tellDatabaseNamed: (NSString*)dbName to: (void (^)(CBLDatabase*))block {
    [self queue: ^{ block([_manager databaseNamed: dbName error: NULL]); }];
}

- (void) tellDatabaseManager: (void (^)(CBLManager*))block {
    [self queue: ^{ block(_manager); }];
}

- (id) waitForDatabaseNamed: (NSString*)dbName to: (id (^)(CBLDatabase*))block {
    return [self waitForDatabaseManager: ^id(CBLManager *manager) {
        return block([manager databaseNamed: dbName error: NULL]);
    }];
}

- (void) close {
    LogTo(Server, @"%@: Closing...", self);
    Class tdURLProtocol = NSClassFromString(@"CBL_URLProtocol");
    if (tdURLProtocol)
        [tdURLProtocol unregisterServer: self];
}

@end




@implementation CBL_DispatchServer
{
    dispatch_queue_t _queue;
}

- (instancetype) initWithManager: (CBLManager*)newManager {
    self = [super initWithManager: newManager];
    if (self) {
        _queue = dispatch_queue_create("Couchbase Lite", DISPATCH_QUEUE_SERIAL);
        newManager.dispatchQueue = _queue;
    }
    return self;
}

- (void) queue: (void(^)())block {
    dispatch_async(_queue, block);
}

- (id) waitForDatabaseManager: (id (^)(CBLManager*))block {
    __block id result;
    dispatch_sync(_queue, ^{
        result = block(_manager);
    });
    return result;
}

- (void) close {
    if (_queue) {
        [super close];
        dispatch_sync(_queue, ^{
            [_manager close];
            _manager = nil;
        });
        _queue = nil;
    }
}

- (void) dealloc {
    if (_queue)
        Warn(@"%@ dealloced with _queue still set: %@", self, _queue);
}

@end




@implementation CBL_RunLoopServer
{
    NSThread* _serverThread;
    BOOL _stopRunLoop;
}


- (instancetype) initWithManager: (CBLManager*)newManager {
    self = [super initWithManager: newManager];
    if (self) {
        _serverThread = [[NSThread alloc] initWithTarget: self
                                                selector: @selector(runServerThread)
                                                  object: nil];
        LogTo(Server, @"%@ Starting server thread ...", self);
        [_serverThread start];
    }
    return self;
}


- (void) dealloc {
    if (_serverThread)
        Warn(@"%@ dealloced with _serverThread still set: %@", self, _serverThread);
}


- (void) runServerThread {
    @autoreleasepool {
        LogTo(Server, @"%@: Server thread starting...", self);

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
        
        LogTo(Server, @"%@: Server thread exiting", self);

        // Clean up; this has to be done on the server thread, not in the -close method.
        [_manager close];
    }
}


- (void) close {
    if (_serverThread) {
        [super close];
        [self waitForDatabaseManager:^id(CBLManager* mgr) {
            LogTo(Server, @"%@: Stopping server thread...", self);
            [_manager close];
            _manager = nil;
            _stopRunLoop = YES;
            return nil;
        }];
        _serverThread = nil;
    }
}


- (void) queue: (void(^)())block {
    Assert(_serverThread, @"-queue: called after -close");
    MYOnThread(_serverThread, block);
}


- (id) waitForDatabaseManager: (id (^)(CBLManager*))block {
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
