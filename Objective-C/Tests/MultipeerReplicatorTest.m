//
//  MultipeerReplicatorTest.m
//  CouchbaseLite
//
//  Copyright (c) 2025 Couchbase, Inc. All rights reserved.
//  COUCHBASE CONFIDENTIAL -- part of Couchbase Lite Enterprise Edition
//

#import "MultipeerReplicatorTest.h"
#import "CBLDatabase+Internal.h"
#import "CBLTLSIdentity+Internal.h"

#define kTestKeyUsages kCBLKeyUsagesClientAuth | kCBLKeyUsagesServerAuth
#define kTestPeerGroupID @"CBLMultipeerReplTestGroup"

#define kTestMaxIdentity 10
#define kTestIdentityCommonName @"CBLMultipeerReplTest"

typedef NSMutableDictionary<CBLPeerID*, CBLPeerReplicatorStatus*> CBLPeerReplicatorStatusMap;

typedef CBLDocument * _Nullable (^MultipeerConflictResolverBlock)(CBLPeerID*, CBLConflict*);

typedef void (^MultipeerCollectionConfigureBlock)(CBLMultipeerCollectionConfiguration*);

/** Wrap CBLMultipeerReplicator protocol with block */
@interface MultipeerConflictResolver: NSObject<CBLMultipeerConflictResolver>

- (instancetype) initWithBlock: (MultipeerConflictResolverBlock)resolver;

- (instancetype) init NS_UNAVAILABLE;

@end

@implementation MultipeerConflictResolver {
    MultipeerConflictResolverBlock _resolver;
}

- (instancetype) initWithBlock: (MultipeerConflictResolverBlock)resolver {
    self = [super init];
    if (self) {
        _resolver = resolver;
    }
    return self;
}

- (CBLDocument *) resolveConflict: (CBLConflict*)conflict forPeer: (CBLPeerID*)peerID {
    return _resolver(peerID, conflict);
}

@end

/**
 Test Spec : https://github.com/couchbaselabs/couchbase-lite-api/blob/master/spec/tests/T0012-MultipeerReplicator.md
 Version : 1.1.0
 */
@implementation MultipeerReplicatorTest {
    NSUInteger _identityCount;
    CBLTLSIdentity* _issuer;
    
    dispatch_queue_t _listenerQueue;
    NSMutableDictionary<NSString*, NSMutableArray<id<CBLListenerToken>>*>* _listenerTokens;
    NSMutableDictionary<NSString*, CBLPeerReplicatorStatusMap*>* _replicatorStatuses;
}

- (void) setUp {
    [super setUp];
    
    XCTSkipUnless(self.isExecutionAllowed);
    
    [self cleanupIdentities];
    [self openOtherDB];
    
    _listenerQueue = dispatch_queue_create("MultipeerReplicatorTest.ListenerQueue", DISPATCH_QUEUE_SERIAL);
    
    _listenerTokens = [NSMutableDictionary dictionary];
    _replicatorStatuses = [NSMutableDictionary dictionary];
}

- (void) tearDown {
    if (self.isExecutionAllowed) {
        [self cleanupIdentities];
    }
    [super tearDown];
}

// TODO: Too flaky, enable after all LiteCore issues have been handled.
- (BOOL) isExecutionAllowed {
#if TARGET_OS_SIMULATOR
    // Cannot be tested on the simulator as local network access permission is required.
    // See FAQ-12 : https://developer.apple.com/forums/thread/663858)
    return NO;
#else
    // Disable as cannot be run on the build VM (Got POSIX Error 50, Network is down)
    return self.keyChainAccessAllowed && false;
#endif
}

- (NSString*) identityNameForNumber: (NSUInteger)num {
    return [NSString stringWithFormat: @"%@-%lu", kTestIdentityCommonName, (unsigned long)num];
}

- (void) cleanupIdentities {
    for (NSUInteger i = 1; i <= kTestMaxIdentity; i++) {
        NSString* label = [self identityNameForNumber: i];
        [self ignoreException: ^{
            [CBLTLSIdentity deleteIdentityWithLabel: label error: nil];
        }];
    }
    _issuer = nil;
}

- (CBLTLSIdentity*) issuer {
    if (_issuer) {
        return _issuer;
    }
    
    NSData* caKeyData = [self dataFromResource: @"identity/ca-key" ofType: @"der"];
    NSData* caCertData = [self dataFromResource: @"identity/ca-cert" ofType: @"der"];
    
    NSError* error;
    _issuer = [CBLTLSIdentity createIssuerWithPrivateKey: caKeyData
                                             certificate: caCertData
                                                   error: &error];
    AssertNotNil(_issuer);
    AssertNil(error);
    
    return _issuer;
}

- (CBLTLSIdentity*) createIdentity {
    Assert(_identityCount++ <= kTestMaxIdentity);
    NSError* error;
    NSString* label = [self identityNameForNumber: _identityCount];
    
    uint64_t timestamp = (uint64_t)([[NSDate date] timeIntervalSince1970] * 1000);
    NSString* cn = [NSString stringWithFormat: @"%@-%llu", label, timestamp];
    NSDictionary* attrs = @{ kCBLCertAttrCommonName: cn };
    
    CBLTLSIdentity* identity = [CBLTLSIdentity createIdentityForKeyUsages: kTestKeyUsages
                                                               attributes: attrs
                                                               expiration: nil
                                                                   issuer: [self issuer]
                                                                    label: label
                                                                    error: &error];
    
    AssertNotNil(identity);
    AssertNil(error);
    return identity;
}

- (CBLMultipeerReplicator*) multipeerReplicatorForDatabase: (CBLDatabase*)database {
    return [self multipeerReplicatorForDatabase: database authenticator: nil collectionConfigureBlock: nil];
}

- (CBLMultipeerReplicator*) multipeerReplicatorForDatabase: (CBLDatabase*)database
                                  collectionConfigureBlock: (nullable MultipeerCollectionConfigureBlock)collectionConfigureBlock {
    return [self multipeerReplicatorForDatabase: database authenticator: nil collectionConfigureBlock: collectionConfigureBlock];
}

