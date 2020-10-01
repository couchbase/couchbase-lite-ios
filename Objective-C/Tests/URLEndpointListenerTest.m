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
#import "CBLURLEndpointListener+Internal.h"
#import "CBLURLEndpointListenerConfiguration.h"
#import "CollectionUtils.h"

#define kWsPort 4984
#define kWssPort 4985

#define kServerCertLabel @"CBL-Server-Cert"
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

#pragma mark - Helper methods

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
    
    return [self listen: config];
}

- (Listener*) listen: (Config*)config {
    return [self listen: config errorCode: 0 errorDomain: nil];
}

- (Listener*) listen: (Config*)config errorCode: (NSInteger)code errorDomain: (nullable NSString*)domain  {
    // Stop:
    if (_listener) {
        [_listener stop];
    }
    
    _listener = [[Listener alloc] initWithConfig: config];
    
    // Start:
    NSError* err = nil;
    BOOL success = [_listener startWithError: &err];
    Assert(success == (code == 0));
    if (code != 0) {
        AssertEqual(err.code, code);
        if (domain)
            AssertEqualObjects(err.domain, domain);
    } else
        AssertNil(err);
    
    return _listener;
}

- (void) stopListen {
    if (_listener) {
        [self stopListener: _listener];
    }
}

- (void) stopListener: (CBLURLEndpointListener*)listener {
    CBLTLSIdentity* identity = listener.tlsIdentity;
    [listener stop];
    if (identity && self.keyChainAccessAllowed) {
        [self deleteFromKeyChain: identity];
    }
}

- (void) deleteFromKeyChain: (CBLTLSIdentity*)identity {
    [self ignoreException:^{
        NSError* error;
        Assert([identity deleteFromKeyChainWithError: &error],
               @"Couldn't delete identity: %@", error);
    }];
}

- (CBLReplicator*) replicator: (CBLDatabase*)db
                    continous: (BOOL)continous
                       target: (id<CBLEndpoint>)target
                   serverCert: (nullable SecCertificateRef)cert {
    CBLReplicatorConfiguration* c;
    c = [[CBLReplicatorConfiguration alloc] initWithDatabase: db target: target];
    c.continuous = continous;
    c.pinnedServerCertificate = cert;
    return [[CBLReplicator alloc] initWithConfig: c];
}

// Two replicators, replicates docs to the listener; validates connection status
- (void) validateMultipleReplicationsTo: (Listener*)listener replType: (CBLReplicatorType)type {
    XCTestExpectation* exp1 = [self expectationWithDescription: @"replicator#1 stopped"];
    XCTestExpectation* exp2 = [self expectationWithDescription: @"replicator#2 stopped"];
    
    NSUInteger existingDocsInListener = listener.config.database.count;
    
    // open DBs
    NSError* err = nil;
    Assert([self deleteDBNamed: @"db1" error: &err], @"Failed to delete db1 %@", err);
    Assert([self deleteDBNamed: @"db2" error: &err], @"Failed to delete db2 %@", err);
    CBLDatabase* db1 = [self openDBNamed: @"db1" error: &err];
    AssertNil(err);
    CBLDatabase* db2 = [self openDBNamed: @"db2" error: &err];
    AssertNil(err);
    
    // For keeping the replication long enough to validate connection status, we will use blob
    NSData* content = [@"i am a blob" dataUsingEncoding: NSUTF8StringEncoding];
    
    // DB#1
    CBLBlob* blob1 = [[CBLBlob alloc] initWithContentType: @"text/plain" data: content];
    CBLMutableDocument* doc1 = [self createDocument: @"doc-1"];
    [doc1 setValue: blob1 forKey: @"blob"];
    Assert([db1 saveDocument: doc1 error: &err], @"Fail to save db1 %@", err);
    
    // DB#2
    CBLBlob* blob2 = [[CBLBlob alloc] initWithContentType: @"text/plain" data: content];
    CBLMutableDocument* doc2 = [self createDocument: @"doc-2"];
    [doc2 setValue: blob2 forKey: @"blob"];
    Assert([db2 saveDocument: doc2 error: &err], @"Fail to save db2 %@", err);
    
    // replicators
    CBLReplicatorConfiguration *config1, *config2;
    config1 = [[CBLReplicatorConfiguration alloc] initWithDatabase: db1 target: listener.localEndpoint];
    config2 = [[CBLReplicatorConfiguration alloc] initWithDatabase: db2 target: listener.localEndpoint];
    config1.replicatorType = type;
    config2.replicatorType = type;
    config1.pinnedServerCertificate = (__bridge SecCertificateRef) listener.tlsIdentity.certs[0];
    config2.pinnedServerCertificate = (__bridge SecCertificateRef) listener.tlsIdentity.certs[0];
    CBLReplicator* repl1 = [[CBLReplicator alloc] initWithConfig: config1];
    CBLReplicator* repl2 = [[CBLReplicator alloc] initWithConfig: config2];
    
    // get listener status
    __block Listener* weakListener = _listener;
    __block uint64_t maxConnectionCount = 0, maxActiveCount = 0;
    id changeListener = ^(CBLReplicatorChange * change) {
        Listener* strongListener = weakListener;
        if (change.status.activity == kCBLReplicatorBusy) {
            maxConnectionCount = MAX(strongListener.status.connectionCount, maxConnectionCount);
            maxActiveCount = MAX(strongListener.status.activeConnectionCount, maxActiveCount);
        } else if (change.status.activity == kCBLReplicatorStopped) {
            if (change.replicator == repl1)
                [exp1 fulfill];
            else
                [exp2 fulfill];
        }
    };
    id token1 = [repl1 addChangeListener: changeListener];
    id token2 = [repl2 addChangeListener: changeListener];
    
    // start & wait for replication
    [repl1 start];
    [repl2 start];
    [self waitForExpectations: @[exp1, exp2] timeout: timeout];
    
    // check replicators connected to listener
    Assert(maxConnectionCount > 0);
    Assert(maxActiveCount > 0);
    
    // all data are transferred to/from
    if (type < kCBLReplicatorTypePull)
        AssertEqual(listener.config.database.count, existingDocsInListener + 2u);
    
    AssertEqual(db1.count, existingDocsInListener + 1/* db2 doc*/);
    AssertEqual(db2.count, existingDocsInListener + 1/* db1 doc*/);
    
    // cleanup
    [repl1 removeChangeListenerWithToken: token1];
    [repl2 removeChangeListenerWithToken: token2];
    repl1 = nil;
    repl2 = nil;
    Assert([db1 close: &err], @"Failed to close db1 %@", err);
    Assert([db2 close: &err], @"Failed to close db2 %@", err);
    db1 = nil;
    db2 = nil;
}

