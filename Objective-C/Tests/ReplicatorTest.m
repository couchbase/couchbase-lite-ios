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

#import "ReplicatorTest.h"
#import "CBLJSON.h"
#import "CBLHTTPLogic.h"
#import "CollectionUtils.h"
#import "CBLURLEndpoint+Internal.h"
#import "CBLReplicator+Internal.h"

@implementation ReplicatorTest {
    BOOL _stopped;
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
    [super setUp];
    
    timeout = 5.0;
    pinServerCert = YES;
    
    [self openOtherDB];
}

- (void) tearDown {
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

#pragma mark - Endpoint

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

#pragma mark - Certifciate

- (SecCertificateRef) secureServerCert {
    NSData* certData = [self dataFromResource: @"SelfSigned" ofType: @"cer"];
    SecCertificateRef cert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certData);
    Assert(cert);
    return (SecCertificateRef)CFAutorelease(cert);
}

- (NSString*) getCertificateID: (SecCertificateRef)cert {
    CFErrorRef* errRef = NULL;
    if (@available(macOS 10.13, iOS 11.0, *)) {
        NSData* data = (NSData*)CFBridgingRelease(SecCertificateCopySerialNumberData(cert, errRef));
        Assert(errRef == NULL);
        return [NSString stringWithFormat: @"%lu", (unsigned long)[data hash]];
    } else {
        return (NSString*) CFBridgingRelease(SecCertificateCopySubjectSummary(cert));
    }
}

#pragma mark - Configs

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
    
    if ([$castIf(CBLURLEndpoint, target).url.scheme isEqualToString: @"wss"] && pinServerCert)
        c.pinnedServerCertificate = self.secureServerCert;
    
    if (continuous)
        c.checkpointInterval = 1.0; // For testing only
    
    return c;
}

#pragma mark - Run Replicator

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
        if (replicator.status.activity != kCBLReplicatorStopped)
            [replicator stop];
        [replicator removeChangeListenerWithToken: token];
    }
    return fulfilled;
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

#pragma mark - P2P Helpers

- (CBLReplicatorConfiguration *)createFailureP2PConfigurationWithProtocol: (CBLProtocolType)protocolType
                                                               atLocation: (CBLMockConnectionLifecycleLocation)location
                                                       withRecoverability: (BOOL)isRecoverable {
    NSInteger recoveryCount = isRecoverable ? 1 : 0;
    CBLTestErrorLogic* errorLogic = [[CBLTestErrorLogic alloc] initAtLocation:location withRecoveryCount:recoveryCount];
    CBLMessageEndpointListenerConfiguration* config = [[CBLMessageEndpointListenerConfiguration alloc] initWithDatabase:self.otherDB protocolType:protocolType];
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
    CBLMessageEndpointListenerConfiguration* config = [[CBLMessageEndpointListenerConfiguration alloc] initWithDatabase:self.otherDB protocolType:kCBLProtocolTypeByteStream];
    CBLMessageEndpointListener* listener = [[CBLMessageEndpointListener alloc] initWithConfig:config];
    CBLMockServerConnection* server = [[CBLMockServerConnection alloc] initWithListener:listener andProtocol:kCBLProtocolTypeByteStream];
    MockConnectionFactory* delegate = [[MockConnectionFactory alloc] initWithErrorLogic: nil];
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

@end

#ifdef COUCHBASE_ENTERPRISE

#pragma mark - Helper Class Implementation

@implementation MockConnectionFactory
{
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
    CBLMockClientConnection* retVal = [[CBLMockClientConnection alloc] initWithEndpoint:endpoint];
    retVal.errorLogic = _errorLogic;
    return retVal;
}

@end

#endif
