//
//  CBLHTTPConnection.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/29/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.
//
//  Based on CocoaHTTPServer/Samples/PostHTTPServer/MyHTTPConnection.m

#import "CBLHTTPConnection.h"
#import "CBLHTTPServer.h"
#import "CBLHTTPResponse.h"
#import "CBLListener.h"
#import "CBL_Server.h"
#import "CBL_Router.h"

#import "CBLBase64.h"
#import "CBLMisc.h"

#import "HTTPAuthenticationRequest.h"
#import "HTTPMessage.h"
#import "HTTPDataResponse.h"
#import "DDData.h"


#import "Test.h"


@implementation CBLHTTPConnection
{
    NSDictionary *_authSession;
}

@synthesize authSession=_authSession;

int const kcouch_httpd_auth_timeout = 600;

- (CBLListener*) listener {
    return ((CBLHTTPServer*)config.server).listener;
}

- (BOOL)isPasswordProtected:(NSString *)path {
    return self.listener.requiresAuth;
}

- (NSString*) realm {
    return self.listener.realm;
}

- (NSString*) passwordForUser: (NSString*)username {
    LogTo(CBLListener, @"Login attempted for user '%@'", username);
    return [self.listener passwordForUser: username];
}

- (BOOL)isSecureServer {
    return self.listener.SSLIdentity != nil;
}

- (NSArray *)sslIdentityAndCertificates {
    NSMutableArray* result = [NSMutableArray arrayWithObject: (__bridge id)self.listener.SSLIdentity];
    NSArray* certs = self.listener.SSLExtraCertificates;
    if (certs.count)
        [result addObjectsFromArray: certs];
    return result;
}


- (BOOL)supportsMethod:(NSString *)method atPath:(NSString *)path {
    return $equal(method, @"POST") || $equal(method, @"PUT") || $equal(method,  @"DELETE")
        || [super supportsMethod: method atPath: path];
}


- (NSObject<HTTPResponse>*)httpResponseForMethod:(NSString *)method URI:(NSString *)path {
    if (requestContentLength > 0)
        LogTo(CBLListener, @"%@ %@ {+%u}", method, path, (unsigned)requestContentLength);
    else
        LogTo(CBLListener, @"%@ %@", method, path);
    
    // Construct an NSURLRequest from the HTTPRequest:
    NSMutableURLRequest* urlRequest = [NSMutableURLRequest requestWithURL: request.url];
    urlRequest.HTTPMethod = method;
    urlRequest.HTTPBody = request.body;
    NSDictionary* headers = request.allHeaderFields;
    for (NSString* header in headers)
        [urlRequest setValue: headers[header] forHTTPHeaderField: header];
    
    // Create a CBL_Router:
    CBL_Router* router = [[CBL_Router alloc] initWithServer: ((CBLHTTPServer*)config.server).tdServer
                                                 connection: self
                                                    request: urlRequest
                                                    isLocal: NO];
    router.processRanges = NO;  // The HTTP server framework does this already
    CBLHTTPResponse* response = [[CBLHTTPResponse alloc] initWithRouter: router
                                                         forConnection: self];
    
    return response;
}


- (BOOL)expectsRequestBodyFromMethod:(NSString *)method atPath:(NSString *)path {
    if ($equal(method, @"PUT")) {
        // Allow PUT to /newdbname without a request body.
        return ! $equal([path stringByDeletingLastPathComponent], @"/");
    }
    return $equal(method, @"POST") || [super expectsRequestBodyFromMethod:method atPath:path];
}

- (void)prepareForBodyWithSize:(UInt64)contentLength {
	// Could use this method to open a temp file for large uploads
}

- (void)processBodyData:(NSData *)postDataChunk {
	// Remember: In order to support LARGE POST uploads, the data is read in chunks.
	// This prevents a 50 MB upload from being stored in RAM.
	// The size of the chunks are limited by the POST_CHUNKSIZE definition.
	// Therefore, this method may be called multiple times for the same POST request.
	
	if (![request appendData:postDataChunk])
		Warn(@"CBLHTTPConnection: couldn't append data chunk");
}

-(void)processAuthSession {
    NSString *authSessionCookie = [self getCookieValue:@"AuthSession"];
    if (!authSessionCookie || [authSessionCookie isEqualToString:@""]) {
        return;
    }
    
    NSData *decodedAuthSession = [CBLBase64 decode:authSessionCookie];
    NSMutableArray *authSessionParts = [[NSMutableArray alloc] init];
    const char * decodedBytes = (const char *)decodedAuthSession.bytes;

    int start = 0;
    for (int i = 0; i < decodedAuthSession.length; i++) {
        if (decodedBytes[i] == ':') {
            NSData * part = [decodedAuthSession subdataWithRange:NSMakeRange(start, i - start)];
            [authSessionParts addObject:part];
            start = i + 1;
        }
    }
    // Grab the final part
    NSData * part = [decodedAuthSession subdataWithRange:NSMakeRange(start, decodedAuthSession.length - start)];
    [authSessionParts addObject:part];
    
    if ([authSessionParts count] != 3) {
        LogTo(CBLListener, @"Malformed AuthSession cookie. Please clear your cookies.");
        
        [self handleInvalidRequest:nil];
        return;
    }

    NSString *userPart = [[NSString alloc] initWithData:authSessionParts[0] encoding:NSUTF8StringEncoding];
    NSString *timePart = [[NSString alloc] initWithData:authSessionParts[1] encoding:NSUTF8StringEncoding];
    NSData *hashPart = authSessionParts[2];
    
    // Verify expiry and hash
    int currentTime = [self makeCookieTime];
    int timeStamp = [timePart intValue];

    // Check the timeout, if not timed out, continue
    if (timeStamp + kcouch_httpd_auth_timeout < currentTime) {
        return;
    }
    
    // Get the user props
    NSDictionary *userProps = [self.listener getUserCreds:userPart];
    if (!userProps) {
        return;
    }
    
    NSData *expectedHash = [self getSessionHash:userPart salt:userProps[@"salt"] timeStamp:timeStamp];
    if (!expectedHash) {
        [self handleInvalidRequest:nil];
        return;
    }
    
    if (CBLSafeCompare(expectedHash, hashPart)) {
        _authSession = userProps;
        
        LogTo(CBLListener, @"Successful session authentication for %@", userPart);
    }
}