- (void) checkEqualForCert: (SecCertificateRef)cert1 andCert: (SecCertificateRef)cert2 {
    if (@available(macOS 10.5, iOS 10.3, *)) {
        CFStringRef cnRef1, cnRef2;
        AssertEqual(SecCertificateCopyCommonName(cert1, &cnRef1), errSecSuccess);
        AssertEqual(SecCertificateCopyCommonName(cert2, &cnRef2), errSecSuccess);
        
        NSString* cn1 = (NSString*)CFBridgingRelease(cnRef1);
        NSString* cn2 = (NSString*)CFBridgingRelease(cnRef2);
        AssertEqualObjects(cn1, cn2);
    }
}

- (CBLTLSIdentity*) tlsIdentity: (BOOL)isServer {
    if (!self.keyChainAccessAllowed) return nil;
    
    // Cleanup:
    [self cleanupTLSIdentity: isServer];
    
    // Create server/client identity:
    NSError* err;
    NSString* label = isServer ? kServerCertLabel : kClientCertLabel;
    NSDictionary* attrs = @{ kCBLCertAttrCommonName: isServer ? @"CBL-Server" : @"daniel" };
    CBLTLSIdentity* identity = [CBLTLSIdentity createIdentityForServer: isServer
                                                            attributes: attrs
                                                            expiration: nil
                                                                 label: label
                                                                 error: &err];
    AssertNotNil(identity);
    AssertNil(err);
    return identity;
}

- (void) cleanupTLSIdentity: (BOOL)isServer {
    if (!self.keyChainAccessAllowed) return;
    
    NSError* err;
    NSString* label = isServer ? kServerCertLabel : kClientCertLabel;
    Assert([CBLTLSIdentity deleteIdentityWithLabel: label error: &err]);
}

- (void) validateActiveReplicationsAndURLEndpointListener: (BOOL)isDeleteDBs {
    if (!self.keyChainAccessAllowed) return;
    
    XCTestExpectation* stopExp1 = [self expectationWithDescription: @"replicator#1 stopped"];
    XCTestExpectation* stopExp2 = [self expectationWithDescription: @"replicator#2 stopped"];
    XCTestExpectation* idleExp1 = [self expectationWithDescription: @"replicator#1 idle"];
    XCTestExpectation* idleExp2 = [self expectationWithDescription: @"replicator#2 idle"];
    
    NSError* err;
    CBLMutableDocument* doc =  [self createDocument: @"db-doc"];
    Assert([self.db saveDocument: doc error: &err], @"Fail to save DB %@", err);
    doc =  [self createDocument: @"other-db-doc"];
    Assert([self.otherDB saveDocument: doc error: &err], @"Fail to save otherDB %@", err);
    
    // start listener
    [self listen];
    
    // replicator #1
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.db];
    CBLReplicatorConfiguration* config = [[CBLReplicatorConfiguration alloc] initWithDatabase: self.otherDB
                                                                                       target: target];
    config.continuous = YES;
    CBLReplicator* repl1 = [[CBLReplicator alloc] initWithConfig: config];

    // replicator #2
    [self deleteDBNamed: @"db2" error: &err];
    CBLDatabase* db2 = [self openDBNamed: @"db2" error: &err];
    AssertNil(err);
    config = [[CBLReplicatorConfiguration alloc] initWithDatabase: db2
                                                           target: _listener.localEndpoint];
    config.continuous = YES;
    config.pinnedServerCertificate = (__bridge SecCertificateRef) _listener.tlsIdentity.certs[0];
    CBLReplicator* repl2 = [[CBLReplicator alloc] initWithConfig: config];
    
    id changeListener = ^(CBLReplicatorChange * change) {
        if (change.status.activity == kCBLReplicatorIdle &&
            change.status.progress.completed == change.status.progress.total) {
            if (change.replicator == repl1)
                [idleExp1 fulfill];
            else
                [idleExp2 fulfill];
            
        } else if (change.status.activity == kCBLReplicatorStopped) {
            if (change.replicator == repl1)
                [stopExp1 fulfill];
            else
                [stopExp2 fulfill];
        }
    };
    id token1 = [repl1 addChangeListener: changeListener];
    id token2 = [repl2 addChangeListener: changeListener];
    
    [repl1 start];
    [repl2 start];
    [self waitForExpectations: @[idleExp1, idleExp2] timeout: timeout];
    
    if (isDeleteDBs) {
        [db2 delete: &err];
        AssertNil(err);
        [self.otherDB delete: &err];
        AssertNil(err);
    } else {
        [db2 close: &err];
        AssertNil(err);
        [self.otherDB close: &err];
        AssertNil(err);
    }
    
    [self waitForExpectations: @[stopExp1, stopExp2] timeout: timeout];
    [repl1 removeChangeListenerWithToken: token1];
    [repl2 removeChangeListenerWithToken: token2];
    [self stopListen];
}

- (void) validateActiveReplicatorAndURLEndpointListeners: (BOOL)isDeleteDB {
    if (!self.keyChainAccessAllowed) return;
    
    XCTestExpectation* idleExp = [self expectationWithDescription: @"replicator idle"];
    XCTestExpectation* stopExp = [self expectationWithDescription: @"replicator stopped"];

    // start listener#1 and listener#2
    NSError* err;
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    Listener* listener1 = [[Listener alloc] initWithConfig: config];
    Listener* listener2 = [[Listener alloc] initWithConfig: config];
    Assert([listener1 startWithError: &err]);
    AssertNil(err);
    Assert([listener2 startWithError: &err]);
    AssertNil(err);
    
    CBLMutableDocument* doc =  [self createDocument: @"db-doc"];
    Assert([self.db saveDocument: doc error: &err], @"Fail to save DB %@", err);
    doc =  [self createDocument: @"other-db-doc"];
    Assert([self.otherDB saveDocument: doc error: &err], @"Fail to save otherDB %@", err);
    
    // start replicator
    CBLReplicatorConfiguration* rConfig = [[CBLReplicatorConfiguration alloc] initWithDatabase: self.db
                                                                                        target: listener1.localEndpoint];
    rConfig.continuous = YES;
    rConfig.pinnedServerCertificate = (__bridge SecCertificateRef) listener1.tlsIdentity.certs[0];
    CBLReplicator* replicator = [[CBLReplicator alloc] initWithConfig: rConfig];
    id token = [replicator addChangeListener: ^(CBLReplicatorChange * change) {
        if (change.status.activity == kCBLReplicatorIdle &&
            change.status.progress.completed == change.status.progress.total) {
            [idleExp fulfill];
        } else if (change.status.activity == kCBLReplicatorStopped) {
            [stopExp fulfill];
        }
    }];
    [replicator start];
    [self waitForExpectations: @[idleExp] timeout: timeout];
    
    // delete / close
    if (isDeleteDB)
        [self.otherDB delete: &err];
    else
        [self.otherDB close: &err];
    
    [self waitForExpectations: @[stopExp] timeout: timeout];
    
    // cleanup
    [replicator removeChangeListenerWithToken: token];
    [self stopListener: listener1];
    [self stopListener: listener2];
}

