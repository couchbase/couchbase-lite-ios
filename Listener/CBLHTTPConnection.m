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
    NSDictionary *_sessionUserProps;
    int _sessionTimeStamp;
}

@synthesize sessionUserProps=_sessionUserProps, sessionTimeStamp=_sessionTimeStamp;

int const kcouch_httpd_auth_timeout = 600;

- (CBLListener*) listener {
    return ((CBLHTTPServer*)config.server).listener;
}

/*
 * This method assumes that the user has already been authenticated with isAuthenticated, otherwise 
 * the response should not proceed to this level
 */
- (NSString *)authUsername
{
    NSString *username;
    
    // Extract the authentication information from the Authorization header
    HTTPAuthenticationRequest *auth = [[HTTPAuthenticationRequest alloc] initWithRequest:request];
    
    if ([self useDigestAccessAuthentication])
    {
        username = [auth username];
    }
    else
    {
        // Decode the base 64 encoded credentials
        NSString *base64Credentials = [auth base64Credentials];
        
        NSData *decodedCredentials = [[base64Credentials dataUsingEncoding:NSUTF8StringEncoding] base64Decoded];
        
        NSString *credentials = [[NSString alloc] initWithData:decodedCredentials encoding:NSUTF8StringEncoding];
        
        // The credentials should be of the form "username:password"
        // The username is not allowed to contain a colon
        
        NSRange colonRange = [credentials rangeOfString:@":"];
        
        username = [credentials substringToIndex:colonRange.location];
    }
    
    // If the username is _ then this should logout
    
    if ([@"_" isEqualToString:username])
    {
        username = nil;
    }
    
    return username;
}

-(void) clearSession
{
    _sessionUserProps = nil;
    _sessionTimeStamp = nil;
}

-(NSDictionary *) authenticate:(NSString *)name password:(NSString *)password {
    
    NSDictionary *userProps = [self.listener getUserCreds:name];
    if (!userProps) {
        return nil;
    }
    
    // TODO, figure out how to authenticate this name/password combination
    // probably checking salt + password_sha

    _sessionTimeStamp = [self makeCookieTime];
    _sessionUserProps = userProps;
    
    return _sessionUserProps;
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

-(void)writeAuthSession
{
    NSLog(@"writing auth session %@", request.url);
}
    
-(void)readAuthSession
{
    NSLog(@"reading auth session %@", request.url);
    
    NSString *authSessionCookie = [self getCookieValue:@"AuthSession"];
    if (!authSessionCookie || [authSessionCookie isEqualToString:@""])
    {
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
    
    if ([authSessionParts count] != 3)
    {
        LogTo(CBLListener, @"Malformed AuthSession cookie. Please clear your cookies.");
        
        [self handleInvalidRequest:nil];
        return;
    }

    NSString *userPart = [[NSString alloc] initWithData:authSessionParts[0] encoding:NSUTF8StringEncoding];
    NSString *timePart = [[NSString alloc] initWithData:authSessionParts[1] encoding:NSUTF8StringEncoding];
    NSData *hashPart = authSessionParts[2];
    
    // Verify expiry and hash
    
    int currentTime = [self makeCookieTime];
    int timeStamp = strtol([timePart cStringUsingEncoding:NSUTF8StringEncoding], NULL, 10);
    if (timeStamp + kcouch_httpd_auth_timeout < currentTime) {
        return;
    }

    // Check the timeout, if not timed out, continue
    
    // Get the user props
    NSDictionary *userProps = [self.listener getUserCreds:userPart];
    if (!userProps) {
        return;
    }
    
    NSData *expectedHash = [self sessionHashFor:userPart salt:userProps[@"salt"] timeStamp:timeStamp];
    if (!expectedHash)
    {
        [self handleInvalidRequest:nil];
        return;
    }
    
    if (CBLSafeCompare(expectedHash, hashPart)) {
        _sessionUserProps = userProps;
        _sessionTimeStamp = currentTime;
        
        NSLog(@"Successful session authentication for %@", userPart);
    }
    
    return;
}

-(NSData *)sessionHashFor:(NSString *)name salt:(NSString *)salt timeStamp:(int)timeStamp
{
    if (!salt) salt = @"";

    NSString *secret = self.listener.authSecret;
    if (!secret)
    {
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
-(NSString *)getCookieValue:(NSString *)name
{
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
        
        if ([name isEqualToString:cookieName])
        {
            return cookieValue;
        } else {
            return nil;
        }
    }
    return nil;
}
    
-(int)makeCookieTime
{
   return floor([[NSDate date]  timeIntervalSince1970]);
}
    


@end
