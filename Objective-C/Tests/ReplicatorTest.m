//
//  ReplicatorTest.m
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
#import "CBLJSON.h"
#import "CBLReplicator+Backgrounding.h"
#import "CBLReplicator+Internal.h"
#import "CBLURLEndpoint+Internal.h"
#import "CBLDatabase+Internal.h"
#import "CBLHTTPLogic.h"
#import "CollectionUtils.h"

#ifdef COUCHBASE_ENTERPRISE
#import "CBLMockConnectionLifecycleLocation.h"
#import "CBLMockConnectionErrorLogic.h"
#import "CBLMockConnection.h"
#import "CBLMessageEndpoint.h"
#endif

@interface ReplicatorTest : CBLTestCase
@end

#ifdef COUCHBASE_ENTERPRISE

@interface MockConnectionFactory : NSObject <CBLMessageEndpointDelegate>
@end

@implementation MockConnectionFactory
{
    id<CBLMockConnectionErrorLogic> _errorLogic;
}

- (instancetype)initWithErrorLogic:(id<CBLMockConnectionErrorLogic>)errorLogic {
    self = [super init];
    if(self) {
        _errorLogic = errorLogic;
    }
    
    return self;
}

- (id<CBLMessageEndpointConnection>)createConnectionForEndpoint:(CBLMessageEndpoint *)endpoint {
    CBLMockClientConnection* retVal = [[CBLMockClientConnection alloc] initWithEndpoint:endpoint];
    retVal.errorLogic = _errorLogic;
    return retVal;
}

@end

#endif

@implementation ReplicatorTest
{
    CBLDatabase* otherDB;
    CBLReplicator* repl;
    NSTimeInterval timeout;
    BOOL _stopped;
    BOOL _pinServerCert;
#ifdef COUCHBASE_ENTERPRISE
    MockConnectionFactory* _delegate;
#endif
}


+ (void) initialize {
    if (self == [ReplicatorTest class]) {
        // You can set environment variables to force use of a proxy:
        // CBL_TEST_PROXY_TYPE      Proxy type: HTTP, SOCKS, PAC (defaults to HTTP)
        // CBL_TEST_PROXY_HOST      Proxy hostname
        // CBL_TEST_PROXY_PORT      Proxy port number
        // CBL_TEST_PROXY_USER      Username for auth
        // CBL_TEST_PROXY_PASS      Password for auth
        // CBL_TEST_PROXY_PAC_URL   URL of PAC file

        NSDictionary* env = NSProcessInfo.processInfo.environment;
        NSString* proxyHost = env[@"CBL_TEST_PROXY_HOST"];
        NSString* proxyType = env[@"CBL_TEST_PROXY_TYPE"];
        int proxyPort = [env[@"CBL_TEST_PROXY_PORT"] intValue] ?: 80;
        if (proxyHost || proxyType) {
            proxyType = [(proxyType ?: @"http") uppercaseString];
            if ([proxyType isEqualToString: @"HTTP"])
                proxyType = (id)kCFProxyTypeHTTP;
            else if ([proxyType isEqualToString: @"SOCKS"])
                proxyType = (id)kCFProxyTypeSOCKS;
            else if ([proxyType isEqualToString: @"PAC"])
                proxyType = (id)kCFProxyTypeAutoConfigurationURL;
            NSMutableDictionary* proxy = [@{(id)kCFProxyTypeKey: proxyType} mutableCopy];
            proxy[(id)kCFProxyHostNameKey] = proxyHost;
            proxy[(id)kCFProxyPortNumberKey] = @(proxyPort);
            if (proxyType == (id)kCFProxyTypeAutoConfigurationURL) {
                NSURL* pacURL = [NSURL URLWithString:  env[@"CBL_TEST_PROXY_PAC_URL"]];
                proxy[(id)kCFProxyAutoConfigurationURLKey] = pacURL;
                Log(@"Using PAC proxy URL %@", pacURL);
            } else {
                Log(@"Using %@ proxy server %@:%d", proxyType, proxyHost, proxyPort);
            }
            proxy[(id)kCFProxyUsernameKey] =  env[@"CBL_TEST_PROXY_USER"];
            proxy[(id)kCFProxyPasswordKey] =  env[@"CBL_TEST_PROXY_PASS"];
            [CBLHTTPLogic setOverrideProxySettings: proxy];
        }
    }
}


- (void) setUp {
    Assert([self deleteDBNamed: @"otherdb" error: nil]);
    
    [super setUp];
    
    timeout = 5.0;
    _pinServerCert = YES;
    NSError* error;
    otherDB = [self openDBNamed: @"otherdb" error: &error];
    AssertNil(error);
    AssertNotNil(otherDB);
}


- (void) tearDown {
    // Workaround to ensure that replicator's background cleaning task was done:
    // https://github.com/couchbase/couchbase-lite-core/issues/520
    // https://github.com/couchbase/couchbase-lite-core/issues/539
    // [NSThread sleepForTimeInterval: 0.5];
    
    Assert([otherDB close: nil]);
    otherDB = nil;
    repl = nil;
    [super tearDown];
}

- (void) saveDocument: (CBLMutableDocument*)document toDatabase:(CBLDatabase*)database {
    NSError* error;
    Assert([database saveDocument: document error: &error], @"Saving error: %@", error);
    
    CBLDocument* savedDoc = [database documentWithID: document.id];
    AssertNotNil(savedDoc);
    AssertEqualObjects(savedDoc.id, document.id);
    AssertEqualObjects([savedDoc toDictionary], [document toDictionary]);
}

/** Returns an endpoint for a Sync Gateway test database, or nil if SG tests are not enabled.
    To enable these tests, set the hostname of the server in the environment variable
    "CBL_TEST_HOST".
    The port number defaults to 4984, or 4994 for SSL. To override these, set the environment
    variables "CBL_TEST_PORT" and/or "CBL_TEST_PORT_SSL".
    Note: On iOS, all endpoints will be SSL regardless of the `secure` flag.
 */
- (CBLURLEndpoint*) remoteEndpointWithName: (NSString*)dbName secure: (BOOL)secure {
    NSString* host = NSProcessInfo.processInfo.environment[@"CBL_TEST_HOST"];
    if (!host) {
        Log(@"NOTE: Skipping test: no CBL_TEST_HOST configured in environment");
        return nil;
    }
    
    NSString* portKey = secure ? @"CBL_TEST_PORT_SSL" : @"CBL_TEST_PORT";
    NSInteger port = NSProcessInfo.processInfo.environment[portKey].integerValue;
    if (!port)
        port = secure ? 4994 : 4984;
    
    NSURLComponents *comp = [NSURLComponents new];
    comp.scheme = secure ? kCBLURLEndpointTLSScheme : kCBLURLEndpointScheme;
    comp.host = host;
    comp.port = @(port);
    comp.path = [NSString stringWithFormat:@"/%@", dbName];
    NSURL* url = comp.URL;
    Assert(url);
    
    return [[CBLURLEndpoint alloc] initWithURL: url];
}


- (void) eraseRemoteEndpoint: (CBLURLEndpoint*)endpoint {
    Assert([endpoint.url.path isEqualToString: @"/scratch"], @"Only scratch db should be erased");
    [self sendRequestToEndpoint: endpoint method: @"POST" path: @"_flush" body: nil];
    Log(@"Erased remote database %@", endpoint.url);
}


- (id) sendRequestToEndpoint: (CBLURLEndpoint*)endpoint
                      method: (NSString*)method
                        path: (nullable NSString*)path
                        body: (nullable id)body
{
    NSURL* endpointURL = endpoint.url;
    NSURLComponents *comp = [NSURLComponents new];
    comp.scheme = [endpointURL.scheme isEqualToString: kCBLURLEndpointTLSScheme] ? @"https" : @"http";
    comp.host = endpointURL.host;
    comp.port = @([endpointURL.port intValue] + 1);   // assuming admin port is at usual offse
    path = path ? ([path hasPrefix: @"/"] ? path : [@"/" stringByAppendingString: path]) : @"";
    comp.path = [NSString stringWithFormat: @"%@%@", endpointURL.path, path];
    NSURL* url = comp.URL;
    Assert(url);
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL: url];
    request.HTTPMethod = method;
    if (body) {
        if ([body isKindOfClass: [NSData class]]) {
            request.HTTPBody = body;
        } else {
            NSError* err = nil;
            request.HTTPBody = [CBLJSON dataWithJSONObject: body options:0 error: &err];
            AssertNil(err);
        }
    }
    
    __block NSError* error = nil;
    __block NSInteger status = 0;
    __block NSData* data = nil;
    XCTestExpectation* x = [self expectationWithDescription: @"Complete Request"];
    NSURLSessionDataTask* task = [[NSURLSession sharedSession] dataTaskWithRequest: request
                                                                 completionHandler:
                                  ^(NSData *d, NSURLResponse *r, NSError *e)
                                  {
                                      error = e;
                                      data = d;
                                      status = ((NSHTTPURLResponse*)r).statusCode;
                                      [x fulfill];
                                  }];
    [task resume];
    [self waitForExpectations: @[x] timeout: timeout];
    
    if (error != nil || status >= 300) {
        XCTFail(@"Failed to send request; URL=<%@>, Method=<%@>, Status=%ld, Error=%@",
                url, method, (long)status, error);
        return nil;
    } else {
        Log(@"Send request succeeded; URL=<%@>, Method=<%@>, Status=%ld",
            url, method, (long)status);
        id result = nil;
        if (data && data.length > 0) {
            result = [CBLJSON JSONObjectWithData: data options: 0 error: &error];
            Assert(result, @"Couldn't parse JSON response: %@", error);
        }
        return result;
    }
}


- (SecCertificateRef) secureServerCert {
    NSData* certData = [self dataFromResource: @"SelfSigned" ofType: @"cer"];
    SecCertificateRef cert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certData);
    Assert(cert);
    return (SecCertificateRef)CFAutorelease(cert);
}


- (CBLReplicatorConfiguration*) configWithTarget: (id<CBLEndpoint>)target
                                            type: (CBLReplicatorType)type
                                      continuous: (BOOL)continuous
{
    return [self configWithTarget: target
                             type: type
                       continuous: continuous
                    authenticator: nil];
}


- (CBLReplicatorConfiguration*) configWithTarget: (id<CBLEndpoint>)target
                                            type: (CBLReplicatorType)type
                                      continuous: (BOOL)continuous
                                   authenticator: (CBLAuthenticator*)authenticator
{
    CBLReplicatorConfiguration* c = [[CBLReplicatorConfiguration alloc] initWithDatabase: self.db
                                                                                  target: target];
    c.replicatorType = type;
    c.continuous = continuous;
    c.authenticator = authenticator;
    
    if ([$castIf(CBLURLEndpoint, target).url.scheme isEqualToString: @"wss"] && _pinServerCert)
        c.pinnedServerCertificate = self.secureServerCert;
    
    if (continuous)
        c.checkpointInterval = 1.0; // For testing only
    
    return c;
}

