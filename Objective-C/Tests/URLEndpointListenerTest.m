//
//  URLEndpointListenerTest.m
//  CouchbaseLite
//
//  Copyright (c) 2020 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
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

- (Listener*) listenAt: (uint16_t)port {
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    config.port = port;
    Listener* listener = [[Listener alloc] initWithConfig: config];
    
    // start listener
    NSError* err = nil;
    Assert([listener startWithError: &err]);
    AssertNil(err);
    
    return listener;
}

- (void) testPort {
    // initialize a listener
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    config.port = kPort;
    Listener* listener = [[Listener alloc] initWithConfig: config];
    AssertEqual(listener.port, 0);
    
    // start listener
    NSError* err = nil;
    Assert([listener startWithError: &err]);
    AssertNil(err);
    AssertEqual(listener.port, kPort);
    
    // stops
    [listener stop];
    AssertEqual(listener.port, 0);
}

- (void) testEmptyPort {
    // initialize a listener
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    config.port = 0;
    Listener* listener = [[Listener alloc] initWithConfig: config];
    AssertEqual(listener.port, 0);
    
    // start listener
    NSError* err = nil;
    Assert([listener startWithError: &err]);
    AssertNil(err);
    Assert(listener.port != 0);
    
    // stops
    [listener stop];
    AssertEqual(listener.port, 0);
}

- (void) testBusyPort {
    Listener* listener1 = [self listenAt: kPort];
    
    // initialize a listener at same port
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    config.port = kPort;
    Listener* listener2 = [[Listener alloc] initWithConfig: config];
    
    // already in use when starting the second listener
    [self ignoreException:^{
        NSError* err = nil;
        [listener2 startWithError: &err];
        AssertEqual(err.code, EADDRINUSE);
        AssertEqual(err.domain, NSPOSIXErrorDomain);
    }];
    
    // stops
    [listener1 stop];
}

// TODO: https://issues.couchbase.com/browse/CBL-948
- (void) _testURLs {
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    config.port = kPort;
    Listener* listener = [[Listener alloc] initWithConfig: config];
    AssertEqual(listener.urls.count, 0);
    
    // start listener
    NSError* err = nil;
    Assert([listener startWithError: &err]);
    AssertNil(err);
    Assert(listener.urls.count != 0);
    
    // stops
    [listener stop];
    AssertEqual(listener.urls.count, 0);
}

- (void) _testStatus {
    CBLDatabase.log.console.level = kCBLLogLevelDebug;
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    config.port = kPort;
    Listener* listener = [[Listener alloc] initWithConfig: config];
    AssertEqual(listener.status.connectionCount, 0);
    AssertEqual(listener.status.activeConnectionCount, 0);
    
    // start listener
    NSError* err = nil;
    Assert([listener startWithError: &err]);
    AssertNil(err);
    AssertEqual(listener.status.connectionCount, 0);
    AssertEqual(listener.status.activeConnectionCount, 0);
    
    [self generateDocumentWithID: @"doc-1"];
    CBLURLEndpoint* target = [[CBLURLEndpoint alloc] initWithURL: kURL];
    id rConfig = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: NO];
    [rConfig setPinnedServerCertificate: (SecCertificateRef)(listener.config.tlsIdentity.certs.firstObject)];
    __block Listener* weakListener = listener;
    __block uint64_t maxConnectionCount = 0, maxActiveCount = 0;
    [self run: rConfig reset: NO errorCode: 0 errorDomain: nil onReplicatorReady:^(CBLReplicator * r) {
        Listener* strongListener = weakListener;
        [r addChangeListener:^(CBLReplicatorChange * change) {
            maxConnectionCount = MAX(strongListener.status.connectionCount, maxConnectionCount);
            maxActiveCount = MAX(strongListener.status.activeConnectionCount, maxActiveCount);
        }];
    }];
    AssertEqual(maxActiveCount, 1);
    AssertEqual(maxConnectionCount, 1);
    AssertEqual(self.otherDB.count, 1);
    
    // stops
    [listener stop];
    AssertEqual(listener.status.connectionCount, 0);
    AssertEqual(listener.status.activeConnectionCount, 0);
}

@end
