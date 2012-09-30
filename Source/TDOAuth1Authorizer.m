//
//  TDOAuth1Authorizer.m
//  TouchDB
//
//  Created by Jens Alfke on 5/21/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TDOAuth1Authorizer.h"
#import "TDMisc.h"
#import "TDBase64.h"
#import "OAMutableURLRequest.h"
#import "OAConsumer.h"
#import "OAToken.h"
#import "OAPlaintextSignatureProvider.h"


@implementation TDOAuth1Authorizer


- (id) initWithConsumerKey: (NSString*)consumerKey
            consumerSecret: (NSString*)consumerSecret
                     token: (NSString*)token
               tokenSecret: (NSString*)tokenSecret
           signatureMethod: (NSString*)signatureMethod
{
    self = [super init];
    if (self) {
        if (!consumerKey || !consumerSecret || !token || !tokenSecret) {
            return nil;
        }
        _consumer = [[OAConsumer alloc] initWithKey: consumerKey secret: consumerSecret];
        _token = [[OAToken alloc] initWithKey: token secret: tokenSecret];
        if ([signatureMethod isEqualToString: @"HMAC-SHA1"] || signatureMethod == nil)
            _signatureProvider = [[OAHMAC_SHA1SignatureProvider alloc] init];
        else if ([signatureMethod isEqualToString: @"PLAINTEXT"])
            _signatureProvider = [[OAPlaintextSignatureProvider alloc] init];
        else {
            Warn(@"Unsupported signature method '%@'", signatureMethod);
            return nil;
        }
    }
    return self;
}




// TDAuthorizer API:
- (NSString*) authorizeURLRequest: (NSMutableURLRequest*)request
                         forRealm: (NSString*)realm
{
    OAMutableURLRequest* oarq = [[OAMutableURLRequest alloc] initWithURL: request.URL
                                                                consumer: _consumer
                                                                   token: _token
                                                                   realm: realm
                                                       signatureProvider: _signatureProvider];
    oarq.HTTPMethod = request.HTTPMethod;
    oarq.HTTPBody = request.HTTPBody;
    [oarq prepare];
    NSString* authorization = [oarq valueForHTTPHeaderField: @"Authorization"];
    return authorization;
}

- (NSString*) authorizeHTTPMessage: (CFHTTPMessageRef)message
                          forRealm: (NSString*)realm
{
    NSURL* url = CFBridgingRelease(CFHTTPMessageCopyRequestURL(message));
    OAMutableURLRequest* oarq = [[OAMutableURLRequest alloc] initWithURL: url
                                                                consumer: _consumer
                                                                   token: _token
                                                                   realm: realm
                                                       signatureProvider: _signatureProvider];
    oarq.HTTPMethod = CFBridgingRelease(CFHTTPMessageCopyRequestMethod(message));
    oarq.HTTPBody = CFBridgingRelease(CFHTTPMessageCopyBody(message));
    [oarq prepare];
    return [oarq valueForHTTPHeaderField: @"Authorization"];
}

@end


// Include our own implementation of this instead of the OAuth library's, because it drags in
// a bunch of other stuff including its own SHA1 and Base64 implementations.
@implementation OAHMAC_SHA1SignatureProvider

- (NSString *)name {
    return @"HMAC-SHA1";
}

- (NSString *)signClearText:(NSString *)text withSecret:(NSString *)secret {
    return [TDBase64 encode: TDHMACSHA1([secret dataUsingEncoding: NSUTF8StringEncoding], 
                                        [text dataUsingEncoding: NSUTF8StringEncoding])];
}

@end