- (BOOL) run: (CBLReplicatorConfiguration*)config
   errorCode: (NSInteger)errorCode
 errorDomain: (NSString*)errorDomain
{
    return [self run: config reset: NO
           errorCode: errorCode errorDomain: errorDomain onReplicatorReady: nil];
}

- (BOOL)  run: (CBLReplicatorConfiguration*)config
        reset: (BOOL)reset
    errorCode: (NSInteger)errorCode
  errorDomain: (NSString*)errorDomain
{
    return [self run: config reset: reset errorCode: errorCode errorDomain: errorDomain onReplicatorReady: nil];
}

- (BOOL) run: (CBLReplicatorConfiguration*)config
       reset: (BOOL)reset
   errorCode: (NSInteger)errorCode
 errorDomain: (NSString*)errorDomain
onReplicatorReady: (nullable void (^)(CBLReplicator*))onReplicatorReady
{
    repl = [[CBLReplicator alloc] initWithConfig: config];
    
    if (reset)
        [repl resetCheckpoint];
    
    if (onReplicatorReady)
        onReplicatorReady(repl);
    
    return [self runWithReplicator: repl errorCode: errorCode errorDomain: errorDomain];
}

- (BOOL) runWithReplicator: (CBLReplicator*)replicator
                 errorCode: (NSInteger)errorCode
               errorDomain: (NSString*)errorDomain
{
    XCTestExpectation* x = [self expectationWithDescription: @"Replicator Stopped"];
    __block BOOL fulfilled = NO;
    __weak typeof(self) wSelf = self;
    id token = [repl addChangeListener: ^(CBLReplicatorChange* change) {
        typeof(self) strongSelf = wSelf;
        [strongSelf verifyChange: change errorCode: errorCode errorDomain:errorDomain];
        if (replicator.config.continuous && change.status.activity == kCBLReplicatorIdle
            && change.status.progress.completed == change.status.progress.total) {
            [strongSelf->repl stop];
        }
        if (change.status.activity == kCBLReplicatorStopped) {
            [x fulfill];
            fulfilled = YES;
        }
    }];
    
    [replicator start];
    
    @try {
        [self waitForExpectations: @[x] timeout: timeout];
    }
    @finally {
        [replicator stop];
        [replicator removeChangeListenerWithToken: token];
    }
    return fulfilled;
}

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

- (XCTestExpectation *) waitForReplicatorIdle:(CBLReplicator*)replicator withProgressAtLeast:(uint64_t)progress {
    XCTestExpectation* x = [self expectationWithDescription:@"Replicator idle"];
    __block id token = nil;
    __weak CBLReplicator* wReplicator = replicator;
    token = [replicator addChangeListener:^(CBLReplicatorChange * _Nonnull change) {
        if(change.status.progress.completed >= progress && change.status.activity == kCBLReplicatorIdle) {
            [x fulfill];
            [wReplicator removeChangeListenerWithToken:token];
        }
    }];
    
    return x;
}

- (XCTestExpectation *) waitForReplicatorStopped:(CBLReplicator*)replicator {
    XCTestExpectation* x = [self expectationWithDescription:@"Replicator stop"];
    __block id token = nil;
    __weak CBLReplicator* wReplicator = replicator;
    token = [replicator addChangeListener:^(CBLReplicatorChange * _Nonnull change) {
        if(change.status.activity == kCBLReplicatorStopped) {
            [x fulfill];
            [wReplicator removeChangeListenerWithToken:token];
        }
    }];
    
    return x;
}

#ifdef COUCHBASE_ENTERPRISE

- (XCTestExpectation *) waitForListenerIdle:(CBLMessageEndpointListener*)listener {
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

- (XCTestExpectation *) waitForListenerStopped:(CBLMessageEndpointListener*)listener {
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

- (CBLReplicatorConfiguration *)createFailureP2PConfigurationWithProtocol:(CBLProtocolType)protocolType atLocation:(CBLMockConnectionLifecycleLocation)location withRecoverability:(BOOL)isRecoverable {
    NSInteger recoveryCount = isRecoverable ? 1 : 0;
    CBLTestErrorLogic* errorLogic = [[CBLTestErrorLogic alloc] initAtLocation:location withRecoveryCount:recoveryCount];
    CBLMessageEndpointListenerConfiguration* config = [[CBLMessageEndpointListenerConfiguration alloc] initWithDatabase:otherDB protocolType:protocolType];
    CBLMessageEndpointListener* listener = [[CBLMessageEndpointListener alloc] initWithConfig:config];
    CBLMockServerConnection* server = [[CBLMockServerConnection alloc] initWithListener:listener andProtocol:protocolType];
    server.errorLogic = errorLogic;
    
    _delegate = [[MockConnectionFactory alloc] initWithErrorLogic:errorLogic];
    CBLMessageEndpoint* endpoint = [[CBLMessageEndpoint alloc] initWithUID:@"p2ptest1" target:server protocolType:protocolType delegate:_delegate];
    CBLReplicatorConfiguration* replConfig = [[CBLReplicatorConfiguration alloc] initWithDatabase:_db target:endpoint];
    replConfig.replicatorType = kCBLReplicatorTypePush;
    return replConfig;
}

- (void) runP2PErrorScenario:(CBLMockConnectionLifecycleLocation)location withRecoverability:(BOOL)isRecoverable {
    NSTimeInterval oldTimeout = timeout;
    timeout = 100.0;
    CBLMutableDocument* mdoc = [CBLMutableDocument documentWithID:@"livesindb"];
    [mdoc setString:@"db" forKey:@"name"];
    NSError* error = nil;
    [_db saveDocument:mdoc error:&error];
    AssertNil(error);
    
    NSString* expectedDomain = isRecoverable ? nil : CBLErrorDomain;
    NSInteger expectedCode = isRecoverable ? 0 : CBLErrorWebSocketCloseUserPermanent;
    CBLReplicatorConfiguration* config = [self createFailureP2PConfigurationWithProtocol:kCBLProtocolTypeByteStream atLocation:location withRecoverability:isRecoverable];
    [self run:config errorCode:expectedCode errorDomain:expectedDomain];
    config = [self createFailureP2PConfigurationWithProtocol:kCBLProtocolTypeMessageStream atLocation:location withRecoverability:isRecoverable];
    [self run:config reset:YES errorCode:expectedCode errorDomain:expectedDomain];
    timeout = oldTimeout;
}

- (void) runTwoStepContinuousWithType:(CBLReplicatorType)replicatorType usingUID:(NSString*)uid {
    CBLMessageEndpointListenerConfiguration* config = [[CBLMessageEndpointListenerConfiguration alloc] initWithDatabase:otherDB protocolType:kCBLProtocolTypeByteStream];
    CBLMessageEndpointListener* listener = [[CBLMessageEndpointListener alloc] initWithConfig:config];
    CBLMockServerConnection* server = [[CBLMockServerConnection alloc] initWithListener:listener andProtocol:kCBLProtocolTypeByteStream];
    MockConnectionFactory* delegate = [[MockConnectionFactory alloc] initWithErrorLogic:nil];
    CBLMessageEndpoint* target = [[CBLMessageEndpoint alloc] initWithUID:uid target:server protocolType:kCBLProtocolTypeByteStream delegate:delegate];
    CBLReplicatorConfiguration* replConfig = [[CBLReplicatorConfiguration alloc] initWithDatabase:_db target:target];
    replConfig.replicatorType = replicatorType;
    replConfig.continuous = YES;
    
    CBLReplicator* replicator = [[CBLReplicator alloc] initWithConfig:replConfig];
    [replicator start];
    CBLDatabase* firstSource = nil;
    CBLDatabase* secondSource = nil;
    CBLDatabase* firstTarget = nil;
    CBLDatabase* secondTarget = nil;
    if(replicatorType == kCBLReplicatorTypePush) {
        firstSource = _db;
        secondSource = _db;
        firstTarget = otherDB;
        secondTarget = otherDB;
    } else if(replicatorType == kCBLReplicatorTypePull) {
        firstSource = otherDB;
        secondSource = otherDB;
        firstTarget = _db;
        secondTarget = _db;
    } else {
        firstSource = _db;
        secondSource = otherDB;
        firstTarget = otherDB;
        secondTarget = _db;
    }
    
    CBLMutableDocument* mdoc = [CBLMutableDocument documentWithID:@"livesindb"];
    [mdoc setString:@"db" forKey:@"name"];
    [mdoc setInteger:1 forKey:@"version"];
    [self saveDocument:mdoc toDatabase:firstSource];
    
    XCTestExpectation* x = [self waitForReplicatorIdle:replicator withProgressAtLeast:0];
    [self waitForExpectations:@[x] timeout:10.0];
    
    uint64_t previousCompleted = replicator.status.progress.completed;
    AssertEqual(firstTarget.count, 1UL);
    
    mdoc = [[secondSource documentWithID:@"livesindb"] toMutable];
    [mdoc setInteger:2 forKey:@"version"];
    [self saveDocument:mdoc toDatabase:secondSource];
    
    x = [self waitForReplicatorIdle:replicator withProgressAtLeast:previousCompleted];
    [self waitForExpectations:@[x] timeout:10.0];
    
    CBLDocument* savedDoc = [secondTarget documentWithID:@"livesindb"];
    AssertEqual([savedDoc integerForKey:@"version"], 2);
    [replicator stop];
    
    x = [self waitForReplicatorStopped:replicator];
    [self waitForExpectations:@[x] timeout:5.0];
}

#endif

#pragma mark - TESTS:

#ifdef COUCHBASE_ENTERPRISE

- (void)testEmptyPush {
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
}


- (void) testPushDoc {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setValue: @"Tiger" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    AssertEqual(self.db.count, 1u);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setValue: @"Cat" forKey: @"name"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(otherDB.count, 2u);
    CBLDocument* savedDoc1 = [otherDB documentWithID: @"doc1"];
    AssertEqualObjects([savedDoc1 stringForKey:@"name"], @"Tiger");
}


- (void) testPushDocContinuous {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setValue: @"Tiger" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    AssertEqual(self.db.count, 1u);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setValue: @"Cat" forKey: @"name"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: YES];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(otherDB.count, 2u);
    CBLDocument* savedDoc1 = [otherDB documentWithID: @"doc1"];
    AssertEqualObjects([savedDoc1 stringForKey:@"name"], @"Tiger");
}


- (void) testPullDoc {
    // For https://github.com/couchbase/couchbase-lite-core/issues/156
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setValue: @"Tiger" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    AssertEqual(self.db.count, 1u);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setValue: @"Cat" forKey: @"name"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(self.db.count, 2u);
    CBLDocument* savedDoc2 = [self.db documentWithID:@"doc2"];
    AssertEqualObjects([savedDoc2 stringForKey:@"name"], @"Cat");
}


- (void) testPullDocContinuous {
    // For https://github.com/couchbase/couchbase-lite-core/issues/156
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID:@"doc1"];
    [doc1 setValue: @"Tiger" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    AssertEqual(self.db.count, 1u);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID:@"doc2"];
    [doc2 setValue: @"Cat" forKey: @"name"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: YES];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(self.db.count, 2u);
    CBLDocument* savedDoc2 = [self.db documentWithID: @"doc2"];
    AssertEqualObjects([savedDoc2 stringForKey:@"name"], @"Cat");
}


