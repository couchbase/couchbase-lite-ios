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
#import "CBLTLSIdentity+Internal.h"
#import "CBLURLEndpointListener.h"
#import "CBLURLEndpointListenerConfiguration.h"
#import "CollectionUtils.h"

#define kWsPort 4984
#define kWssPort 4985

#define kClientCertLabel @"CBL-Client-Cert"

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
    // Stop:
    if (_listener) {
        [_listener stop];
    }
    
    // Listener:
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    config.port = tls ? kWssPort : kWsPort;
    config.disableTLS = !tls;
    config.authenticator = auth;
    _listener = [[Listener alloc] initWithConfig: config];
    
    // Start:
    NSError* err = nil;
    Assert([_listener startWithError: &err]);
    AssertNil(err);
    
    return _listener;
}

- (void) tearDown {
    if (_listener) {
        [_listener stop];
        if (_listener.config.tlsIdentity) {
            [self ignoreException:^{
                NSError* error;
                Assert([_listener.config.tlsIdentity deleteFromKeyChainWithError: &error],
                       @"Couldn't delete identity: %@", error);
            }];
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

- (void) testStatus {
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    config.port = kWsPort;
    config.disableTLS = YES;
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
    CBLListenerPasswordAuthenticator* auth = [[CBLListenerPasswordAuthenticator alloc] initWithBlock:
        ^BOOL(NSString *username, NSString *password) {
            return ([username isEqualToString: @"daniel"] && [password isEqualToString: @"123"]);
        }];
    Listener* listener = [self listenWithTLS: NO auth: auth];
    
    // Replicator - No Authenticator:
    [self runWithTarget: listener.localEndpoint
                   type: kCBLReplicatorTypePushAndPull
             continuous: NO
          authenticator: nil
             serverCert: nil
              errorCode: CBLErrorHTTPAuthRequired
            errorDomain: CBLErrorDomain];
    
    // Replicator - Wrong Credentials:
    [self runWithTarget: listener.localEndpoint
                   type: kCBLReplicatorTypePushAndPull
             continuous: NO
          authenticator: [[CBLBasicAuthenticator alloc] initWithUsername: @"daniel" password: @"456"]
             serverCert: nil
              errorCode: CBLErrorHTTPAuthRequired
            errorDomain: CBLErrorDomain];
    
    // Replicator - Success:
    [self runWithTarget: listener.localEndpoint
                   type: kCBLReplicatorTypePushAndPull
             continuous: NO
          authenticator: [[CBLBasicAuthenticator alloc] initWithUsername: @"daniel" password: @"123"]
             serverCert: nil
              errorCode: 0
            errorDomain: nil];
    
    [listener stop];
}

#ifdef TARGET_OS_OSX
// Not working on iOS:
// https://issues.couchbase.com/browse/CBL-995
- (void) testClientCertAuthenticatorWithBlock {
    if (!self.keyChainAccessAllowed) return;
    
    // Listener:
    CBLListenerCertificateAuthenticator* listenerAuth =
        [[CBLListenerCertificateAuthenticator alloc] initWithBlock: ^BOOL(NSArray *certs) {
            AssertEqual(certs.count, 1);
            SecCertificateRef cert = (__bridge SecCertificateRef)(certs[0]);
            CFStringRef cnRef;
            OSStatus status = SecCertificateCopyCommonName(cert, &cnRef);
            AssertEqual(status, errSecSuccess);
            NSString* cn = (NSString*)CFBridgingRelease(cnRef);
            return [cn isEqualToString: @"daniel"];
        }];
    
    Listener* listener = [self listenWithTLS: YES auth: listenerAuth];
    AssertNotNil(listener);
    AssertEqual(listener.config.tlsIdentity.certs.count, 1);
    
    // Cleanup:
    NSError* error;
    Assert([CBLTLSIdentity deleteIdentityWithLabel: kClientCertLabel error: &error]);
    
    // Create client identity:
    NSDictionary* attrs = @{ kCBLCertAttrCommonName: @"daniel" };
    CBLTLSIdentity* identity = [CBLTLSIdentity createIdentityForServer: NO
                                                            attributes: attrs
                                                            expiration: nil
                                                                 label: kClientCertLabel
                                                                 error: &error];
    AssertNotNil(identity);
    AssertNil(error);
    
    // Replicator:
    [self runWithTarget: listener.localEndpoint
                   type: kCBLReplicatorTypePushAndPull
             continuous: NO
          authenticator: [[CBLClientCertificateAuthenticator alloc] initWithIdentity: identity]
             serverCert: (__bridge SecCertificateRef) listener.config.tlsIdentity.certs[0]
              errorCode: 0
            errorDomain: nil];
    
    // Cleanup:
    Assert([CBLTLSIdentity deleteIdentityWithLabel: kClientCertLabel error: &error]);
}
#endif

- (void) testClientCertAuthenticatorRootCerts {
    if (!self.keyChainAccessAllowed) return;
    
    NSData* rootCertData = [self dataFromResource: @"identity/client-ca" ofType: @"der"];
    SecCertificateRef rootCertRef = SecCertificateCreateWithData(kCFAllocatorDefault, (CFDataRef)rootCertData);
    AssertNotNil((__bridge id)rootCertRef);
    
    CBLListenerCertificateAuthenticator* listenerAuth =
        [[CBLListenerCertificateAuthenticator alloc] initWithRootCerts: @[(id)CFBridgingRelease(rootCertRef)]];
    Listener* listener = [self listenWithTLS: YES auth: listenerAuth];
    AssertNotNil(listener);
    
    // Cleanup:
    __block NSError* error;
    Assert([CBLTLSIdentity deleteIdentityWithLabel: kClientCertLabel error: &error]);
    
    // Create client identity:
    NSData* clientIdentityData = [self dataFromResource: @"identity/client" ofType: @"p12"];
    __block CBLTLSIdentity* identity;
    [self ignoreException: ^{
        identity = [CBLTLSIdentity importIdentityWithData: clientIdentityData
                                                 password: @"123"
                                                    label: kClientCertLabel
                                                    error: &error];
    }];
    AssertNotNil(identity);
    AssertNil(error);
    
    // Create Replicator:
    CBLReplicatorConfiguration* config = nil;
    CBLClientCertificateAuthenticator* auth = nil;
    auth = [[CBLClientCertificateAuthenticator alloc] initWithIdentity: identity];
    SecCertificateRef serverCert = (__bridge SecCertificateRef) listener.config.tlsIdentity.certs[0];
    config = [self configWithTarget: listener.localEndpoint
                               type: kCBLReplicatorTypePushAndPull
                         continuous: NO
                      authenticator: auth
                   pinnedServerCert: serverCert];
    
    // Start Replicator:
    [self ignoreException: ^{
        [self run: config errorCode: 0 errorDomain: nil];
    }];
    
    // Cleanup:
    Assert([CBLTLSIdentity deleteIdentityWithLabel: kClientCertLabel error: &error]);
}

@end
