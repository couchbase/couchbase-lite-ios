//
//  MultipeerReplicatorTest.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/6/25.
//  Copyright © 2025 Couchbase. All rights reserved.
//

#import "MultipeerReplicatorTest.h"
#import "CBLTLSIdentity+Internal.h"

#define kTestKeyUsages kCBLKeyUsagesClientAuth | kCBLKeyUsagesServerAuth
#define kTestPeerGroupID @"CBLMultipeerReplTestGroup"

#define kTestMaxIdentity 2 // Increase this when testing more than two peers.
#define kTestIdentityCommonName @"CBLMultipeerReplTest"


@implementation MultipeerReplicatorTest {
    NSUInteger _identityCount;
}

- (void) setUp {
    [super setUp];
    [self cleanupIdentity];
    [self openOtherDB];
}

- (void) tearDown {
    [self cleanupIdentity];
    [super tearDown];
}

- (NSString*) identityNameForNumber: (NSUInteger)num {
    return [NSString stringWithFormat: @"%@-%lu", kTestIdentityCommonName, (unsigned long)num];
}

- (void) cleanupIdentity {
    for (NSUInteger i = 1; i <= kTestMaxIdentity; i++) {
        NSString* label = [self identityNameForNumber: i];
        [self ignoreException: ^{
            [CBLTLSIdentity deleteIdentityWithLabel: label error: nil];
        }];
    }
}

- (CBLTLSIdentity*) createIdentity {
    Assert(_identityCount++ <= kTestMaxIdentity);

    NSError* error;
    NSString* name = [self identityNameForNumber: _identityCount];
    NSDictionary* attrs = @{ kCBLCertAttrCommonName: name };
    CBLTLSIdentity* identity = [CBLTLSIdentity createIdentityForKeyUsages: kTestKeyUsages
                                                               attributes: attrs
                                                               expiration: nil
                                                                    label: name
                                                                    error: &error];
    AssertNotNil(identity);
    AssertNil(error);
    return identity;
}

/** A function to return a multipeer replicator for the default collection of the given database.
    Will be enhanced it later for more customization as needed by tests. */
- (CBLMultipeerReplicator*) replicatorForDatabase: (CBLDatabase*)database {
    CBLCollection* collection = [self.db defaultCollection: nil];
    AssertNotNil(collection);
    
    CBLMultipeerCollectionConfiguration* collConfig =
        [[CBLMultipeerCollectionConfiguration alloc] initWithCollection: collection];
    
    CBLMultipeerCertificateAuthenticator* auth =
        [[CBLMultipeerCertificateAuthenticator alloc] initWithBlock: ^BOOL(CBLPeerID* peerID, NSArray* certs) {
            return YES;
        }];
    
    CBLTLSIdentity* identity = [self createIdentity];
    
    CBLMultipeerReplicatorConfiguration* config =
        [[CBLMultipeerReplicatorConfiguration alloc] initWithPeerGroupID: kTestPeerGroupID
                                                                identity: identity
                                                           authenticator: auth
                                                             collections: @[collConfig]];
    
    NSError* error;
    CBLMultipeerReplicator* repl = [[CBLMultipeerReplicator alloc] initWithConfig: config error: &error];
    AssertNotNil(repl);
    AssertNil(error);
    return repl;
}

- (void) testSanityStartStop {
    XCTSkipUnless(self.keyChainAccessAllowed, @"Keychain access is required.");
    
    CBLMultipeerReplicator* repl = [self replicatorForDatabase: self.db];
    
    XCTestExpectation* xActive = [self expectationWithDescription: @"Active"];
    XCTestExpectation* xUnactive = [self expectationWithDescription: @"Unactive"];
    [repl addStatusListenerWithQueue: nil listener: ^(CBLMultipeerReplicatorStatus* status) {
        AssertNil(status.error);
        if (status.active) {
            [xActive fulfill];
        } else {
            [xUnactive fulfill];
        }
    }];
    
    [repl start];
    [self waitForExpectations: @[xActive] timeout: 10.0];
    
    [repl stop];
    [self waitForExpectations: @[xUnactive] timeout: 10.0];
}