- (void) testPullConflict {
    // Create a document and push it to otherDB:
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID:@"doc"];
    [doc1 setValue: @"Tiger" forKey: @"species"];
    Assert([self.db saveDocument: doc1 error: &error]);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id pushConfig = [self configWithTarget: target type :kCBLReplicatorTypePush continuous: NO];
    [self run: pushConfig errorCode: 0 errorDomain: nil];
    
    // Now make different changes in db and otherDB:
    doc1 = [[self.db documentWithID: @"doc"] toMutable];
    [doc1 setValue: @"Hobbes" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    
    CBLMutableDocument* doc2 = [[otherDB documentWithID: @"doc"] toMutable];
    Assert(doc2);
    [doc2 setValue: @"striped" forKey: @"pattern"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    [doc2 setValue: @"black-yellow" forKey: @"color"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    // Pull from otherDB, creating a conflict to resolve:
    id pullConfig = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO];
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    // Check that it was resolved:
    AssertEqual(self.db.count, 1u);
    CBLDocument* savedDoc = [self.db documentWithID: @"doc"];
    
    // Most-Active Win:
    NSDictionary* expectedResult = @{@"species": @"Tiger",
                                     @"pattern": @"striped",
                                     @"color": @"black-yellow"};
    AssertEqualObjects(savedDoc.toDictionary, expectedResult);
    
    // Push to otherDB again to verify there is no replication conflict now,
    // and that otherDB ends up with the same resolved document:
    [self run: pushConfig errorCode: 0 errorDomain: nil];
    
    AssertEqual(otherDB.count, 1u);
    CBLDocument* otherSavedDoc = [otherDB documentWithID: @"doc"];
    AssertEqualObjects(otherSavedDoc.toDictionary, expectedResult);
}


- (void) testPullConflictNoBaseRevision {
    // Create the conflicting docs separately in each database. They have the same base revID
    // because the contents are identical, but because the db never pushed revision 1, it doesn't
    // think it needs to preserve its body; so when it pulls a conflict, there won't be a base
    // revision for the resolver.
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc"];
    [doc1 setValue: @"Tiger" forKey: @"species"];
    Assert([self.db saveDocument: doc1 error: &error]);
    [doc1 setValue: @"Hobbes" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc"];
    [doc2 setValue: @"Tiger" forKey: @"species"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    [doc2 setValue: @"striped" forKey: @"pattern"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    [doc2 setValue: @"black-yellow" forKey: @"color"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type :kCBLReplicatorTypePull continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(self.db.count, 1u);
    CBLDocument* savedDoc = [self.db documentWithID: @"doc"];
    AssertEqualObjects(savedDoc.toDictionary, (@{@"species": @"Tiger",
                                                 @"pattern": @"striped",
                                                 @"color": @"black-yellow"}));
}


- (void) testPullConflictDeleteWins {
    // Create a document and push it to otherDB:
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID:@"doc"];
    [doc1 setValue: @"Tiger" forKey: @"species"];
    Assert([self.db saveDocument: doc1 error: &error]);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id pushConfig = [self configWithTarget: target type :kCBLReplicatorTypePush continuous: NO];
    [self run: pushConfig errorCode: 0 errorDomain: nil];
    
    // Delete the document from db:
    Assert([self.db deleteDocument: doc1 error: &error]);
    AssertNil([self.db documentWithID: doc1.id]);
    
    // Update the document in otherDB:
    CBLMutableDocument* doc2 = [[otherDB documentWithID: doc1.id] toMutable];
    Assert(doc2);
    [doc2 setValue: @"striped" forKey: @"pattern"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    [doc2 setValue: @"black-yellow" forKey: @"color"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    // Pull from otherDB, creating a conflict to resolve:
    id pullConfig = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO];
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    // Check that it was resolved as delete wins:
    AssertEqual(self.db.count, 0u);
    AssertNil([self.db documentWithID: doc1.id]);
}


- (void) testStopContinuousReplicator {
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePushAndPull continuous: YES];
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: config];
    
    NSArray* stopWhen = @[@(kCBLReplicatorConnecting), @(kCBLReplicatorBusy),
                          @(kCBLReplicatorIdle), @(kCBLReplicatorIdle)];
    NSArray* activities = @[@"stopped", @"offline", @"connecting", @"idle", @"busy"];
    for (id when in stopWhen) {
        XCTestExpectation* x = [self expectationWithDescription: @"Replicator Change"];
        __weak typeof(self) wSelf = self;
        id token = [r addChangeListener: ^(CBLReplicatorChange *change) {
            [wSelf verifyChange: change errorCode: 0 errorDomain: nil];
            int whenValue = [when intValue];
            if (change.status.activity == whenValue) {
                NSLog(@"****** Stop Replicator (when %@) ******", activities[whenValue]);
                [change.replicator stop];
            } else if (change.status.activity == kCBLReplicatorStopped) {
                NSLog(@"****** Replicator is stopped ******");
                [x fulfill];
            }
        }];
        
        NSLog(@"****** Start Replicator ******");
        [r start];
        [self waitForExpectations: @[x] timeout: 10.0];
        [r removeChangeListenerWithToken: token];
        
        // Add some delay:
        // [NSThread sleepForTimeInterval: 1.0];
    }
    r = nil;
}


// Runs -testStopContinuousReplicator over and over again indefinitely. (Disabled, obviously)
- (void) _testStopContinuousReplicatorForever {
    for (int i = 0; true; i++) {
        @autoreleasepool {
            Log(@"**** Begin iteration %d ****", i);
            @autoreleasepool {
                [self testStopContinuousReplicator];
            }
            Log(@"**** End iteration %d ****", i);
            fprintf(stderr, "\n\n");
            [self tearDown];
            [NSThread sleepForTimeInterval: 1.0];
            [self setUp];
        }
    }
}


- (void) testCloseDatabaseWithActiveReplicator {
    // Add a replicator to the DB:
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePushAndPull continuous: YES];
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: config];
    
    XCTestExpectation *x1 = [self expectationWithDescription: @"Idle"];
    XCTestExpectation *x2 = [self expectationWithDescription: @"Stop"];
    id token = [r addChangeListener: ^(CBLReplicatorChange* change) {
        if (change.status.activity == kCBLReplicatorIdle)
            [x1 fulfill];
        
        if (change.status.activity == kCBLReplicatorStopped)
            [x2 fulfill];
    }];
    
    [r start];
    AssertEqual(self.db.activeReplications.count,(unsigned long)1);
    [self waitForExpectations: @[x1] timeout: 5.0];
    
    // Close Database:
    [self expectError: CBLErrorDomain code: CBLErrorBusy in: ^BOOL(NSError** err) {
        return [self.db close: err];
    }];
    
    [r stop];
    [self waitForExpectations: @[x2] timeout: 5.0];
    [r removeChangeListenerWithToken: token];
    r = nil;
    AssertEqual(self.db.activeReplications.count, (unsigned long)0);
}


- (void) testDeleteDatabaseWithActiveReplicator {
    // add a replicator to the DB
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePushAndPull continuous: YES];
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: config];
    
    XCTestExpectation *x1 = [self expectationWithDescription: @"Connect"];
    XCTestExpectation *x2 = [self expectationWithDescription: @"Stop"];
    
    // add observer to check if replicators are stopped on DB close
    id token = [r addChangeListener: ^(CBLReplicatorChange* change) {
        if (change.status.activity == kCBLReplicatorConnecting)
            [x1 fulfill];
        
        if (change.status.activity == kCBLReplicatorStopped)
            [x2 fulfill];
    }];
    
    [r start];
    AssertEqual(self.db.activeReplications.count,(unsigned long)1);
    [self waitForExpectations: @[x1] timeout: 5.0];
    
    // Close Database:
    [self expectError: CBLErrorDomain code: CBLErrorBusy in: ^BOOL(NSError** err) {
        return [self.db delete: err];
    }];
    
    [r stop];
    [self waitForExpectations: @[x2] timeout: 5.0];
    [r removeChangeListenerWithToken: token];
    r = nil;
    
    // Close Database - This should trigger a replication stop which should be caught by listener
    NSError* error;
    Assert([self.db delete:&error], @"Cannot delete database: %@", error);
}


- (void) testPushBlob {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    NSData* data = [self dataFromResource: @"image" ofType: @"jpg"];
    Assert(data);
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType: @"image/jpg"
                                                    data: data];
    [doc1 setBlob: blob forKey: @"blob"];
    Assert([self.db saveDocument: doc1 error: &error]);
    AssertEqual(self.db.count, 1u);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(otherDB.count, 1u);
    CBLDocument* savedDoc1 = [otherDB documentWithID: @"doc1"];
    AssertEqualObjects([savedDoc1 blobForKey:@"blob"], blob);
}


- (void) testPullBlob {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    NSData* data = [self dataFromResource: @"image" ofType: @"jpg"];
    Assert(data);
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType: @"image/jpg"
                                                    data: data];
    [doc1 setBlob: blob forKey: @"blob"];
    Assert([otherDB saveDocument: doc1 error: &error]);
    AssertEqual(otherDB.count, 1u);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: YES];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(self.db.count, 1u);
    CBLDocument* savedDoc1 = [self.db documentWithID: @"doc1"];
    AssertEqualObjects([savedDoc1 blobForKey:@"blob"], blob);
}


#if TARGET_OS_IPHONE