- (CBLMultipeerReplicator*) multipeerReplicatorForDatabase: (CBLDatabase*)database
                                             authenticator: (nullable id<CBLMultipeerAuthenticator>)authenticator
                                  collectionConfigureBlock: (nullable MultipeerCollectionConfigureBlock)collectionConfigureBlock {
    CBLCollection* collection = [database defaultCollection: nil];
    AssertNotNil(collection);
    
    CBLMultipeerCollectionConfiguration* collConfig =
    [[CBLMultipeerCollectionConfiguration alloc] initWithCollection: collection];
    
    if (collectionConfigureBlock) {
        collectionConfigureBlock(collConfig);
    }
    
    CBLMultipeerCertificateAuthenticator* auth = authenticator ? authenticator :
    [[CBLMultipeerCertificateAuthenticator alloc] initWithBlock: ^BOOL(CBLPeerID *peerID, NSArray *certs) {
        AssertNotNil(peerID);
        Assert(certs.count > 0);
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

- (NSString*) replicatorID: (CBLMultipeerReplicator*)repl {
    return [NSString stringWithFormat: @"%p", repl];
}

- (void) addListenerToken: (id<CBLListenerToken>)token forReplicator: (CBLMultipeerReplicator*)repl {
    NSString* replID = [self replicatorID: repl];
    NSMutableArray<id<CBLListenerToken>>* tokens = _listenerTokens[replID];
    if (!tokens) {
        tokens = [NSMutableArray array];
        _listenerTokens[replID] = tokens;
    }
    [tokens addObject: token];
}

- (void) resetListenerTokensForReplicator: (CBLMultipeerReplicator*)repl {
    NSString* replID = [self replicatorID: repl];
    NSMutableArray<id<CBLListenerToken>>* tokens = _listenerTokens[replID];
    if (tokens) {
        for (id<CBLListenerToken> token in tokens) {
            [token remove];
        }
        [tokens removeAllObjects];
    }
}

- (void) startMultipeerReplicator: (CBLMultipeerReplicator*)repl {
    XCTestExpectation* xActive = [self expectationWithDescription: @"Active"];
    id<CBLListenerToken> token1 =
    [repl addStatusListenerWithQueue: _listenerQueue listener: ^(CBLMultipeerReplicatorStatus* status) {
        AssertNil(status.error);
        if (status.active) {
            [xActive fulfill];
        }
    }];
    
    NSString* replID = [self replicatorID: repl];
    __weak MultipeerReplicatorTest* weakSelf = self;
    
    id<CBLListenerToken> token2 =
    [repl addPeerReplicatorStatusListenerWithQueue: _listenerQueue
                                          listener: ^(CBLPeerReplicatorStatus* status) {
        MultipeerReplicatorTest* strongSelf = weakSelf;
        if (!strongSelf) { return; }
        
        CBLPeerReplicatorStatusMap* map = strongSelf->_replicatorStatuses[replID];
        if (!map) {
            map = [CBLPeerReplicatorStatusMap dictionary];
            [strongSelf->_replicatorStatuses setObject: map forKey: replID];
        }
        map[status.peerID] = status;
    }];
    [self addListenerToken: token2 forReplicator: repl];
    
    [repl start];
    [self waitForExpectations: @[xActive] timeout: kExpTimeout];
    [token1 remove];
}

- (void) stopMultipeerReplicator: (CBLMultipeerReplicator*)repl  {
    XCTestExpectation* xInactive = [self expectationWithDescription: @"Inactive"];
    id<CBLListenerToken> token = [repl addStatusListenerWithQueue: _listenerQueue
                                                         listener: ^(CBLMultipeerReplicatorStatus* status) {
        AssertNil(status.error);
        if (!status.active) {
            [xInactive fulfill];
        }
    }];
    [repl stop];
    [self waitForExpectations: @[xInactive] timeout: kExpTimeout];
    [token remove];
    
    [self resetListenerTokensForReplicator: repl];
}

- (CBLPeerReplicatorStatus*) replicatorStatus: (CBLMultipeerReplicator*)repl peerID: (CBLPeerID*)peerID {
    __block CBLPeerReplicatorStatus* status = nil;
    dispatch_sync(_listenerQueue, ^{
        NSString* replID = [self replicatorID: repl];
        CBLPeerReplicatorStatusMap* map = _replicatorStatuses[replID];
        if (map) {
            status = map[peerID];
        }
    });
    return status;
}

- (void) waitForReplicatorStatus: (CBLMultipeerReplicator*)repl
                          peerID: (CBLPeerID*)peerID
                   activityLevel: (CBLReplicatorActivityLevel)activityLevel {
    [self waitForReplicatorStatus: repl
                           peerID: peerID
                    activityLevel: activityLevel
                        errorCode: 0
                      errorDomain: nil] ;
}

- (void) waitForReplicatorStatus: (CBLMultipeerReplicator*)repl
                          peerID: (CBLPeerID*)peerID
                   activityLevel: (CBLReplicatorActivityLevel)activityLevel
                       errorCode: (NSInteger)errorCode
                     errorDomain: (nullable NSString*)errorDomain {
    int idleCount = 0;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: kExpTimeout];
    while ([[NSDate date] compare: deadline] == NSOrderedAscending) {
        CBLPeerReplicatorStatus *status = [self replicatorStatus: repl peerID: peerID];
        if (status && status.status.activity == activityLevel) {
            if (activityLevel == kCBLReplicatorIdle) {
                if (++idleCount >= 3) {
                    return; // IDLE confirmed
                }
                [NSThread sleepForTimeInterval: 0.5];
                continue;
            } else if (activityLevel == kCBLReplicatorStopped) {
                if (errorCode != 0) {
                    AssertEqual(status.status.error.code, errorCode);
                    if (errorDomain) {
                        AssertEqualObjects(status.status.error.domain, errorDomain);
                    }
                } else {
                    AssertNil(status.status.error);
                }
                return;
            } else {
                return;
            }
        }
        idleCount = 0; // Reset if not idle
        [NSThread sleepForTimeInterval: 0.5];
    }
    
    Assert(NO, @"Timeout waiting for activity level: %d", activityLevel);
}

#pragma mark - Configuration

/**
 ### 1. TestConfiguration
 
 #### Description
 Test that the configuration can be created successfully.
 
 #### Steps
 1. Create the configuration with the following:
 - peerGroupID: "MultipeerReplTestGroup"
 - identity: A TLSIdentity signed by an issuer from asset #1.
 - authenticator: Authenticator with a callback returning true.
 - collections: Collection configs containing a default collection
 - documentIDs: ["doc1"]
 - push/pull filter that returns true
 - a custom conflict resolver
 2. Check that the configuration is created successfully.
 3. Check that each property returns the correct value.
 */
- (void) testConfiguration {
    // Create the configuration:
    CBLTLSIdentity* identity = [self createIdentity];
    
    CBLMultipeerCertificateAuthenticator* auth = [[CBLMultipeerCertificateAuthenticator alloc] initWithBlock:
                                                  ^BOOL(CBLPeerID *peerID, NSArray *certs) {
        return YES;
    }];
    
    CBLMultipeerCollectionConfiguration* collConfig =
    [[CBLMultipeerCollectionConfiguration alloc] initWithCollection: self.defaultCollection];
    
    collConfig.documentIDs = @[@"doc1"];
    
    collConfig.pushFilter = ^BOOL(CBLPeerID* peerID, CBLDocument* doc, CBLDocumentFlags flags) {
        return [doc.id isEqualToString: @"doc1"];
    };
    collConfig.pullFilter = ^BOOL(CBLPeerID* peerID, CBLDocument* doc, CBLDocumentFlags flags) {
        return [doc.id isEqualToString: @"doc4"];
    };
    
    MultipeerConflictResolverBlock block = ^CBLDocument*(CBLPeerID* peerID, CBLConflict* conflict) {
        return conflict.remoteDocument;
    };
    
    collConfig.conflictResolver = [[MultipeerConflictResolver alloc] initWithBlock: block];
    
    CBLMultipeerReplicatorConfiguration* config =
    [[CBLMultipeerReplicatorConfiguration alloc] initWithPeerGroupID: kTestPeerGroupID
                                                            identity: identity
                                                       authenticator: auth
                                                         collections: @[collConfig]];
    
    // Check that the configuration is created successfully:
    AssertNotNil(config);
    
    // Check that each property returns the correct value:
    AssertEqualObjects(config.peerGroupID, kTestPeerGroupID);
    AssertEqualObjects(config.identity, identity);
    AssertEqualObjects(config.authenticator, auth);
    AssertEqualObjects(config.collections, @[collConfig]);
}

/**
 ### 2. TestConfigurationValidation
 
 #### Description
 Validate that a configuration cannot be created if the peerGroupID or collections are invalid.
 
 #### Steps
 1. Create the configuration with an empty peerGroupID::
 - peerGroupID: ""
 - identity: A TLSIdentity signed by an issuer from asset #1.
 - authenticator: Authenticator with a callback returning true.
 - collections: Collection configs containing the default collection
 2. Check that the configuration cannot be created as the peerGroupID is empty.
 3. Create the configuration with an empty collections:
 - peerGroupID: "MultipeerReplTestGroup"
 - identity: A self-signed TLSIdentity for both client and server auth
 - authenticator: Authenticator with a callback returning true.
 - collections: Zero collections
 4. Check that the configuration cannot be created as the collections are empty.
 */
- (void) testConfigurationValidation {
    // When exception is thrown, the object will not get released:
    self.disableObjectLeakCheck = YES;
    
    CBLTLSIdentity* identity = [self createIdentity];
    
    CBLMultipeerCertificateAuthenticator* auth = [[CBLMultipeerCertificateAuthenticator alloc] initWithBlock:
                                                  ^BOOL(CBLPeerID *peerID, NSArray *certs) {
        return YES;
    }];
    
    CBLMultipeerCollectionConfiguration* collConfig =
    [[CBLMultipeerCollectionConfiguration alloc] initWithCollection: self.defaultCollection];
    
    // Create the configuration with an empty peerGroupID:
    [self expectException: @"NSInvalidArgumentException" in: ^{
        CBLMultipeerReplicatorConfiguration* config =
        [[CBLMultipeerReplicatorConfiguration alloc] initWithPeerGroupID: @""
                                                                identity: identity
                                                           authenticator: auth
                                                             collections: @[collConfig]];
        (void)config; // Prevent unused variable warning
    }];
    
    // Create the configuration with an empty collections:
    [self expectException: @"NSInvalidArgumentException" in: ^{
        CBLMultipeerReplicatorConfiguration* config =
        [[CBLMultipeerReplicatorConfiguration alloc] initWithPeerGroupID: kTestPeerGroupID
                                                                identity: identity
                                                           authenticator: auth
                                                             collections: @[]];
        (void)config; // Prevent unused variable warning
    }];
}

/// Stop and Restart

/**
 ### 3. TestStartStop
 
 #### Description
 Test that a MultipeerReplicator can be started and stopped.
 
 #### Steps
 1. Create a MultipeerReplicator for a database with the following config:
 - peerGroupID: "MultipeerReplTestGroup"
 - identity: A TLSIdentity signed by an issuer from asset #1.
 - authenticator: An authenticator with a callback that returns true.
 - collections: Collection configs containing the default collection.
 2. Add a listener to monitor the replicator's active status.
 3. Start the replicator.
 4. Wait until the replicator is active and ensure that there are no errors.
 5. Stop the replicator.
 6. Wait until the replicator is inactive and ensure that there are no errors.
 7. Start the replicator again and check that it cannot be restarted (for 3.3.0).
 */
- (void) testStartStop {
    CBLMultipeerReplicator* repl = [self multipeerReplicatorForDatabase: self.db];
    
    XCTestExpectation* xActive = [self expectationWithDescription: @"Active"];
    XCTestExpectation* xInactive = [self expectationWithDescription: @"Inactive"];
    
    id<CBLListenerToken> token = [repl addStatusListenerWithQueue: nil
                                                         listener: ^(CBLMultipeerReplicatorStatus* status) {
        AssertNil(status.error);
        if (status.active) {
            [xActive fulfill];
        } else {
            [xInactive fulfill];
        }
    }];
    
    [repl start];
    [self waitForExpectations: @[xActive] timeout: kExpTimeout];
    
    [repl stop];
    [self waitForExpectations: @[xInactive] timeout: kExpTimeout];
    
    [token remove];
    
    // Check that the replicator cannot be restarted
    [self expectException: @"NSInternalInconsistencyException" in: ^{
        [repl start];
    }];
}

/**
 ### 4. TestImmediateStartStop
 
 #### Description
 Test that a MultipeerReplicator can be started then stopped immediately.
 
 #### Steps
 1. Create a MultipeerReplicator for a database with the following config:
 - peerGroupID: "MultipeerReplTestGroup"
 - identity: A TLSIdentity signed by an issuer from asset #1.
 - authenticator: An authenticator with a callback that returns true.
 - collections: Collection configs containing the default collection.
 2. Add a listener to monitor the replicator's active status.
 3. Start the replicator.
 4. Stop the replicator.
 5. Wait until the replicator is inactive and ensure that there are no errors.
 */
- (void) testImmediateStartStop {
    CBLMultipeerReplicator* repl = [self multipeerReplicatorForDatabase: self.db];
    
    XCTestExpectation* xInactive = [self expectationWithDescription: @"Inactive"];
    id<CBLListenerToken> token = [repl addStatusListenerWithQueue: nil
                                                         listener: ^(CBLMultipeerReplicatorStatus* status) {
        if (!status.active) {
            [xInactive fulfill];
        }
    }];
    
    [repl start];
    [repl stop];
    
    [self waitForExpectations: @[xInactive] timeout: kExpTimeout];
    
    [token remove];
}

/// Database Close

/**
 ### 5. TestStopOnCloseDatabase
 
 #### Description
 Test that a MultipeerReplicator can be started and stopped when the database is closed.
 
 #### Steps
 1. Create a MultipeerReplicator for a database with the following config:
 - peerGroupID: "MultipeerReplTestGroup"
 - identity: A TLSIdentity signed by an issuer from asset #1.
 - authenticator: Authenticator with a callback returning true.
 - collections: Collection configs containing the default collection.
 2. Add a listener to monitor the replicator's active status.
 3. Start the replicator.
 4. Wait until the replicator is active and ensure that there are no errors.
 5. Close the database.
 6. Wait until the MultipeerReplicator is inactive and ensure that there are no errors.
 */
- (void) testStopOnCloseDatabase {
    CBLMultipeerReplicator* repl = [self multipeerReplicatorForDatabase: self.db];
    
    XCTestExpectation* xActive = [self expectationWithDescription: @"Active"];
    XCTestExpectation* xUnactive = [self expectationWithDescription: @"Inactive"];
    id<CBLListenerToken> token = [repl addStatusListenerWithQueue: nil listener: ^(CBLMultipeerReplicatorStatus* status) {
        AssertNil(status.error);
        if (status.active) {
            [xActive fulfill];
        } else {
            [xUnactive fulfill];
        }
    }];
    
    [repl start];
    [self waitForExpectations: @[xActive] timeout: kExpTimeout];
    
    NSError* error;
    Assert([self.db close: &error]);
    AssertNil(error);
    
    [self waitForExpectations: @[xUnactive] timeout: kExpTimeout];
    
    [token remove];
}

#pragma mark - Replication

/**
 ### 6. TestBasicReplication
 
 #### Description
 Test basic replication between two multipeer replicators.
 
 #### Steps
 1. Create a document in the default collection of db#1:
 - docID: "doc1"
 - body: {"greeting": "hello"}
 2. Create a document in the default collection of db#2:
 - docID: "doc2"
 - body: {"greeting": "hi"}
 3. Create MultipeerReplicator#1 for db#1 with the following config:
 - peerGroupID: "MultipeerReplTestGroup"
 - identity: A TLSIdentity signed by an issuer from asset #1.
 - authenticator: Authenticator with a callback returning true.
 - collections: Collection configs containing the default collection.
 4. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
 5. Start MultipeerReplicator#1 and wait until the replicator is active.
 6. Create MultipeerReplicator#2 for db#2 with the following config:
 - peerGroupID: "MultipeerReplTestGroup"
 - identity: A TLSIdentity signed by an issuer from asset #1.
 - authenticator: Authenticator with a callback returning true.
 - collections: Collection configs containing the default collection.
 7. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
 8. Start MultipeerReplicator#2 and wait until the replicator is active.
 9. For MultipeerReplicator#1, wait until the replicator to peer#2 becomes IDLE without an error.
 10. For MultipeerReplicator#2, wait until the replicator to peer#1 becomes IDLE without an error.
 11. Verify that both doc1 and doc2 exist in both databases.
 12. Stop both replicators and wait until the replicators are inactive.
 */
- (void) testBasicReplication {
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"hello" forKey: @"greeting"];
    [self saveDocument: doc1 collection: self.defaultCollection];
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setString: @"hi" forKey: @"greeting"];
    [self saveDocument: doc2 collection: self.otherDBDefaultCollection];
    
    CBLMultipeerReplicator *repl1, *repl2;
    
    repl1 = [self multipeerReplicatorForDatabase: self.db];
    [self startMultipeerReplicator: repl1];
    
    repl2 = [self multipeerReplicatorForDatabase: self.otherDB];
    [self startMultipeerReplicator: repl2];
    
    [self waitForReplicatorStatus: repl1 peerID: repl2.peerID activityLevel: kCBLReplicatorIdle];
    [self waitForReplicatorStatus: repl2 peerID: repl1.peerID activityLevel: kCBLReplicatorIdle];
    
    CBLDocument* checkDoc1a = [self.defaultCollection documentWithID: @"doc1" error: nil];
    AssertNotNil(checkDoc1a);
    
    CBLDocument* checkDoc2a = [self.defaultCollection documentWithID: @"doc2" error: nil];
    AssertNotNil(checkDoc2a);
    
    CBLDocument* checkDoc1b = [self.otherDBDefaultCollection documentWithID: @"doc1" error: nil];
    AssertNotNil(checkDoc1b);
    
    CBLDocument* checkDoc2b = [self.otherDBDefaultCollection documentWithID: @"doc2" error: nil];
    AssertNotNil(checkDoc2b);
    
    [self stopMultipeerReplicator: repl1];
    [self stopMultipeerReplicator: repl2];
}

