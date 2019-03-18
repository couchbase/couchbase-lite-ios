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
#import "CBLBasicAuthenticator.h"
#import "CBLTestCase.h"

@interface AuthenticatorTest : CBLTestCase

@end

@implementation AuthenticatorTest

- (void)testBasicAuthenticatorInstance {
    NSString* username = @"someUsername";
    NSString* password = @"somePassword";
    
    CBLBasicAuthenticator* auth = [[CBLBasicAuthenticator alloc] initWithUsername: username
                                                                         password: password];
    AssertEqualObjects([auth username], username);
    AssertEqualObjects([auth password], password);
}

- (void)testSessionAuthenticatorWithSessionID {
    NSString* sessionID = @"someSessionID";
    
    CBLSessionAuthenticator* auth = [[CBLSessionAuthenticator alloc] initWithSessionID: sessionID];
    AssertEqualObjects([auth sessionID], sessionID);
    AssertEqualObjects([auth cookieName], @"SyncGatewaySession");
}

- (void)testSessionAuthenticatorWithSessionIDAndCookie {
    NSString* sessionID = @"someSessionID";
    NSString* cookie = @"someCookie";
    
    CBLSessionAuthenticator* auth = [[CBLSessionAuthenticator alloc] initWithSessionID: sessionID
                                                                            cookieName: cookie];
    AssertEqualObjects([auth sessionID], sessionID);
    AssertEqualObjects([auth cookieName], cookie);
}

- (void)testSessionAuthenticatorEmptyCookie {
    NSString* sessionID = @"someSessionID";
    
    CBLSessionAuthenticator* auth = [[CBLSessionAuthenticator alloc] initWithSessionID: sessionID
                                                                            cookieName: nil];
    AssertEqualObjects([auth sessionID], sessionID);
    AssertEqualObjects([auth cookieName], @"SyncGatewaySession");
}

@end

