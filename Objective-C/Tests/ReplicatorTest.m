//
//  ReplicatorTest.m
//  CouchbaseLite
//
//  Copyright (c) 2025 Couchbase, Inc All rights reserved.
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
#import "CollectionUtils.h"

#ifdef COUCHBASE_ENTERPRISE
#endif

@implementation ReplicatorTest {
    BOOL _stopped;
}

@synthesize disableDefaultServerCertPinning=_disableDefaultServerCertPinning;
@synthesize crashWhenStoppedTimeoutOccurred=_crashWhenStoppedTimeoutOccurred;

// TODO: Remove https://issues.couchbase.com/browse/CBL-3206
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

- (void) setUp {
    [super setUp];
    
    self.crashWhenStoppedTimeoutOccurred = YES;
    
    [self openOtherDB];
}

- (void) tearDown {
    repl = nil;
    [super tearDown];
}

#pragma mark - Endpoint

#pragma mark - Certificate

- (SecCertificateRef) defaultServerCert {
    NSData* certData = [self dataFromResource: @"SelfSigned" ofType: @"cer"];
    SecCertificateRef cert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certData);
    Assert(cert);
    return (SecCertificateRef)CFAutorelease(cert);
}

- (NSString*) getCertificateID: (SecCertificateRef)cert {
    CFErrorRef* errRef = NULL;
        NSData* data = (NSData*)CFBridgingRelease(SecCertificateCopySerialNumberData(cert, errRef));
        Assert(errRef == NULL);
        return [NSString stringWithFormat: @"%lu", (unsigned long)[data hash]];
}

#pragma mark - Configs

- (CBLReplicatorConfiguration*) configWithTarget: (id<CBLEndpoint>)target
                                            type: (CBLReplicatorType)type
                                      continuous: (BOOL)continuous {
    return [self configWithTarget: target
                             type: type
                       continuous: continuous
                    authenticator: nil
                       serverCert: nil];
}

- (CBLReplicatorConfiguration*) configWithTarget: (id<CBLEndpoint>)target
                                            type: (CBLReplicatorType)type
                                      continuous: (BOOL)continuous
                                   authenticator: (nullable CBLAuthenticator*)authenticator {
    return [self configWithTarget: target
                             type: type
                       continuous: continuous
                    authenticator: authenticator
                       serverCert: nil];
}

- (CBLReplicatorConfiguration*) configWithTarget: (id<CBLEndpoint>)target
                                            type: (CBLReplicatorType)type
                                      continuous: (BOOL)continuous
                                   authenticator: (nullable CBLAuthenticator*)authenticator
                                      serverCert: (nullable SecCertificateRef)serverCert {
    return [self configWithTarget: target
                             type: type
                       continuous: continuous
                    authenticator: authenticator
                       serverCert: serverCert
                      maxAttempts: -1];
}

- (CBLReplicatorConfiguration*) configWithTarget: (id<CBLEndpoint>)target
                                            type: (CBLReplicatorType)type
                                      continuous: (BOOL)continuous
                                   authenticator: (nullable CBLAuthenticator*)authenticator
                                      serverCert: (nullable SecCertificateRef)serverCert
                                     maxAttempts: (NSInteger)maxAttempts /* for default, set -1 */ {
    CBLReplicatorConfiguration* c = [self configWithCollections: @[self.defaultCollection]
                                                         target: target
                                                           type: type
                                                     continuous: continuous];
    
    c.authenticator = authenticator;
    
    if (maxAttempts >= 0)
        c.maxAttempts = maxAttempts;
    
    if ([$castIf(CBLURLEndpoint, target).url.scheme isEqualToString: @"wss"]) {
        if (serverCert)
            c.pinnedServerCertificate = serverCert;
        else if (!_disableDefaultServerCertPinning)
            c.pinnedServerCertificate = self.defaultServerCert;
    }
    
    return c;
}

#ifdef COUCHBASE_ENTERPRISE
- (CBLReplicatorConfiguration*) configWithTarget: (id<CBLEndpoint>)target
                                            type: (CBLReplicatorType)type
                                      continuous: (BOOL)continuous
                                   authenticator: (nullable CBLAuthenticator*)authenticator
                            acceptSelfSignedOnly: (BOOL)acceptSelfSignedOnly
                                      serverCert: (nullable SecCertificateRef)serverCert {
    CBLReplicatorConfiguration* c = [self configWithTarget: target
                                                      type: type
                                                continuous: continuous
                                             authenticator: authenticator
                                                serverCert: serverCert];
    c.acceptOnlySelfSignedServerCertificate = acceptSelfSignedOnly;
    return c;
}
#endif

