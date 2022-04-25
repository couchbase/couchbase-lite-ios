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

@interface MockConnectionFactory : NSObject <CBLMessageEndpointDelegate>

- (instancetype) initWithErrorLogic: (nullable id<CBLMockConnectionErrorLogic>)errorLogic;

- (id<CBLMessageEndpointConnection>) createConnectionForEndpoint: (CBLMessageEndpoint*)endpoint;

@end

@interface ReplicatorTest_MessageEndpoint : ReplicatorTest

@end

@implementation ReplicatorTest_MessageEndpoint {
    MockConnectionFactory* _delegate;
}

- (XCTestExpectation *) waitForListenerIdle: (CBLMessageEndpointListener*)listener {
    XCTestExpectation* x = [self expectationWithDescription:@"Listener idle"];
    __block id token = nil;
    __weak CBLMessageEndpointListener* wListener = listener;
    token = [listener addChangeListener:^(CBLMessageEndpointListenerChange * _Nonnull change) {
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
    token = [listener addChangeListener:^(CBLMessageEndpointListenerChange * _Nonnull change) {
        if(change.status.activity == kCBLReplicatorStopped) {
            [x fulfill];
            [wListener removeChangeListenerWithToken:token];
        }
    }];
    return x;
}

- (CBLReplicatorConfiguration*) createFailureP2PConfigurationWithProtocol: (CBLProtocolType)protocolType
                                                               atLocation: (CBLMockConnectionLifecycleLocation)location
                                                       withRecoverability: (BOOL)isRecoverable
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
    CBLMessageEndpoint* endpoint = [[CBLMessageEndpoint alloc] initWithUID: @"p2ptest1"
                                                                    target: server
                                                              protocolType: protocolType
                                                                  delegate: _delegate];
    CBLReplicatorConfiguration* replConfig = [[CBLReplicatorConfiguration alloc] initWithDatabase:_db target:endpoint];
    replConfig.replicatorType = kCBLReplicatorTypePush;
    return replConfig;
}

- (void) runTwoStepContinuousWithType: (CBLReplicatorType)replicatorType usingUID: (NSString*)uid {
    CBLMessageEndpointListenerConfiguration* config =
        [[CBLMessageEndpointListenerConfiguration alloc] initWithDatabase: self.otherDB
                                                             protocolType: kCBLProtocolTypeByteStream];
    CBLMessageEndpointListener* listener = [[CBLMessageEndpointListener alloc] initWithConfig:config];
    XCTestExpectation* listenerStop = [self waitForListenerStopped: listener];
    CBLMockServerConnection* server = [[CBLMockServerConnection alloc] initWithListener: listener
                                                                            protocol: kCBLProtocolTypeByteStream];
    MockConnectionFactory* delegate = [[MockConnectionFactory alloc] initWithErrorLogic: nil];
    CBLMessageEndpoint* target = [[CBLMessageEndpoint alloc] initWithUID: uid
                                                                  target: server
                                                            protocolType: kCBLProtocolTypeByteStream delegate: delegate];
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
    
    CBLMutableDocument* mdoc = [CBLMutableDocument documentWithID: @"livesindb"];
    [mdoc setString: @"db" forKey: @"name"];
    [mdoc setInteger: 1 forKey: @"version"];
    [self saveDocument:mdoc toDatabase: firstSource];
    
    XCTestExpectation* x = [self waitForReplicatorIdle: replicator withProgressAtLeast: 0];
    [self waitForExpectations: @[x] timeout: 10.0];
    
    uint64_t previousCompleted = replicator.status.progress.completed;
    AssertEqual(firstTarget.count, 1UL);
    
    mdoc = [[secondSource documentWithID: @"livesindb"] toMutable];
    [mdoc setInteger: 2 forKey: @"version"];
    [self saveDocument: mdoc toDatabase: secondSource];
    
    x = [self waitForReplicatorIdle: replicator withProgressAtLeast: previousCompleted];
    [self waitForExpectations: @[x] timeout: 10.0];
    
    CBLDocument* savedDoc = [secondTarget documentWithID: @"livesindb"];
    AssertEqual([savedDoc integerForKey: @"version"], 2);
    [replicator stop];
    
    // Wait for replicator to stop:
    x = [self waitForReplicatorStopped: replicator];
    [self waitForExpectations: @[x] timeout: 5.0];
    
    // Wait for listener to stop:
    [self waitForExpectations: @[listenerStop] timeout: 10.0];
}

- (void) runP2PErrorScenario: (CBLMockConnectionLifecycleLocation)location withRecoverability: (BOOL)isRecoverable {
    NSTimeInterval oldTimeout = timeout;
    timeout = 100.0;
    
    CBLMutableDocument* mdoc = [CBLMutableDocument documentWithID: @"livesindb"];
    [mdoc setString: @"db" forKey: @"name"];
    NSError* error = nil;
    [_db saveDocument: mdoc error: &error];
    AssertNil(error);
    
    XCTestExpectation* listenerStop;
    NSString* expectedDomain = isRecoverable ? nil : CBLErrorDomain;
    NSInteger expectedCode = isRecoverable ? 0 : CBLErrorWebSocketCloseUserPermanent;
    CBLMessageEndpointListener* listener;
    CBLReplicatorConfiguration* config = [self createFailureP2PConfigurationWithProtocol: kCBLProtocolTypeByteStream
                                                                              atLocation: location
                                                                      withRecoverability: isRecoverable
                                                                                listener: &listener];
    if (location != kCBLMockConnectionConnect) {
        listenerStop = [self waitForListenerStopped: listener];
    }
    
    [self run: config errorCode: expectedCode errorDomain: expectedDomain];
    
    if (listenerStop) {
        [self waitForExpectations: @[listenerStop] timeout: 10.0];
    }
    
    config = [self createFailureP2PConfigurationWithProtocol: kCBLProtocolTypeMessageStream
                                                  atLocation: location
                                          withRecoverability: isRecoverable
                                                    listener: &listener];
    
    if (location != kCBLMockConnectionConnect) {
        listenerStop = [self waitForListenerStopped: listener];
    }
    
    [self run: config reset: YES errorCode: expectedCode errorDomain: expectedDomain];
    
    if (listenerStop) {
        [self waitForExpectations: @[listenerStop] timeout: 10.0];
    }
    
    timeout = oldTimeout;
}

- (void) testMEP2PWithMessageStream {
    CBLProtocolType protocolType = kCBLProtocolTypeMessageStream;
    
    CBLMutableDocument* mdoc = [CBLMutableDocument documentWithID: @"livesindb"];
    [mdoc setString: @"db" forKey: @"name"];
    [self saveDocument: mdoc];
    
    mdoc = [CBLMutableDocument documentWithID: @"livesinotherdb"];
    [mdoc setString: @"otherdb" forKey: @"name"];
    [self saveDocument: mdoc toDatabase: self.otherDB];
    
    // PUSH
    Log(@"----> Push Replication ...");
    
    CBLMessageEndpointListenerConfiguration* config =
        [[CBLMessageEndpointListenerConfiguration alloc] initWithDatabase: self.otherDB
                                                             protocolType: protocolType];
    CBLMessageEndpointListener* listener = [[CBLMessageEndpointListener alloc] initWithConfig: config];
    XCTestExpectation* listenerStop = [self waitForListenerStopped: listener];
    CBLMockServerConnection* server = [[CBLMockServerConnection alloc] initWithListener: listener protocol: protocolType];
    MockConnectionFactory* delegate = [[MockConnectionFactory alloc] initWithErrorLogic: nil];
    CBLMessageEndpoint* target = [[CBLMessageEndpoint alloc] initWithUID: [NSString stringWithFormat:@"test1"]
                                                                  target: server
                                                            protocolType: protocolType
                                                                delegate: delegate];
    CBLReplicatorConfiguration* replConfig = [[CBLReplicatorConfiguration alloc] initWithDatabase: _db target: target];
    replConfig.replicatorType = kCBLReplicatorTypePush;
    [self run:replConfig errorCode: 0 errorDomain: nil];
    AssertEqual(self.otherDB.count, 2UL);
    AssertEqual(_db.count, 1UL);
    
    // Wait for listener to stop:
    [self waitForExpectations: @[listenerStop] timeout: 10.0];
    
    // PULL
    Log(@"----> Pull Replication ...");
    
    listenerStop = [self waitForListenerStopped: listener];
    server = [[CBLMockServerConnection alloc] initWithListener: listener protocol: protocolType];
    target = [[CBLMessageEndpoint alloc] initWithUID: [NSString stringWithFormat: @"test1"]
                                              target: server
                                        protocolType: protocolType
                                            delegate: delegate];
    replConfig = [[CBLReplicatorConfiguration alloc] initWithDatabase: _db target: target];
    replConfig.replicatorType = kCBLReplicatorTypePull;
    [self run:replConfig errorCode: 0 errorDomain: nil];
    AssertEqual(_db.count, 2UL);
    
    // Wait for listener to stop:
    [self waitForExpectations: @[listenerStop] timeout: 10.0];
    
    // PUSH & PULL
    Log(@"----> Push and Pull Replication ...");
    
    mdoc = [[_db documentWithID: @"livesinotherdb"] toMutable];
    [mdoc setBoolean:YES forKey: @"modified"];
    [self saveDocument:mdoc];
    
    mdoc = [[self.otherDB documentWithID: @"livesindb"] toMutable];
    [mdoc setBoolean: YES forKey: @"modified"];
    [self saveDocument:mdoc toDatabase: self.otherDB];
    
    listenerStop = [self waitForListenerStopped: listener];
    server = [[CBLMockServerConnection alloc] initWithListener: listener protocol: protocolType];
    target = [[CBLMessageEndpoint alloc] initWithUID: [NSString stringWithFormat:@"test1"]
                                              target: server
                                        protocolType: protocolType
                                            delegate: delegate];
    replConfig = [[CBLReplicatorConfiguration alloc] initWithDatabase: _db target: target];
    [self run: replConfig errorCode: 0 errorDomain: nil];
    AssertEqual(_db.count, 2UL);
    
    CBLDocument* savedDoc = [_db documentWithID: @"livesindb"];
    Assert([savedDoc booleanForKey: @"modified"]);
    savedDoc = [self.otherDB documentWithID: @"livesinotherdb"];
    Assert([savedDoc booleanForKey: @"modified"]);
    
    // Wait for listener to stop:
    [self waitForExpectations: @[listenerStop] timeout: 10.0];
    
    NSError* err = nil;
    BOOL success = [_db delete: &err];
    Assert(success);
    [self reopenDB];
    success = [self.otherDB delete: &err];
    Assert(success);
}

- (void) testMEP2PWithByteStream {
    CBLProtocolType protocolType = kCBLProtocolTypeByteStream;
    
    CBLMutableDocument* mdoc = [CBLMutableDocument documentWithID: @"livesindb"];
    [mdoc setString: @"db" forKey: @"name"];
    [self saveDocument: mdoc];
    
    mdoc = [CBLMutableDocument documentWithID: @"livesinotherdb"];
    [mdoc setString: @"otherdb" forKey: @"name"];
    [self saveDocument: mdoc toDatabase: self.otherDB];
    
    // PUSH
    Log(@"----> Push Replication ...");
    
    CBLMessageEndpointListenerConfiguration* config =
        [[CBLMessageEndpointListenerConfiguration alloc] initWithDatabase: self.otherDB
                                                             protocolType: protocolType];
    CBLMessageEndpointListener* listener = [[CBLMessageEndpointListener alloc] initWithConfig: config];
    XCTestExpectation* listenerStop = [self waitForListenerStopped: listener];
    CBLMockServerConnection* server = [[CBLMockServerConnection alloc] initWithListener: listener
                                                                            protocol: protocolType];
    MockConnectionFactory* delegate = [[MockConnectionFactory alloc] initWithErrorLogic: nil];
    CBLMessageEndpoint* target = [[CBLMessageEndpoint alloc] initWithUID: [NSString stringWithFormat:@"test1"]
                                                                  target: server
                                                            protocolType: protocolType
                                                                delegate: delegate];
    CBLReplicatorConfiguration* replConfig = [[CBLReplicatorConfiguration alloc] initWithDatabase: _db target: target];
    replConfig.replicatorType = kCBLReplicatorTypePush;
    [self run: replConfig errorCode: 0 errorDomain: nil];
    AssertEqual(self.otherDB.count, 2UL);
    AssertEqual(_db.count, 1UL);
    
    // Wait for listener to stop:
    [self waitForExpectations: @[listenerStop] timeout: 10.0];
    
    // PULL
    Log(@"----> Pull Replication ...");
    
    listenerStop = [self waitForListenerStopped: listener];
    server = [[CBLMockServerConnection alloc] initWithListener: listener protocol: protocolType];
    target = [[CBLMessageEndpoint alloc] initWithUID: [NSString stringWithFormat:@"test1"]
                                              target: server
                                        protocolType: protocolType
                                            delegate: delegate];
    replConfig = [[CBLReplicatorConfiguration alloc] initWithDatabase: _db target: target];
    replConfig.replicatorType = kCBLReplicatorTypePull;
    [self run: replConfig errorCode:0 errorDomain: nil];
    AssertEqual(_db.count, 2UL);
    
    // Wait for listener to stop:
    [self waitForExpectations: @[listenerStop] timeout: 10.0];
    
    // PUSH & PULL
    Log(@"----> Push and Pull Replication ...");
    
    mdoc = [[_db documentWithID: @"livesinotherdb"] toMutable];
       [mdoc setBoolean: YES forKey: @"modified"];
       [self saveDocument: mdoc];
       
       mdoc = [[self.otherDB documentWithID: @"livesindb"] toMutable];
       [mdoc setBoolean: YES forKey: @"modified"];
       [self saveDocument: mdoc toDatabase: self.otherDB];
    
    listenerStop = [self waitForListenerStopped: listener];
    server = [[CBLMockServerConnection alloc] initWithListener: listener protocol: protocolType];
    target = [[CBLMessageEndpoint alloc] initWithUID: [NSString stringWithFormat:@"test1"]
                                              target: server
                                        protocolType: protocolType
                                            delegate: delegate];
    replConfig = [[CBLReplicatorConfiguration alloc] initWithDatabase: _db target: target];
    [self run: replConfig errorCode: 0 errorDomain: nil];
    AssertEqual(_db.count, 2UL);
    
    CBLDocument* savedDoc = [_db documentWithID: @"livesindb"];
    Assert([savedDoc booleanForKey: @"modified"]);
    savedDoc = [self.otherDB documentWithID: @"livesinotherdb"];
    Assert([savedDoc booleanForKey: @"modified"]);
    
    // Wait for listener to stop:
    [self waitForExpectations: @[listenerStop] timeout: 10.0];
    
    NSError* err = nil;
    BOOL success = [_db delete: &err];
    Assert(success);
    [self reopenDB];
    success = [self.otherDB delete: &err];
    Assert(success);
}

- (void) testMEP2PContinuousPush {
    [self runTwoStepContinuousWithType: kCBLReplicatorTypePush usingUID: @"p2ptest1"];
}

- (void) testMEP2PContinuousPull {
    [self runTwoStepContinuousWithType: kCBLReplicatorTypePull usingUID: @"p2ptest2"];
}

- (void) testMEP2PContinuousPushPull {
    [self runTwoStepContinuousWithType: kCBLReplicatorTypePushAndPull usingUID: @"p2ptest3"];
}

- (void) testMEP2PRecoverableFailureDuringOpen {
    [self runP2PErrorScenario: kCBLMockConnectionConnect withRecoverability: YES];
}

- (void) testMEP2PRecoverableFailureDuringSend {
    [self runP2PErrorScenario: kCBLMockConnectionSend withRecoverability: YES];
}

- (void) testMEP2PRecoverableFailureDuringReceive {
    [self runP2PErrorScenario: kCBLMockConnectionReceive withRecoverability: YES];
}

- (void) testMEP2PPermanentFailureDuringOpen {
    [self runP2PErrorScenario: kCBLMockConnectionConnect withRecoverability: NO];
}

- (void) testMEP2PPermanentFailureDuringSend {
    [self runP2PErrorScenario: kCBLMockConnectionSend withRecoverability: NO];
}

- (void)testMEP2PPermanentFailureDuringReceive {
    [self runP2PErrorScenario: kCBLMockConnectionReceive withRecoverability: NO];
}

- (void)testMEP2PPassiveClose {
    CBLMessageEndpointListenerConfiguration* config =
        [[CBLMessageEndpointListenerConfiguration alloc] initWithDatabase: self.otherDB
                                                             protocolType: kCBLProtocolTypeMessageStream];
    CBLMessageEndpointListener* listener = [[CBLMessageEndpointListener alloc] initWithConfig: config];
    CBLMockServerConnection* server = [[CBLMockServerConnection alloc] initWithListener: listener
                                                                            protocol: kCBLProtocolTypeMessageStream];
    CBLReconnectErrorLogic* errorLogic = [CBLReconnectErrorLogic new];
    MockConnectionFactory* delegate = [[MockConnectionFactory alloc] initWithErrorLogic: errorLogic];
    CBLMessageEndpoint* target = [[CBLMessageEndpoint alloc] initWithUID: @"p2ptest1"
                                                                  target: server
                                                            protocolType: kCBLProtocolTypeMessageStream
                                                                delegate: delegate];
    CBLReplicatorConfiguration* replConfig = [[CBLReplicatorConfiguration alloc] initWithDatabase: _db target: target];
    replConfig.continuous = YES;
    
    XCTestExpectation* listenerStop = [self waitForListenerStopped: listener];
    NSMutableArray* listenerErrors = [NSMutableArray array];
    [listener addChangeListener:^(CBLMessageEndpointListenerChange * _Nonnull change) {
        if(change.status.error) {
            [listenerErrors addObject: change.status.error];
        }
    }];
    
    CBLReplicator* replicator = [[CBLReplicator alloc] initWithConfig: replConfig];
    XCTestExpectation* x = [self waitForReplicatorIdle: replicator withProgressAtLeast: 0];
    [replicator start];
    [self waitForExpectations: @[x] timeout: 10.0];
    errorLogic.isErrorActive = true;
    x = [self waitForReplicatorStopped: replicator];
    
    [listener close: server];
    [self waitForExpectations:@[x, listenerStop] timeout:10.0];
    AssertEqual(listenerErrors.count, 0UL);
    AssertNotNil(replicator.status.error);
}

- (void) testMEP2PPassiveCloseAll {
    CBLMutableDocument* doc = [CBLMutableDocument documentWithID:@"test"];
    [doc setString:@"Smokey" forKey:@"name"];
    [self saveDocument:doc];
    
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
    CBLMessageEndpoint* target = [[CBLMessageEndpoint alloc] initWithUID: @"p2ptest1"
                                                                  target: serverConnection1
                                                            protocolType: kCBLProtocolTypeMessageStream
                                                                delegate: delegate];
    CBLReplicatorConfiguration* replConfig = [[CBLReplicatorConfiguration alloc] initWithDatabase: _db
                                                                                           target: target];
    replConfig.continuous = YES;
    MockConnectionFactory* delegate2 = [[MockConnectionFactory alloc] initWithErrorLogic: errorLogic];
    CBLMessageEndpoint* target2 = [[CBLMessageEndpoint alloc] initWithUID: @"p2ptest2"
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
    [self waitForExpectations: @[idle1, idle2] timeout: 10.0];
    
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
    [self waitForExpectations: @[listenerStop1, listenerStop2] timeout: 10.0];
    [listener removeChangeListenerWithToken: listenerToken];
    [self waitForExpectations: @[stop1, stop2] timeout: 10.0];
    AssertNotNil(replicator.status.error);
    AssertNotNil(replicator2.status.error);
}

- (void)testMEP2PChangeListener {
    NSMutableArray* statuses = [NSMutableArray array];
    CBLMessageEndpointListener* listener =
        [[CBLMessageEndpointListener alloc] initWithConfig:
            [[CBLMessageEndpointListenerConfiguration alloc] initWithDatabase: self.otherDB
                                                                 protocolType: kCBLProtocolTypeByteStream]];
    
    CBLMockServerConnection* serverConnection = [[CBLMockServerConnection alloc] initWithListener: listener
                                                                                         protocol: kCBLProtocolTypeByteStream];
    MockConnectionFactory* delegate = [[MockConnectionFactory alloc] initWithErrorLogic: nil];
    CBLMessageEndpoint* target = [[CBLMessageEndpoint alloc] initWithUID: @"p2ptest1"
                                                                  target: serverConnection
                                                            protocolType: kCBLProtocolTypeByteStream
                                                                delegate: delegate];
    
    CBLReplicatorConfiguration* config = [[CBLReplicatorConfiguration alloc] initWithDatabase:_db target:target];
    config.continuous = YES;
    XCTestExpectation *x = [self waitForListenerStopped:listener];
    [listener addChangeListener: ^(CBLMessageEndpointListenerChange * _Nonnull change) {
        [statuses addObject: @(change.status.activity)];
    }];
    
    [self run: config errorCode: 0 errorDomain: nil];
    [self waitForExpectations: @[x] timeout:10.0];
    Assert(statuses.count > 0);
}

- (void)testMEP2PRemoveChangeListener {
    NSMutableArray* statuses = [NSMutableArray array];
    CBLMessageEndpointListener* listener = [[CBLMessageEndpointListener alloc] initWithConfig:
        [[CBLMessageEndpointListenerConfiguration alloc] initWithDatabase: self.otherDB
                                                             protocolType: kCBLProtocolTypeByteStream]];
    CBLMockServerConnection* serverConnection = [[CBLMockServerConnection alloc] initWithListener: listener
                                                                                      protocol: kCBLProtocolTypeByteStream];
    MockConnectionFactory* delegate = [[MockConnectionFactory alloc] initWithErrorLogic: nil];
    CBLMessageEndpoint* target = [[CBLMessageEndpoint alloc] initWithUID :@"p2ptest1"
                                                                   target: serverConnection
                                                             protocolType: kCBLProtocolTypeByteStream
                                                                 delegate: delegate];
    CBLReplicatorConfiguration* config = [[CBLReplicatorConfiguration alloc] initWithDatabase: _db
                                                                                       target: target];
    config.continuous = YES;
    XCTestExpectation *x = [self waitForListenerStopped: listener];
    id token = [listener addChangeListener:^(CBLMessageEndpointListenerChange * _Nonnull change) {
        [statuses addObject: @(change.status.activity)];
    }];
    [listener removeChangeListenerWithToken: token];
    
    [self run: config errorCode: 0 errorDomain: nil];
    [self waitForExpectations: @[x] timeout: 10.0];
    Assert(statuses.count == 0UL);
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

@end