-(void) writeAuthSession:(CBLResponse *)response {
    if (_authSession) {
        int timeStamp = [self makeCookieTime];
        
        NSData *sessionHash = [self getSessionHash:_authSession[@"name"]
                                              salt:_authSession[@"salt"]
                                         timeStamp:timeStamp];
        NSString *authSessionHeader = [NSString stringWithFormat:@"%@:%i:",
                                       _authSession[@"name"],
                                       timeStamp];
        NSMutableData *authSessionData = [[NSMutableData alloc] init];
        [authSessionData appendData:[authSessionHeader dataUsingEncoding:NSUTF8StringEncoding]];
        [authSessionData appendData:sessionHash];
        NSString *encodedAuthSession = [CBLBase64 encode:authSessionData];
        
        // TODO: handle cookie scheme (set secure based on SSL)
        NSString *cookie = [NSString stringWithFormat:@"AuthSession=%@; Max-Age=%i; Path=/; Version=1",
                            encodedAuthSession,
                            kcouch_httpd_auth_timeout];
     
        response.headers[@"Set-Cookie"] = cookie;
    }
}

-(void) clearAuthSession {
    _authSession = nil;
}

-(NSData *)getSessionHash:(NSString *)name salt:(NSString *)salt timeStamp:(int)timeStamp {
    // In some cases the salt is nil, here we default empty
    if (!salt) salt = @"";

    NSString *secret = self.listener.authSecret;
    if (!secret) {
        LogTo(CBLListener, @"You have not set the CBLListener authSecret.");
        return nil;
    }
    NSMutableData *fullSecret = [[NSMutableData alloc] init];
    [fullSecret appendData:[secret dataUsingEncoding:NSUTF8StringEncoding]];
    [fullSecret appendData:[salt dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSString *userTimeValue = [NSString stringWithFormat:@"%@+%i", name, timeStamp];
    return CBLHMACSHA1(fullSecret, [userTimeValue dataUsingEncoding:NSUTF8StringEncoding]);
}
    
// Rudimentary cookie parsing, not according to spec
-(NSString *)getCookieValue:(NSString *)name {
    NSDictionary *fields = [request allHeaderFields];
    NSString *cookieHeader = [fields valueForKey:@"Cookie"];
    NSArray *cookies = [cookieHeader componentsSeparatedByString:@";"];
    for (NSString* cookie in cookies) {
        NSScanner *scanner = [NSScanner scannerWithString:cookie];
        NSString *cookieName;
        [scanner scanUpToString:@"=" intoString:&cookieName];
        NSString *cookieValue = [cookie substringFromIndex:scanner.scanLocation + 1];
        if (!cookieValue || cookieValue.length == 0) continue;
        cookieName = [cookieName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        cookieValue = [cookieValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        
        if ([name isEqualToString:cookieName]) {
            return cookieValue;
        } else {
            return nil;
        }
    }
    return nil;
}

-(int)makeCookieTime {
   return floor([[NSDate date]  timeIntervalSince1970]);
}

-(NSDictionary *)authenticate:(NSString *)name password:(NSString *)password {
    // Clear by default
    _authSession = nil;
    
    NSDictionary *userProps = [self.listener getUserCreds:name];
    if (!userProps) {
        return nil;
    }
    
    // Check if this user has a plain password (might be an admin)
    NSString *plainPassword = userProps[@"password"];
    
    if (plainPassword) {
        if (![plainPassword isEqualToString:password]) {
          return nil;
        }
    } else {
        NSString *passwordScheme = userProps[@"password_scheme"];
        if (passwordScheme && [passwordScheme isEqualToString:@"pbkdf2"]) {
            LogTo(CBLListener, @"pbkdf2 passwords are not yet supported.");
            return nil;
        }

        // Assuming simple password_scheme
        NSString *passwordSha = userProps[@"password_sha"];
        NSString *salt = userProps[@"salt"];
        if (!passwordSha || !salt) {
            return nil;
        }
        
        NSMutableData *saltedPassword = [[NSMutableData alloc] init];
        [saltedPassword appendData:[password dataUsingEncoding:NSUTF8StringEncoding]];
        [saltedPassword appendData:[salt dataUsingEncoding:NSUTF8StringEncoding]];
        
        NSString *hex = CBLHexSHA1Digest(saltedPassword);
        if (![hex isEqualToString:passwordSha]) {
            return nil;
        }
    }
    
    _authSession = userProps;
    
    return _authSession;
}

@end