- (void) releaseCF: (CFTypeRef)ref {
    if (ref != NULL) CFRelease(ref);
}

- (void) cleanUpIdentities {
    if (self.keyChainAccessAllowed) {
        [self ignoreException: ^{
            NSError* error;
            Assert([CBLURLEndpointListener deleteAnonymousIdentitiesWithError: &error],
                   @"Cannot delete anonymous identity: %@", error);
        }];
    }
}

- (void) setUp {
    [super setUp];
    [self cleanUpIdentities];
}

- (void) tearDown {
    [self stopListen];
    [self cleanUpIdentities];
    [super tearDown];
}

#pragma mark - Tests

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
    [self stopListener: listener];
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
    [self stopListener: listener];
    AssertEqual(listener.port, 0);
}

- (void) testBusyPort {
    [self listenWithTLS: NO];
    
    // initialize a listener at same port
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    config.port = _listener.config.port;
    config.disableTLS = YES;
    Listener* listener2 = [[Listener alloc] initWithConfig: config];
    
    // Already in use when starting the second listener
    [self ignoreException:^{
        NSError* err = nil;
        [listener2 startWithError: &err];
        AssertEqual(err.code, EADDRINUSE);
        AssertEqual(err.domain, NSPOSIXErrorDomain);
    }];
    
    // stops
    [self stopListen];
}

- (void) testURLs {
    if (!self.keyChainAccessAllowed) return;
    
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    _listener = [[Listener alloc] initWithConfig: config];
    AssertNil(_listener.urls);
    
    // start listener
    NSError* err = nil;
    Assert([_listener startWithError: &err]);
    AssertNil(err);
    Assert(_listener.urls.count != 0);
    
    // stops
    [self stopListener: _listener];
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
    
    XCTestExpectation* x = [self expectationWithDescription: @"Replicator Stopped"];
    id rConfig = [self configWithTarget: _listener.localEndpoint type: kCBLReplicatorTypePush continuous: NO];
    CBLReplicator* replicator = [[CBLReplicator alloc] initWithConfig: rConfig];
    
    __block Listener* weakListener = _listener;
    __block uint64_t maxConnectionCount = 0, maxActiveCount = 0;
    id token = [replicator addChangeListener: ^(CBLReplicatorChange* change) {
        Listener* strongListener = weakListener;
        maxConnectionCount = MAX(strongListener.status.connectionCount, maxConnectionCount);
        maxActiveCount = MAX(strongListener.status.activeConnectionCount, maxActiveCount);
        if (change.status.activity == kCBLReplicatorStopped)
            [x fulfill];
    }];
    
    [replicator start];
    [self waitForExpectations: @[x] timeout: timeout];
    [replicator removeChangeListenerWithToken: token];
    
    AssertEqual(maxActiveCount, 1);
    AssertEqual(maxConnectionCount, 1);
    AssertEqual(self.otherDB.count, 1);
    
    // stops
    [self stopListener: _listener];
    AssertEqual(_listener.status.connectionCount, 0);
    AssertEqual(_listener.status.activeConnectionCount, 0);
}

- (void) testTLSListenerAnonymousIdentity {
    if (!self.keyChainAccessAllowed) return;
    
    NSError* error;
    CBLMutableDocument* doc = [self createDocument];
    Assert([self.otherDB saveDocument: doc error: &error], @"Fail to save otherDB %@", error);
    
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    Listener* listener = [[Listener alloc] initWithConfig: config];
    AssertNil(listener.tlsIdentity);
    
    Assert([listener startWithError: &error]);
    AssertNil(error);
    AssertNotNil(listener.tlsIdentity);
    [self runWithTarget: listener.localEndpoint
                   type: kCBLReplicatorTypePushAndPull
             continuous: NO
          authenticator: nil
             serverCert: (__bridge SecCertificateRef) listener.tlsIdentity.certs[0]
              errorCode: 0
            errorDomain: nil];
    
    // different pinned cert
    CBLTLSIdentity* identity = [self tlsIdentity: NO];
    [self runWithTarget: listener.localEndpoint
                   type: kCBLReplicatorTypePushAndPull
             continuous: NO
          authenticator: nil
             serverCert: (__bridge SecCertificateRef)identity.certs[0]
              errorCode: CBLErrorTLSCertUnknownRoot
            errorDomain: CBLErrorDomain];
    [self cleanupTLSIdentity: NO];
    
    // No pinned cert
    [self runWithTarget: listener.localEndpoint
                   type: kCBLReplicatorTypePushAndPull
             continuous: NO
          authenticator: nil
             serverCert: nil
              errorCode: CBLErrorTLSCertUnknownRoot
            errorDomain: CBLErrorDomain];
    
    [self stopListener: listener];
    AssertNil(listener.tlsIdentity);
}

- (void) testTLSListenerUserIdentity {
    if (!self.keyChainAccessAllowed) return;
    
    NSError* error;
    CBLMutableDocument* doc = [self createDocument];
    Assert([self.otherDB saveDocument: doc error: &error], @"Fail to save otherDB %@", error);
    
    CBLTLSIdentity* tlsIdentity = [self tlsIdentity: YES];
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    config.tlsIdentity = tlsIdentity;
    Listener* listener = [[Listener alloc] initWithConfig: config];
    AssertNil(listener.tlsIdentity);
    
    Assert([listener startWithError: &error]);
    AssertNil(error);
    AssertNotNil(listener.tlsIdentity);
    AssertEqual(listener.tlsIdentity, tlsIdentity);
    [self runWithTarget: listener.localEndpoint
                   type: kCBLReplicatorTypePushAndPull
             continuous: NO
          authenticator: nil
             serverCert: (__bridge SecCertificateRef) listener.tlsIdentity.certs[0]
              errorCode: 0
            errorDomain: nil];
    
    // different pinned cert
    CBLTLSIdentity* identity = [self tlsIdentity: NO];
    [self runWithTarget: listener.localEndpoint
                   type: kCBLReplicatorTypePushAndPull
             continuous: NO
          authenticator: nil
             serverCert: (__bridge SecCertificateRef)identity.certs[0]
              errorCode: CBLErrorTLSCertUnknownRoot
            errorDomain: CBLErrorDomain];
    [self cleanupTLSIdentity: NO];
    
    // No pinned cert
    [self runWithTarget: listener.localEndpoint
                   type: kCBLReplicatorTypePushAndPull
             continuous: NO
          authenticator: nil
             serverCert: nil
              errorCode: CBLErrorTLSCertUnknownRoot
            errorDomain: CBLErrorDomain];
    
    [self stopListener: listener];
    AssertNil(listener.tlsIdentity);
}

