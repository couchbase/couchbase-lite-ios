//
//  NSObject+ReplicatorTest_MessageEndPoint.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/9/20.
//  Copyright © 2020 Couchbase. All rights reserved.
//

#import "ReplicatorTest.h"
#import "CBLReplicator+Internal.h"
#import "CBLMessageEndpoint.h"
#import "CBLMockConnection.h"
#import "CBLMockConnectionErrorLogic.h"
#import "CBLMockConnectionLifecycleLocation.h"
#import "CBLMessageEndpointListener.h"
#import "CBLErrors.h"

@interface MockConnectionFactory : NSObject <CBLMessageEndpointDelegate>

- (instancetype) initWithErrorLogic: (nullable id<CBLMockConnectionErrorLogic>)errorLogic;

- (id<CBLMessageEndpointConnection>) createConnectionForEndpoint: (CBLMessageEndpoint*)endpoint;

@end

@interface ReplicatorTest_MessageEndpoint : ReplicatorTest

@end

@implementation ReplicatorTest_MessageEndpoint {
    MockConnectionFactory* _delegate;
}

// TODO: Remove https://issues.couchbase.com/browse/CBL-3206
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

- (XCTestExpectation *) waitForListenerIdle: (CBLMessageEndpointListener*)listener {
    XCTestExpectation* x = [self expectationWithDescription:@"Listener idle"];
    __block id token = nil;
    __weak CBLMessageEndpointListener* wListener = listener;
    token = [listener addChangeListener:^(CBLMessageEndpointListenerChange* change) {
        if(change.status.activity == kCBLReplicatorIdle) {
            [x fulfill];
            [wListener removeChangeListenerWithToken:token];
        }
    }];
    
    return x;
}

- (XCTestExpectation *) waitForListenerStopped: (CBLMessageEndpointListener*)listener {
    XCTestExpectation* x = [self expectationWithDescription:@"Listener stop"];
    __block id token = nil;
    __weak CBLMessageEndpointListener* wListener = listener;
    token = [listener addChangeListener: ^(CBLMessageEndpointListenerChange * change) {
        if(change.status.activity == kCBLReplicatorStopped) {
            [x fulfill];
            [wListener removeChangeListenerWithToken:token];
        }
    }];
    return x;
}

- (NSString*) clientID {
    return [[NSUUID UUID] UUIDString];
}

- (CBLReplicatorConfiguration*) createFailureConfigurationWithProtocol: (CBLProtocolType)protocolType
                                                              location: (CBLMockConnectionLifecycleLocation)location
                                                           recoverable: (BOOL)isRecoverable
                                                              listener: (CBLMessageEndpointListener**)outListener {
    NSInteger recoveryCount = isRecoverable ? 1 : 0;
    CBLTestErrorLogic* errorLogic = [[CBLTestErrorLogic alloc] initAtLocation: location
                                                            withRecoveryCount: recoveryCount];
    CBLMessageEndpointListenerConfiguration* config =
        [[CBLMessageEndpointListenerConfiguration alloc] initWithDatabase: self.otherDB
                                                             protocolType:protocolType];
    CBLMessageEndpointListener* listener = [[CBLMessageEndpointListener alloc] initWithConfig: config];
    if (outListener)
        *outListener = listener;
    CBLMockServerConnection* server = [[CBLMockServerConnection alloc] initWithListener: listener
                                                                            protocol: protocolType];
    server.errorLogic = errorLogic;
    
    _delegate = [[MockConnectionFactory alloc] initWithErrorLogic: errorLogic];
    CBLMessageEndpoint* endpoint = [[CBLMessageEndpoint alloc] initWithUID: [self clientID]
                                                                    target: server
                                                              protocolType: protocolType
                                                                  delegate: _delegate];
    CBLReplicatorConfiguration* replConfig = [[CBLReplicatorConfiguration alloc] initWithDatabase:_db target:endpoint];
    replConfig.replicatorType = kCBLReplicatorTypePush;
    return replConfig;
}