#pragma mark - Authenticator

/**
 ### 7. TestAuthenticationWithRootCerts
 
 #### Description
 Test that the authenticator can authenticate a peer's certificate that is signed by the
 given root certificates.
 
 #### Steps
 1. Create MultipeerReplicator#1 for db#1 with the following config:
 - peerGroupID: "MultipeerReplTestGroup"
 - identity: A TLSIdentity signed by an issuer from asset #1.
 - authenticator: Authenticator with the issuer certificate.
 - collections: Collection configs containing the default collection.
 2. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
 3. Start MultipeerReplicator#1 and wait until the replicator is active.
 4. Create MultipeerReplicator#2 for db#2 with the following config:
 - peerGroupID: "MultipeerReplTestGroup"
 - identity: A TLSIdentity signed by an issuer from asset #1.
 - authenticator: Authenticator with the issuer certificate.
 - collections: Collection configs containing the default collection.
 5. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
 6. Start MultipeerReplicator#2 and wait until the replicator is active.
 7. For MultipeerReplicator#1, wait until the replicator to peer#2 becomes IDLE without an error.
 8. For MultipeerReplicator#2, wait until the replicator to peer#1 becomes IDLE without an error.
 9. Stop both replicators and wait until the replicators are inactive.
 */
- (void) testAuthenticateWithRootCerts {
    CBLMultipeerReplicator *repl1, *repl2;
    
    CBLTLSIdentity* issuer = [self issuer];
    
    id<CBLMultipeerAuthenticator> auth =
    [[CBLMultipeerCertificateAuthenticator alloc] initWithRootCerts: issuer.certs];
    
    // Peer#1
    repl1 = [self multipeerReplicatorForDatabase: self.db authenticator: auth collectionConfigureBlock: nil];
    [self startMultipeerReplicator: repl1];
    
    // Peer#2
    repl2 = [self multipeerReplicatorForDatabase: self.otherDB authenticator: auth collectionConfigureBlock: nil];
    [self startMultipeerReplicator: repl2];
    
    // Wait until the replicator is IDLE
    [self waitForReplicatorStatus: repl1 peerID: repl2.peerID activityLevel: kCBLReplicatorIdle];
    [self waitForReplicatorStatus: repl2 peerID: repl1.peerID activityLevel: kCBLReplicatorIdle];
    
    [self stopMultipeerReplicator: repl1];
    [self stopMultipeerReplicator: repl2];
}