- (void) testNonTLSNullListenerAuthenticator {
    if (!self.keyChainAccessAllowed) return;
    
    NSError* err;
    CBLMutableDocument* doc1 =  [self createDocument];
    Assert([self.otherDB saveDocument: doc1 error: &err], @"Fail to save to otherDB %@", err);
    Listener* listener = [self listenWithTLS: NO];
    AssertNil(listener.tlsIdentity);
    
    // Replicator - No Authenticator:
    [self runWithTarget: listener.localEndpoint
                   type: kCBLReplicatorTypePushAndPull
             continuous: NO
          authenticator: nil
             serverCert: nil
              errorCode: 0
            errorDomain: nil];
    
    // Replicator - Basic Authenticator
    [self runWithTarget: listener.localEndpoint
                   type: kCBLReplicatorTypePushAndPull
             continuous: NO
          authenticator: [[CBLBasicAuthenticator alloc] initWithUsername: @"daniel" password: @"456"]
             serverCert: nil
              errorCode: 0
            errorDomain: nil];
    
    // Replicator - Certificate Authenticator
    [self runWithTarget: listener.localEndpoint
                   type: kCBLReplicatorTypePushAndPull
             continuous: NO
          authenticator: [[CBLClientCertificateAuthenticator alloc] initWithIdentity: [self tlsIdentity: NO]]
             serverCert: nil
              errorCode: 0
            errorDomain: nil];
    
    // cleanup client cert authenticator identity
    [self cleanupTLSIdentity: NO];
    
    [self stopListener: listener];
}

- (void) testNonTLSPasswordListenerAuthenticator {
    if (!self.keyChainAccessAllowed) return;
    
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
    
    // Replicator - Wrong Username:
    [self runWithTarget: listener.localEndpoint
                   type: kCBLReplicatorTypePushAndPull
             continuous: NO
          authenticator: [[CBLBasicAuthenticator alloc] initWithUsername: @"daneil" password: @"456"]
             serverCert: nil
              errorCode: CBLErrorHTTPAuthRequired
            errorDomain: CBLErrorDomain];
    
    // Replicator - Wrong Password:
    [self runWithTarget: listener.localEndpoint
                   type: kCBLReplicatorTypePushAndPull
             continuous: NO
          authenticator: [[CBLBasicAuthenticator alloc] initWithUsername: @"daniel" password: @"456"]
             serverCert: nil
              errorCode: CBLErrorHTTPAuthRequired
            errorDomain: CBLErrorDomain];
    
    // Replicator - ClientCert Authenticator
    [self runWithTarget: listener.localEndpoint
                   type: kCBLReplicatorTypePushAndPull
             continuous: NO
          authenticator: [[CBLClientCertificateAuthenticator alloc] initWithIdentity: [self tlsIdentity: NO]]
             serverCert: nil
              errorCode: CBLErrorHTTPAuthRequired
            errorDomain: CBLErrorDomain];
    
    // cleanup client cert authenticator identity
    [self cleanupTLSIdentity: NO];
    
    // Replicator - Success:
    [self runWithTarget: listener.localEndpoint
                   type: kCBLReplicatorTypePushAndPull
             continuous: NO
          authenticator: [[CBLBasicAuthenticator alloc] initWithUsername: @"daniel" password: @"123"]
             serverCert: nil
              errorCode: 0
            errorDomain: nil];
    
    [self stopListener: listener];
}

- (void) testTLSPasswordListenerAuthenticator {
    if (!self.keyChainAccessAllowed) return;
    
    NSError* err;
    CBLMutableDocument* doc1 =  [self createDocument];
    Assert([self.otherDB saveDocument: doc1 error: &err], @"Fail to save to otherDB %@", err);
    
    // Listener:
    CBLListenerPasswordAuthenticator* auth = [[CBLListenerPasswordAuthenticator alloc] initWithBlock:
        ^BOOL(NSString *username, NSString *password) {
            return ([username isEqualToString: @"daniel"] && [password isEqualToString: @"123"]);
        }];
    Listener* listener = [self listenWithTLS: YES auth: auth];
    
    // Replicator - No Authenticator:
    [self runWithTarget: listener.localEndpoint
                   type: kCBLReplicatorTypePushAndPull
             continuous: NO
          authenticator: nil
             serverCert: (__bridge SecCertificateRef) listener.tlsIdentity.certs[0]
              errorCode: CBLErrorHTTPAuthRequired
            errorDomain: CBLErrorDomain];
    
    // Replicator - Wrong Username:
    [self runWithTarget: listener.localEndpoint
                   type: kCBLReplicatorTypePushAndPull
             continuous: NO
          authenticator: [[CBLBasicAuthenticator alloc] initWithUsername: @"daneil" password: @"456"]
             serverCert: (__bridge SecCertificateRef) listener.tlsIdentity.certs[0]
              errorCode: CBLErrorHTTPAuthRequired
            errorDomain: CBLErrorDomain];
    
    // Replicator - Wrong Password:
    [self runWithTarget: listener.localEndpoint
                   type: kCBLReplicatorTypePushAndPull
             continuous: NO
          authenticator: [[CBLBasicAuthenticator alloc] initWithUsername: @"daniel" password: @"456"]
             serverCert: (__bridge SecCertificateRef) listener.tlsIdentity.certs[0]
              errorCode: CBLErrorHTTPAuthRequired
            errorDomain: CBLErrorDomain];
    
    // Replicator - Different ClientCertAuthenticator
    [self runWithTarget: listener.localEndpoint
                   type: kCBLReplicatorTypePushAndPull
             continuous: NO
          authenticator: [[CBLClientCertificateAuthenticator alloc] initWithIdentity: [self tlsIdentity: NO]]
             serverCert: (__bridge SecCertificateRef) listener.tlsIdentity.certs[0]
              errorCode: CBLErrorHTTPAuthRequired
            errorDomain: CBLErrorDomain];
    
    // cleanup client cert authenticator identity
    [self cleanupTLSIdentity: NO];
    
    // Replicator - Success:
    [self runWithTarget: listener.localEndpoint
                   type: kCBLReplicatorTypePushAndPull
             continuous: NO
          authenticator: [[CBLBasicAuthenticator alloc] initWithUsername: @"daniel" password: @"123"]
             serverCert: (__bridge SecCertificateRef) listener.tlsIdentity.certs[0]
              errorCode: 0
            errorDomain: nil];
    
    [self stopListener: listener];
    
}