- (void) runTestWithType: (CBLReplicatorType)replicatorType protocol: (CBLProtocolType)protocol {
    // Listener:
    CBLMessageEndpointListenerConfiguration* config = [[CBLMessageEndpointListenerConfiguration alloc] initWithDatabase: self.otherDB
                                                                                                           protocolType: protocol];
    CBLMessageEndpointListener* listener = [[CBLMessageEndpointListener alloc] initWithConfig: config];
    XCTestExpectation* listenerStop = [self waitForListenerStopped: listener];
    
    // Replicator:
    CBLMockServerConnection* server = [[CBLMockServerConnection alloc] initWithListener: listener
                                                                            protocol: protocol];
    MockConnectionFactory* delegate = [[MockConnectionFactory alloc] initWithErrorLogic: nil];
    CBLMessageEndpoint* target = [[CBLMessageEndpoint alloc] initWithUID: [self clientID]
                                                                  target: server
                                                            protocolType: protocol
                                                                delegate: delegate];
    CBLReplicatorConfiguration* replConfig = [[CBLReplicatorConfiguration alloc] initWithDatabase: _db target: target];
    replConfig.replicatorType = replicatorType;
    replConfig.continuous = YES;
    
    CBLReplicator* replicator = [[CBLReplicator alloc] initWithConfig: replConfig];
    [replicator start];
    
    CBLDatabase* firstSource = nil;
    CBLDatabase* secondSource = nil;
    CBLDatabase* firstTarget = nil;
    CBLDatabase* secondTarget = nil;
    
    if(replicatorType == kCBLReplicatorTypePush) {
        firstSource = self.db;
        secondSource = self.db;
        firstTarget = self.otherDB;
        secondTarget = self.otherDB;
    } else if(replicatorType == kCBLReplicatorTypePull) {
        firstSource = self.otherDB;
        secondSource = self.otherDB;
        firstTarget = self.db;
        secondTarget = self.db;
    } else {
        firstSource = self.db;
        secondSource = self.otherDB;
        firstTarget = self.otherDB;
        secondTarget = self.db;
    }
    
    XCTestExpectation* x = [self waitForReplicatorIdle: replicator withProgressAtLeast: 0];
    CBLMutableDocument* mdoc = [CBLMutableDocument documentWithID: @"doc1"];
    [mdoc setString: @"db" forKey: @"name"];
    [mdoc setInteger: 1 forKey: @"version"];
    [self saveDocument:mdoc toDatabase: firstSource];
    [self waitForExpectations: @[x] timeout: expTimeout];
    
    uint64_t previousCompleted = replicator.status.progress.completed;
    AssertEqual(firstTarget.count, 1UL);
    
    x = [self waitForReplicatorIdle: replicator withProgressAtLeast: previousCompleted];
    mdoc = [[secondSource documentWithID: @"doc1"] toMutable];
    [mdoc setInteger: 2 forKey: @"version"];
    [self saveDocument: mdoc toDatabase: secondSource];
    [self waitForExpectations: @[x] timeout: expTimeout];
    
    x = [self waitForReplicatorStopped: replicator];
    CBLDocument* savedDoc = [secondTarget documentWithID: @"doc1"];
    AssertEqual([savedDoc integerForKey: @"version"], 2);
    [replicator stop];
    [self waitForExpectations: @[x] timeout: expTimeout];
    [self waitForExpectations: @[listenerStop] timeout: expTimeout];
}

- (void) runErrorTestForCase: (CBLMockConnectionLifecycleLocation)location
                    protocol: (CBLProtocolType)protocolType
                 recoverable: (BOOL)isRecoverable {
    NSError* error = nil;
    CBLMutableDocument* mdoc = [CBLMutableDocument documentWithID: @"livesindb"];
    [mdoc setString: @"db" forKey: @"name"];
    [_db saveDocument: mdoc error: &error];
    AssertNil(error);
    
    XCTestExpectation* listenerStop;
    NSString* expectedDomain = isRecoverable ? nil : CBLErrorDomain;
    NSInteger expectedCode = isRecoverable ? 0 : CBLErrorWebSocketCloseUserPermanent;
    
    CBLMessageEndpointListener* listener;
    CBLReplicatorConfiguration* config = [self createFailureConfigurationWithProtocol: protocolType
                                                                             location: location
                                                                          recoverable: isRecoverable
                                                                             listener: &listener];
    if (location != kCBLMockConnectionConnect) {
        listenerStop = [self waitForListenerStopped: listener];
    }
    
    [self run: config errorCode: expectedCode errorDomain: expectedDomain];
    
    if (listenerStop) {
        [self waitForExpectations: @[listenerStop] timeout: expTimeout];
    }
}

