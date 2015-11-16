//
//  CBLHTTPConnection.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/29/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
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
#import "CBLHTTPResponse.h"
#import "CBLListener+Internal.h"
#import "CBL_Server.h"
#import "CBL_Router.h"

#import "HTTPMessage.h"
#import "HTTPDataResponse.h"
#import "GCDAsyncSocket.h"

#import "MYErrorUtils.h"
#import "Test.h"


@implementation CBLHTTPConnection
{
    BOOL _hasClientCert;
}

@synthesize username=_username;


- (CBLListener*) listener {
    return ((CBLHTTPServer*)config.server).listener;
}


- (SSLAuthenticate)sslClientSideAuthentication {
    return kTryAuthenticate;
}

static void evaluate(SecTrustRef trust, SecTrustCallback callback) {
    if (trust)
        SecTrustEvaluateAsync(trust, dispatch_get_main_queue(), callback);
    else
        callback(trust, kSecTrustResultInvalid);
}

- (void)socket:(GCDAsyncSocket *)sock
        didReceiveTrust:(SecTrustRef)trust
        completionHandler:(void (^)(BOOL shouldTrustPeer))completionHandler
{
    // This only gets called if the SSL settings disable regular cert validation.
    evaluate(trust, ^(SecTrustRef trustRef, SecTrustResultType result)
    {
        LogTo(CBLListener, @"Login attempted with%@ client cert; trust result = %d",
              (trust ? @"" : @"out"), result);
        id<CBLListenerDelegate> delegate = self.listener.delegate;
        BOOL ok;
        if (result == kSecTrustResultDeny || result == kSecTrustResultFatalTrustFailure
                                          || result == kSecTrustResultOtherError) {
            ok = NO;
        } else if ([delegate respondsToSelector: @selector(authenticateConnectionFromAddress:withTrust:)]) {
            _username = [delegate authenticateConnectionFromAddress: sock.connectedAddress
                                                          withTrust: trust];
            ok = (_username != nil);
        } else {
            ok = (result == kSecTrustResultProceed || result == kSecTrustResultUnspecified
                                                   || result == kSecTrustResultInvalid);
            // kSecTrustResultInvalid means there's no TrustRef, i.e. no client cert. OK by default.
        }
        _hasClientCert = ok;
        completionHandler(ok);
    });
}

- (BOOL)isPasswordProtected:(NSString *)path {
    return !_hasClientCert && self.listener.requiresAuth;
}

- (NSString*) realm {
    return self.listener.realm;
}

- (BOOL)useDigestAccessAuthentication {
    // CBL/.NET doesn't support digest auth on the client side, so turn it off, as long as the
    // connection is SSL (Basic auth is too insecure to use over an unencrypted connection.) #784
    return !self.isSecureServer;
}

- (NSString*) passwordForUser: (NSString*)username {
    LogTo(CBLListener, @"Login attempted for user '%@'", username);
    _username = username;
    return [self.listener passwordForUser: username];
}

- (BOOL)isSecureServer {
    return self.listener.SSLIdentity != nil;
}

- (NSArray *)sslIdentityAndCertificates {
    return self.listener.SSLIdentityAndCertificates;
}


- (void) socketDidDisconnect: (GCDAsyncSocket*)socket withError: (NSError*)error {
    if (error && ![error my_hasDomain: GCDAsyncSocketErrorDomain
                                 code: GCDAsyncSocketClosedError]
              && ![error my_hasDomain: GCDAsyncSocketErrorDomain
                                 code: GCDAsyncSocketReadTimeoutError]) {
        Warn(@"CBLHTTPConnection: Client disconnected: %@", error);
    }
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
    CBL_Router* router = [[CBL_Router alloc] initWithServer: ((CBLHTTPServer*)config.server).cblServer
                                                request: urlRequest
                                                isLocal: NO];
    router.processRanges = NO;  // The HTTP server framework does this already
    if (_username) {
        NSString* str = [@"user:" stringByAppendingString: [_username stringByAddingPercentEscapesUsingEncoding: NSUTF8StringEncoding]];
        router.source = [NSURL URLWithString: str];
    }
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


@end




@implementation CBLHTTPServer

@synthesize listener=_listener, cblServer=_cblServer;

@end
