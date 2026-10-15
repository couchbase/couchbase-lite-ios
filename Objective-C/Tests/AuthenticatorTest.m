//
//  AuthenticatorTest.m
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

#import <XCTest/XCTest.h>
#import "CBLTestCase.h"
#ifndef CBL_BINARY_TEST
#import "CBLAuthenticator+Internal.h"
#import "CBLHTTPLogic.h"
#import "CBLTestCustomLogSink.h"
#endif

@interface AuthenticatorTest : CBLTestCase

@end

@implementation AuthenticatorTest

- (void) testBasicAuthenticatorInstance {
    NSString* username = @"someUsername";
    NSString* password = @"somePassword";
    
    CBLBasicAuthenticator* auth = [[CBLBasicAuthenticator alloc] initWithUsername: username
                                                                         password: password];
    AssertEqualObjects([auth username], username);
    AssertEqualObjects([auth password], password);
}

- (void) testSessionAuthenticatorWithSessionID {
    NSString* sessionID = @"someSessionID";
    
    CBLSessionAuthenticator* auth = [[CBLSessionAuthenticator alloc] initWithSessionID: sessionID];
    AssertEqualObjects([auth sessionID], sessionID);
    AssertEqualObjects([auth cookieName], @"SyncGatewaySession");
}

- (void) testSessionAuthenticatorWithSessionIDAndCookie {
    NSString* sessionID = @"someSessionID";
    NSString* cookie = @"someCookie";
    
    CBLSessionAuthenticator* auth = [[CBLSessionAuthenticator alloc] initWithSessionID: sessionID
                                                                            cookieName: cookie];
    AssertEqualObjects([auth sessionID], sessionID);
    AssertEqualObjects([auth cookieName], cookie);
}

- (void) testSessionAuthenticatorEmptyCookie {
    NSString* sessionID = @"someSessionID";
    
    CBLSessionAuthenticator* auth = [[CBLSessionAuthenticator alloc] initWithSessionID: sessionID
                                                                            cookieName: nil];
    AssertEqualObjects([auth sessionID], sessionID);
    AssertEqualObjects([auth cookieName], @"SyncGatewaySession");
}

// CBL-9042: Rejecting a URL with embedded credentials must not print the credentials,
// even when the URL also has an invalid scheme.
- (void) testURLEndpointWithEmbeddedCredentials {
    for (NSString* str in @[@"wss://someUsername:somePassword@localhost:4984/db",
                            @"https://someUsername:somePassword@localhost:4984/db"]) {
        NSString* reason = nil;
        @try {
            (void) [[CBLURLEndpoint alloc] initWithURL: [NSURL URLWithString: str]];
        } @catch (NSException* e) {
            reason = e.reason;
        }
        Assert([reason containsString: @"Embedded credentials"], @"Unexpected reason: %@", reason);
        AssertFalse([reason containsString: @"someUsername"]);
        AssertFalse([reason containsString: @"somePassword"]);
    }

    // A URL without credentials still fails the scheme check:
    NSString* reason = nil;
    @try {
        (void) [[CBLURLEndpoint alloc] initWithURL: [NSURL URLWithString: @"https://localhost:4984/db"]];
    } @catch (NSException* e) {
        reason = e.reason;
    }
    Assert([reason containsString: @"Invalid scheme"], @"Unexpected reason: %@", reason);
}

#pragma mark - Internal

// White-box tests that verify internal state; excluded from the binary tests.
#ifndef CBL_BINARY_TEST

- (void) testBasicAuthenticatorAuthenticate {
    NSString* username = @"someUsername";
    NSString* password = @"somePassword";
    
    CBLBasicAuthenticator* auth = [[CBLBasicAuthenticator alloc] initWithUsername: username
                                                                         password: password];
    
    NSMutableDictionary* options = [NSMutableDictionary dictionary];
    AssertEqualObjects(options, @{});
    
    [auth authenticate: options];
    AssertEqualObjects(options[@"auth"][@"type"], @"Basic");
    AssertEqualObjects(options[@"auth"][@"username"], username);
    AssertEqualObjects(options[@"auth"][@"password"], password);
}