- (void) testPushWithMessageStream {
    [self runTestWithType: kCBLReplicatorTypePush protocol: kCBLProtocolTypeMessageStream];
}

- (void) testPushWithByteStream {
    [self runTestWithType: kCBLReplicatorTypePush protocol: kCBLProtocolTypeByteStream];
}

- (void) testPullWithMessageStream {
    [self runTestWithType: kCBLReplicatorTypePull protocol: kCBLProtocolTypeMessageStream];
}

- (void) testPullWithByteStream {
    [self runTestWithType: kCBLReplicatorTypePull protocol: kCBLProtocolTypeByteStream];
}

- (void) testPushPullWithMessageStream {
    [self runTestWithType: kCBLReplicatorTypePushAndPull protocol: kCBLProtocolTypeMessageStream];
}

- (void) testPushPullWithByteStream {
    [self runTestWithType: kCBLReplicatorTypePushAndPull protocol: kCBLProtocolTypeByteStream];
}

// Error Tests During Open:

- (void) testRecoverableErrorDuringOpenWithMessageStream {
    [self runErrorTestForCase: kCBLMockConnectionConnect protocol: kCBLProtocolTypeMessageStream recoverable: YES];
}

- (void) testRecoverableErrorDuringOpenWithByteStream {
    [self runErrorTestForCase: kCBLMockConnectionConnect protocol: kCBLProtocolTypeByteStream recoverable: YES];
}

- (void) testPermanentErrorDuringOpenWithMessageStream {
    [self runErrorTestForCase: kCBLMockConnectionConnect protocol: kCBLProtocolTypeMessageStream recoverable: NO];
}

- (void) testPermanentErrorDuringOpenWithByteStream {
    [self runErrorTestForCase: kCBLMockConnectionConnect protocol: kCBLProtocolTypeByteStream recoverable: NO];
}

// Error Tests During Send:

- (void) testRecoverableErrorDuringSendWithMessageStream {
    [self runErrorTestForCase: kCBLMockConnectionSend protocol: kCBLProtocolTypeMessageStream recoverable: YES];
}

- (void) testRecoverableErrorDuringSendWithByteStream {
    [self runErrorTestForCase: kCBLMockConnectionSend protocol: kCBLProtocolTypeByteStream recoverable: YES];
}

- (void) testPermanentErrorDuringSendWithMessageStream {
    [self runErrorTestForCase: kCBLMockConnectionSend protocol: kCBLProtocolTypeMessageStream recoverable: NO];
}

- (void) testPermanentErrorDuringSendWithByteStream {
    [self runErrorTestForCase: kCBLMockConnectionSend protocol: kCBLProtocolTypeByteStream recoverable: NO];
}

// Error Tests During Receive:

- (void) testRecoverableErrorDuringReceiveWithMessageStream {
    [self runErrorTestForCase: kCBLMockConnectionReceive protocol: kCBLProtocolTypeMessageStream recoverable: YES];
}

- (void) testRecoverableErrorDuringReceiveWithByteStream {
    [self runErrorTestForCase: kCBLMockConnectionReceive protocol: kCBLProtocolTypeByteStream recoverable: YES];
}

- (void) testPermanentErrorDuringReceiveWithMessageStream {
    [self runErrorTestForCase: kCBLMockConnectionReceive protocol: kCBLProtocolTypeMessageStream recoverable: NO];
}

- (void) testPermanentErrorDuringReceiveWithByteStream {
    [self runErrorTestForCase: kCBLMockConnectionReceive protocol: kCBLProtocolTypeByteStream recoverable: NO];
}

