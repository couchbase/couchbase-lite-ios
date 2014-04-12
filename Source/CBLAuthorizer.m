//
//  CBLAuthorizer.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/21/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLAuthorizer.h"
#import "CBLMisc.h"
#import "CBLBase64.h"
#import "MYURLUtils.h"


@implementation CBLBasicAuthorizer

- (instancetype) initWithCredential: (NSURLCredential*)credential {
    Assert(credential);
    self = [super init];
    if (self) {
        _credential = credential;
    }
    return self;
}


- (instancetype) initWithURL: (NSURL*)url {
    NSURLCredential *cred = [url my_credentialForRealm: nil
                                  authenticationMethod: NSURLAuthenticationMethodHTTPBasic];
    if (!cred)
        return nil;
    return [self initWithCredential: cred];
}


- (NSString*) authorizeURLRequest: (NSMutableURLRequest*)request
                         forRealm: (NSString*)realm
{
    NSString* username = _credential.user;
    NSString* password = _credential.password;
    if (username && password) {
        NSString* seekrit = $sprintf(@"%@:%@", username, password);
        seekrit = [CBLBase64 encode: [seekrit dataUsingEncoding: NSUTF8StringEncoding]];
        return [@"Basic " stringByAppendingString: seekrit];
    }
    return nil;
}

- (NSString*) authorizeHTTPMessage: (CFHTTPMessageRef)message
                            forRealm: (NSString*)realm
{
    NSString* username = _credential.user;
    NSString* password = _credential.password;
    if (username && password) {
        NSString* seekrit = $sprintf(@"%@:%@", username, password);
        seekrit = [CBLBase64 encode: [seekrit dataUsingEncoding: NSUTF8StringEncoding]];
        return [@"Basic " stringByAppendingString: seekrit];
    }
    return nil;
}

- (NSString*) description {
    return $sprintf(@"%@[%@/****]", self.class, _credential.user);
}

#if 0
// If enabled, these methods would make CouchbaseLite use cookie-based login intstead of basic auth;
// but there's not really much point in doing so, as such logins expire, which would cause trouble
// with long-lived replications.

- (NSString*) loginPathForSite: (NSURL*)site {
    return @"/_session";
}

- (NSDictionary*) loginParametersForSite: (NSURL*)site {
    NSString* username = _credential.user;
    NSString* password = _credential.password;
    if (username && password) {
        return @{@"name": username, @"password": password};
    }
    return nil;
}
#endif

@end


#if 0 // UNUSED
@implementation CBLMACAuthorizer

- (instancetype) initWithKey: (NSString*)key
                  identifier: (NSString*)identifier
                   algorithm: (NSString*)algorithm
                   issueTime: (NSDate*)issueTime
{
    self = [super init];
    if (self) {
        _key = [key copy];
        _identifier = [identifier copy];
        _issueTime = [issueTime copy];
        if ([algorithm isEqualToString: @"hmac-sha-1"])
            _hmacFunction = &CBLHMACSHA1;
        else if ([algorithm isEqualToString: @"hmac-sha-256"])
            _hmacFunction = &CBLHMACSHA256;
        else {
            return nil;
        }
    }
    return self;
}




- (NSString*) authorizeMethod: (NSString*)httpMethod
                          URL: (NSURL*)url
                         body: (NSData*)body
{
    // <http://tools.ietf.org/html/draft-ietf-oauth-v2-http-mac-00>
    return nil;
    NSString* nonce = $sprintf(@"%.0f:%@", -[_issueTime timeIntervalSinceNow], CBLCreateUUID());
    NSString* ext = @"";  // not implemented yet

    NSString* bodyHash = @"";
    if (body.length > 0) {
        NSData* digest = (_hmacFunction == &CBLHMACSHA1) ? CBLSHA1Digest(body) : CBLSHA256Digest(body);
        bodyHash = [CBLBase64 encode: digest];
    }

    NSString* normalized = $sprintf(@"%@\n%@%@\n%@\n%d\n%@\n%@\n",
                                    nonce,
                                    httpMethod,
                                    url.my_pathAndQuery,
                                    [url.host lowercaseString],
                                    url.my_effectivePort,
                                    bodyHash,
                                    ext);
    NSString* mac;
    mac = [CBLBase64 encode: _hmacFunction([_key dataUsingEncoding: NSUTF8StringEncoding],
                                          [normalized dataUsingEncoding: NSUTF8StringEncoding])];
    return $sprintf(@"MAC id=\"%@\", nonce=\"%@\", bodyhash=\"%@\", mac=\"%@\"",
                    _identifier, nonce, bodyHash, mac);
}


- (NSString*) authorizeURLRequest: (NSMutableURLRequest*)request
                         forRealm: (NSString*)realm
{
    if (!request)
        return nil;
    return [self authorizeMethod: request.HTTPMethod
                             URL: request.URL
                            body: request.HTTPBody];
}


- (NSString*) authorizeHTTPMessage: (CFHTTPMessageRef)message
                          forRealm: (NSString*)realm
{
    if (!message)
        return nil;
    NSString* method = CFBridgingRelease(CFHTTPMessageCopyRequestMethod(message));
    NSURL* url = CFBridgingRelease(CFHTTPMessageCopyRequestURL(message));
    NSData* body = CFBridgingRelease(CFHTTPMessageCopyBody(message));
    return [self authorizeMethod: method URL: url body: body];
}


@end
#endif