- (void) testSwitchBackgroundForeground {
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePushAndPull continuous: YES];
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: config];
    
    static NSInteger numRounds = 10;
    
    NSMutableArray* foregroundExps = [NSMutableArray arrayWithCapacity: numRounds + 1];
    NSMutableArray* backgroundExps = [NSMutableArray arrayWithCapacity: numRounds];
    for (NSInteger i = 0; i < numRounds; i++) {
        [foregroundExps addObject: [self expectationWithDescription: @"Foregrounding"]];
        [backgroundExps addObject: [self expectationWithDescription: @"Backgrounding"]];
    }
    [foregroundExps addObject: [self expectationWithDescription: @"Foregrounding"]];
    
    __block NSInteger backgroundCount = 0;
    __block NSInteger foregroundCount = 0;
    
    XCTestExpectation* stopped = [self expectationWithDescription: @"Stopped"];
    
    id token = [r addChangeListener: ^(CBLReplicatorChange* change) {
        AssertNil(change.status.error);
        if (change.status.activity == kCBLReplicatorIdle) {
            [foregroundExps[foregroundCount++] fulfill];
        } else if (change.status.activity == kCBLReplicatorOffline) {
            [backgroundExps[backgroundCount++] fulfill];
        } else if (change.status.activity == kCBLReplicatorStopped) {
            [stopped fulfill];
        }
    }];
    
    [r start];
    [self waitForExpectations: @[foregroundExps[0]] timeout: 5.0];
    
    for (int i = 0; i < numRounds; i++) {
        [r appBackgrounding];
        [self waitForExpectations: @[backgroundExps[i]] timeout: 5.0];
        
        [r appForegrounding];
        [self waitForExpectations: @[foregroundExps[i+1]] timeout: 5.0];
    }
    
    [r stop];
    [self waitForExpectations: @[stopped] timeout: 5.0];
    
    AssertEqual(foregroundCount, numRounds + 1);
    AssertEqual(backgroundCount, numRounds);
    
    [r removeChangeListenerWithToken: token];
    r = nil;
}


- (void) testBackgroundingWhenStopping {
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePushAndPull continuous: YES];
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: config];
    
    __block BOOL foregrounding = NO;
    
    XCTestExpectation* idle = [self expectationWithDescription: @"Idle after starting"];
    XCTestExpectation* stopped = [self expectationWithDescription: @"Stopped"];
    XCTestExpectation* done = [self expectationWithDescription: @"Done"];
    
    id token = [r addChangeListener: ^(CBLReplicatorChange* change) {
        Assert(!foregrounding);
        AssertNil(change.status.error);
        Assert(change.status.activity != kCBLReplicatorOffline);
        
        if (change.status.activity == kCBLReplicatorIdle) {
            [idle fulfill];
        } else if (change.status.activity == kCBLReplicatorStopped) {
            [stopped fulfill];
        }
    }];
    
    [r start];
    [self waitForExpectations: @[idle] timeout: 5.0];
    
    [r stop];
    
    // This shouldn't prevent the replicator to stop:
    [r appBackgrounding];
    [self waitForExpectations: @[stopped] timeout: 5.0];
    
    // This shouldn't wake up the replicator:
    foregrounding = YES;
    [r appForegrounding];
    
    // Wait for 0.3 seconds to ensure no more changes notified and cause !foregrounding to fail:
    id block = [NSBlockOperation blockOperationWithBlock: ^{ [done fulfill]; }];
    [NSTimer scheduledTimerWithTimeInterval: 0.3
                                     target: block
                                   selector: @selector(main) userInfo: nil repeats: NO];
    [self waitForExpectations: @[done] timeout: 1.0];
    
    [r removeChangeListenerWithToken: token];
    r = nil;
}


#endif // TARGET_OS_IPHONE


- (void) testResetCheckpoint {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"Tiger" forKey: @"species"];
    [doc1 setString: @"Hobbes" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setString: @"Tiger" forKey: @"species"];
    [doc2 setString: @"striped" forKey: @"pattern"];
    Assert([self.db saveDocument: doc2 error: &error]);
    
    // Push:
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    // Pull:
    config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(self.db.count, 2u);
    
    CBLDocument* doc = [self.db documentWithID: @"doc1"];
    Assert([self.db purgeDocument: doc error: &error]);
    
    doc = [self.db documentWithID: @"doc2"];
    Assert([self.db purgeDocument: doc error: &error]);
    
    AssertEqual(self.db.count, 0u);
    
    // Pull again, shouldn't have any new changes:
    [self run: config errorCode: 0 errorDomain: nil];
    AssertEqual(self.db.count, 0u);
    
    // Reset and pull:
    [self run: config reset: YES errorCode: 0 errorDomain: nil];
    AssertEqual(self.db.count, 2u);
}


- (void) testResetCheckpointContinuous {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"Tiger" forKey: @"species"];
    [doc1 setString: @"Hobbes" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setString: @"Tiger" forKey: @"species"];
    [doc2 setString: @"striped" forKey: @"pattern"];
    Assert([self.db saveDocument: doc2 error: &error]);
    
    // Push:
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: YES];
    [self run: config errorCode: 0 errorDomain: nil];
    
    // Pull:
    config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: YES];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(self.db.count, 2u);
    
    CBLDocument* doc = [self.db documentWithID: @"doc1"];
    Assert([self.db purgeDocument: doc error: &error]);
    
    doc = [self.db documentWithID: @"doc2"];
    Assert([self.db purgeDocument: doc error: &error]);
    
    AssertEqual(self.db.count, 0u);
    
    // Pull again, shouldn't have any new changes:
    [self run: config errorCode: 0 errorDomain: nil];
    AssertEqual(self.db.count, 0u);
    
    // Reset and pull:
    [self run: config reset: YES errorCode: 0 errorDomain: nil];
    AssertEqual(self.db.count, 2u);
}


- (void)testShortP2P {
    //int testNo = 1;
    for(int i = 0; i < 2; i++) {
        CBLProtocolType protocolType = i % 1 ? kCBLProtocolTypeMessageStream : kCBLProtocolTypeByteStream;
        CBLMutableDocument* mdoc = [CBLMutableDocument documentWithID:@"livesindb"];
        [mdoc setString:@"db" forKey:@"name"];
        [self saveDocument:mdoc];
        
        mdoc = [CBLMutableDocument documentWithID:@"livesinotherdb"];
        [mdoc setString:@"otherdb" forKey:@"name"];
        [self saveDocument:mdoc toDatabase:otherDB];
        
        // PUSH
        CBLMessageEndpointListenerConfiguration* config = [[CBLMessageEndpointListenerConfiguration alloc] initWithDatabase:otherDB protocolType:protocolType];
        CBLMessageEndpointListener* listener = [[CBLMessageEndpointListener alloc] initWithConfig:config];
        CBLMockServerConnection* server = [[CBLMockServerConnection alloc] initWithListener:listener andProtocol:protocolType];
        MockConnectionFactory* delegate = [[MockConnectionFactory alloc] initWithErrorLogic:nil];
        CBLMessageEndpoint* target = [[CBLMessageEndpoint alloc] initWithUID:[NSString stringWithFormat:@"test1"] target:server protocolType:protocolType delegate:delegate];
        CBLReplicatorConfiguration* replConfig = [[CBLReplicatorConfiguration alloc] initWithDatabase:_db target:target];
        replConfig.replicatorType = kCBLReplicatorTypePush;
        [self run:replConfig errorCode:0 errorDomain:nil];
        AssertEqual(otherDB.count, 2UL);
        AssertEqual(_db.count, 1UL);
        
        // PULL
        server = [[CBLMockServerConnection alloc] initWithListener:listener andProtocol:protocolType];
        target = [[CBLMessageEndpoint alloc] initWithUID:[NSString stringWithFormat:@"test1"] target:server protocolType:protocolType delegate:delegate];
        replConfig = [[CBLReplicatorConfiguration alloc] initWithDatabase:_db target:target];
        replConfig.replicatorType = kCBLReplicatorTypePull;
        [self run:replConfig errorCode:0 errorDomain:nil];
        AssertEqual(_db.count, 2UL);
        
        mdoc = [[_db documentWithID:@"livesinotherdb"] toMutable];
        [mdoc setBoolean:YES forKey:@"modified"];
        [self saveDocument:mdoc];
        
        mdoc = [[otherDB documentWithID:@"livesindb"] toMutable];
        [mdoc setBoolean:YES forKey:@"modified"];
        [self saveDocument:mdoc toDatabase:otherDB];
        
        // PUSH & PULL
        server = [[CBLMockServerConnection alloc] initWithListener:listener andProtocol:protocolType];
        target = [[CBLMessageEndpoint alloc] initWithUID:[NSString stringWithFormat:@"test1"] target:server protocolType:protocolType delegate:delegate];
        replConfig = [[CBLReplicatorConfiguration alloc] initWithDatabase:_db target:target];
        [self run:replConfig errorCode:0 errorDomain:nil];
        AssertEqual(_db.count, 2UL);
        
        // Workaround : https://github.com/couchbase/couchbase-lite-core/issues/539
        // [NSThread sleepForTimeInterval: 0.5];
        
        CBLDocument* savedDoc = [_db documentWithID:@"livesindb"];
        Assert([savedDoc booleanForKey:@"modified"]);
        savedDoc = [otherDB documentWithID:@"livesinotherdb"];
        Assert([savedDoc booleanForKey:@"modified"]);
        
        NSError* err = nil;
        BOOL success = [_db delete:&err];
        Assert(success);
        [self reopenDB];
        success = [otherDB delete:&err];
        Assert(success);
        otherDB = [self openDBNamed:otherDB.name error:&err];
        AssertNotNil(otherDB);
    }
}


- (void)testContinuousP2P {
    NSError* err = nil;
    BOOL success = [otherDB delete:&err];
    otherDB = [self openDBNamed:otherDB.name error:&err];
    Assert(success);
    success = [_db delete:&err];
    Assert(success);
    [self reopenDB];
    [self runTwoStepContinuousWithType:kCBLReplicatorTypePush usingUID:@"p2ptest1"];
    
    // Workaround : https://github.com/couchbase/couchbase-lite-core/issues/539
    // [NSThread sleepForTimeInterval: 0.5];
    
    success = [otherDB delete:&err];
    otherDB = [self openDBNamed:otherDB.name error:&err];
    Assert(success);
    success = [_db delete:&err];
    Assert(success);
    [self reopenDB];
    [self runTwoStepContinuousWithType:kCBLReplicatorTypePull usingUID:@"p2ptest2"];
    
    // Workaround : https://github.com/couchbase/couchbase-lite-core/issues/539
    // [NSThread sleepForTimeInterval: 0.5];
    
    success = [otherDB delete:&err];
    otherDB = [self openDBNamed:otherDB.name error:&err];
    Assert(success);
    success = [_db delete:&err];
    Assert(success);
    [self reopenDB];
    [self runTwoStepContinuousWithType:kCBLReplicatorTypePushAndPull usingUID:@"p2ptest3"];
}


- (void) testP2PRecoverableFailureDuringOpen {
    [self runP2PErrorScenario:kCBLMockConnectionConnect withRecoverability:YES];
}


- (void)testP2PRecoverableFailureDuringSend {
    [self runP2PErrorScenario:kCBLMockConnectionSend withRecoverability:YES];
}


- (void)testP2PRecoverableFailureDuringReceive {
    [self runP2PErrorScenario:kCBLMockConnectionReceive withRecoverability:YES];
}


- (void)testP2PPermanentFailureDuringOpen {
    [self runP2PErrorScenario:kCBLMockConnectionConnect withRecoverability:NO];
}


- (void)testP2PPermanentFailureDuringSend {
    [self runP2PErrorScenario:kCBLMockConnectionSend withRecoverability:NO];
}