- (void) testCloseListener {
    CBLMutableDocument* doc = [CBLMutableDocument documentWithID: @"doc1"];
    [doc setString: @"Smokey" forKey: @"name"];
    [self saveDocument: doc];
    
    CBLMessageEndpointListenerConfiguration* config =
        [[CBLMessageEndpointListenerConfiguration alloc] initWithDatabase: self.otherDB
                                                             protocolType: kCBLProtocolTypeMessageStream];
    CBLMessageEndpointListener* listener = [[CBLMessageEndpointListener alloc] initWithConfig: config];
    
    CBLMockServerConnection* serverConnection1 = [[CBLMockServerConnection alloc] initWithListener: listener
                                                                                       protocol: kCBLProtocolTypeMessageStream];
    
    CBLMockServerConnection* serverConnection2 = [[CBLMockServerConnection alloc] initWithListener: listener
                                                                                       protocol: kCBLProtocolTypeMessageStream];
    CBLReconnectErrorLogic* errorLogic = [CBLReconnectErrorLogic new];
    MockConnectionFactory* delegate = [[MockConnectionFactory alloc] initWithErrorLogic: errorLogic];
    CBLMessageEndpoint* target = [[CBLMessageEndpoint alloc] initWithUID: [self clientID]
                                                                  target: serverConnection1
                                                            protocolType: kCBLProtocolTypeMessageStream
                                                                delegate: delegate];
    CBLReplicatorConfiguration* replConfig = [[CBLReplicatorConfiguration alloc] initWithDatabase: _db
                                                                                           target: target];
    replConfig.continuous = YES;
    MockConnectionFactory* delegate2 = [[MockConnectionFactory alloc] initWithErrorLogic: errorLogic];
    CBLMessageEndpoint* target2 = [[CBLMessageEndpoint alloc] initWithUID: [self clientID]
                                                                   target: serverConnection2
                                                             protocolType: kCBLProtocolTypeMessageStream
                                                                 delegate: delegate2];
    CBLReplicatorConfiguration* replConfig2 = [[CBLReplicatorConfiguration alloc] initWithDatabase: _db
                                                                                            target: target2];
    replConfig2.continuous = YES;
    CBLReplicator* replicator = [[CBLReplicator alloc] initWithConfig: replConfig];
    CBLReplicator* replicator2 = [[CBLReplicator alloc] initWithConfig: replConfig2];
    XCTestExpectation* idle1 = [self waitForReplicatorIdle: replicator withProgressAtLeast: 0];
    XCTestExpectation* idle2 = [self waitForReplicatorIdle: replicator2 withProgressAtLeast: 0];
    XCTestExpectation* stop1 = [self waitForReplicatorStopped: replicator];
    XCTestExpectation* stop2 = [self waitForReplicatorStopped: replicator2];
    
    [replicator start];
    [replicator2 start];
    [self waitForExpectations: @[idle1, idle2] timeout: expTimeout];
    
    errorLogic.isErrorActive = YES;
    
    XCTestExpectation* listenerStop1 = [self expectationWithDescription: @"First Listener Stopped"];
    XCTestExpectation* listenerStop2 = [self expectationWithDescription: @"Second Listener Stopped"];
    id listenerToken = [listener addChangeListener:^(CBLMessageEndpointListenerChange * _Nonnull change) {
        if(change.status.activity == kCBLReplicatorStopped) {
            if(change.connection == serverConnection1) {
                [listenerStop1 fulfill];
            } else {
                [listenerStop2 fulfill];
            }
        }
    }];
    
    [listener closeAll];
    [self waitForExpectations: @[listenerStop1, listenerStop2] timeout: expTimeout];
    [listener removeChangeListenerWithToken: listenerToken];
    [self waitForExpectations: @[stop1, stop2] timeout: expTimeout];
    AssertNotNil(replicator.status.error);
    AssertNotNil(replicator2.status.error);
}

@end

@implementation MockConnectionFactory {
    id<CBLMockConnectionErrorLogic> _errorLogic;
}

- (instancetype) initWithErrorLogic: (nullable id<CBLMockConnectionErrorLogic>)errorLogic {
    self = [super init];
    if(self) {
        _errorLogic = errorLogic;
    }
    
    return self;
}

- (id<CBLMessageEndpointConnection>)createConnectionForEndpoint: (CBLMessageEndpoint *)endpoint {
    CBLMockClientConnection* retVal = [[CBLMockClientConnection alloc] initWithEndpoint: endpoint];
    retVal.errorLogic = _errorLogic;
    return retVal;
}

#pragma clang diagnostic pop

@end
