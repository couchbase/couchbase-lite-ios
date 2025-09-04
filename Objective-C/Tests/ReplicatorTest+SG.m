//
//  ReplicatorTest_SG
//  CouchbaseLite
//
//  Copyright (c) 2022 Couchbase, Inc All rights reserved.
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

@interface ReplicatorTest_SG : ReplicatorTest

@end

@implementation ReplicatorTest_SG

- (void) testAuthenticationFailure_SG {
    id target = [self remoteEndpointWithName: @"seekrit" secure: YES];
    if (!target)
        return;
    
    NSData* cert = [self dataFromResource: @"identity/walrus" ofType: @"der"];
    Assert(cert);
    id rootCertRef = CFBridgingRelease(SecCertificateCreateWithData(kCFAllocatorDefault, (CFDataRef)cert));
    id auth = [[CBLBasicAuthenticator alloc] initWithUsername: @"test" password: @"test"];
    
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO authenticator: auth serverCert: (__bridge SecCertificateRef) rootCertRef];
    [self run: config errorCode: CBLErrorHTTPAuthRequired errorDomain: CBLErrorDomain];
}

- (void) testAuthenticatedPull_SG {
    id target = [self remoteEndpointWithName: @"seekrit" secure: YES];
    if (!target)
        return;
    
    NSData* cert = [self dataFromResource: @"identity/walrus" ofType: @"der"];
    Assert(cert);
    id rootCertRef = CFBridgingRelease(SecCertificateCreateWithData(kCFAllocatorDefault, (CFDataRef)cert));
    id auth = [[CBLBasicAuthenticator alloc] initWithUsername: @"pupshaw" password: @"frank"];

    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO authenticator: auth serverCert: (__bridge SecCertificateRef) rootCertRef];
    [self run: config errorCode: 0 errorDomain: nil];
}

- (void) testPushBlob_SG {
    id target = [self remoteEndpointWithName: @"scratch" secure: NO];
    if (!target)
        return;

    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    NSData* data = [self dataFromResource: @"image" ofType: @"jpg"];
    Assert(data);
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType: @"image/jpeg"
                                                    data: data];
    [doc1 setBlob: blob forKey: @"blob"];
    Assert([self.defaultCollection saveDocument: doc1 error: &error]);
    AssertEqual(self.defaultCollection.count, 1u);
    
    [self eraseRemoteEndpoint: target];
    id config = [self configWithTarget: target type : kCBLReplicatorTypePush continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
}

- (void) testMissingHost_SG {
    // Set maxAttempts 1 as will get Transient otherwise and keep retrying
    id target = [[CBLURLEndpoint alloc] initWithURL:[NSURL URLWithString:@"ws://foo.couchbase.com/db"]];
    if (!target)
        return;
    
    id config = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: YES authenticator: nil serverCert: nil maxAttempts: 1];
    [self run: config errorCode: CBLErrorUnknownHost errorDomain: CBLErrorDomain];
}

- (void) testSelfSignedSSLFailure_SG {
    id target = [self remoteEndpointWithName: @"scratch" secure: YES];
    if (!target)
        return;
    
    self.disableDefaultServerCertPinning = YES;    // without this, SSL handshake will fail
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO];
    [self run: config errorCode: CBLErrorTLSCertUnknownRoot errorDomain: CBLErrorDomain];
}

// disabled - scratch TLS unknown
- (void) _testSelfSignedSSLPinned_SG {
    id target = [self remoteEndpointWithName: @"scratch" secure: YES];
    if (!target)
        return;
    
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
}

- (void)  dontTestContinuousPushNeverending_SG {
    // NOTE: This test never stops even after the replication goes idle.
    // It can be used to test the response to connectivity issues like killing the remote server.
    id target = [self remoteEndpointWithName: @"scratch" secure: NO];
    if (!target)
        return;
    id config = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: YES];
    repl = [[CBLReplicator alloc] initWithConfig: config];
    [repl start];
    
    XCTestExpectation* x = [self expectationWithDescription: @"When pigs fly"];
    [self waitForExpectations: @[x] timeout: 1e9];
}

// https://issues.couchbase.com/browse/CBL-1054
- (void) testStopReplicatorAfterOffline_SG {
    id target = [[CBLURLEndpoint alloc] initWithURL: [NSURL URLWithString: @"ws://foo.couchbase.com/db"]];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: YES];
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: config];
    
    __block BOOL isOffline = NO;
    XCTestExpectation* x1 = [self expectationWithDescription: @"Offline"];
    XCTestExpectation* x2 = [self expectationWithDescription: @"Stopped"];
    id token = [r addChangeListener: ^(CBLReplicatorChange* change) {
        if (change.status.activity == kCBLReplicatorOffline) {
            // CBL-983: The replicator might retry right away and report offline again
            // before it gets stopped due to the reachability changed report. Hence
            // adding isOffline check to prevent fulfilling twice.
            if (!isOffline) {
                [change.replicator stop];
                [x1 fulfill];
                isOffline = YES;
            }
        }
        if (change.status.activity == kCBLReplicatorStopped) {
            [x2 fulfill];
        }
    }];
    
    [r start];
    [self waitForExpectations: @[x1, x2] timeout: kExpTimeout];
    [token remove];
    r = nil;
}