- (void)testP2PPermanentFailureDuringReceive {
    [self runP2PErrorScenario:kCBLMockConnectionReceive withRecoverability:NO];
}


- (void)testP2PPassiveClose {
    CBLMessageEndpointListenerConfiguration* config = [[CBLMessageEndpointListenerConfiguration alloc] initWithDatabase:otherDB protocolType:kCBLProtocolTypeMessageStream];
    CBLMessageEndpointListener* listener = [[CBLMessageEndpointListener alloc] initWithConfig:config];
    CBLMockServerConnection* server = [[CBLMockServerConnection alloc] initWithListener:listener andProtocol:kCBLProtocolTypeMessageStream];
    CBLReconnectErrorLogic* errorLogic = [CBLReconnectErrorLogic new];
    MockConnectionFactory* delegate = [[MockConnectionFactory alloc] initWithErrorLogic:errorLogic];
    CBLMessageEndpoint* target = [[CBLMessageEndpoint alloc] initWithUID:@"p2ptest1" target:server protocolType:kCBLProtocolTypeMessageStream delegate:delegate];
    CBLReplicatorConfiguration* replConfig = [[CBLReplicatorConfiguration alloc] initWithDatabase:_db target:target];
    replConfig.continuous = YES;
    
    XCTestExpectation* listenerStop = [self waitForListenerStopped:listener];
    NSMutableArray* listenerErrors = [NSMutableArray new];
    __block id listenerToken = nil;
    listenerToken = [listener addChangeListener:^(CBLMessageEndpointListenerChange * _Nonnull change) {
        if(change.status.error) {
            [listenerErrors addObject:change.status.error];
        }
    }];
    
    CBLReplicator* replicator = [[CBLReplicator alloc] initWithConfig:replConfig];
    XCTestExpectation* x = [self waitForReplicatorIdle:replicator withProgressAtLeast:0];
    [replicator start];
    [self waitForExpectations:@[x] timeout:10.0];
    errorLogic.isErrorActive = true;
    x = [self waitForReplicatorStopped:replicator];
    
    [listener close:server];
    [self waitForExpectations:@[x, listenerStop] timeout:10.0];
    AssertEqual(listenerErrors.count, 0UL);
    AssertNotNil(replicator.status.error);
}


- (void) testP2PPassiveCloseAll {
    CBLMutableDocument* doc = [CBLMutableDocument documentWithID:@"test"];
    [doc setString:@"Smokey" forKey:@"name"];
    [self saveDocument:doc];
    
    CBLMessageEndpointListenerConfiguration* config = [[CBLMessageEndpointListenerConfiguration alloc] initWithDatabase:otherDB protocolType:kCBLProtocolTypeMessageStream];
    CBLMessageEndpointListener* listener = [[CBLMessageEndpointListener alloc] initWithConfig:config];
    CBLMockServerConnection* serverConnection1 = [[CBLMockServerConnection alloc] initWithListener:listener andProtocol:kCBLProtocolTypeMessageStream];
    CBLMockServerConnection* serverConnection2 = [[CBLMockServerConnection alloc] initWithListener:listener andProtocol:kCBLProtocolTypeMessageStream];
    CBLReconnectErrorLogic* errorLogic = [CBLReconnectErrorLogic new];
    MockConnectionFactory* delegate = [[MockConnectionFactory alloc] initWithErrorLogic:errorLogic];
    CBLMessageEndpoint* target = [[CBLMessageEndpoint alloc] initWithUID:@"p2ptest1" target:serverConnection1 protocolType:kCBLProtocolTypeMessageStream delegate:delegate];
    CBLReplicatorConfiguration* replConfig = [[CBLReplicatorConfiguration alloc] initWithDatabase:_db target:target];
    replConfig.continuous = YES;
    MockConnectionFactory* delegate2 = [[MockConnectionFactory alloc] initWithErrorLogic:errorLogic];
    CBLMessageEndpoint* target2 = [[CBLMessageEndpoint alloc] initWithUID:@"p2ptest2" target:serverConnection2 protocolType:kCBLProtocolTypeMessageStream delegate:delegate2];
    CBLReplicatorConfiguration* replConfig2 = [[CBLReplicatorConfiguration alloc] initWithDatabase:_db target:target2];
    replConfig2.continuous = YES;
    CBLReplicator* replicator = [[CBLReplicator alloc] initWithConfig:replConfig];
    CBLReplicator* replicator2 = [[CBLReplicator alloc] initWithConfig:replConfig2];
    XCTestExpectation* idle1 = [self waitForReplicatorIdle:replicator withProgressAtLeast:0];
    XCTestExpectation* idle2 = [self waitForReplicatorIdle:replicator2 withProgressAtLeast:0];
    XCTestExpectation* stop1 = [self waitForReplicatorStopped:replicator];
    XCTestExpectation* stop2 = [self waitForReplicatorStopped:replicator2];
    
    [replicator start];
    [replicator2 start];
    [self waitForExpectations:@[idle1, idle2] timeout:10.0];
    errorLogic.isErrorActive = YES;
    
    XCTestExpectation* listenerStop1 = [self expectationWithDescription:@"First Listener Stopped"];
    XCTestExpectation* listenerStop2 = [self expectationWithDescription:@"Second Listener Stopped"];
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
    [self waitForExpectations:@[listenerStop1, listenerStop2] timeout:10.0];
    [listener removeChangeListenerWithToken:listenerToken];
    [self waitForExpectations:@[stop1, stop2] timeout:10.0];
    AssertNotNil(replicator.status.error);
    AssertNotNil(replicator2.status.error);
}


- (void)testP2PChangeListener {
    NSMutableArray* statuses = [NSMutableArray new];
    CBLMessageEndpointListener* listener = [[CBLMessageEndpointListener alloc] initWithConfig:[[CBLMessageEndpointListenerConfiguration alloc] initWithDatabase:otherDB protocolType:kCBLProtocolTypeByteStream]];
    CBLMockServerConnection* serverConnection = [[CBLMockServerConnection alloc] initWithListener:listener andProtocol:kCBLProtocolTypeByteStream];
    MockConnectionFactory* delegate = [[MockConnectionFactory alloc] initWithErrorLogic:nil];
    CBLMessageEndpoint* target = [[CBLMessageEndpoint alloc] initWithUID:@"p2ptest1" target:serverConnection protocolType:kCBLProtocolTypeByteStream delegate:delegate];
    CBLReplicatorConfiguration* config = [[CBLReplicatorConfiguration alloc] initWithDatabase:_db target:target];
    config.continuous = YES;
    XCTestExpectation *x = [self waitForListenerStopped:listener];
    [listener addChangeListener:^(CBLMessageEndpointListenerChange * _Nonnull change) {
        [statuses addObject:@(change.status.activity)];
    }];
    
    [self run:config errorCode:0 errorDomain:nil];
    [self waitForExpectations:@[x] timeout:10.0];
    Assert(statuses.count > 0);
}


- (void)testP2PRemoveChangeListener {
    NSMutableArray* statuses = [NSMutableArray new];
    CBLMessageEndpointListener* listener = [[CBLMessageEndpointListener alloc] initWithConfig:[[CBLMessageEndpointListenerConfiguration alloc] initWithDatabase:otherDB protocolType:kCBLProtocolTypeByteStream]];
    CBLMockServerConnection* serverConnection = [[CBLMockServerConnection alloc] initWithListener:listener andProtocol:kCBLProtocolTypeByteStream];
    MockConnectionFactory* delegate = [[MockConnectionFactory alloc] initWithErrorLogic:nil];
    CBLMessageEndpoint* target = [[CBLMessageEndpoint alloc] initWithUID:@"p2ptest1" target:serverConnection protocolType:kCBLProtocolTypeByteStream delegate:delegate];
    CBLReplicatorConfiguration* config = [[CBLReplicatorConfiguration alloc] initWithDatabase:_db target:target];
    config.continuous = YES;
    XCTestExpectation *x = [self waitForListenerStopped:listener];
    id token = [listener addChangeListener:^(CBLMessageEndpointListenerChange * _Nonnull change) {
        [statuses addObject:@(change.status.activity)];
    }];
    [listener removeChangeListenerWithToken:token];
    
    [self run:config errorCode:0 errorDomain:nil];
    [self waitForExpectations:@[x] timeout:10.0];
    Assert(statuses.count == 0UL);
}


- (void) testP2PPushWithDocIDsFilter {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"doc1" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setString: @"doc2" forKey: @"name"];
    Assert([self.db saveDocument: doc2 error: &error]);
    
    CBLMutableDocument* doc3 = [[CBLMutableDocument alloc] initWithID: @"doc3"];
    [doc3 setString: @"doc3" forKey: @"name"];
    Assert([self.db saveDocument: doc3 error: &error]);
    
    // Push:
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    CBLReplicatorConfiguration* config =
        [self configWithTarget: target type: kCBLReplicatorTypePush continuous: NO];
    config.documentIDs = @[@"doc1", @"doc3"];
    
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(otherDB.count, 2u);
    AssertNotNil([otherDB documentWithID: @"doc1"]);
    AssertNotNil([otherDB documentWithID: @"doc3"]);
    AssertNil([otherDB documentWithID: @"doc2"]);
}


- (void) testP2PPullWithDocIDsFilter {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"doc1" forKey: @"name"];
    Assert([otherDB saveDocument: doc1 error: &error]);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setString: @"doc2" forKey: @"name"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    CBLMutableDocument* doc3 = [[CBLMutableDocument alloc] initWithID: @"doc3"];
    [doc3 setString: @"doc3" forKey: @"name"];
    Assert([otherDB saveDocument: doc3 error: &error]);
    
    // Pull:
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    CBLReplicatorConfiguration* config =
    [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO];
    config.documentIDs = @[@"doc1", @"doc3"];
    
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(self.db.count, 2u);
    AssertNotNil([self.db documentWithID: @"doc1"]);
    AssertNotNil([self.db documentWithID: @"doc3"]);
    AssertNil([self.db documentWithID: @"doc2"]);
}


- (void) testP2PPushAndPullWithDocIDsFilter {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"doc1" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setString: @"doc2" forKey: @"name"];
    Assert([self.db saveDocument: doc2 error: &error]);
    
    CBLMutableDocument* doc3 = [[CBLMutableDocument alloc] initWithID: @"doc3"];
    [doc3 setString: @"doc3" forKey: @"name"];
    Assert([otherDB saveDocument: doc3 error: &error]);
    
    CBLMutableDocument* doc4 = [[CBLMutableDocument alloc] initWithID: @"doc4"];
    [doc4 setString: @"doc4" forKey: @"name"];
    Assert([otherDB saveDocument: doc4 error: &error]);
    
    // Push:
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    CBLReplicatorConfiguration* config =
    [self configWithTarget: target type: kCBLReplicatorTypePushAndPull continuous: NO];
    config.documentIDs = @[@"doc1", @"doc4"];
    
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(self.db.count, 3u);
    AssertNotNil([self.db documentWithID: @"doc1"]);
    AssertNotNil([self.db documentWithID: @"doc2"]);
    AssertNotNil([self.db documentWithID: @"doc4"]);
    AssertNil([self.db documentWithID: @"doc3"]);
    
    AssertEqual(otherDB.count, 3u);
    AssertNotNil([otherDB documentWithID: @"doc1"]);
    AssertNotNil([otherDB documentWithID: @"doc3"]);
    AssertNotNil([otherDB documentWithID: @"doc4"]);
    AssertNil([otherDB documentWithID: @"doc2"]);
}


