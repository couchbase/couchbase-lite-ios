//
//  URLEndpointListenerTest.m
//  CouchbaseLite
//
//  Created by Jayahari Vavachan on 5/13/20.
//  Copyright © 2020 Couchbase. All rights reserved.
//

#import "ReplicatorTest.h"
#import "CBLURLEndpointListener.h"
#import "CBLURLEndpointListenerConfiguration.h"
#import "CollectionUtils.h"

#define kPort 4984
#define kURL [NSURL URLWithString: $sprintf(@"ws://localhost:%d/otherdb", kPort)]

API_AVAILABLE(macos(10.12), ios(10.0))
@interface URLEndpointListenerTest : ReplicatorTest
typedef CBLURLEndpointListenerConfiguration Config;
typedef CBLURLEndpointListener Listener;

@end

@implementation URLEndpointListenerTest

- (Listener*) listenAt: (uint16)port {
    Config* config = [[Config alloc] initWithDatabase: self.otherDB port: port];
    config.disableTLS = YES;
    Listener* list = [[Listener alloc] initWithConfig: config];
    
    // start listener
    NSError* err = nil;
    Assert([list startWithError: &err]);
    AssertNil(err);
    
    return list;
}

- (void) testPort {
    // initialize a listener
    Config* config = [[Config alloc] initWithDatabase: self.otherDB port: kPort];
    config.disableTLS = YES;
    Listener* list = [[Listener alloc] initWithConfig: config];
    AssertEqual(list.port, 0);
    
    // start listener
    NSError* err = nil;
    Assert([list startWithError: &err]);
    AssertNil(err);
    AssertEqual(list.port, kPort);
    
    // stops
    [list stop];
    AssertEqual(list.port, 0);
}

- (void) testEmptyPort {
    // initialize a listener
    Config* config = [[Config alloc] initWithDatabase: self.otherDB port: 0];
    config.disableTLS = YES;
    Listener* list = [[Listener alloc] initWithConfig: config];
    AssertEqual(list.port, 0);
    
    // start listener
    NSError* err = nil;
    Assert([list startWithError: &err]);
    AssertNil(err);
    Assert(list.port != 0);
    
    // stops
    [list stop];
    AssertEqual(list.port, 0);
}

- (void) testBusyPort {
    Listener* list1 = [self listenAt: kPort];
    
    // initialize a listener at same port
    Config* config = [[Config alloc] initWithDatabase: self.otherDB port: kPort];
    config.disableTLS = YES;
    Listener* list2 = [[Listener alloc] initWithConfig: config];
    
    // already in use when starting the second listener
    [self ignoreException:^{
        NSError* err = nil;
        [list2 startWithError: &err];
        AssertEqual(err.code, EADDRINUSE);
        AssertEqual(err.domain, NSPOSIXErrorDomain);
    }];
    
    // stops
    [list1 stop];
}

// TODO: https://issues.couchbase.com/browse/CBL-948
- (void) _testURLs {
    Config* config = [[Config alloc] initWithDatabase: self.otherDB port: kPort];
    config.disableTLS = YES;
    Listener* list = [[Listener alloc] initWithConfig: config];
    AssertEqual(list.urls.count, 0);
    
    // start listener
    NSError* err = nil;
    Assert([list startWithError: &err]);
    AssertNil(err);
    Assert(list.urls.count != 0);
    
    // stops
    [list stop];
    AssertEqual(list.urls.count, 0);
}

// TODO: LiteCore-EE C++ Test "P2P Sync connection count" Failure!
- (void) _testStatus {
    CBLDatabase.log.console.level = kCBLLogLevelDebug;
    Config* config = [[Config alloc] initWithDatabase: self.otherDB port: kPort];
    config.disableTLS = YES;
    Listener* list = [[Listener alloc] initWithConfig: config];
    AssertEqual(list.status.connectionCount, 0);
    AssertEqual(list.status.activeConnectionCount, 0);
    
    // start listener
    NSError* err = nil;
    Assert([list startWithError: &err]);
    AssertNil(err);
    AssertEqual(list.status.connectionCount, 0);
    AssertEqual(list.status.activeConnectionCount, 0);
    
    [self generateDocumentWithID: @"doc-1"];
    CBLURLEndpoint* target = [[CBLURLEndpoint alloc] initWithURL: kURL];
    id rConfig = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: NO];
    __block Listener* tempListener = list;
    __block uint64 maxConnectionCount = 0, maxActiveCount = 0;
    [self run: rConfig reset: NO errorCode: 0 errorDomain: nil onReplicatorReady:^(CBLReplicator * r) {
        Listener* sListener = tempListener;
        [r addChangeListener:^(CBLReplicatorChange * change) {
            maxConnectionCount = MAX(sListener.status.connectionCount, maxConnectionCount);
            maxActiveCount = MAX(sListener.status.activeConnectionCount, maxActiveCount);
        }];
    }];
    AssertEqual(maxActiveCount, 1);
    AssertEqual(maxConnectionCount, 1);
    AssertEqual(self.otherDB.count, 1);
    
    // stops
    [list stop];
    AssertEqual(list.status.connectionCount, 0);
    AssertEqual(list.status.activeConnectionCount, 0);
}

@end