- (void) testPullConflictDeleteWins_SG {
    id target = [self remoteEndpointWithName: @"scratch" secure: NO];
    if (!target)
        return;
    
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID:@"doc1"];
    [doc1 setValue: @"Tiger" forKey: @"species"];
    Assert([self.defaultCollection saveDocument: doc1 error: &error]);
    
    [self eraseRemoteEndpoint: target];
    
    // Push to SG:
    id config = [self configWithTarget: target type :kCBLReplicatorTypePush continuous: NO];
    if (![self run: config errorCode: 0 errorDomain: nil])
        return;
    
    // Get doc form SG:
    NSDictionary* json = [self sendRequestToEndpoint: target method: @"GET" path: doc1.id body: nil];
    Assert(json);
    Log(@"----> Common ancestor revision is %@", json[@"_rev"]);
    
    // Update doc on SG:
    NSMutableDictionary* nuData = [json mutableCopy];
    nuData[@"species"] = @"Cat";
    json = [self sendRequestToEndpoint: target method: @"PUT" path: doc1.id body: nuData];
    Assert(json);
    Log(@"----> Conflicting server revision is %@", json[@"rev"]);
    
    // Delete local doc:
    Assert([self.defaultCollection deleteDocument: doc1 error: &error]);
    AssertNil([self.defaultCollection documentWithID: doc1.id error: &error]);
    
    // Start pull replicator:
    Log(@"-------- Starting pull replication to pick up conflict --------");
    config = [self configWithTarget: target type :kCBLReplicatorTypePull continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    // Verify local doc should be nil:
    AssertNil([self.defaultCollection documentWithID: doc1.id error: &error]);
    AssertNil(error);
}

- (void) testPushAndPullBigBodyDocument_SG {
    id target = [self remoteEndpointWithName: @"scratch" secure: NO];
    if (!target)
        return;
    
    // Create a big document (~500KB)
    CBLMutableDocument *doc = [[CBLMutableDocument alloc] init];
    for (int i = 0; i < 1000; i++) {
        NSString *text = [self randomStringWithLength: 512];
        [doc setValue:text forKey:[NSString stringWithFormat:@"text-%d", i]];
    }
    
    NSError* error;
    Assert([self.defaultCollection saveDocument: doc error: &error], @"Save Error: %@", error);
    
    // Erase remote data:
    [self eraseRemoteEndpoint: target];
    
    // PUSH to SG:
    Log(@"-------- Starting push replication --------");
    id config = [self configWithTarget: target type :kCBLReplicatorTypePush continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    // Clean database:
    [self cleanDB];
    
    // PULL from SG:
    Log(@"-------- Starting pull replication --------");
    config = [self configWithTarget: target type :kCBLReplicatorTypePull continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
}

- (void) testPushAndPullExpiredDocument_SG {
    id target = [self remoteEndpointWithName: @"scratch" secure: NO];
    if (!target)
        return;
    
    NSError* error;
    NSString* propertyKey = @"expiredDocumentKey";
    NSString* value = @"some random text";
    CBLMutableDocument *doc = [[CBLMutableDocument alloc] init];
    [doc setString: value forKey: propertyKey];
    Assert([self.defaultCollection saveDocument: doc error: &error], @"Save Error: %@", error);
    AssertEqual(self.defaultCollection.count, 1u);
    
    // Setup document change notification
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    id token = [self.defaultCollection addDocumentChangeListenerWithID: doc.id
                                                              listener: ^(CBLDocumentChange *change)
                {
                    NSError* err;
                    AssertEqualObjects(change.documentID, doc.id);
                    if ([change.collection documentWithID: change.documentID error: &err] == nil) {
                        [expectation fulfill];
                    }
                }];
    
    // Set expiry
    NSDate* expiryDate = [NSDate dateWithTimeIntervalSinceNow: 1.0];
    Assert([self.defaultCollection setDocumentExpirationWithID: doc.id expiration: expiryDate error: &error]);
    AssertNil(error);
    
    // Wait for the document get expired.
    [self waitForExpectations: @[expectation] timeout: kExpTimeout];
    [token remove];
    
    // Erase remote data:
    [self eraseRemoteEndpoint: target];
    
    // PUSH to SG:
    Log(@"-------- Starting push replication --------");
    id config = [self configWithTarget: target type :kCBLReplicatorTypePush continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    // Clean database:
    AssertEqual(self.defaultCollection.count, 0u);
    
    // PULL from SG:
    Log(@"-------- Starting pull replication --------");
    config = [self configWithTarget: target type :kCBLReplicatorTypePull continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    // should not be replicated
    AssertEqual(self.defaultCollection.count, 0u);
    CBLDocument* savedDoc = [self.defaultCollection documentWithID: doc.id error: &error];
    AssertNil([savedDoc stringForKey: propertyKey]);
}

@end