- (CBLReplicatorConfiguration*) configWithCollectionConfigs: (NSArray<CBLCollectionConfiguration*>*)configs
                                                     target: (id<CBLEndpoint>)target
                                                       type: (CBLReplicatorType)type
                                                 continuous: (BOOL)continuous {
    CBLReplicatorConfiguration* c = [[CBLReplicatorConfiguration alloc] initWithCollections: configs
                                                                                     target: target];
    c.replicatorType = type;
    c.continuous = continuous;
    return c;
}

- (CBLReplicatorConfiguration*) configWithCollections: (NSArray<CBLCollection*>*)collections
                                               target: (id<CBLEndpoint>)target
                                                 type: (CBLReplicatorType)type
                                           continuous: (BOOL)continuous {
    return [self configWithCollectionConfigs: [CBLCollectionConfiguration fromCollections: collections]
                                      target: target
                                        type: type
                                  continuous: continuous];
}

#pragma mark - Run Replicator

- (BOOL) run: (CBLReplicatorConfiguration*)config
   errorCode: (NSInteger)errorCode
 errorDomain: (NSString*)errorDomain {
    return [self run: config
               reset: NO
           errorCode: errorCode
         errorDomain: errorDomain
   onReplicatorReady: nil];
}

- (BOOL)  run: (CBLReplicatorConfiguration*)config
        reset: (BOOL)reset
    errorCode: (NSInteger)errorCode
  errorDomain: (NSString*)errorDomain {
    return [self run: config
               reset: reset
           errorCode: errorCode
         errorDomain: errorDomain
   onReplicatorReady: nil];
}

- (BOOL) run: (CBLReplicatorConfiguration*)config
       reset: (BOOL)reset
   errorCode: (NSInteger)errorCode
 errorDomain: (NSString*)errorDomain
onReplicatorReady: (nullable void (^)(CBLReplicator*))onReplicatorReady {
    repl = [[CBLReplicator alloc] initWithConfig: config];
    
    if (onReplicatorReady)
        onReplicatorReady(repl);
    
    return [self runWithReplicator: repl
                             reset: reset
                         errorCode: errorCode
                       errorDomain: errorDomain];
}

- (BOOL) runWithTarget: (id<CBLEndpoint>)target
                  type: (CBLReplicatorType)type
            continuous: (BOOL)continuous
         authenticator: (nullable CBLAuthenticator*)authenticator
            serverCert: (nullable SecCertificateRef)serverCert
             errorCode: (NSInteger)errorCode
           errorDomain: (nullable NSString*)errorDomain {
    return [self runWithTarget: target
                          type: type
                    continuous: continuous
                 authenticator: authenticator
                    serverCert: serverCert
                   maxAttempts: -1
                     errorCode: errorCode
                   errorDomain: errorDomain];
}

- (BOOL) runWithTarget: (id<CBLEndpoint>)target
                  type: (CBLReplicatorType)type
            continuous: (BOOL)continuous
         authenticator: (nullable CBLAuthenticator*)authenticator
            serverCert: (nullable SecCertificateRef)serverCert
           maxAttempts: (NSInteger)maxAttempts // set to -1 for default maxRetry
             errorCode: (NSInteger)errorCode
           errorDomain: (nullable NSString*)errorDomain {
    id config = [self configWithTarget: target
                                  type: type
                            continuous: continuous
                         authenticator: authenticator
                            serverCert: serverCert
                           maxAttempts: maxAttempts];
    return [self run: config errorCode: errorCode errorDomain: errorDomain];
}

#ifdef COUCHBASE_ENTERPRISE
- (BOOL) runWithTarget: (id<CBLEndpoint>)target
                  type: (CBLReplicatorType)type
            continuous: (BOOL)continuous
         authenticator: (nullable CBLAuthenticator*)authenticator
  acceptSelfSignedOnly: (BOOL)acceptSelfSignedOnly
            serverCert: (nullable SecCertificateRef)serverCert
             errorCode: (NSInteger)errorCode
           errorDomain: (nullable NSString*)errorDomain {
    id config = [self configWithTarget: target
                                  type: type
                            continuous: continuous
                         authenticator: authenticator
                  acceptSelfSignedOnly: acceptSelfSignedOnly
                            serverCert: serverCert];
    return [self run: config errorCode: errorCode errorDomain: errorDomain];
}
#endif

- (BOOL) runWithReplicator: (CBLReplicator*)replicator
                 errorCode: (NSInteger)errorCode
               errorDomain: (NSString*)errorDomain {
    return [self runWithReplicator: replicator
                             reset: NO
                         errorCode: errorCode
                       errorDomain: errorDomain];
}