- (void) testClientCertAuthWithCallback API_AVAILABLE(macos(10.12), ios(10.3)) {
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
    AssertEqual(listener.tlsIdentity.certs.count, 1);
    
    // Replicator:
    
    [self runWithTarget: listener.localEndpoint
                   type: kCBLReplicatorTypePushAndPull
             continuous: NO
          authenticator: [[CBLClientCertificateAuthenticator alloc] initWithIdentity: [self tlsIdentity: NO]]
             serverCert: (__bridge SecCertificateRef) listener.tlsIdentity.certs[0]
              errorCode: 0
            errorDomain: nil];
    
    // Cleanup client cert authenticator identity
    [self cleanupTLSIdentity: NO];
    
    [self stopListener: listener];
}

- (void) testClientCertAuthWithCallbackError API_AVAILABLE(macos(10.12), ios(10.3)) {
    if (!self.keyChainAccessAllowed) return;
    
    // Listener:
    CBLListenerCertificateAuthenticator* listenerAuth =
        [[CBLListenerCertificateAuthenticator alloc] initWithBlock: ^BOOL(NSArray *certs) {
            AssertEqual(certs.count, 1);
            return NO;
        }];
    
    Listener* listener = [self listenWithTLS: YES auth: listenerAuth];
    AssertNotNil(listener);
    AssertEqual(listener.tlsIdentity.certs.count, 1);
    
    // Replicator:
    [self runWithTarget: listener.localEndpoint
                   type: kCBLReplicatorTypePushAndPull
             continuous: NO
          authenticator: [[CBLClientCertificateAuthenticator alloc] initWithIdentity: [self tlsIdentity: NO]]
             serverCert: (__bridge SecCertificateRef) listener.tlsIdentity.certs[0]
              errorCode: CBLErrorTLSClientCertRejected
            errorDomain: CBLErrorDomain];
    
    // Cleanup:
    [self cleanupTLSIdentity: NO];
    
    [self stopListener: listener];
}

- (void) testClientCertAuthRootCerts {
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
    
    // Start Replicator:
    [self ignoreException: ^{
        [self runWithTarget: listener.localEndpoint
                       type: kCBLReplicatorTypePushAndPull
                 continuous: NO
              authenticator: [[CBLClientCertificateAuthenticator alloc] initWithIdentity: identity]
                 serverCert: (__bridge SecCertificateRef) listener.tlsIdentity.certs[0]
                  errorCode: 0
                errorDomain: nil];
    }];

    // Cleanup:
    Assert([CBLTLSIdentity deleteIdentityWithLabel: kClientCertLabel error: &error]);
    
    [self stopListener: listener];
}

- (void) testClientCertAuthRootCertsError {
    if (!self.keyChainAccessAllowed) return;
    
    NSData* rootCertData = [self dataFromResource: @"identity/client-ca" ofType: @"der"];
    SecCertificateRef rootCertRef = SecCertificateCreateWithData(kCFAllocatorDefault, (CFDataRef)rootCertData);
    AssertNotNil((__bridge id)rootCertRef);
    
    CBLListenerCertificateAuthenticator* listenerAuth =
        [[CBLListenerCertificateAuthenticator alloc] initWithRootCerts: @[(id)CFBridgingRelease(rootCertRef)]];
    Listener* listener = [self listenWithTLS: YES auth: listenerAuth];
    AssertNotNil(listener);
    
    // Start Replicator:
    [self ignoreException: ^{
        [self runWithTarget: listener.localEndpoint
                       type: kCBLReplicatorTypePushAndPull
                 continuous: NO
              authenticator: [[CBLClientCertificateAuthenticator alloc] initWithIdentity: [self tlsIdentity: NO]]
                 serverCert: (__bridge SecCertificateRef) listener.tlsIdentity.certs[0]
                  errorCode: CBLErrorTLSClientCertRejected
                errorDomain: CBLErrorDomain];
    }];

    // Cleanup:
    [self cleanupTLSIdentity: NO];
    
    [self stopListener: listener];
}

- (void) testEmptyNetworkInterface {
    if (!self.keyChainAccessAllowed) return;
    
    [self listen];
    NSArray* urls = _listener.urls;
    
    /** Link local addresses cannot be assigned via network interface because they don't map to any given interface.  */
    NSPredicate* p = [NSPredicate predicateWithFormat: @"NOT(SELF.host CONTAINS 'fe80::') AND NOT(SELF.host CONTAINS '.local')"];
    NSArray* notLinkLocal = [urls filteredArrayUsingPredicate: p];
    
    NSError* err = nil;
    for (uint i = 0; i < notLinkLocal.count; i++ ) {
        // separate db instance!
        NSURL* url = notLinkLocal[i];
        CBLDatabase* db = [[CBLDatabase alloc] initWithName: $sprintf(@"db-%d", i) error: &err];
        AssertNil(err);
        CBLMutableDocument* doc = [self createDocument];
        [doc setString: url.absoluteString forKey: @"url"];
        [db saveDocument: doc error: &err];
        AssertNil(err);
        
        // separate replicator instance
        id end = [[CBLURLEndpoint alloc] initWithURL: url];
        id rConfig = [[CBLReplicatorConfiguration alloc] initWithDatabase: db target: end];
        [rConfig setPinnedServerCertificate: (SecCertificateRef)(_listener.tlsIdentity.certs.firstObject)];
        [self run: rConfig errorCode: 0 errorDomain: nil];
        
        // remove the separate db
        [self deleteDatabase: db];
    }
    
    AssertEqual(self.otherDB.count, notLinkLocal.count);
    CBLQuery* q = [CBLQueryBuilder select: @[[CBLQuerySelectResult all]]
                                     from: [CBLQueryDataSource database: self.otherDB]];
    CBLQueryResultSet* rs = [q execute: &err];
    AssertNil(err);
    NSMutableArray* result = [NSMutableArray arrayWithCapacity: notLinkLocal.count];
    for(CBLQueryResult* res in rs.allObjects) {
        CBLDictionary* dict = [res dictionaryAtIndex: 0];
        [result addObject: [NSURL URLWithString: [dict stringForKey: @"url"]]];
    }
    
    AssertEqualObjects(result, notLinkLocal);
    
    // validate 0.0.0.0 meta-address should return same empty response.
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    config.networkInterface = @"0.0.0.0";
    config.port = kWssPort;
    [self listen: config];
    AssertEqualObjects(urls, _listener.urls);
    
    [self stopListen];
}

