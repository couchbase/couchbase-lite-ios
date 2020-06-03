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
    config1.pinnedServerCertificate = (__bridge SecCertificateRef) listener.config.tlsIdentity.certs[0];
    config2.pinnedServerCertificate = (__bridge SecCertificateRef) listener.config.tlsIdentity.certs[0];
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
    
    // check both replicators access listener at same time
    AssertEqual(maxConnectionCount, 2u);
    AssertEqual(maxActiveCount, 2u);
    
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

- (void) testURLs {
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

- (void) testClientCertAuthenticatorWithBlock API_AVAILABLE(macos(10.12), ios(10.3)) {
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
    
    // Start Replicator:
    [self ignoreException: ^{
        [self runWithTarget: listener.localEndpoint
                       type: kCBLReplicatorTypePushAndPull
                 continuous: NO
              authenticator: [[CBLClientCertificateAuthenticator alloc] initWithIdentity: identity]
                 serverCert: (__bridge SecCertificateRef) listener.config.tlsIdentity.certs[0]
                  errorCode: 0
                errorDomain: nil];
    }];

    // Cleanup:
    Assert([CBLTLSIdentity deleteIdentityWithLabel: kClientCertLabel error: &error]);
}

- (void) testServerCertVerificationModeSelfSignedCert {
    if (!self.keyChainAccessAllowed) return;
    
    // Listener:
    Listener* listener = [self listenWithTLS: YES];
    AssertNotNil(listener);
    AssertEqual(listener.config.tlsIdentity.certs.count, 1);
    
    self.disableDefaultServerCertPinning = YES;
    
    // Replicator - TLS Error:
    [self ignoreException: ^{
        [self runWithTarget: listener.localEndpoint
                       type: kCBLReplicatorTypePushAndPull
                 continuous: NO
              authenticator: nil
       serverCertVerifyMode: kCBLServerCertVerificationModeCACert
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
       serverCertVerifyMode: kCBLServerCertVerificationModeSelfSignedCert
                 serverCert: nil
                  errorCode: 0
                errorDomain: nil];
    }];
}

- (void) testServerCertVerificationModeCACert {
    if (!self.keyChainAccessAllowed) return;
    
    // Listener:
    Listener* listener = [self listenWithTLS: YES];
    AssertNotNil(listener);
    AssertEqual(listener.config.tlsIdentity.certs.count, 1);
    
    self.disableDefaultServerCertPinning = YES;
    
    // Replicator - TLS Error:
    [self ignoreException: ^{
        [self runWithTarget: listener.localEndpoint
                       type: kCBLReplicatorTypePushAndPull
                 continuous: NO
              authenticator: nil
       serverCertVerifyMode: kCBLServerCertVerificationModeCACert
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
       serverCertVerifyMode: kCBLServerCertVerificationModeCACert
                 serverCert: (__bridge SecCertificateRef) listener.config.tlsIdentity.certs[0]
                  errorCode: 0
                errorDomain: nil];
    }];
}

- (void) _testEmptyNetworkInterface {
    [self listen];
    
    NSArray* urls = _listener.urls;
    NSError* err = nil;
    for (uint i = 0; i < urls.count; i++ ) {
        // separate db instance!
        NSURL* url = urls[i];
        CBLDatabase* db = [[CBLDatabase alloc] initWithName: $sprintf(@"db-%d", i) error: &err];
        AssertNil(err);
        CBLMutableDocument* doc = [self createDocument];
        [doc setString: url.absoluteString forKey: @"url"];
        [db saveDocument: doc error: &err];
        AssertNil(err);
        
        // separate replicator instance
        id end = [[CBLURLEndpoint alloc] initWithURL: url];
        id rConfig = [[CBLReplicatorConfiguration alloc] initWithDatabase: db target: end];
        [rConfig setPinnedServerCertificate: (SecCertificateRef)(_listener.config.tlsIdentity.certs.firstObject)];
        [self run: rConfig errorCode: 0 errorDomain: nil];
        
        // remove the separate db
        [self deleteDatabase: db];
    }
    
    AssertEqual(self.otherDB.count, urls.count);
    CBLQuery* q = [CBLQueryBuilder select: @[[CBLQuerySelectResult all]]
                                     from: [CBLQueryDataSource database: self.otherDB]];
    CBLQueryResultSet* rs = [q execute: &err];
    AssertNil(err);
    NSMutableArray* result = [NSMutableArray arrayWithCapacity: urls.count];
    for(CBLQueryResult* res in rs.allObjects) {
        CBLDictionary* dict = [res dictionaryAtIndex: 0];
        [result addObject: [NSURL URLWithString: [dict stringForKey: @"url"]]];
    }
    
    AssertEqualObjects(result, urls);
    
    // validate 0.0.0.0 meta-address should return same empty response.
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    config.networkInterface = @"0.0.0.0";
    [self listen: config];
    AssertEqualObjects(urls, _listener.urls);
    
    [_listener stop];
}

- (void) testUnavailableNetworkInterface {
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    config.networkInterface = @"1.1.1.256";
    [self ignoreException:^{
        [self listen: config errorCode: CBLErrorUnknownHost errorDomain: CBLErrorDomain];
    }];

    [_listener stop];
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
             serverCert: (__bridge SecCertificateRef) listener1.config.tlsIdentity.certs[0]
              errorCode: 0
            errorDomain: nil];
    
    [listener1 stop];
    [listener2 stop];
    [self ignoreException:^{
        NSError* error = nil;
        // Note: listener 1 and 2 are sharing the same anonymous identity:
        Assert([listener1.config.tlsIdentity deleteFromKeyChainWithError: &error],
               @"Couldn't delete identity1: %@", error);
    }];
    AssertEqual(self.otherDB.count, 1);
}

// TODO: https://issues.couchbase.com/browse/CBL-1033
- (void) _testMultipleReplicatorsToListener {
    if (!self.keyChainAccessAllowed) return;
    
    [self listen]; // writable listener
    
    // save a doc on listenerDB
    NSError* err = nil;
    CBLMutableDocument* doc = [self createDocument: @"doc"];
    [doc setValue: @"Tiger" forKey: @"species"];
    Assert([self.otherDB saveDocument: doc error: &err], @"Failed to save listener DB %@", err);
    
    [self validateMultipleReplicationsTo: _listener replType: kCBLReplicatorTypePushAndPull];
    
    // cleanup
    [_listener stop];
}

// TODO: https://issues.couchbase.com/browse/CBL-1033
- (void) _testMultipleReplicatorsOnReadOnlyListener {
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
    [_listener stop];
}

@end