- (void) testAuthenticateSession {
    NSString* sessionID = @"someSessionID";
    NSString* cookie = @"someCookie";
    
    CBLSessionAuthenticator* auth = [[CBLSessionAuthenticator alloc] initWithSessionID: sessionID
                                                                            cookieName: cookie];
    
    NSMutableDictionary* options = [NSMutableDictionary dictionary];
    AssertNil(options[@"cookies"]);
    
    [auth authenticate: options];
    AssertNotNil(options[@"cookies"]);
    NSString* cookies = [NSString stringWithFormat: @"%@=%@", cookie, sessionID];
    AssertEqualObjects(options[@"cookies"], cookies);
}

// CBL-9042: A 401 response must not log the Authorization header or keep it in the error.
- (void) testHTTPAuthFailureDoesNotLeakCredentials {
    CBLTestCustomLogSink* logSink = [[CBLTestCustomLogSink alloc] init];
    CBLLogSinks.custom = [[CBLCustomLogSink alloc] initWithLevel: kCBLLogLevelInfo logSink: logSink];

    NSURL* url = [NSURL URLWithString: @"https://localhost:4984/db/_blipsync"];
    CBLHTTPLogic* logic = [[CBLHTTPLogic alloc] initWithURLRequest: [NSURLRequest requestWithURL: url]];
    logic.proxySettings = nil;
    logic.credential = [NSURLCredential credentialWithUser: @"someUsername"
                                                  password: @"somePassword"
                                               persistence: NSURLCredentialPersistenceNone];

    // Make sure the request was sent with the Basic credential:
    NSString* encoded = [[@"someUsername:somePassword" dataUsingEncoding: NSUTF8StringEncoding]
                         base64EncodedStringWithOptions: 0];
    NSString* request = [[NSString alloc] initWithData: logic.HTTPRequestData
                                              encoding: NSUTF8StringEncoding];
    Assert([request containsString: encoded]);

    CFHTTPMessageRef response = CFHTTPMessageCreateResponse(NULL, 401, CFSTR("Unauthorized"),
                                                            kCFHTTPVersion1_1);
    CFHTTPMessageSetHeaderFieldValue(response, CFSTR("WWW-Authenticate"),
                                     CFSTR("Basic realm=\"Couchbase Sync Gateway\""));
    [logic receivedResponse: response];
    CFRelease(response);

    AssertEqual(logic.httpStatus, 401);
    AssertNotNil(logic.error);
    AssertNil(logic.error.userInfo[@"HTTPAuthorization"]);
    AssertNotNil(logic.error.userInfo[@"HTTPAuthenticateHeader"]);

    Assert([logSink containsString: @"HTTP auth failed"]);
    AssertFalse([logSink containsString: encoded]);
    AssertFalse([logSink containsString: @"someUsername"]);
    AssertFalse([logSink containsString: @"somePassword"]);

    CBLLogSinks.custom = nil;
}

// CBL-9042: A 407 proxy challenge must not log the proxy credential.
- (void) testHTTPProxyAuthChallengeDoesNotLeakCredentials {
    CBLTestCustomLogSink* logSink = [[CBLTestCustomLogSink alloc] init];
    CBLLogSinks.custom = [[CBLCustomLogSink alloc] initWithLevel: kCBLLogLevelInfo logSink: logSink];

    // The proxy credential is looked up from the user and password in the URL:
    NSURL* url = [NSURL URLWithString: @"http://proxyUsername:proxyPassword@localhost:4984/db"];
    CBLHTTPLogic* logic = [[CBLHTTPLogic alloc] initWithURLRequest: [NSURLRequest requestWithURL: url]];
    logic.proxySettings = @{(id)kCFProxyTypeKey: (id)kCFProxyTypeHTTP,
                            (id)kCFProxyHostNameKey: @"localhost",
                            (id)kCFProxyPortNumberKey: @(8080)};

    CFHTTPMessageRef response = CFHTTPMessageCreateResponse(NULL, 407,
                                                            CFSTR("Proxy Authentication Required"),
                                                            kCFHTTPVersion1_1);
    CFHTTPMessageSetHeaderFieldValue(response, CFSTR("Proxy-Authenticate"),
                                     CFSTR("Basic realm=\"proxy\""));
    [logic receivedResponse: response];
    CFRelease(response);

    AssertEqual(logic.httpStatus, 407);
    Assert(logic.shouldRetry);

    Assert([logSink containsString: @"Proxy auth challenge"]);
    AssertFalse([logSink containsString: @"proxyUsername"]);
    AssertFalse([logSink containsString: @"proxyPassword"]);

    CBLLogSinks.custom = nil;
}

#endif

@end
