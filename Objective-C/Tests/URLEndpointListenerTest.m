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

#define kWsPort 4984
#define kWssPort 4985

NS_ASSUME_NONNULL_BEGIN

@interface CBLURLEndpointListener (Test)
@property (nonatomic, readonly) NSURL* localURL;
@property (nonatomic, readonly) CBLURLEndpoint* localEndpoint;
@end

NS_ASSUME_NONNULL_END

@implementation CBLURLEndpointListener (Test)

- (NSURL*) localURL {
    assert(self.port > 0);
    NSURLComponents* comps = [[NSURLComponents alloc] init];
    comps.scheme = self.config.disableTLS ? @"ws" : @"wss";
    comps.host = @"localhost";
    comps.port = @(self.port);
    comps.path = $sprintf(@"/%@",self.config.database.name);
    return comps.URL;
}

- (CBLURLEndpoint*) localEndpoint {
    return [[CBLURLEndpoint alloc] initWithURL: self.localURL];
}

@end

API_AVAILABLE(macos(10.12), ios(10.0))
@interface URLEndpointListenerTest : ReplicatorTest
typedef CBLURLEndpointListenerConfiguration Config;
typedef CBLURLEndpointListener Listener;
@end

@implementation URLEndpointListenerTest {
    CBLURLEndpointListener* _listener;
}

- (Listener*) listen {
    return [self listenWithTLS: YES];
}

- (Listener*) listenWithTLS: (BOOL)tls {
    return [self listenWithTLS: tls auth: nil];
}

- (Listener*) listenWithTLS: (BOOL)tls auth: (id<CBLListenerAuthenticator>)auth {
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    config.port = tls ? kWssPort : kWsPort;
    config.disableTLS = !tls;
    config.authenticator = auth;
    Listener* listener = [[Listener alloc] initWithConfig: config];
    
    // start listener
    NSError* err = nil;
    Assert([listener startWithError: &err]);
    AssertNil(err);
    
    _listener = listener;
    return listener;
}

- (void) tearDown {
    if (_listener) {
        [_listener stop];
        if (_listener.config.tlsIdentity) {
            // TODO: Cleanup KeyChain
        }
    }
    [super tearDown];
}

- (void) testPort {
    // initialize a listener
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    config.port = kWsPort;
    config.disableTLS = YES;
    Listener* listener = [[Listener alloc] initWithConfig: config];
    AssertEqual(listener.port, 0);
    
    // start listener
    NSError* err = nil;
    Assert([listener startWithError: &err]);
    AssertNil(err);
    AssertEqual(listener.port, kWsPort);
    
    // stops
    [listener stop];
    AssertEqual(listener.port, 0);
}

- (void) testEmptyPort {
    // initialize a listener
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    config.port = 0;
    config.disableTLS = YES;
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
    Listener* listener1 = [self listenWithTLS: NO];
    
    // initialize a listener at same port
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    config.port = listener1.config.port;
    config.disableTLS = YES;
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
    _listener = [[Listener alloc] initWithConfig: config];
    AssertEqual(_listener.urls.count, 0);
    
    // start listener
    NSError* err = nil;
    Assert([_listener startWithError: &err]);
    AssertNil(err);
    Assert(_listener.urls.count != 0);
    
    // stops
    [_listener stop];
    AssertEqual(_listener.urls.count, 0);
}

- (void) _testStatus {
    CBLDatabase.log.console.level = kCBLLogLevelDebug;
    
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    _listener = [[Listener alloc] initWithConfig: config];
    AssertEqual(_listener.status.connectionCount, 0);
    AssertEqual(_listener.status.activeConnectionCount, 0);
    
    // start listener
    NSError* err = nil;
    Assert([_listener startWithError: &err]);
    AssertNil(err);
    AssertEqual(_listener.status.connectionCount, 0);
    AssertEqual(_listener.status.activeConnectionCount, 0);
    
    [self generateDocumentWithID: @"doc-1"];
    
    id rConfig = [self configWithTarget: _listener.localEndpoint type: kCBLReplicatorTypePush continuous: NO];
    [rConfig setPinnedServerCertificate: (SecCertificateRef)(_listener.config.tlsIdentity.certs.firstObject)];
    __block Listener* weakListener = _listener;
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
    [_listener stop];
    AssertEqual(_listener.status.connectionCount, 0);
    AssertEqual(_listener.status.activeConnectionCount, 0);
}

- (void) testPaswordAuthenticator {
    // Listener:
    CBLListenerPasswordAuthenticator* listenerAuth = [[CBLListenerPasswordAuthenticator alloc] initWithBlock:
        ^BOOL(NSString *username, NSString *password) {
            return ([username isEqualToString: @"daniel"] && [password isEqualToString: @"123"]);
        }];
    Listener* listener = [self listenWithTLS: NO auth: listenerAuth];
    
    // Replicator - Failed:
    CBLReplicatorConfiguration* config = nil;
    CBLBasicAuthenticator* auth = nil;
    config = [self configWithTarget: listener.localEndpoint
                               type: kCBLReplicatorTypePushAndPull
                         continuous: NO
                      authenticator: auth];
    [self run: config errorCode: CBLErrorHTTPAuthRequired errorDomain: CBLErrorDomain];
    
    auth = [[CBLBasicAuthenticator alloc] initWithUsername: @"daniel" password: @"456"];
    config = [self configWithTarget: listener.localEndpoint
                               type: kCBLReplicatorTypePushAndPull
                         continuous: NO
                      authenticator: auth];
    [self run: config errorCode: CBLErrorHTTPAuthRequired errorDomain: CBLErrorDomain];
    
    // Replicator - OK:
    auth = [[CBLBasicAuthenticator alloc] initWithUsername: @"daniel" password: @"123"];
    config = [self configWithTarget: listener.localEndpoint
                               type: kCBLReplicatorTypePushAndPull
                         continuous: NO
                      authenticator: auth];
    [self run: config errorCode: 0 errorDomain: nil];
    
    [listener stop];
}

@end
