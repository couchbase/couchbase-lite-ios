//
//  ReplicatorTest.h
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
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

#import "CBLTestCase.h"

#ifdef COUCHBASE_ENTERPRISE
#import "CBLMessageEndpoint.h"
#import "CBLMockConnection.h"
#import "CBLMockConnectionErrorLogic.h"
#import "CBLMockConnectionLifecycleLocation.h"
#endif

NS_ASSUME_NONNULL_BEGIN

#ifdef COUCHBASE_ENTERPRISE

#pragma mark - Helper Class Interface

@interface MockConnectionFactory : NSObject <CBLMessageEndpointDelegate>

- (instancetype) initWithErrorLogic: (nullable id<CBLMockConnectionErrorLogic>)errorLogic;

- (id<CBLMessageEndpointConnection>) createConnectionForEndpoint: (CBLMessageEndpoint *)endpoint;

@end

#endif

@interface ReplicatorTest : CBLTestCase {
    CBLReplicator* repl;
    NSTimeInterval timeout;    
    BOOL pinServerCert;
}

- (void) saveDocument: (CBLMutableDocument*)document
           toDatabase: (CBLDatabase*)database;

#pragma mark - Endpoint

/** Returns an endpoint for a Sync Gateway test database, or nil if SG tests are not enabled.
 To enable these tests, set the hostname of the server in the environment variable
 "CBL_TEST_HOST".
 The port number defaults to 4984, or 4994 for SSL. To override these, set the environment
 variables "CBL_TEST_PORT" and/or "CBL_TEST_PORT_SSL".
 Note: On iOS, all endpoints will be SSL regardless of the `secure` flag.
 */
- (nullable CBLURLEndpoint*) remoteEndpointWithName: (NSString*)dbName secure: (BOOL)secure;

- (void) eraseRemoteEndpoint: (CBLURLEndpoint*)endpoint;

- (id) sendRequestToEndpoint: (CBLURLEndpoint*)endpoint
                      method: (NSString*)method
                        path: (nullable NSString*)path
                        body: (nullable id)body;

#pragma mark - Certifciate

- (SecCertificateRef) secureServerCert;

- (NSString*) getCertificateID: (SecCertificateRef)cert;

#pragma mark - Configs

- (CBLReplicatorConfiguration*) configWithTarget: (id<CBLEndpoint>)target
                                            type: (CBLReplicatorType)type
                                      continuous: (BOOL)continuous;

- (CBLReplicatorConfiguration*) configWithTarget: (id<CBLEndpoint>)target
                                            type: (CBLReplicatorType)type
                                      continuous: (BOOL)continuous
                                   authenticator: (nullable CBLAuthenticator*)authenticator;

#pragma mark - Run Replicator

- (BOOL) run: (CBLReplicatorConfiguration*)config
   errorCode: (NSInteger)errorCode
 errorDomain: (nullable NSString*)errorDomain;

- (BOOL)  run: (CBLReplicatorConfiguration*)config
        reset: (BOOL)reset
    errorCode: (NSInteger)errorCode
  errorDomain: (nullable NSString*)errorDomain;

- (BOOL) run: (CBLReplicatorConfiguration*)config
       reset: (BOOL)reset
   errorCode: (NSInteger)errorCode
 errorDomain: (nullable NSString*)errorDomain
onReplicatorReady: (nullable void (^)(CBLReplicator*))onReplicatorReady;

- (BOOL) runWithReplicator: (CBLReplicator*)replicator
                 errorCode: (NSInteger)errorCode
               errorDomain: (nullable NSString*)errorDomain;

#pragma mark - Verify Replicator Change

- (void) verifyChange: (CBLReplicatorChange*)change
            errorCode: (NSInteger)code
          errorDomain: (nullable NSString*)domain;

#pragma mark - Wait

- (XCTestExpectation *) waitForReplicatorIdle: (CBLReplicator*)replicator
                          withProgressAtLeast: (uint64_t)progress;

- (XCTestExpectation *) waitForReplicatorStopped: (CBLReplicator*)replicator;


#ifdef COUCHBASE_ENTERPRISE

- (XCTestExpectation *) waitForListenerIdle: (CBLMessageEndpointListener*)listener;

- (XCTestExpectation *) waitForListenerStopped: (CBLMessageEndpointListener*)listener;

#pragma mark - P2P Helpers

- (CBLReplicatorConfiguration *)createFailureP2PConfigurationWithProtocol: (CBLProtocolType)protocolType
                                                               atLocation: (CBLMockConnectionLifecycleLocation)location
                                                       withRecoverability: (BOOL)isRecoverable;


- (void) runP2PErrorScenario: (CBLMockConnectionLifecycleLocation)location
          withRecoverability: (BOOL)isRecoverable;

- (void) runTwoStepContinuousWithType: (CBLReplicatorType)replicatorType
                             usingUID: (NSString*)uid;

#endif

@end

NS_ASSUME_NONNULL_END