/**
 ### 8. TestAuthenticationWithRootCertsFailed
 
 #### Description
 Test that the authenticator can reject a peer's certificate that is not signed by the given root certificates.
 
 #### Steps
 
 1. Create MultipeerReplicator#1 for db#1 with the following config:
 - peerGroupID: "MultipeerReplTestGroup"
 - identity: A TLSIdentity signed by an issuer from asset #1.
 - authenticator: Authenticator with the invalid root cert from asset #2.
 - collections: Collection configs containing the default collection.
 2. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
 3. Start MultipeerReplicator#1 and wait until the replicator is active.
 4. Create MultipeerReplicator#2 for db#2 with the following config:
 - peerGroupID: "MultipeerReplTestGroup"
 - identity: A TLSIdentity signed by an issuer from asset #1.
 - authenticator: Authenticator with the issuer certificate.
 - collections: Collection configs containing the default collection.
 5. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
 6. Start MultipeerReplicator#2 and wait until the replicator is active.
 7. Wait until a peer's replicator becomes STOPPED with a TLSClientCertRejected (5010) error.
 Only the MultipeerReplicator that has an active replicator will report the replicator status.
 As you don't know which MultipeerReplicator's replicator will be active,
 you should listen to the replicator status on both MultipeerReplicators and ensure
 that one of the replicators is STOPPED with the error.
 */
- (void) testAuthenticateWithRootCertsFailed {
    NSString* rootCertPEM = @"-----BEGIN CERTIFICATE-----\n"
    @"MIIE/DCCAuSgAwIBAgIUHKj9KlERcqJF62FpOzQn7rC9PPgwDQYJKoZIhvcNAQEL\n"
    @"BQAwFjEUMBIGA1UEAwwLQ0JMLVRFU1QtQ0EwHhcNMjUwNjIwMjExNDQ5WhcNMzUw\n"
    @"NjE4MjExNDQ5WjAWMRQwEgYDVQQDDAtDQkwtVEVTVC1DQTCCAiIwDQYJKoZIhvcN\n"
    @"AQEBBQADggIPADCCAgoCggIBALePrUMEM/yZtxMghU3MJ5RlA+OxYqt+NTFvPMTY\n"
    @"xOzdEhT/fZr5AoGoOYSHdBoixOrztsJqoJSkfZrmGbSITVfr/p/KD9XwUYRn0EGq\n"
    @"hVWN/HWPU5uu1TJ6nrbmuFHu99ydjohsgse+O20nskgacMxnO90L8rahKqnxz5ex\n"
    @"HSfmn2NfB9Z5+cMK335eXYp4+RXeJv7PXIW2eWDJElO+qr5jZky3c8Vx62jGasQr\n"
    @"A+2ld2o5eEAwAfqRTy9quTtClCaucR5zVyq2Al7VromYSnVe1LMqj+VwHR8tVAlk\n"
    @"O+01zse45Gyrl/13YqUOGig+bhG0WTew2cF1TMK7fwnYLid/GD4Pn7gJBnglShd5\n"
    @"nwKEXyse/6YC/TsEHgTxzbkEOX8o0fVIGusQ2v3Jxne7ikqtE/D3i10wJzBBzxfo\n"
    @"rHFFl8gJdejq2YpclwXJN52cNVDEfz43gwDrCvh3WnfSrZmbAOAzbgNd4GMOLJ+Q\n"
    @"PaAAdes295n++ShU6Cf6qEusxPhhazWqxjf86PPmAZNDRjrb4MbVY0DZK3Pq8Pr3\n"
    @"bOVxzRSReu8phM/wcUuk4PVnHtE1ewN9mkWCqIDumibOTYPPVPXAF09SLB7TK0Lz\n"
    @"XZWrvA+U/A1g+JgNbjslio7ezgf9RtMBOvj63pYwLTvYqZnQalTmxlTTs8ThEeFK\n"
    @"3Xm7AgMBAAGjQjBAMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMB0G\n"
    @"A1UdDgQWBBT9ffZwg9GBhCkDqTmtK0dNezxl8DANBgkqhkiG9w0BAQsFAAOCAgEA\n"
    @"l3I3BZ6e88Q+vmOgQoLgc9JS+tQHSfTf1PFhlxHcMpvLcFQ66VFJowrARtDEIdHj\n"
    @"1xFJpoidXVAtX9ku4toT+65G9EnGvjut4zf1BcqAesxeSlMpr8nYIff2RZpNOkeF\n"
    @"bURKabyfOHeK28SiJaOhCpZZznzlBwpI68zdAHRA12wiVjZHx1sZwK2eRJB+GE59\n"
    @"d9HTM3xntWW1rJRUOS83HbaxN3P/XcD/DLcfRQf1GTszsxh3MpYFOOGMODV7xJ+a\n"
    @"LQ5sdvsTtslcgqgaGqVMyShcKB12PFyJOsScZHMPFK2Bu9VnR5yUQsJLxlYtHJS7\n"
    @"9IpAy/XW/ivEsTZJd6VrTsBobRIrUkLGgJnK1pFlcIDO6Cj1K/ZpX7u+v1aD+Btu\n"
    @"2C1bHc0kwqj7xYv7EQUfeseiig/9prHCKpPrZp9cH+UppQZCXdINFvu+0w+3pdzr\n"
    @"AStjq18eOYpplAAbkqj5WhNDCS3jF+7Uf/Azkh7BpG+ZTb+J3xBiU+SUZZoTIjc0\n"
    @"hnbgyPPvzE1X+EMbR/5bQFeoxgEzp+MvWXIfgtQNptdIaPiRr0paKktF//2vP6JR\n"
    @"/qle/sPmxhj5/U3SvLifM3lNnK21AEhJkCJSzTXffCWem+FP5c8Vr5xWG7p3q+cr\n"
    @"0qsmhfuPRNBMd7cfE0Qz1koitWi9U3jVedH2eUNCf5k=\n"
    @"-----END CERTIFICATE-----";
    
    SecCertificateRef certRef = [self createSecCertFromPEM: rootCertPEM];
    id<CBLMultipeerAuthenticator> auth =
    [[CBLMultipeerCertificateAuthenticator alloc] initWithRootCerts: @[(__bridge id) certRef]];
    
    // Note : Only active replicator will have the replicator status error. The passive replicator
    // doesn't get started due to authentication error. As we don't know in advance which peer
    // will have an active replicator, setup the listener for both.
    XCTestExpectation* xStopped = [self expectationWithDescription: @"Stopped"];
    
    CBLMultipeerReplicator *repl1, *repl2;
    
    // Peer#1
    repl1 = [self multipeerReplicatorForDatabase: self.db authenticator: auth collectionConfigureBlock: nil];
    id<CBLListenerToken> token1 = [repl1 addPeerReplicatorStatusListenerWithQueue: nil
                                                                         listener: ^(CBLPeerReplicatorStatus* change) {
        if (change.status.activity == kCBLReplicatorStopped) {
            NSError* error = change.status.error;
            AssertNotNil(error);
            AssertEqual(error.code, CBLErrorTLSClientCertRejected);
            AssertEqualObjects(error.domain, CBLErrorDomain);
            [xStopped fulfill];
        }
    }];
    [self startMultipeerReplicator: repl1];
    
    // Peer#2
    repl2 = [self multipeerReplicatorForDatabase: self.otherDB authenticator: auth collectionConfigureBlock: nil];
    id<CBLListenerToken> token2 = [repl2 addPeerReplicatorStatusListenerWithQueue: nil
                                                                         listener: ^(CBLPeerReplicatorStatus* change) {
        if (change.status.activity == kCBLReplicatorStopped) {
            NSError* error = change.status.error;
            AssertNotNil(error);
            AssertEqual(error.code, CBLErrorTLSClientCertRejected);
            AssertEqualObjects(error.domain, CBLErrorDomain);
            [xStopped fulfill];
        }
    }];
    [self startMultipeerReplicator: repl2];
    
    [self waitForExpectations: @[xStopped] timeout: kExpTimeout];
    
    [self stopMultipeerReplicator: repl1];
    [self stopMultipeerReplicator: repl2];
    
    [token1 remove];
    [token2 remove];
}

/**
 ### 9. TestAuthenticationWithCallbackFailed
 
 #### Description
 Test that the authenticator can reject via the authentication callback.
 
 #### Steps
 
 1. Create MultipeerReplicator#1 for db#1 with the following config:
 - peerGroupID: "MultipeerReplTestGroup"
 - identity: A TLSIdentity signed by an issuer from asset #1.
 - authenticator: Authenticator with a callback that returns false.
 - collections: Collection configs containing the default collection.
 2. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
 3. Start MultipeerReplicator#1 and wait until the replicator is active.
 4. Create MultipeerReplicator#2 for db#2 with the following config:
 - peerGroupID: "MultipeerReplTestGroup"
 - identity: A TLSIdentity signed by an issuer from asset #1.
 - authenticator: Authenticator with the issuer certificate.
 - collections: Collection configs containing the default collection.
 5. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
 6. Start MultipeerReplicator#2 and wait until the replicator is active.
 7. Wait until a peer's replicator becomes STOPPED with a TLSClientCertRejected (5010) error.
 Only the MultipeerReplicator that has an active replicator will report the replicator status.
 As you don't know which MultipeerReplicator's replicator will be active,
 you should listen to the replicator status on both MultipeerReplicators and ensure
 that one of the replicators is STOPPED with the error.
 */