- (void) testUnavailableNetworkInterface {
    if (!self.keyChainAccessAllowed) return;
    
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    config.networkInterface = @"1.1.1.256";
    [self ignoreException:^{
        [self listen: config errorCode: CBLErrorUnknownHost errorDomain: CBLErrorDomain];
    }];
    
    config.networkInterface = @"blah";
    [self ignoreException:^{
        [self listen: config errorCode: CBLErrorUnknownHost errorDomain: CBLErrorDomain];
    }];
}

- (void) testNetworkInterfaceName {
    if (!self.keyChainAccessAllowed) return;
    
    NSArray* interfaces = [Listener allInterfaceNames];
    for (NSString* i in interfaces) {
        Config* config = [[Config alloc] initWithDatabase: self.otherDB];
        config.networkInterface = i;
        
        [self listen: config];
        
        /// make sure, connection is successful and no error thrown!
        
        [self stopListen];
    }
}

- (void) testMultipleListenersOnSameDatabase {
    if (!self.keyChainAccessAllowed) return;
    
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    Listener* listener1 = [[Listener alloc] initWithConfig: config];
    Listener* listener2 = [[Listener alloc] initWithConfig: config];
    
    NSError* err = nil;
    Assert([listener1 startWithError: &err]);
    AssertNil(err);
    Assert([listener2 startWithError: &err]);
    AssertNil(err);
    
    // replicate doc
    [self generateDocumentWithID: @"doc-1"];
    [self runWithTarget: listener1.localEndpoint
                   type: kCBLReplicatorTypePushAndPull
             continuous: NO
          authenticator: nil
             serverCert: (__bridge SecCertificateRef) listener1.tlsIdentity.certs[0]
              errorCode: 0
            errorDomain: nil];
    
    [listener2 stop];
    [self stopListener: listener1];
    AssertEqual(self.otherDB.count, 1);
}

- (void) testMultipleReplicatorsToListener {
    if (!self.keyChainAccessAllowed) return;
    
    [self listen]; // writable listener
    
    // save a doc on listenerDB
    NSError* err = nil;
    CBLMutableDocument* doc = [self createDocument: @"doc"];
    [doc setValue: @"Tiger" forKey: @"species"];
    Assert([self.otherDB saveDocument: doc error: &err], @"Failed to save listener DB %@", err);
    
    [self validateMultipleReplicationsTo: _listener replType: kCBLReplicatorTypePushAndPull];
    
    // cleanup
    [self stopListen];
}

- (void) testMultipleReplicatorsOnReadOnlyListener {
    if (!self.keyChainAccessAllowed) return;
    
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    config.readOnly = YES;
    [self listen: config];
    
    // save a doc on listenerDB
    NSError* err = nil;
    CBLMutableDocument* doc = [self createDocument: @"doc"];
    [doc setValue: @"Tiger" forKey: @"species"];
    Assert([self.otherDB saveDocument: doc error: &err], @"Failed to save listener DB %@", err);
    
    [self validateMultipleReplicationsTo: _listener replType: kCBLReplicatorTypePull];
    
    // cleanup
    [self stopListen];
}

/**
 1. Listener on `otherDB`
 2. Replicator#1 on `otherDB` (otherDB -> DB#1)
 3. Replicator#2  (DB#2 -> otherDB)
 */
- (void) testReplicatorAndListenerOnSameDatabase {
    if (!self.keyChainAccessAllowed) return;
    
    XCTestExpectation* exp1 = [self expectationWithDescription: @"replicator#1 stopped"];
    XCTestExpectation* exp2 = [self expectationWithDescription: @"replicator#2 stopped"];
    
    // Listener
    NSError* err = nil;
    CBLMutableDocument* doc = [self createDocument];
    Assert([self.otherDB saveDocument: doc error: &err], @"Failed to save listener DB %@", err);
    
    [self listen];
    
    // Replicator#1 (otherDB -> DB#1)
    CBLMutableDocument* doc1 =  [self createDocument];
    Assert([self.db saveDocument: doc1 error: &err], @"Fail to save db1 %@", err);
    
    CBLDatabaseEndpoint* target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.db];
    CBLReplicator* repl1 = [self replicator: self.otherDB continous: YES target: target
                                 serverCert: nil];
    
    // Replicator#2 (DB#2 -> Listener(otherDB))
    Assert([self deleteDBNamed: @"db2" error: &err], @"Failed to delete db2 %@", err);
    CBLDatabase* db2 = [self openDBNamed: @"db2" error: &err];
    AssertNil(err);
    
    CBLMutableDocument* doc2 =  [self createDocument];
    Assert([db2 saveDocument: doc2 error: &err], @"Fail to save db2 %@", err);
    CBLReplicator* repl2 = [self replicator: db2 continous: YES target: _listener.localEndpoint
                                 serverCert: (__bridge SecCertificateRef) _listener.tlsIdentity.certs[0]];
    
    id changeListener = ^(CBLReplicatorChange * change) {
        if (change.status.activity == kCBLReplicatorIdle &&
            change.status.progress.completed == change.status.progress.total) {
            if (self.otherDB.count == 3u && self.db.count == 3u && db2.count == 3u)
                [change.replicator stop];
        }
        
        if (change.status.activity == kCBLReplicatorStopped) {
            if (change.replicator == repl1)
                [exp1 fulfill];
            else
                [exp2 fulfill];
        }
    };
    
    id token1 = [repl1 addChangeListener: changeListener];
    id token2 = [repl2 addChangeListener: changeListener];
    
    [repl1 start];
    [repl2 start];
    [self waitForExpectations: @[exp1, exp2] timeout: timeout];
    
    // all data are transferred to/from
    AssertEqual(self.otherDB.count, 3u);
    AssertEqual(self.db.count, 3u);
    AssertEqual(db2.count, 3u);

    // cleanup
    [repl1 removeChangeListenerWithToken: token1];
    [repl2 removeChangeListenerWithToken: token2];
    repl1 = nil;
    repl2 = nil;
    Assert([db2 close: &err], @"Failed to close db2 %@", err);
    db2 = nil;
    
    [self stopListen];
}

- (void) testReadOnlyListener {
    if (!self.keyChainAccessAllowed) return;
    
    NSError* err;
    CBLMutableDocument* doc1 =  [self createDocument];
    Assert([self.db saveDocument: doc1 error: &err], @"Fail to save db1 %@", err);
    
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    config.readOnly = YES;
    [self listen: config];
    
    // Push Replication to ReadOnly Listener
    [self ignoreException: ^{
        [self runWithTarget: _listener.localEndpoint
                       type: kCBLReplicatorTypePushAndPull
                 continuous: NO
              authenticator: nil
                 serverCert: (__bridge SecCertificateRef) _listener.tlsIdentity.certs[0]
                  errorCode: CBLErrorHTTPForbidden
                errorDomain: CBLErrorDomain];
    }];
    
    // cleanup
    [self stopListen];
}