- (BOOL) runWithReplicator: (CBLReplicator*)replicator
                     reset: (BOOL)reset
                 errorCode: (NSInteger)errorCode
               errorDomain: (NSString*)errorDomain {
    XCTestExpectation* x = [self expectationWithDescription: @"Replicator Stopped"];
    __block BOOL fulfilled = NO;
    __weak typeof(self) wSelf = self;
    __weak CBLReplicator* wRepl = replicator;
    id token = [replicator addChangeListener: ^(CBLReplicatorChange* change) {
        typeof(self) strongSelf = wSelf;
        CBLReplicator* strongRepl = wRepl;
        [strongSelf verifyChange: change errorCode: errorCode errorDomain:errorDomain];
        if (strongRepl.config.continuous && change.status.activity == kCBLReplicatorIdle
            && change.status.progress.completed == change.status.progress.total) {
            [strongRepl stop];
        }
        if (change.status.activity == kCBLReplicatorStopped) {
            [x fulfill];
            fulfilled = YES;
        }
    }];
    
    if (reset) {
        [replicator startWithReset: reset];
    } else {
        [replicator start];
    }
    
    @try {
        XCTWaiterResult result = [XCTWaiter waitForExpectations: @[x] timeout: kExpTimeout];
        if (result != XCTWaiterResultCompleted) {
            if (result == XCTWaiterResultTimedOut) {
                if (self.crashWhenStoppedTimeoutOccurred) {
                    NSLog(@"!!! Exceeding stopped timeout, let's crash the test to get thread dump ...");
                    assert(false);
                }
                XCTFail(@"Unfulfilled expectations for %@ as exceeding timeout of %f seconds)", x.expectationDescription, kExpTimeout);
            } else {
                XCTFail(@"Unfulfilled expectations for %@ as result = %ld", x.expectationDescription, (long)result);
            }
        }
    }
    @finally {
        if (replicator.status.activity != kCBLReplicatorStopped)
            [replicator stop];
        [token remove];
    }
    
    // Workaround:
    // https://issues.couchbase.com/browse/CBL-1061
    [NSThread sleepForTimeInterval: 0.5];
    
    return fulfilled;
}

- (CBLReplicatorConfiguration*) configForCollection:(CBLCollection*)collection
                                             target:(id <CBLEndpoint>)target
                                        configBlock:(nullable void (^)(CBLCollectionConfiguration *config))block {
    CBLCollectionConfiguration* colConfig = [[CBLCollectionConfiguration alloc] initWithCollection: collection];
    
    if (block) {
        block(colConfig);
    }
    
    return [[CBLReplicatorConfiguration alloc] initWithCollections:@[colConfig] target:target];
}

#pragma mark - Verify Replicator Change

- (void) verifyChange: (CBLReplicatorChange*)change
            errorCode: (NSInteger)code
          errorDomain: (NSString*)domain
{
    CBLReplicatorStatus* s = change.status;
    static const char* const kActivityNames[5] = { "stopped", "offline", "connecting", "idle", "busy" };
    NSLog(@"---Status: %s (%llu / %llu), lastError = %@",
          kActivityNames[s.activity], s.progress.completed, s.progress.total,
          s.error.localizedDescription);
    
    if (s.activity == kCBLReplicatorStopped) {
        if (code != 0) {
            AssertEqual(s.error.code, code);
            if (domain)
                AssertEqualObjects(s.error.domain, domain);
        } else
            AssertNil(s.error);
    }
}

#pragma mark - Wait

- (XCTestExpectation *) waitForReplicatorIdle:(CBLReplicator*)replicator withProgressAtLeast:(uint64_t)progress {
    XCTestExpectation* x = [self expectationWithDescription:@"Replicator idle"];
    __block id token = nil;
    token = [replicator addChangeListener:^(CBLReplicatorChange * _Nonnull change) {
        if(change.status.progress.completed >= progress && change.status.activity == kCBLReplicatorIdle) {
            [x fulfill];
            [token remove];
        }
    }];
    
    return x;
}

- (XCTestExpectation *) waitForReplicatorStopped:(CBLReplicator*)replicator {
    XCTestExpectation* x = [self expectationWithDescription:@"Replicator stop"];
    __block id token = nil;
    token = [replicator addChangeListener:^(CBLReplicatorChange * _Nonnull change) {
        if(change.status.activity == kCBLReplicatorStopped) {
            [x fulfill];
            [token remove];
        }
    }];
    
    return x;
}

#pragma clang diagnostic pop

@end

@implementation TestConflictResolver {
    CBLDocument* (^_resolver)(CBLConflict*);
}

@synthesize winner=_winner;

// set this resolver, which will be used while resolving the conflict
- (instancetype) initWithResolver: (CBLDocument* (^)(CBLConflict*))resolver {
    self = [super init];
    if (self) {
        _resolver = resolver;
    }
    return self;
}

- (CBLDocument *) resolve:(CBLConflict *)conflict {
    _winner = _resolver(conflict);
    return _winner;
}

@end
