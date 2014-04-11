//
//  CBLAuthenticator.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 4/11/14.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.


#import "CBLAuthenticator.h"
#import "CBLAuthorizer.h"
#import "CBLTokenAuthorizer.h"
#import "CBLOAuth1Authorizer.h"


@implementation CBLAuthenticator


+ (id<CBLAuthenticator>) basicAuthenticatorWithName: (NSString*)name
                                           password: (NSString*)password
{
    NSURLCredential *cred = [NSURLCredential credentialWithUser: name
                                                       password: password
                                                    persistence: NSURLCredentialPersistenceNone];
    return [[CBLBasicAuthorizer alloc] initWithCredential: cred];
}

+ (id<CBLAuthenticator>) facebookAuthenticatorWithToken: (NSString*)token {
    return [[CBLTokenAuthorizer alloc] initWithLoginPath: @"_facebook"
                                          postParameters: @{@"access_token": token}];
}

+ (id<CBLAuthenticator>) personaAuthenticatorWithAssertion: (NSString*)assertion {
    return [[CBLTokenAuthorizer alloc] initWithLoginPath: @"_persona"
                                          postParameters: @{@"assertion": assertion}];
}

+ (id<CBLAuthenticator>) OAuth1AuthenticatorWithConsumerKey: (NSString*)consumerKey
                                             consumerSecret: (NSString*)consumerSecret
                                                      token: (NSString*)token
                                                tokenSecret: (NSString*)tokenSecret
                                            signatureMethod: (NSString*)signatureMethod
{
    return [[CBLOAuth1Authorizer alloc] initWithConsumerKey: consumerKey
                                             consumerSecret: consumerSecret
                                                      token: token
                                                tokenSecret: tokenSecret
                                            signatureMethod: signatureMethod];
}


@end