- (void) testDocumentReplicationEvent {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"Tiger" forKey: @"species"];
    [doc1 setString: @"Hobbes" forKey: @"pattern"];
    Assert([self.db saveDocument: doc1 error: &error]);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setString: @"Tiger" forKey: @"species"];
    [doc2 setString: @"Striped" forKey: @"pattern"];
    Assert([self.db saveDocument: doc2 error: &error]);
    
    // Push:
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: NO];

    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    NSMutableArray<CBLReplicatedDocument*>* docs = [NSMutableArray array];
    [self run: config reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
        replicator = r;
        token = [r addDocumentReplicationListener: ^(CBLDocumentReplication *docReplication) {
            Assert(docReplication.isPush);
            for (CBLReplicatedDocument* doc in docReplication.documents) {
                [docs addObject: doc];
            }
        }];
    }];
    
    // Check if getting two document replication events:
    AssertEqual(docs.count, 2u);
    AssertEqualObjects(docs[0].id, @"doc1");
    AssertNil(docs[0].error);
    Assert((docs[0].flags & kCBLDocumentFlagsDeleted) != kCBLDocumentFlagsDeleted);
    Assert((docs[0].flags & kCBLDocumentFlagsAccessRemoved) != kCBLDocumentFlagsAccessRemoved);
    
    AssertEqualObjects(docs[1].id, @"doc2");
    AssertNil(docs[1].error);
    Assert((docs[1].flags & kCBLDocumentFlagsDeleted) != kCBLDocumentFlagsDeleted);
    Assert((docs[1].flags & kCBLDocumentFlagsAccessRemoved) != kCBLDocumentFlagsAccessRemoved);
    
    // Add another doc:
    CBLMutableDocument* doc3 = [[CBLMutableDocument alloc] initWithID: @"doc3"];
    [doc3 setString: @"Tiger" forKey: @"species"];
    [doc3 setString: @"Star" forKey: @"pattern"];
    Assert([self.db saveDocument: doc3 error: &error]);
    
    // Run the replicator again:
    [self runWithReplicator: replicator errorCode: 0 errorDomain: 0];
    
    // Check if getting a new document replication event:
    AssertEqual(docs.count, 3u);
    AssertEqualObjects(docs[2].id, @"doc3");
    AssertNil(docs[2].error);
    Assert((docs[2].flags & kCBLDocumentFlagsDeleted) != kCBLDocumentFlagsDeleted);
    Assert((docs[2].flags & kCBLDocumentFlagsAccessRemoved) != kCBLDocumentFlagsAccessRemoved);
    
    // Add another doc:
    CBLMutableDocument* doc4 = [[CBLMutableDocument alloc] initWithID: @"doc4"];
    [doc4 setString: @"Tiger" forKey: @"species"];
    [doc4 setString: @"WhiteStriped" forKey: @"pattern"];
    Assert([self.db saveDocument: doc4 error: &error]);
    
    // Remove document replication listener:
    [replicator removeChangeListenerWithToken: token];
    
    // Run the replicator again:
    [self runWithReplicator: replicator errorCode: 0 errorDomain: 0];
    
    // Should not getting a new document replication event:
    AssertEqual(docs.count, 3u);
}


- (void) testDocumentReplicationEventWithPushConflict {
    NSError* error;
    CBLMutableDocument* doc1a = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1a setString: @"Tiger" forKey: @"species"];
    [doc1a setString: @"Star" forKey: @"pattern"];
    Assert([self.db saveDocument: doc1a error: &error]);
    
    CBLMutableDocument* doc1b = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1b setString: @"Tiger" forKey: @"species"];
    [doc1b setString: @"Striped" forKey: @"pattern"];
    Assert([otherDB saveDocument: doc1b error: &error]);
    
    // Push:
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: NO];
    
    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    NSMutableArray<CBLReplicatedDocument*>* docs = [NSMutableArray array];
    [self run: config reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
        replicator = r;
        token = [r addDocumentReplicationListener: ^(CBLDocumentReplication *docReplication) {
            Assert(docReplication.isPush);
            for (CBLReplicatedDocument* doc in docReplication.documents) {
                [docs addObject: doc];
            }
        }];
    }];
    
    // Run the replicator:
    [self runWithReplicator: replicator errorCode: 0 errorDomain: 0];
    
    // Check:
    AssertEqual(docs.count, 1u);
    AssertEqualObjects(docs[0].id, @"doc1");
    AssertNotNil(docs[0].error);
    AssertEqualObjects(docs[0].error.domain, CBLErrorDomain);
    AssertEqual(docs[0].error.code, CBLErrorHTTPConflict);
    Assert((docs[0].flags & kCBLDocumentFlagsDeleted) != kCBLDocumentFlagsDeleted);
    Assert((docs[0].flags & kCBLDocumentFlagsAccessRemoved) != kCBLDocumentFlagsAccessRemoved);
    
    // Remove document replication listener:
    [replicator removeChangeListenerWithToken: token];
}


- (void) testDocumentReplicationEventWithPullConflict {
    NSError* error;
    CBLMutableDocument* doc1a = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1a setString: @"Tiger" forKey: @"species"];
    [doc1a setString: @"Star" forKey: @"pattern"];
    Assert([self.db saveDocument: doc1a error: &error]);
    
    CBLMutableDocument* doc1b = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1b setString: @"Tiger" forKey: @"species"];
    [doc1b setString: @"Striped" forKey: @"pattern"];
    Assert([otherDB saveDocument: doc1b error: &error]);
    
    // Pull:
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO];
    
    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    NSMutableArray<CBLReplicatedDocument*>* docs = [NSMutableArray array];
    [self run: config reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
        replicator = r;
        token = [r addDocumentReplicationListener: ^(CBLDocumentReplication *docReplication) {
            AssertFalse(docReplication.isPush);
            for (CBLReplicatedDocument* doc in docReplication.documents) {
                [docs addObject: doc];
            }
        }];
    }];
    
    // Check:
    AssertEqual(docs.count, 1u);
    AssertEqualObjects(docs[0].id, @"doc1");
    AssertNil(docs[0].error);
    Assert((docs[0].flags & kCBLDocumentFlagsDeleted) != kCBLDocumentFlagsDeleted);
    Assert((docs[0].flags & kCBLDocumentFlagsAccessRemoved) != kCBLDocumentFlagsAccessRemoved);
    
    // Remove document replication listener:
    [replicator removeChangeListenerWithToken: token];
}


- (void) testDocumentReplicationEventWithDeletion {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"Tiger" forKey: @"species"];
    [doc1 setString: @"Star" forKey: @"pattern"];
    Assert([self.db saveDocument: doc1 error: &error]);
    
    // Delete:
    Assert([self.db deleteDocument: doc1 error: &error]);
    
    // Push:
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: NO];
    
    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    NSMutableArray<CBLReplicatedDocument*>* docs = [NSMutableArray array];
    [self run: config reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
        replicator = r;
        token = [r addDocumentReplicationListener: ^(CBLDocumentReplication *docReplication) {
            Assert(docReplication.isPush);
            for (CBLReplicatedDocument* doc in docReplication.documents) {
                [docs addObject: doc];
            }
        }];
    }];
    
    // Run the replicator:
    [self runWithReplicator: replicator errorCode: 0 errorDomain: 0];
    
    // Check:
    AssertEqual(docs.count, 1u);
    AssertEqualObjects(docs[0].id, @"doc1");
    AssertNil(docs[0].error);
    Assert((docs[0].flags & kCBLDocumentFlagsDeleted) == kCBLDocumentFlagsDeleted);
    Assert((docs[0].flags & kCBLDocumentFlagsAccessRemoved) != kCBLDocumentFlagsAccessRemoved);
    
    // Remove document replication listener:
    [replicator removeChangeListenerWithToken: token];
}


- (void) testSingleShotPushFilter {
    [self testPushFilter: NO];
}


- (void) testContinuousPushFilter {
    [self testPushFilter: YES];
}


- (void) testPushFilter: (BOOL)isContinuous {
    // Create documents:
    NSError* error;
    NSData* content = [@"I'm a tiger." dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType:@"text/plain" data: content];
    
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"Tiger" forKey: @"species"];
    [doc1 setString: @"Hobbes" forKey: @"pattern"];
    [doc1 setBlob: blob forKey: @"photo"];
    Assert([self.db saveDocument: doc1 error: &error]);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setString: @"Tiger" forKey: @"species"];
    [doc2 setString: @"Striped" forKey: @"pattern"];
    [doc2 setBlob: blob forKey: @"photo"];
    Assert([self.db saveDocument: doc2 error: &error]);
    
    CBLMutableDocument* doc3 = [[CBLMutableDocument alloc] initWithID: @"doc3"];
    [doc3 setString: @"Tiger" forKey: @"species"];
    [doc3 setString: @"Star" forKey: @"pattern"];
    [doc3 setBlob: blob forKey: @"photo"];
    Assert([self.db saveDocument: doc3 error: &error]);
    Assert([self.db deleteDocument: doc3 error: &error]);
    
    // Create replicator with push filter:
    NSMutableSet<NSString*>* docIds = [NSMutableSet set];
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    CBLReplicatorConfiguration* config = [self configWithTarget: target
                                                           type: kCBLReplicatorTypePush
                                                     continuous: isContinuous];
    config.pushFilter = ^BOOL(CBLDocument* document, CBLDocumentFlags flags) {
        // Check document ID:
        AssertNotNil(document.id);
        
        // isDeleted:
        BOOL isDeleted = (flags & kCBLDocumentFlagsDeleted) == kCBLDocumentFlagsDeleted;
        
        // Check deleted flag:
        Assert([document.id isEqualToString: @"doc3"] ? isDeleted : !isDeleted);
        if (!isDeleted) {
            // Check content:
            AssertNotNil([document valueForKey: @"pattern"]);
            AssertEqualObjects([document valueForKey: @"species"], @"Tiger");
            
            // Check blob:
            CBLBlob *photo = [document blobForKey: @"photo"];
            AssertNotNil(photo);
            AssertEqualObjects(photo.content, photo.content);
        } else
            AssertEqualObjects(document.toDictionary, @{});
        
        // Gather document ID:
        [docIds addObject: document.id];
        
        // Reject doc2:
        return [document.id isEqualToString: @"doc2"] ? NO : YES;
    };
    [self run: config errorCode: 0 errorDomain: nil];
    
    // Check documents passed to the filter:
    AssertEqual(docIds.count, 3u);
    Assert([docIds containsObject: @"doc1"]);
    Assert([docIds containsObject: @"doc2"]);
    Assert([docIds containsObject: @"doc3"]);
    
    // Check replicated documents:
    AssertNotNil([otherDB documentWithID: @"doc1"]);
    AssertNil([otherDB documentWithID: @"doc2"]);
    AssertNil([otherDB documentWithID: @"doc3"]);
}