- (void) testCloseWithActiveListener {
    if (!self.keyChainAccessAllowed) return;
    
    [self listen];
    
    NSError* err = nil;
    CBLTLSIdentity* identity = _listener.tlsIdentity;
    
    // Close database should also stop the listener:
    Assert([self.otherDB close: &err]);
    AssertNil(err);
    
    AssertEqual(_listener.port, 0);
    AssertEqual(_listener.urls.count, 0);
    
    // Cleanup:
    if (identity) {
        [self deleteFromKeyChain: identity];
    }
}

- (void) testReplicatorServerCertificate {
    if (!self.keyChainAccessAllowed) return;
    
    XCTestExpectation* x1 = [self expectationWithDescription: @"idle"];
    XCTestExpectation* x2 = [self expectationWithDescription: @"stopped"];
    
    Listener* listener = [self listen];
    
    SecCertificateRef serverCert = (__bridge SecCertificateRef) listener.tlsIdentity.certs[0];
    CBLReplicator* replicator = [self replicator: self.otherDB
                                       continous: YES
                                          target: listener.localEndpoint
                                      serverCert: serverCert];
    [replicator addChangeListener: ^(CBLReplicatorChange *change) {
        CBLReplicatorActivityLevel activity = change.status.activity;
        if (activity == kCBLReplicatorIdle)
            [x1 fulfill];
        else if (activity == kCBLReplicatorStopped && !change.status.error)
            [x2 fulfill];
    }];
    Assert(replicator.serverCertificate == NULL);
    
    [replicator start];
    
    [self waitForExpectations: @[x1] timeout: timeout];
    
    SecCertificateRef receivedServerCert = replicator.serverCertificate;
    Assert(receivedServerCert != NULL);
    [self checkEqualForCert: serverCert andCert: receivedServerCert];
    [self releaseCF: receivedServerCert];
    
    [replicator stop];
    
    [self waitForExpectations: @[x2] timeout: timeout];
    
    receivedServerCert = replicator.serverCertificate;
    Assert(receivedServerCert != NULL);
    [self checkEqualForCert: serverCert andCert: receivedServerCert];
    [self releaseCF: receivedServerCert];
    
    [self stopListen];
}

- (void) testReplicatorServerCertificateWithTLSError {
    if (!self.keyChainAccessAllowed) return;
    
    XCTestExpectation* x1 = [self expectationWithDescription: @"stopped"];
    
    Listener* listener = [self listen];
    
    SecCertificateRef serverCert = (__bridge SecCertificateRef) listener.tlsIdentity.certs[0];
    CBLReplicator* replicator = [self replicator: self.otherDB
                                       continous: YES
                                          target: listener.localEndpoint
                                      serverCert: nil];
    [replicator addChangeListener: ^(CBLReplicatorChange *change) {
        CBLReplicatorActivityLevel activity = change.status.activity;
        if (activity == kCBLReplicatorStopped && change.status.error)
            [x1 fulfill];
    }];
    Assert(replicator.serverCertificate == NULL);
    
    [replicator start];
    
    [self waitForExpectations: @[x1] timeout: timeout];
    SecCertificateRef receivedServerCert = replicator.serverCertificate;
    Assert(receivedServerCert != NULL);
    [self checkEqualForCert: serverCert andCert: receivedServerCert];
    
    // Use the received certificate to pin:
    serverCert = receivedServerCert;
    x1 = [self expectationWithDescription: @"idle"];
    XCTestExpectation* x2 = [self expectationWithDescription: @"stopped"];
    replicator = [self replicator: self.otherDB
                        continous: YES
                           target: listener.localEndpoint
                       serverCert: serverCert];
    [replicator addChangeListener: ^(CBLReplicatorChange *change) {
        CBLReplicatorActivityLevel activity = change.status.activity;
        if (activity == kCBLReplicatorIdle)
            [x1 fulfill];
        else if (activity == kCBLReplicatorStopped && !change.status.error)
            [x2 fulfill];
    }];
    Assert(replicator.serverCertificate == NULL);
    
    [replicator start];
    
    [self waitForExpectations: @[x1] timeout: timeout];
    receivedServerCert = replicator.serverCertificate;
    Assert(receivedServerCert != NULL);
    [self checkEqualForCert: serverCert andCert: receivedServerCert];
    [self releaseCF: receivedServerCert];
    
    [replicator stop];
    
    [self waitForExpectations: @[x2] timeout: timeout];
    receivedServerCert = replicator.serverCertificate;
    Assert(receivedServerCert != NULL);
    [self checkEqualForCert: serverCert andCert: receivedServerCert];
    [self releaseCF: receivedServerCert];
    [self releaseCF: serverCert];
    
    [self stopListen];
}

- (void) testReplicatorServerCertificateWithTLSDisabled {
    XCTestExpectation* x1 = [self expectationWithDescription: @"idle"];
    XCTestExpectation* x2 = [self expectationWithDescription: @"stopped"];
    
    Listener* listener = [self listenWithTLS: NO];
    
    CBLReplicator* replicator = [self replicator: self.otherDB
                                       continous: YES
                                          target: listener.localEndpoint
                                      serverCert: nil];
    [replicator addChangeListener: ^(CBLReplicatorChange *change) {
        CBLReplicatorActivityLevel level = change.status.activity;
        if (level == kCBLReplicatorIdle)
            [x1 fulfill];
        else if (level == kCBLReplicatorStopped && !change.status.error)
            [x2 fulfill];
    }];
    Assert(replicator.serverCertificate == NULL);
    
    [replicator start];
    
    [self waitForExpectations: @[x1] timeout: timeout];
    Assert(replicator.serverCertificate == NULL);
    
    [replicator stop];
    
    [self waitForExpectations: @[x2] timeout: timeout];
    Assert(replicator.serverCertificate == NULL);
    
    [self stopListen];
}

- (void) testAcceptOnlySelfSignedCertificate {
    if (!self.keyChainAccessAllowed) return;
    
    // Listener:
    Listener* listener = [self listenWithTLS: YES];
    AssertNotNil(listener);
    AssertEqual(listener.tlsIdentity.certs.count, 1);
    
    self.disableDefaultServerCertPinning = YES;
    
    // Replicator - TLS Error:
    [self ignoreException: ^{
        [self runWithTarget: listener.localEndpoint
                       type: kCBLReplicatorTypePushAndPull
                 continuous: NO
              authenticator: nil
       acceptSelfSignedOnly: NO
                 serverCert: nil
                  errorCode: CBLErrorTLSCertUnknownRoot
                errorDomain: CBLErrorDomain];
    }];
    
    // Replicator - Success:
    [self ignoreException: ^{
        [self runWithTarget: listener.localEndpoint
                       type: kCBLReplicatorTypePushAndPull
                 continuous: NO
              authenticator: nil
       acceptSelfSignedOnly: YES
                 serverCert: nil
                  errorCode: 0
                errorDomain: nil];
    }];
    
    [self stopListener: listener];
}