- (void) testAuthenticateWithCallbackFailed {
    CBLMultipeerReplicator *repl1, *repl2;
    
    id<CBLMultipeerAuthenticator> auth =
    [[CBLMultipeerCertificateAuthenticator alloc] initWithBlock:^BOOL(CBLPeerID *peerID, NSArray *certs) {
        AssertNotNil(peerID);
        Assert(certs.count > 0);
        return false;
    }];
    
    // Note : Only active replicator will have the replicator status error. The passive replicator
    // doesn't get started due to authentication error. As we don't know in advance which peer
    // will have an active replicator, setup the listener for both.
    XCTestExpectation* xStopped = [self expectationWithDescription: @"Stopped"];
    
    // Peer#1
    repl1 = [self multipeerReplicatorForDatabase: self.db authenticator: auth collectionConfigureBlock: nil];
    id<CBLListenerToken> token1 = [repl1 addPeerReplicatorStatusListenerWithQueue: nil
                                                                         listener: ^(CBLPeerReplicatorStatus* change) {
        if (change.status.activity == kCBLReplicatorStopped) {
            NSError* error = change.status.error;
            AssertNotNil(error);
            AssertEqual(error.code, CBLErrorTLSClientCertRejected);
            AssertEqualObjects(error.domain, CBLErrorDomain);
            [xStopped fulfill];
        }
    }];
    [self startMultipeerReplicator: repl1];
    
    // Peer#2
    repl2 = [self multipeerReplicatorForDatabase: self.otherDB authenticator: auth collectionConfigureBlock: nil];
    id<CBLListenerToken> token2 = [repl2 addPeerReplicatorStatusListenerWithQueue: nil
                                                                         listener: ^(CBLPeerReplicatorStatus* change) {
        if (change.status.activity == kCBLReplicatorStopped) {
            NSError* error = change.status.error;
            AssertNotNil(error);
            AssertEqual(error.code, CBLErrorTLSClientCertRejected);
            AssertEqualObjects(error.domain, CBLErrorDomain);
            [xStopped fulfill];
        }
    }];
    [self startMultipeerReplicator: repl2];
    
    [self waitForExpectations: @[xStopped] timeout: kExpTimeout];
    
    [self stopMultipeerReplicator: repl1];
    [self stopMultipeerReplicator: repl2];
    
    [token1 remove];
    [token2 remove];
}

#pragma mark - Listener

/**
 ### 10. TestPeerDiscoveryListener
 
 #### Description
 Test that the peer discovery listener can receive the peer discovery events.
 
 #### Steps
 
 1. Create MultipeerReplicator#1 for db#1 with the following config:
 - peerGroupID: "MultipeerReplTestGroup"
 - identity: A TLSIdentity signed by an issuer from asset #1.
 - authenticator: Authenticator with a callback returning true.
 - collections: Collection configs containing the default collection.
 2. Add a listener to monitor the replicator’s active status.
 3. Add a listener to monitor peer discovery status.
 4. Start MultipeerReplicator#1 and wait until the replicator is active.
 5. Create MultipeerReplicator#2 for db#2 with the following config:
 - peerGroupID: "MultipeerReplTestGroup"
 - identity: A TLSIdentity signed by an issuer from asset #1.
 - authenticator: Authenticator with a callback returning true.
 - collections: Collection configs containing the default collection.
 6. Add a listener to monitor the replicator’s active status,
 7. Add a listener to monitor peer discovery status.
 8. Start MultipeerReplicator#2 and wait until the replicator is active.
 9. Based on the peer discovery listener of the MultipeerReplicator#1,
 wait until MultipeerReplicator#2 is online.
 10. Based on the peer discovery listener of the MultipeerReplicator#2,
 wait until MultipeerReplicator#1 is online.
 11. Stop MultipeerReplicator#1 and wait until the replicator is inactive.
 12. Based on the peer discovery listener of the MultipeerReplicator#2,
 wait until MultipeerReplicator#1 is offline.
 13. Stop MultipeerReplicator#2 and wait until the replicator is inactive.
 */
- (void) testPeerDiscoveryListener {
    CBLMultipeerReplicator *repl1, *repl2;
    
    repl1 = [self multipeerReplicatorForDatabase: self.db];
    repl2 = [self multipeerReplicatorForDatabase: self.otherDB];
    
    XCTestExpectation* xPeer2Online = [self expectationWithDescription: @"Peer#2 Online"];
    id<CBLListenerToken> token1 = [repl1 addPeerDiscoveryStatusListenerWithQueue: _listenerQueue
                                                                        listener: ^(CBLPeerDiscoveryStatus *status) {
        AssertEqualObjects(status.peerID, repl2.peerID);
        if (status.online) {
            [xPeer2Online fulfill];
        }
    }];
    [self startMultipeerReplicator: repl1];
    
    XCTestExpectation* xPeer1Online = [self expectationWithDescription: @"Peer#1 Online"];
    XCTestExpectation* xPeer1Offline = [self expectationWithDescription: @"Peer#1 Offline"];
    xPeer1Offline.assertForOverFulfill = NO;
    
    id<CBLListenerToken> token2 = [repl2 addPeerDiscoveryStatusListenerWithQueue: _listenerQueue
                                                                        listener: ^(CBLPeerDiscoveryStatus *status) {
        AssertEqualObjects(status.peerID, repl1.peerID);
        if (status.online) {
            [xPeer1Online fulfill];
        } else {
            [xPeer1Offline fulfill];
        }
    }];
    [self startMultipeerReplicator: repl2];
    
    [self waitForExpectations: @[xPeer2Online, xPeer1Online] timeout: kExpTimeout];
    
    [NSThread sleepForTimeInterval: 1.0];
    
    [self stopMultipeerReplicator: repl1];
    
    [self waitForExpectations: @[xPeer1Offline] timeout: kExpTimeout];
    
    [self stopMultipeerReplicator: repl2];
    
    [token1 remove];
    [token2 remove];
}

/**
 ### 11. TestDocumentReplicationListener

 #### Description
 Test that the document replication listener can receive the document replication events.
 Note : This test could be combined with TestBasicReplication.

 #### Steps

 1. Create MultipeerReplicator#1 for db#1 with the following config:
     - peerGroupID: "MultipeerReplTestGroup"
     - identity: A TLSIdentity signed by an issuer from asset #1.
     - authenticator: Authenticator with a callback returning true.
     - collections: Collection configs containing the default collection.
 2. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
 3. Add a document replication listener that will record the document replication events.
 4. Start MultipeerReplicator#1 and wait until the replicator is active.
 5. Create MultipeerReplicator#2 for db#2 with the following config:
     - peerGroupID: "MultipeerReplTestGroup"
     - identity: A TLSIdentity signed by an issuer from asset #1.
     - authenticator: Authenticator with a callback returning true.
     - collections: Collection configs containing the default collection.
 6. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
 7. Add a document replication listener that will record the document replication events.
 8. Start MultipeerReplicator#2 and wait until the replicator is active.
 9. Create a document in the default collection of db#1:
     - docID: "doc1"
     - body: {"greeting": "hello"}
 10. For MultipeerReplicator#1, wait until the replicator to peer#2 becomes IDLE without an error.
 11. For MultipeerReplicator#2, wait until the replicator to peer#1 becomes IDLE without an error.
 12. Verify the recorded document replication events of MultipeerReplicator#1.
     - Verify that number of document replication : 1
     - Verify that number of replicated document : 1
     - Verify the replicated document :
         { isPush : true,  id : "doc1", flags : 0, error: NULL, scope: " _default", collection: "_default" }
 13. Verify the recorded document replication events of MultipeerReplicator#1.
     - Verify that number of document replication : 1
     - Verify that number of replicated document : 1
     - Verify the replicated document :
     { isPush : false,  id : "doc1", flags : 0, error: NULL, scope: " _default", collection: "_default" }
 14. Stop both replicators and wait until the replicators are inactive.
 */