- (void) testPullFilter {
    // Add a document to db database so that it can pull the deleted docs from:
    NSError* error;
    CBLMutableDocument* doc0 = [[CBLMutableDocument alloc] initWithID: @"doc0"];
    [doc0 setString: @"Cat" forKey: @"species"];
    Assert([self.db saveDocument: doc0 error: &error]);
    
    // Create documents to otherDB:
    NSData* data = [self dataFromResource: @"image" ofType: @"jpg"];
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType: @"image/jpeg" data: data];
    
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"Tiger" forKey: @"species"];
    [doc1 setString: @"Hobbes" forKey: @"pattern"];
    [doc1 setBlob: blob forKey: @"photo"];
    Assert([otherDB saveDocument: doc1 error: &error]);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setString: @"Tiger" forKey: @"species"];
    [doc2 setString: @"Striped" forKey: @"pattern"];
    [doc2 setBlob: blob forKey: @"photo"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    CBLMutableDocument* doc3 = [[CBLMutableDocument alloc] initWithID: @"doc3"];
    [doc3 setString: @"Tiger" forKey: @"species"];
    [doc3 setString: @"Star" forKey: @"pattern"];
    [doc2 setBlob: blob forKey: @"photo"];
    Assert([otherDB saveDocument: doc3 error: &error]);
    Assert([otherDB deleteDocument: doc3 error: &error]);
    
    // Create replicator with pull filter:
    NSMutableSet<NSString*>* docIds = [NSMutableSet set];
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    CBLReplicatorConfiguration* config = [self configWithTarget: target
                                                           type: kCBLReplicatorTypePull
                                                     continuous: NO];
    config.pullFilter = ^BOOL(CBLDocument* document, CBLDocumentFlags flags) {
        // Check document ID:
        AssertNotNil(document.id);
        
        // isDeleted:
        BOOL isDeleted = (flags & kCBLDocumentFlagsDeleted) == kCBLDocumentFlagsDeleted;
        
        // Check deleted flag:
        Assert([document.id isEqualToString: @"doc3"] ? isDeleted : !isDeleted);
        if (!isDeleted) {
            // Check content:
            AssertNotNil([document valueForKey: @"pattern"]);
            AssertEqualObjects([document valueForKey: @"species"], @"Tiger");
            
            // Check Blob:
            CBLBlob *photo = [document blobForKey: @"photo"];
            AssertNotNil(photo);
            
            // Note: Cannot access content because there is no actual blob file saved on disk yet.
            // AssertEqualObjects(photo.content, photo.content);
        } else
            AssertEqualObjects(document.toDictionary, @{});
        
        // Gather document ID:
        [docIds addObject: document.id];
        
        // Reject doc2:
        return [document.id isEqualToString: @"doc2"] ? NO : YES;
    };
    
    // Run the replicator:
    [self run: config errorCode: 0 errorDomain: nil];
    
    // Check documents passed to the filter:
    AssertEqual(docIds.count, 3u);
    Assert([docIds containsObject: @"doc1"]);
    Assert([docIds containsObject: @"doc2"]);
    Assert([docIds containsObject: @"doc3"]);
    
    // Check replicated documents:
    AssertNotNil([self.db documentWithID: @"doc1"]);
    AssertNil([self.db documentWithID: @"doc2"]);
    AssertNil([self.db documentWithID: @"doc3"]);
}


- (void) testPushAndForget {
    NSError* error;
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] initWithID: @"doc"];
    [doc setString: @"Tiger" forKey: @"species"];
    [doc setString: @"Hobbes" forKey: @"pattern"];
    Assert([self.db saveDocument: doc error: &error]);
    
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    id docChangeToken = [self.db addDocumentChangeListenerWithID: doc.id
                                                        listener: ^(CBLDocumentChange *change)
                         {
                             AssertEqualObjects(change.documentID, doc.id);
                             if ([change.database documentWithID: change.documentID] == nil) {
                                 [expectation fulfill];
                             }
                         }];
    
    // Push:
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: NO];
    
    __block id<CBLListenerToken> docReplToken;
    __block CBLReplicator* replicator;
    [self run: config reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
        replicator = r;
        docReplToken = [r addDocumentReplicationListener: ^(CBLDocumentReplication *docReplication) {
            NSError* err;
            Assert([self.db setDocumentExpirationWithID: doc.id
                                             expiration: [NSDate date]
                                                  error: &err]);
        }];
    }];
    
    [self waitForExpectationsWithTimeout: 5.0 handler: nil];
    
    AssertEqual(self.db.count, 0u);
    AssertEqual(otherDB.count, 1u);
    [self.db removeChangeListenerWithToken: docChangeToken];
    [replicator removeChangeListenerWithToken: docReplToken];
}


#pragma mark Removed Doc with Filter


- (void) testPullRemovedDocWithFilterSingleShot {
    [self testPullRemovedDocWithFilter: NO];
}


- (void) testPullRemovedDocWithFilterContinuous {
    [self testPullRemovedDocWithFilter: YES];
}


- (void) testPullRemovedDocWithFilter: (BOOL)isContinuous {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"pass" forKey: @"name"];
    Assert([otherDB saveDocument: doc1 error: &error]);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"pass"];
    [doc2 setString: @"pass" forKey: @"name"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    // replicator with pull filter
    NSMutableSet<NSString*>* docIds = [NSMutableSet set];
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    CBLReplicatorConfiguration* config = [self configWithTarget: target
                                                           type: kCBLReplicatorTypePull
                                                     continuous: isContinuous];
    config.pullFilter = ^BOOL(CBLDocument* document, CBLDocumentFlags flags) {
        AssertNotNil(document.id);
        BOOL isAccessRemoved = (flags & kCBLDocumentFlagsAccessRemoved) == kCBLDocumentFlagsAccessRemoved;
        if (isAccessRemoved) {
            [docIds addObject: document.id];
            
            // if access removed only allow  `docID = pass` is allowed.
            return [document.id isEqualToString: @"pass"];
        }
        // allow all docs with `name = pass`
        return [[document stringForKey: @"name"] isEqualToString: @"pass"];
    };
    
    [self run: config errorCode: 0 errorDomain: nil];
    AssertEqual(docIds.count, 0u);
    
    // Update the `_removed` flag
    doc1 = [[otherDB documentWithID: @"doc1"] toMutable];
    [doc1 setData: @{@"_removed": @YES}];
    Assert([otherDB saveDocument: doc1 error: &error]);
    
    doc2 = [[otherDB documentWithID: @"pass"] toMutable];
    [doc2 setData: @{@"_removed": @YES}];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    // pull replication again...
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(docIds.count, 2u);
    
    // shouldn't delete the one with `docID != pass`
    AssertNotNil([self.db documentWithID: @"doc1"]);
    AssertNil([self.db documentWithID: @"pass"]);
}


#pragma mark Deleted Doc with Filter


- (void) testPushDeletedDocWithFilterSingleShot {
    [self testPushDeletedDocWithFilter: NO];
}


- (void) testPushDeletedDocWithFilterContinuous {
    [self testPushDeletedDocWithFilter: YES];
}


- (void) testPullDeletedDocWithFilterSingleShot {
    [self testPullDeletedDocWithFilter: NO];
}


- (void) testPullDeletedDocWithFilterContinuous {
    [self testPullDeletedDocWithFilter: YES];
}


- (void) testPushDeletedDocWithFilter: (BOOL)isContinuous {
    // Create documents:
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"pass" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"pass"];
    [doc2 setString: @"pass" forKey: @"name"];
    Assert([self.db saveDocument: doc2 error: &error]);
    
    // Create replicator with push filter:
    NSMutableSet<NSString*>* docIds = [NSMutableSet set];
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    CBLReplicatorConfiguration* config = [self configWithTarget: target
                                                           type: kCBLReplicatorTypePush
                                                     continuous: isContinuous];
    config.pushFilter = ^BOOL(CBLDocument* document, CBLDocumentFlags flags) {
        AssertNotNil(document.id);
        
        BOOL isDeleted = (flags & kCBLDocumentFlagsDeleted) == kCBLDocumentFlagsDeleted;
        if (isDeleted) {
            [docIds addObject: document.id];
            
            // if deleted only allow  `docID = pass` is allowed.
            return [document.id isEqualToString: @"pass"];
        }
        // allow all docs with `name = pass`
        return [[document stringForKey: @"name"] isEqualToString: @"pass"];
    };
    
    [self run: config errorCode: 0 errorDomain: nil];
    AssertEqual(docIds.count, 0u);
    
    // Check replicated documents:
    AssertNotNil([otherDB documentWithID: @"doc1"]);
    AssertNotNil([otherDB documentWithID: @"pass"]);
    
    Assert([self.db deleteDocument: doc1 error: &error]);
    Assert([self.db deleteDocument: doc2 error: &error]);
    
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(docIds.count, 2u);
    Assert([docIds containsObject: @"doc1"]);
    Assert([docIds containsObject: @"pass"]);
    
    // shouldn't delete the one with `docID != pass`
    AssertNotNil([otherDB documentWithID: @"doc1"]);
    AssertNil([otherDB documentWithID: @"pass"]);
}