- (void) testSanityReplication {
    XCTSkipUnless(self.keyChainAccessAllowed, @"Keychain access is required.");
    
    // Peer#1
    CBLMultipeerReplicator* repl1 = [self replicatorForDatabase: self.db];
    
    XCTestExpectation* xActive1 = [self expectationWithDescription: @"Active"];
    XCTestExpectation* xUnactive1 = [self expectationWithDescription: @"Unactive"];
    [repl1 addStatusListenerWithQueue: nil listener: ^(CBLMultipeerReplicatorStatus* status) {
        AssertNil(status.error);
        if (status.active) {
            [xActive1 fulfill];
        } else {
            [xUnactive1 fulfill];
        }
    }];
    
    XCTestExpectation* xOnline1 = [self expectationWithDescription: @"Online"];
    [repl1 addPeerDiscoveryStatusListener: nil listener: ^(CBLPeerDiscoveryStatus* status) {
        AssertNotNil(status.peerID);
        if (status.online) {
            [xOnline1 fulfill];
        }
    }];
    
    XCTestExpectation* xIdle1 = [self expectationWithDescription: @"Idle"];
    [xIdle1 setAssertForOverFulfill: NO]; // TODO: Investigate if it's an issue or not.
    XCTestExpectation* xStopped1 = [self expectationWithDescription: @"Stopped"];
    [repl1 addPeerReplicatorStatusListener: nil listener: ^(CBLPeerReplicatorStatus* change) {
        AssertNotNil(change.peerID);
        if (change.status.activity == kCBLReplicatorIdle) {
            [xIdle1 fulfill];
        } else if (change.status.activity == kCBLReplicatorStopped) {
            [xStopped1 fulfill];
        }
    }];
    
    [repl1 start];
    
    [self waitForExpectations: @[xActive1] timeout: 10.0];
    
    // Peer#2
    CBLMultipeerReplicator* repl2 = [self replicatorForDatabase: self.otherDB];
    
    XCTestExpectation* xActive2 = [self expectationWithDescription: @"Active"];
    XCTestExpectation* xUnactive2 = [self expectationWithDescription: @"Unactive"];
    [repl2 addStatusListenerWithQueue: nil listener: ^(CBLMultipeerReplicatorStatus* status) {
        AssertNil(status.error);
        if (status.active) {
            [xActive2 fulfill];
        } else {
            [xUnactive2 fulfill];
        }
    }];
    
    XCTestExpectation* xOnline2 = [self expectationWithDescription: @"Online"];
    XCTestExpectation* xOffline2 = [self expectationWithDescription: @"Offline"];
    [xOffline2 setAssertForOverFulfill: NO]; // TODO: Investigate if it's an issue or not.
    [repl2 addPeerDiscoveryStatusListener: nil listener: ^(CBLPeerDiscoveryStatus* status) {
        AssertNotNil(status.peerID);
        if (status.online) {
            [xOnline2 fulfill];
        } else {
            [xOffline2 fulfill];
        }
    }];
    
    XCTestExpectation* xIdle2 = [self expectationWithDescription: @"Idle"];
    [xIdle2 setAssertForOverFulfill: NO]; // TODO: Investigate if it's an issue or not.
    XCTestExpectation* xStopped2 = [self expectationWithDescription: @"Stopped"];
    [repl2 addPeerReplicatorStatusListener: nil listener: ^(CBLPeerReplicatorStatus* change) {
        AssertNotNil(change.peerID);
        if (change.status.activity == kCBLReplicatorIdle) {
            [xIdle2 fulfill];
        } else if (change.status.activity == kCBLReplicatorStopped) {
            [xStopped2 fulfill];
        }
    }];
    
    [repl2 start];
    
    [self waitForExpectations: @[xActive2, xOnline1, xOnline2] timeout: 10.0];
    
    [self waitForExpectations: @[xIdle1, xIdle2] timeout: 10.0];
    
    [repl1 stop];
    
    [self waitForExpectations: @[xStopped1, xStopped2] timeout: 10.0];
    
    [self waitForExpectations: @[xOffline2] timeout: 10.0];
    
    [self waitForExpectations: @[xUnactive1] timeout: 60.0];
    
    [repl2 stop];
    
    [self waitForExpectations: @[xUnactive2] timeout: 10.0];
}

@end