- (void) testDocumentReplicationListener {
    CBLMultipeerReplicator *repl1, *repl2;
    
    repl1 = [self multipeerReplicatorForDatabase: self.db];
    NSMutableArray<CBLPeerDocumentReplication*>* docRepl1 = [NSMutableArray array];
    id<CBLListenerToken> token1 = [repl1 addPeerDocumentReplicationListenerWithQueue: _listenerQueue
                                                                            listener: ^(CBLPeerDocumentReplication *docRepl) {
        [docRepl1 addObject: docRepl];
    }];
    
    repl2 = [self multipeerReplicatorForDatabase: self.otherDB];
    NSMutableArray<CBLPeerDocumentReplication*>* docRepl2 = [NSMutableArray array];
    id<CBLListenerToken> token2 = [repl2 addPeerDocumentReplicationListenerWithQueue: _listenerQueue
                                              listener: ^(CBLPeerDocumentReplication *docRepl) {
        [docRepl2 addObject: docRepl];
    }];
    
    [self startMultipeerReplicator: repl1];
    [self startMultipeerReplicator: repl2];
    
    // Save a doc in one peer:
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"hello" forKey: @"greeting"];
    [self saveDocument: doc1 collection: self.defaultCollection];
    
    [self waitForReplicatorStatus: repl1 peerID: repl2.peerID activityLevel: kCBLReplicatorIdle];
    [self waitForReplicatorStatus: repl2 peerID: repl1.peerID activityLevel: kCBLReplicatorIdle];
    
    AssertEqual(docRepl1.count, 1);
    Assert(docRepl1[0].isPush);
    AssertEqual(docRepl1[0].documents.count, 1);
    AssertEqualObjects(docRepl1[0].documents[0].id, @"doc1");
    AssertEqual(docRepl1[0].documents[0].flags, 0);
    AssertNil(docRepl1[0].documents[0].error);
    AssertEqualObjects(docRepl1[0].documents[0].scope, @"_default");
    AssertEqualObjects(docRepl1[0].documents[0].collection, @"_default");
    
    AssertEqual(docRepl2.count, 1);
    AssertFalse(docRepl2[0].isPush);
    AssertEqual(docRepl2[0].documents.count, 1);
    AssertEqualObjects(docRepl2[0].documents[0].id, @"doc1");
    AssertEqual(docRepl2[0].documents[0].flags, 0);
    AssertNil(docRepl2[0].documents[0].error);
    AssertEqualObjects(docRepl2[0].documents[0].scope, @"_default");
    AssertEqualObjects(docRepl2[0].documents[0].collection, @"_default");
    
    [self stopMultipeerReplicator: repl1];
    [self stopMultipeerReplicator: repl2];
    
    [token1 remove];
    [token2 remove];
}

#pragma mark - Conflict Resolver

- (void) runConflictResolverTestWithResolver: (nullable MultipeerConflictResolver*)resolver
                                 verifyBlock: (BOOL(^)(CBLDocument* _Nullable resolvedDoc))verifyBlock {
    CBLMultipeerReplicator *repl1, *repl2;
    
    // Peer#1
    repl1 = [self multipeerReplicatorForDatabase: self.db
                        collectionConfigureBlock: ^(CBLMultipeerCollectionConfiguration* config) {
        config.conflictResolver = resolver;
    }];
    [self startMultipeerReplicator: repl1];
    
    // Peer#2
    repl2 = [self multipeerReplicatorForDatabase: self.otherDB
                        collectionConfigureBlock: ^(CBLMultipeerCollectionConfiguration* config) {
        config.conflictResolver = resolver;
    }];
    [self startMultipeerReplicator: repl2];
    
    // Save a doc in peer #1:
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"hello" forKey: @"greeting"];
    [self saveDocument: doc1 collection: self.defaultCollection];
    
    // Wait until the replicator is IDLE
    [self waitForReplicatorStatus: repl1 peerID: repl2.peerID activityLevel: kCBLReplicatorIdle];
    [self waitForReplicatorStatus: repl2 peerID: repl1.peerID activityLevel: kCBLReplicatorIdle];
    
    // Stops:
    [self stopMultipeerReplicator: repl1];
    [self stopMultipeerReplicator: repl2];
    
    // Update the doc in both peers but saving on the otherDB twice:
    doc1 = [[self.defaultCollection documentWithID: @"doc1" error: nil] toMutable];
    [doc1 setString: @"hi" forKey: @"greeting"];
    [self saveDocument:doc1 collection: self.defaultCollection];
    
    CBLMutableDocument* doc2 = [[self.otherDBDefaultCollection documentWithID: @"doc1" error: nil] toMutable];
    [doc2 setString: @"hey" forKey: @"greeting"];
    [self saveDocument:doc2 collection: self.otherDBDefaultCollection];
    
    [doc2 setString: @"howdy" forKey: @"greeting"];
    [self saveDocument:doc2 collection: self.otherDBDefaultCollection];
    
    // Restart both peers:
    
    repl1 = [self multipeerReplicatorForDatabase: self.db
                        collectionConfigureBlock:^(CBLMultipeerCollectionConfiguration* config) {
        config.conflictResolver = resolver;
    }];
    [self startMultipeerReplicator: repl1];
    
    repl2 = [self multipeerReplicatorForDatabase: self.otherDB
                        collectionConfigureBlock: ^(CBLMultipeerCollectionConfiguration* config) {
        config.conflictResolver = resolver;
    }];
    [self startMultipeerReplicator: repl2];
    
    // Wait until the replicator is IDLE
    [self waitForReplicatorStatus: repl1 peerID: repl2.peerID activityLevel: kCBLReplicatorIdle];
    [self waitForReplicatorStatus: repl2 peerID: repl1.peerID activityLevel: kCBLReplicatorIdle];
    
    // Check the doc on both peers:
    CBLDocument* checkDoc1 = [self.defaultCollection documentWithID: @"doc1" error: nil];
    Assert(verifyBlock(checkDoc1));
    
    CBLDocument* checkDoc2 = [self.otherDBDefaultCollection documentWithID: @"doc1" error: nil];
    Assert(verifyBlock(checkDoc2));
    
    [self stopMultipeerReplicator: repl1];
    [self stopMultipeerReplicator: repl2];
}

 /**
  ### 12. TestDefaultConflictResolver

  #### Description
  Test that default conflict resolver is used when no custom conflict resolver specified.

  #### Steps

  1. Create MultipeerReplicator#1 for db#1 with the following config:
      - peerGroupID: "MultipeerReplTestGroup"
      - identity: A TLSIdentity signed by an issuer from asset #1.
      - authenticator: Authenticator with a callback that returns false.
      - collections: Collection configs containing the default collection.
  2. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
  3. Start MultipeerReplicator#1 and wait until the replicator is active.
  4. Create MultipeerReplicator#2 for db#2 with the following config:
      - peerGroupID: "MultipeerReplTestGroup"
      - identity: A TLSIdentity signed by an issuer from asset #1.
      - authenticator: Authenticator with a callback that returns false.
      - collections: Collection configs containing the default collection.
  5. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
  6. Start MultipeerReplicator#1 and wait until the replicator is active.
  7. Create a document in the default collection of db#1:
      - docID: "doc1"
      - body: {"greeting": "hello"}
  8. For MultipeerReplicator#1, wait until the replicator to peer#2 becomes IDLE without an error.
  9. For MultipeerReplicator#2, wait until the replicator to peer#1 becomes IDLE without an error.
  10. Stop MultipeerReplicator#2 and wait until the replicator is inactive.
  11. Update doc1 in db#1
      - docID: "doc1"
      - body: {"greeting": "hi"}
  12. Update doc1 in db#2
      - docID: "doc1"
      - body: {"greeting": "hey"}
  13. Update doc1 in db#2 again.
      - docID: "doc1"
      - body: {"greeting": "howdy"}
  14. Recreate and start both MultipeerReplicators.
  15. For MultipeerReplicator#1, wait until the replicator to peer#2 becomes IDLE without an error.
  16. For MultipeerReplicator#2, wait until the replicator to peer#1 becomes IDLE without an error.
  17. Stop both MultipeerReplicators.
  18. Check the doc1 in both peers and verify that the its body is {"greeting": "howdy"}.
  */
- (void) testDefaultConflictResolver {
    [self runConflictResolverTestWithResolver: nil verifyBlock: ^BOOL (CBLDocument* resolvedDoc) {
        return [[resolvedDoc stringForKey: @"greeting"] isEqualToString: @"howdy"];
    }];
}

/**
 ### 13. TestCustomConflictResolver

 #### Description
 Test that custom conflict resolver is used when it is specified.

 #### Steps

 1. Create MultipeerReplicator#1 for db#1 with the following config:
     - peerGroupID: "MultipeerReplTestGroup"
     - identity: A TLSIdentity signed by an issuer from asset #1.
     - authenticator: Authenticator with a callback that returns false.
     - collections: Collection configs containing the default collection.
         - A custom conflict resolver running the document having greeting property's value == "hi"
 2. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
 3. Start MultipeerReplicator#1 and wait until the replicator is active.
 4. Create MultipeerReplicator#2 for db#2 with the following config:
     - peerGroupID: "MultipeerReplTestGroup"
     - identity: A TLSIdentity signed by an issuer from asset #1.
     - authenticator: Authenticator with a callback that returns false.
     - collections: Collection configs containing the default collection.
 5. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
 6. Start MultipeerReplicator#1 and wait until the replicator is active.
 7. Create a document in the default collection of db#1:
     - docID: "doc1"
     - body: {"greeting": "hello"}
 8. For MultipeerReplicator#1, wait until the replicator to peer#2 becomes IDLE without an error.
 9. For MultipeerReplicator#2, wait until the replicator to peer#1 becomes IDLE without an error.
 10. Stop MultipeerReplicator#2 and wait until the replicator is inactive.
 11. Update doc1 in db#1
     - docID: "doc1"
     - body: {"greeting": "hi"}
 12. Update doc1 in db#2
     - docID: "doc1"
     - body: {"greeting": "hey"}
 13. Update doc1 in db#2 again.
     - docID: "doc1"
     - body: {"greeting": "howdy"}
 14. Recreate and start both MultipeerReplicators.
 15. For MultipeerReplicator#1, wait until the replicator to peer#2 becomes IDLE without an error.
 16. For MultipeerReplicator#2, wait until the replicator to peer#1 becomes IDLE without an error.
 17. Stop both MultipeerReplicators.
 18. Check the doc1 in both peers and verify that the its body is {"greeting": "hi"}.
 */