- (void) testPullDeletedDocWithFilter: (BOOL)isContinuous {
    // Create documents:
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"pass" forKey: @"name"];
    Assert([otherDB saveDocument: doc1 error: &error]);
    
    CBLMutableDocument* pass = [[CBLMutableDocument alloc] initWithID: @"pass"];
    [pass setString: @"pass" forKey: @"name"];
    Assert([otherDB saveDocument: pass error: &error]);
    
    NSMutableSet<NSString*>* docIds = [NSMutableSet set];
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    CBLReplicatorConfiguration* config = [self configWithTarget: target
                                                           type: kCBLReplicatorTypePull
                                                     continuous: isContinuous];
    config.pullFilter = ^BOOL(CBLDocument* document, CBLDocumentFlags flags) {
        AssertNotNil(document.id);
        
        BOOL isDeleted = (flags & kCBLDocumentFlagsDeleted) == kCBLDocumentFlagsDeleted;
        if (isDeleted) {
            [docIds addObject: document.id];
            
            // if deleted only allow  `docID = pass` is allowed.
            return [document.id isEqualToString: @"pass"];
        }
        // allow all docs with `name = pass`
        return [[document stringForKey: @"name"] isEqualToString: @"pass"];
    };
    
    [self run: config errorCode: 0 errorDomain: nil];
    AssertEqual(docIds.count, 0u);
    
    // should replicate all docs with `name = pass`
    AssertNotNil([self.db documentWithID: @"doc1"]);
    AssertNotNil([self.db documentWithID: @"pass"]);
    AssertEqual(self.db.count, 2u);
    AssertEqual(otherDB.count, 2u);
    
    Assert([otherDB deleteDocument: doc1 error: &error]);
    Assert([otherDB deleteDocument: pass error: &error]);
    
    [self run: config errorCode: 0 errorDomain: nil];
    
    // Check documents passed to the filter:
    AssertEqual(docIds.count, 2u);
    Assert([docIds containsObject: @"doc1"]);
    Assert([docIds containsObject: @"pass"]);
    
    // shouldn't delete the one with `docID != pass`
    AssertNotNil([self.db documentWithID: @"doc1"]);
    AssertNil([self.db documentWithID: @"pass"]);
    AssertEqual(self.db.count, 1u);
    AssertEqual(otherDB.count, 0u);
}


#pragma mark stop and restart the replication with filter


- (void) testStopAndRestartPushReplicationWithFilter {
    // Create documents
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"pass" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    
    NSMutableSet<NSString*>* docIds = [NSMutableSet set];
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    CBLReplicatorConfiguration* config = [self configWithTarget: target
                                                           type: kCBLReplicatorTypePush
                                                     continuous: YES];
    config.pushFilter = ^BOOL(CBLDocument* document, CBLDocumentFlags flags) {
        AssertNotNil(document.id);
        [docIds addObject: document.id];
        
        // allow all docs with `name = pass`
        return [[document stringForKey: @"name"] isEqualToString: @"pass"];
    };
    
    repl = [[CBLReplicator alloc] initWithConfig: config];
    [self runWithReplicator: repl errorCode: 0 errorDomain: nil];
    AssertEqual(docIds.count, 1u);
    AssertEqual(self.db.count, 1u);
    AssertEqual(otherDB.count, 1u);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setString: @"pass" forKey: @"name"];
    Assert([self.db saveDocument: doc2 error: &error]);
    
    CBLMutableDocument* doc3 = [[CBLMutableDocument alloc] initWithID: @"doc3"];
    [doc3 setString: @"donotpass" forKey: @"name"];
    Assert([self.db saveDocument: doc3 error: &error]);
    
    [docIds removeAllObjects];
    [self runWithReplicator: repl errorCode: 0 errorDomain: nil];
    
    // Check documents passed to the filter:
    AssertEqual(docIds.count, 2u);
    Assert([docIds containsObject: @"doc3"]);
    Assert([docIds containsObject: @"doc2"]);
    
    // shouldn't delete the one with `docID != pass`
    AssertNotNil([otherDB documentWithID: @"doc1"]);
    AssertNotNil([otherDB documentWithID: @"doc2"]);
    AssertNil([otherDB documentWithID: @"doc3"]);
    AssertEqual(self.db.count, 3u);
    AssertEqual(otherDB.count, 2u);
}


- (void) testStopAndRestartPullReplicationWithFilter {
    // Create documents
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"pass" forKey: @"name"];
    Assert([otherDB saveDocument: doc1 error: &error]);
    
    NSMutableSet<NSString*>* docIds = [NSMutableSet set];
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    CBLReplicatorConfiguration* config = [self configWithTarget: target
                                                           type: kCBLReplicatorTypePull
                                                     continuous: YES];
    config.pullFilter = ^BOOL(CBLDocument* document, CBLDocumentFlags flags) {
        AssertNotNil(document.id);
        [docIds addObject: document.id];
        
        // allow all docs with `name = pass`
        return [[document stringForKey: @"name"] isEqualToString: @"pass"];
    };
    
    repl = [[CBLReplicator alloc] initWithConfig: config];
    [self runWithReplicator: repl errorCode: 0 errorDomain: nil];
    AssertEqual(docIds.count, 1u);
    AssertEqual(self.db.count, 1u);
    AssertEqual(otherDB.count, 1u);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setString: @"pass" forKey: @"name"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    CBLMutableDocument* doc3 = [[CBLMutableDocument alloc] initWithID: @"doc3"];
    [doc3 setString: @"donotpass" forKey: @"name"];
    Assert([otherDB saveDocument: doc3 error: &error]);
    
    [docIds removeAllObjects];
    [self runWithReplicator: repl errorCode: 0 errorDomain: nil];
    
    // Check documents passed to the filter:
    AssertEqual(docIds.count, 2u);
    Assert([docIds containsObject: @"doc3"]);
    Assert([docIds containsObject: @"doc2"]);
    
    // shouldn't delete the one with `docID != pass`
    AssertNotNil([self.db documentWithID: @"doc1"]);
    AssertNotNil([self.db documentWithID: @"doc2"]);
    AssertNil([self.db documentWithID: @"doc3"]);
    AssertEqual(otherDB.count, 3u);
    AssertEqual(self.db.count, 2u);
}

#endif // COUCHBASE_ENTERPRISE


#pragma mark - Sync Gateway Tests


- (void) testAuthenticationFailure_SG {
    id target = [self remoteEndpointWithName: @"seekrit" secure: NO];
    if (!target)
        return;
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO];
    [self run: config errorCode: CBLErrorHTTPAuthRequired errorDomain: CBLErrorDomain];
}


- (void) testAuthenticatedPull_SG {
    id target = [self remoteEndpointWithName: @"seekrit" secure: NO];
    if (!target)
        return;
    id auth = [[CBLBasicAuthenticator alloc] initWithUsername: @"pupshaw" password: @"frank"];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO authenticator: auth];
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
    Assert([self.db saveDocument: doc1 error: &error]);
    AssertEqual(self.db.count, 1u);
    
    [self eraseRemoteEndpoint: target];
    id config = [self configWithTarget: target type : kCBLReplicatorTypePush continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
}


- (void) dontTestMissingHost_SG {
    // Note: The replication doesn't fail with an error; because the unknown-host error is
    // considered transient, the replicator just stays offline and waits for a network change.
    // This causes the test to time out.
    timeout = 200;
    
    id target = [[CBLURLEndpoint alloc] initWithURL:[NSURL URLWithString:@"ws://foo.couchbase.com/db"]];
    if (!target)
        return;
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: YES];
    [self run: config errorCode: 0 errorDomain: nil];
}


- (void) testSelfSignedSSLFailure_SG {
    id target = [self remoteEndpointWithName: @"scratch" secure: YES];
    if (!target)
        return;
    _pinServerCert = NO;    // without this, SSL handshake will fail
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO];
    [self run: config errorCode: CBLErrorTLSCertUnknownRoot errorDomain: CBLErrorDomain];
}


- (void) testSelfSignedSSLPinned_SG {
    id target = [self remoteEndpointWithName: @"scratch" secure: YES];
    if (!target)
        return;
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
}


- (void) dontTestContinuousPushNeverending_SG {
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


- (void) testStopReplicatorAfterOffline_SG {
    id target = [[CBLURLEndpoint alloc] initWithURL: [NSURL URLWithString:@"ws://foo.couchbase.com/db"]];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: YES];
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: config];
    
    XCTestExpectation* x1 = [self expectationWithDescription: @"Offline"];
    XCTestExpectation* x2 = [self expectationWithDescription: @"Stopped"];
    id token = [r addChangeListener: ^(CBLReplicatorChange* change) {
        if (change.status.activity == kCBLReplicatorOffline) {
            [change.replicator stop];
            [x1 fulfill];
        }
        
        if (change.status.activity == kCBLReplicatorStopped) {
            [x2 fulfill];
        }
    }];
    
    [r start];
    [self waitForExpectations: @[x1, x2] timeout: 10.0];
    [repl removeChangeListenerWithToken: token];
    r = nil;
}


- (void) testPullConflictDeleteWins_SG {
    id target = [self remoteEndpointWithName: @"scratch" secure: NO];
    if (!target)
        return;
    
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID:@"doc1"];
    [doc1 setValue: @"Tiger" forKey: @"species"];
    Assert([self.db saveDocument: doc1 error: &error]);
    
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
    Assert([self.db deleteDocument: doc1 error: &error]);
    AssertNil([self.db documentWithID: doc1.id]);
    
    // Start pull replicator:
    Log(@"-------- Starting pull replication to pick up conflict --------");
    config = [self configWithTarget: target type :kCBLReplicatorTypePull continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    // Verify local doc should be nil:
    AssertNil([self.db documentWithID: doc1.id]);
}


- (void) testPushAndPullBigBodyDocument_SG {
    timeout = 200;
    
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
    Assert([self.db saveDocument: doc error: &error], @"Save Error: %@", error);
    
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
    timeout = 200;
    
    id target = [self remoteEndpointWithName: @"scratch" secure: NO];
    if (!target)
        return;
    
    NSError* error;
    NSString* propertyKey = @"expiredDocumentKey";
    NSString* value = @"some random text";
    CBLMutableDocument *doc = [[CBLMutableDocument alloc] init];
    [doc setString: value forKey: propertyKey];
    Assert([self.db saveDocument: doc error: &error], @"Save Error: %@", error);
    AssertEqual(self.db.count, 1u);
    
    // Setup document change notification
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    id token = [self.db addDocumentChangeListenerWithID: doc.id
                                               listener: ^(CBLDocumentChange *change)
    {
        AssertEqualObjects(change.documentID, doc.id);
        if ([change.database documentWithID: change.documentID] == nil) {
            [expectation fulfill];
        }
    }];
    
    // Set expiry
    NSDate* expiryDate = [NSDate dateWithTimeIntervalSinceNow: 1.0];
    NSError* err;
    Assert([self.db setDocumentExpirationWithID: doc.id expiration: expiryDate error: &err]);
    AssertNil(err);
    
    // Wait for the document get expired.
    [self waitForExpectationsWithTimeout: 5.0 handler: nil];
    [self.db removeChangeListenerWithToken: token];
    
    // Erase remote data:
    [self eraseRemoteEndpoint: target];
    
    // PUSH to SG:
    Log(@"-------- Starting push replication --------");
    id config = [self configWithTarget: target type :kCBLReplicatorTypePush continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    // Clean database:
    AssertEqual(self.db.count, 0u);
    
    // PULL from SG:
    Log(@"-------- Starting pull replication --------");
    config = [self configWithTarget: target type :kCBLReplicatorTypePull continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    // should not be replicated
    AssertEqual(self.db.count, 0u);
    CBLDocument* savedDoc = [self.db documentWithID: doc.id];
    AssertNil([savedDoc stringForKey: propertyKey]);
}

@end
