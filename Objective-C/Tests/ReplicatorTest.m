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

#ifdef COUCHBASE_ENTERPRISE
#import "CBLReplicatorConfiguration+ServerCert.h"
#endif

@implementation ReplicatorTest {
    BOOL _stopped;
}

@synthesize disableDefaultServerCertPinning=_disableDefaultServerCertPinning;
@synthesize crashWhenStoppedTimeoutOccurred=_crashWhenStoppedTimeoutOccurred;

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
    
    self.crashWhenStoppedTimeoutOccurred = YES;
    
    timeout = 15.0; // TODO: CBL-973
    
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

#pragma mark - Certificate

- (SecCertificateRef) defaultServerCert {
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
                       maxRetries: -1];
}

- (CBLReplicatorConfiguration*) configWithTarget: (id<CBLEndpoint>)target
                                            type: (CBLReplicatorType)type
                                      continuous: (BOOL)continuous
                                   authenticator: (nullable CBLAuthenticator*)authenticator
                                      serverCert: (nullable SecCertificateRef)serverCert
                                      maxRetries: (NSInteger)maxRetries /* for default, set -1 */ {
    CBLReplicatorConfiguration* c = [[CBLReplicatorConfiguration alloc] initWithDatabase: self.db
                                                                                  target: target];
    c.replicatorType = type;
    c.continuous = continuous;
    c.authenticator = authenticator;
    
    if (maxRetries >= 0)
        c.maxRetries = maxRetries;
    
    if ([$castIf(CBLURLEndpoint, target).url.scheme isEqualToString: @"wss"]) {
        if (serverCert)
            c.pinnedServerCertificate = serverCert;
        else if (!_disableDefaultServerCertPinning)
            c.pinnedServerCertificate = self.defaultServerCert;
    }
    
    if (continuous)
        c.checkpointInterval = 1.0; // For testing only
    
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
                    maxRetries: -1
                     errorCode: errorCode
                   errorDomain: errorDomain];
}

- (BOOL) runWithTarget: (id<CBLEndpoint>)target
                  type: (CBLReplicatorType)type
            continuous: (BOOL)continuous
         authenticator: (nullable CBLAuthenticator*)authenticator
            serverCert: (nullable SecCertificateRef)serverCert
            maxRetries: (NSInteger)maxRetries // set to -1 for default maxRetry
             errorCode: (NSInteger)errorCode
           errorDomain: (nullable NSString*)errorDomain {
    id config = [self configWithTarget: target
                                  type: type
                            continuous: continuous
                         authenticator: authenticator
                            serverCert: serverCert
                            maxRetries: maxRetries];
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
        XCTWaiterResult result = [XCTWaiter waitForExpectations: @[x] timeout: timeout];
        if (result != XCTWaiterResultCompleted) {
            if (result == XCTWaiterResultTimedOut) {
                if (self.crashWhenStoppedTimeoutOccurred) {
                    NSLog(@"!!! Exceeding stopped timeout, let's crash the test to get thread dump ...");
                    assert(false);
                }
                XCTFail(@"Unfulfilled expectations for %@ as exceeding timeout of %f seconds)", x.expectationDescription, timeout);
            } else {
                XCTFail(@"Unfulfilled expectations for %@ as result = %ld", x.expectationDescription, (long)result);
            }
        }
    }
    @finally {
        if (replicator.status.activity != kCBLReplicatorStopped)
            [replicator stop];
        [replicator removeChangeListenerWithToken: token];
    }
    
    // Workaround:
    // https://issues.couchbase.com/browse/CBL-1061
    [NSThread sleepForTimeInterval: 0.5];
    
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

@end