- (void) testCustomConflictResolver {
    MultipeerConflictResolverBlock block = ^CBLDocument*(CBLPeerID* peerID, CBLConflict* conflict) {
        NSString* greeting = [conflict.localDocument stringForKey: @"greeting"];
        return [greeting isEqualToString: @"hi"] ? conflict.localDocument : conflict.remoteDocument;
    };
    
    [self runConflictResolverTestWithResolver: [[MultipeerConflictResolver alloc] initWithBlock: block]
                                  verifyBlock: ^BOOL(CBLDocument *resolvedDoc) {
        return [[resolvedDoc stringForKey: @"greeting"] isEqualToString: @"hi"];
    }];
}

#pragma mark - Replication Filter

/**
 ### 14. TestDocumentIDsFilter

 #### Description
 Test that the documentIDs filter is used when it's specified.

 #### Steps
 1. Create MultipeerReplicator#1 for db#1 with the following config:
     - peerGroupID: "MultipeerReplTestGroup"
     - identity: A TLSIdentity signed by an issuer from asset #1.
     - authenticator: Authenticator with a callback that returns false.
     - collections: Collection configs containing the default collection.
         - A documentIDs filter as ["doc1", "doc3"]
 2. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
 3. Start MultipeerReplicator#1 and wait until the replicator is active.
 4. Create MultipeerReplicator#2 for db#2 with the following config:
     - peerGroupID: "MultipeerReplTestGroup"
     - identity: A TLSIdentity signed by an issuer from asset #1.
     - authenticator: Authenticator with a callback that returns false.
     - collections: Collection configs containing the default collection.
 5. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
 6. Start MultipeerReplicator#2 and wait until the replicator is active.
 7. Save 3 documents in db#1
     - doc1: {"greeting": "hello"}
     - doc2: {"greeting": "hi"}
     - doc3: {"greeting": "howdy"}
 8. For MultipeerReplicator#1, wait until the replicator to peer#2 becomes IDLE without an error.
 9. For MultipeerReplicator#2, wait until the replicator to peer#1 becomes IDLE without an error.
 10. Check that only doc1 and doc3 are pushed to MultipeerReplicator#2.
 11. Stop both replicators and wait until the replicators are inactive.
 */
- (void) testDocumentIDsFilter {
    CBLMultipeerReplicator *repl1, *repl2;
    
    // Peer#1
    repl1 = [self multipeerReplicatorForDatabase: self.db
                        collectionConfigureBlock: ^(CBLMultipeerCollectionConfiguration* config) {
        config.documentIDs = @[@"doc1", @"doc3"];
    }];
    [self startMultipeerReplicator: repl1];
    
    // Peer#2
    repl2 = [self multipeerReplicatorForDatabase: self.otherDB];
    [self startMultipeerReplicator: repl2];
    
    // Save 3 docs in peer #1:
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"hello" forKey: @"greeting"];
    [self saveDocument: doc1 collection: self.defaultCollection];
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setString: @"hi" forKey: @"greeting"];
    [self saveDocument: doc2 collection: self.defaultCollection];
    
    CBLMutableDocument* doc3 = [[CBLMutableDocument alloc] initWithID: @"doc3"];
    [doc3 setString: @"howdy" forKey: @"greeting"];
    [self saveDocument: doc3 collection: self.defaultCollection];
    
    // Wait until the replicator is IDLE
    [self waitForReplicatorStatus: repl1 peerID: repl2.peerID activityLevel: kCBLReplicatorIdle];
    [self waitForReplicatorStatus: repl2 peerID: repl1.peerID activityLevel: kCBLReplicatorIdle];
    
    // Check that only doc1 and doc3 are pushed to Peer #2
    CBLDocument* checkDoc1 = [self.otherDBDefaultCollection documentWithID: @"doc1" error: nil];
    AssertNotNil(checkDoc1);
    AssertEqualObjects([checkDoc1 stringForKey: @"greeting"], @"hello");
    
    CBLDocument* checkDoc2 = [self.otherDBDefaultCollection documentWithID: @"doc2" error: nil];
    AssertNil(checkDoc2);
    
    CBLDocument* checkDoc3 = [self.otherDBDefaultCollection documentWithID: @"doc3" error: nil];
    AssertNotNil(checkDoc3);
    AssertEqualObjects([checkDoc3 stringForKey: @"greeting"], @"howdy");
    
    [self stopMultipeerReplicator: repl1];
    [self stopMultipeerReplicator: repl2];
}

/**
 ### 15. TestPushPullFilter

 #### Description
 Test that the push and pull filter are used when they are specified.

 #### Steps
 1. Create MultipeerReplicator#1 for db#1 with the following config:
     - peerGroupID: "MultipeerReplTestGroup"
     - identity: A TLSIdentity signed by an issuer from asset #1.
     - authenticator: Authenticator with a callback that returns false.
     - collections: Collection configs containing the default collection.
         - pushFilter : Allow only document's ID == "doc1"
         - pullFilter : Allow only document's ID == "doc4"
 2. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
 3. Start MultipeerReplicator#1 and wait until the replicator is active.
 4. Create MultipeerReplicator#2 for db#2 with the following config:
     - peerGroupID: "MultipeerReplTestGroup"
     - identity: A TLSIdentity signed by an issuer from asset #1.
     - authenticator: Authenticator with a callback that returns false.
     - collections: Collection configs containing the default collection.
 5. Add listeners to monitor the replicator’s active status and the peers’ replicator statuses.
 6. Start MultipeerReplicator#2 and wait until the replicator is active.
 7. Save 2 documents in db#1
     - doc1: {"greeting": "hello"}
     - doc2: {"greeting": "hi"}
 8. Save 2 documents in db#2
     - doc3: {"greeting": "howdy"}
     - doc4: {"greeting": "hey"}
 9. For MultipeerReplicator#1, wait until the replicator to peer#2 becomes IDLE without an error.
 10. For MultipeerReplicator#2, wait until the replicator to peer#1 becomes IDLE without an error.
 11. Check that only doc4 but not doc3 are pulled to MultipeerReplicator#1.
 12. Check that only doc1 but not doc2 are pushed to MultipeerReplicator#2.
 13. Stop both replicators and wait until the replicators are inactive.  
 */
- (void) testPushPullFilter {
    CBLMultipeerReplicator *repl1, *repl2;
    
    // Peer#1
    repl1 = [self multipeerReplicatorForDatabase: self.db
                        collectionConfigureBlock: ^(CBLMultipeerCollectionConfiguration* config) {
        config.pushFilter = ^BOOL(CBLPeerID* peerID, CBLDocument* doc, CBLDocumentFlags flags) {
            return [doc.id isEqualToString: @"doc1"];
        };
        config.pullFilter = ^BOOL(CBLPeerID* peerID, CBLDocument* doc, CBLDocumentFlags flags) {
            return [doc.id isEqualToString: @"doc4"];
        };
    }];
    [self startMultipeerReplicator: repl1];
    
    // Peer#2
    repl2 = [self multipeerReplicatorForDatabase: self.otherDB];
    [self startMultipeerReplicator: repl2];
    
    // Save doc1 and doc2 in peer #1:
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"hello" forKey: @"greeting"];
    [self saveDocument: doc1 collection: self.defaultCollection];
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setString: @"hi" forKey: @"greeting"];
    [self saveDocument: doc2 collection: self.defaultCollection];
    
    // Save doc3 and doc4 in peer #2:
    CBLMutableDocument* doc3 = [[CBLMutableDocument alloc] initWithID: @"doc3"];
    [doc3 setString: @"howdy" forKey: @"greeting"];
    [self saveDocument: doc3 collection: self.otherDBDefaultCollection];
    
    CBLMutableDocument* doc4 = [[CBLMutableDocument alloc] initWithID: @"doc4"];
    [doc4 setString: @"hey" forKey: @"greeting"];
    [self saveDocument: doc4 collection: self.otherDBDefaultCollection];
    
    // Wait until the replicator is IDLE:
    [self waitForReplicatorStatus: repl1 peerID: repl2.peerID activityLevel: kCBLReplicatorIdle];
    [self waitForReplicatorStatus: repl2 peerID: repl1.peerID activityLevel: kCBLReplicatorIdle];
    
    // Check that only doc4 but not doc3 are pulled to peer #1:
    CBLDocument* checkDoc4 = [self.defaultCollection documentWithID: @"doc4" error: nil];
    AssertNotNil(checkDoc4);
    AssertEqualObjects([checkDoc4 stringForKey: @"greeting"], @"hey");
    
    CBLDocument* checkDoc3 = [self.defaultCollection documentWithID: @"doc3" error: nil];
    AssertNil(checkDoc3);
    
    // Check that only doc1 but not doc2 are pushed to peer #2:
    CBLDocument* checkDoc1 = [self.otherDBDefaultCollection documentWithID: @"doc1" error: nil];
    AssertNotNil(checkDoc1);
    AssertEqualObjects([checkDoc1 stringForKey: @"greeting"], @"hello");
    
    CBLDocument* checkDoc2 = [self.otherDBDefaultCollection documentWithID: @"doc2" error: nil];
    AssertNil(checkDoc2);
    
    [self stopMultipeerReplicator: repl1];
    [self stopMultipeerReplicator: repl2];
}