- (void) testPinnedServerCertificate {
    if (!self.keyChainAccessAllowed) return;
    
    // Listener:
    Listener* listener = [self listenWithTLS: YES];
    AssertNotNil(listener);
    AssertEqual(listener.tlsIdentity.certs.count, 1);
    
    self.disableDefaultServerCertPinning = YES;
    
    // Replicator - TLS Error:
    [self ignoreException: ^{
        [self runWithTarget: listener.localEndpoint
                       type: kCBLReplicatorTypePushAndPull
                 continuous: NO
              authenticator: nil
       acceptSelfSignedOnly: NO
                 serverCert: nil
                  errorCode: CBLErrorTLSCertUnknownRoot
                errorDomain: CBLErrorDomain];
    }];
    
    // Replicator - Success:
    [self ignoreException: ^{
        [self runWithTarget: listener.localEndpoint
                       type: kCBLReplicatorTypePushAndPull
                 continuous: NO
              authenticator: nil
       acceptSelfSignedOnly: NO
                 serverCert: (__bridge SecCertificateRef) listener.tlsIdentity.certs[0]
                  errorCode: 0
                errorDomain: nil];
    }];
    
    [self stopListener: listener];
}

- (void) testAcceptOnlySelfSignedCertificateWithPinnedCertificate {
    if (!self.keyChainAccessAllowed) return;
    
    // Listener:
    Listener* listener = [self listenWithTLS: YES];
    AssertNotNil(listener);
    AssertEqual(listener.tlsIdentity.certs.count, 1);
    
    // listener = cert1; replicator.pin = cert2; acceptSelfSigned = true => fail
    [self runWithTarget: listener.localEndpoint
                   type: kCBLReplicatorTypePushAndPull
             continuous: NO
          authenticator: nil
   acceptSelfSignedOnly: YES
             serverCert: self.defaultServerCert
              errorCode: CBLErrorTLSCertUnknownRoot
            errorDomain: CBLErrorDomain];
    
    // listener = cert1; replicator.pin = cert1; acceptSelfSigned = false => pass
    [self runWithTarget: listener.localEndpoint
                   type: kCBLReplicatorTypePushAndPull
             continuous: NO
          authenticator: nil
   acceptSelfSignedOnly: NO
             serverCert: (__bridge SecCertificateRef) listener.tlsIdentity.certs[0]
              errorCode: 0
            errorDomain: nil];
    
    [self stopListener: listener];
}

- (void) testListenerWithImportIdentity {
    if (!self.keyChainAccessAllowed) return;
    
    NSError* err = nil;
    NSData* data = [self dataFromResource: @"identity/certs" ofType: @"p12"];
    __block CBLTLSIdentity* identity;
    [self ignoreException: ^{
        NSError* error = nil;
        identity = [CBLTLSIdentity importIdentityWithData: data password: @"123"
                                                    label:kServerCertLabel error:&error];
        AssertNil(error);
    }];
    
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    config.tlsIdentity = identity;
    _listener = [[Listener alloc] initWithConfig: config];
    AssertNil(_listener.tlsIdentity);
    
    [self ignoreException:^{
        NSError* error = nil;
        Assert([_listener startWithError: &error]);
        AssertNil(error);
    }];
    
    AssertNotNil(_listener.tlsIdentity);
    AssertEqual(_listener.tlsIdentity, config.tlsIdentity);
    
    // make sure, replication works
    [self generateDocumentWithID: @"doc-1"];
    AssertEqual(self.otherDB.count, 0);
    [self runWithTarget: _listener.localEndpoint
                   type: kCBLReplicatorTypePushAndPull
             continuous: NO
          authenticator: nil
             serverCert: (__bridge SecCertificateRef) _listener.tlsIdentity.certs[0]
              errorCode: 0
            errorDomain: nil];
    AssertEqual(self.otherDB.count, 1u);
    
    // stop and cleanup
    [self stopListener: _listener];
    Assert([CBLTLSIdentity deleteIdentityWithLabel: kServerCertLabel error: &err]);
    AssertNil(err);
}

- (void) testStopListener {
    XCTestExpectation* x1 = [self expectationWithDescription: @"idle"];
    XCTestExpectation* x2 = [self expectationWithDescription: @"stopped"];
    
    // Listen:
    Listener* listener = [self listenWithTLS: NO];
    
    // Replicator:
    CBLURLEndpoint* target = listener.localEndpoint;
    CBLReplicator* replicator = [self replicator: self.otherDB
                                       continous: YES
                                          target: target
                                      serverCert: nil];
    [replicator addChangeListener: ^(CBLReplicatorChange *change) {
        CBLReplicatorActivityLevel level = change.status.activity;
        if (level == kCBLReplicatorIdle)
            [x1 fulfill];
        else if (level == kCBLReplicatorStopped)
            [x2 fulfill];
    }];
    [replicator start];
    
    // Wait until idle then stop the listener:
    [self waitForExpectations: @[x1] timeout: timeout];
    
    // Stop listen:
    [self stopListen];
    
    // Wait for the replicator to be stopped:
    [self waitForExpectations: @[x2] timeout: timeout];
    
    // Check error
    AssertEqual(replicator.status.error.code, CBLErrorWebSocketGoingAway);
    
    // Check to ensure that the replicator is not accessible:
    [self runWithTarget: target
                   type: kCBLReplicatorTypePushAndPull
             continuous: NO
          authenticator: nil
             serverCert: nil
              errorCode: ECONNREFUSED
            errorDomain: NSPOSIXErrorDomain];
}

#pragma mark - Close & Delete Replicators and Listeners

- (void) testCloseWithActiveReplicationsAndURLEndpointListener {
    [self validateActiveReplicationsAndURLEndpointListener: NO];
}

- (void) testDeleteWithActiveReplicationsAndURLEndpointListener {
    [self validateActiveReplicationsAndURLEndpointListener: YES];
}

- (void) testCloseWithActiveReplicatorAndURLEndpointListeners {
    [self validateActiveReplicatorAndURLEndpointListeners: NO];
}

- (void) testDeleteWithActiveReplicatorAndURLEndpointListeners {
    [self validateActiveReplicatorAndURLEndpointListeners: YES];
}

@end