#pragma mark - Peer Info

/**
 ### 16. TestPeerID

 #### Description
 Test that getting the MultipeerReplicator's peerID returns a value as expected.

 #### Steps
 1. Create a MultipeerReplicator#1 for a database with the following config:
     - peerGroupID: "MultipeerReplTestGroup"
     - identity: A TLSIdentity signed by an issuer from asset #1.
     - authenticator: An authenticator with a callback that returns true.
     - collections: Collection configs containing the default collection.
 2. Get the peerID of the replicator and and check that its data length is 32 bytes.
 3. Start MultipeerReplicator#1 and wait until the replicator is active.
 4. Stop MultipeerReplicator#1 and wait until the replicator is inactive.
 5. Get the peerID of the replicator and and check that its data length is 32 bytes.
 */
- (void) testPeerID {
    CBLMultipeerReplicator *repl = [self multipeerReplicatorForDatabase: self.db];
    AssertNotNil(repl.peerID);
    AssertEqual(repl.peerID.bytes.length, 32);
    
    [self startMultipeerReplicator: repl];
    [self stopMultipeerReplicator: repl];
    
    AssertNotNil(repl.peerID);
    AssertEqual(repl.peerID.bytes.length, 32);
}

/**
 ### 17. TestNeighborPeers

 #### Description
 Test that getting the MultipeerReplicator's neighborPeers returns the online peers
 as expected.

 #### Steps
 1. Create a MultipeerReplicator#1 for a database with the following config:
     - peerGroupID: "MultipeerReplTestGroup"
     - identity: A TLSIdentity signed by an issuer from asset #1.
     - authenticator: An authenticator with a callback that returns true.
     - collections: Collection configs containing the default collection.
 2. Verify that MultipeerReplicator#1's neighborPeers is empty.
 3. Start MultipeerReplicator#1.
 4. Create MultipeerReplicator#2 for db#2 with the following config:
     - peerGroupID: "MultipeerReplTestGroup"
     - identity: A TLSIdentity signed by an issuer from asset #1.
     - authenticator: Authenticator with a callback that returns false.
     - collections: Collection configs containing the default collection.
 5. Verify that MultipeerReplicator#2's neighborPeers is empty.
 6. Start MultipeerReplicator#2
 7. For MultipeerReplicator#1, wait until the replicator to peer#2 becomes IDLE without an error.
 8. Verify that MultipeerReplicator#1's neighborPeers includes MultipeerReplicator#2’s peerID.
 9. Verify that MultipeerReplicator#2's neighborPeers includes MultipeerReplicator#1’s peerID.
 10. Stop MultipeerReplicator#1 and wait until the replicator is inactive.
 11. Verify that the neighborPeers of both replicators are empty.
 12. Stop MultipeerReplicator#2 and wait until the replicator is inactive.
 13. Verify that MultipeerReplicator#2's neighborPeers is empty.
 */
- (void) testNeighborPeers {
    CBLMultipeerReplicator *repl1, *repl2;
    
    repl1 = [self multipeerReplicatorForDatabase: self.db];
    AssertEqual(repl1.neighborPeers.count, 0);
    
    [self startMultipeerReplicator: repl1];
    AssertEqual(repl1.neighborPeers.count, 0);
    
    repl2 = [self multipeerReplicatorForDatabase: self.otherDB];
    AssertEqual(repl2.neighborPeers.count, 0);
    
    [self startMultipeerReplicator: repl2];
    
    [self waitForReplicatorStatus: repl2 peerID: repl1.peerID activityLevel: kCBLReplicatorIdle];
    
    AssertEqual(repl1.neighborPeers.count, 1);
    AssertEqualObjects(repl1.neighborPeers[0], repl2.peerID);
    
    AssertEqual(repl2.neighborPeers.count, 1);
    AssertEqualObjects(repl2.neighborPeers[0], repl1.peerID);
    
    [self stopMultipeerReplicator: repl1];
    AssertEqual(repl1.neighborPeers.count, 0);
    
    // Wait to ensure the neighborPeers are updated
    [NSThread sleepForTimeInterval: 5.0];
    AssertEqual(repl2.neighborPeers.count, 0);
    
    [self stopMultipeerReplicator: repl2];
    AssertEqual(repl2.neighborPeers.count, 0);
}

/**
 ### 18. TestPeerInfo

 #### Description
 Verify that retrieving peer info returns the expected PeerInfo object for known peers.
 If the peer is unknown, ensure that nil is returned as expected.

 #### Steps
 1. Create a MultipeerReplicator#1 for a database with the following config:
     - peerGroupID: "MultipeerReplTestGroup"
     - identity: A TLSIdentity signed by an issuer from asset #1.
     - authenticator: An authenticator with a callback that returns true.
     - collections: Collection configs containing the default collection.
 2. Create MultipeerReplicator#2 for db#2 with the following config:
     - peerGroupID: "MultipeerReplTestGroup"
     - identity: A TLSIdentity signed by an issuer from asset #1.
     - authenticator: Authenticator with a callback that returns false.
     - collections: Collection configs containing the default collection.
 3. From MultipeerReplicator#1, get peerInfo using its own peerID.
 4. Verify:
     - The returned peerInfo is not nil.
     - The peerID matches MultipeerReplicator#1’s peerID.
     - The certificate is not nil.
     - neighborPeers is empty.
     - The replicator activity level is STOPPED.
 5. From MultipeerReplicator#1, get peerInfo using MultipeerReplicator#2’s peerID.
 6. Verify that the returned peerInfo is nil as the peer is not yet discovered.
 7. Start both MultipeerReplicators.
 8. For MultipeerReplicator#1, wait until the replicator to peer#2 becomes IDLE without an error.
 9. For MultipeerReplicator#2, wait until the replicator to peer#1 becomes IDLE without an error.
 10. Re-fetch peerInfo from MultipeerReplicator#1 using both its own and MultipeerReplicator#2’s peerID.
 11.    Verify MultipeerReplicator#1's own peerInfo:
     - neighborPeers contains Replicator#2's peerID.
     - Activity level is STOPPED as no replication to itself
 12.    Verify MultipeerReplicator#2' peerInfo:
     - neighborPeers contains Replicator#1's peerID.
     - Activity level is IDLE
 13. Stop both replicators and wait until the replicators are inactive.
 */
- (void) testPeerInfo {
    CBLMultipeerReplicator *repl1, *repl2;
    
    repl1 = [self multipeerReplicatorForDatabase: self.db];
    repl2 = [self multipeerReplicatorForDatabase: self.otherDB];
    
    CBLPeerInfo* repl1Peer1 = [repl1 peerInfoForPeerID: repl1.peerID];
    AssertNotNil(repl1Peer1);
    AssertEqualObjects(repl1Peer1.peerID, repl1.peerID);
    AssertNotNil((__bridge id)repl1Peer1.certificate);
    AssertEqual(repl1Peer1.neighborPeers.count, 0);
    AssertEqual(repl1Peer1.replicatorStatus.activity, kCBLReplicatorStopped);
    
    CBLPeerInfo* repl1Peer2 = [repl1 peerInfoForPeerID: repl2.peerID];
    AssertNil(repl1Peer2);
    
    [self startMultipeerReplicator: repl1];
    [self startMultipeerReplicator: repl2];
    
    [self waitForReplicatorStatus: repl1 peerID: repl2.peerID activityLevel: kCBLReplicatorIdle];
    [self waitForReplicatorStatus: repl2 peerID: repl1.peerID activityLevel: kCBLReplicatorIdle];
    
    repl1Peer1 = [repl1 peerInfoForPeerID: repl1.peerID];
    AssertNotNil(repl1Peer1);
    AssertEqual(repl1Peer1.neighborPeers.count, 1);
    AssertEqualObjects(repl1Peer1.neighborPeers[0], repl2.peerID);
    AssertEqual(repl1Peer1.replicatorStatus.activity, kCBLReplicatorStopped); // No replication to itself
    
    repl1Peer2 = [repl1 peerInfoForPeerID: repl2.peerID];
    AssertNotNil(repl1Peer2);
    AssertEqual(repl1Peer2.neighborPeers.count, 1);
    AssertEqualObjects(repl1Peer2.neighborPeers[0], repl1.peerID);
    AssertEqual(repl1Peer2.replicatorStatus.activity, kCBLReplicatorIdle);
    
    [self stopMultipeerReplicator: repl1];
    [self stopMultipeerReplicator: repl2];
}

@end
