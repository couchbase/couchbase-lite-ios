//
//  TDHTTPConnection.m
//  TouchDB
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

#import "TDHTTPConnection.h"
#import "TDHTTPServer.h"
#import "TDHTTPResponse.h"
#import "TDListener.h"
#import "TDServer.h"
#import "TDRouter.h"

#import "HTTPMessage.h"
#import "HTTPDataResponse.h"

#import "Test.h"


@implementation TDHTTPConnection


- (TDListener*) listener {
    return ((TDHTTPServer*)config.server).listener;
}


- (BOOL)isPasswordProtected:(NSString *)path {
    return self.listener.requiresAuth;
}

- (NSString*) realm {
    return self.listener.realm;
}

- (NSString*) passwordForUser: (NSString*)username {
    LogTo(TDListener, @"Login attempted for user '%@'", username);
    return [self.listener passwordForUser: username];
}


- (BOOL)supportsMethod:(NSString *)method atPath:(NSString *)path {
    return $equal(method, @"POST") || $equal(method, @"PUT") || $equal(method,  @"DELETE")
        || [super supportsMethod: method atPath: path];
}


- (NSObject<HTTPResponse>*)httpResponseForMethod:(NSString *)method URI:(NSString *)path {
    if (requestContentLength > 0)
        LogTo(TDListener, @"%@ %@ {+%u}", method, path, (unsigned)requestContentLength);
    else
        LogTo(TDListener, @"%@ %@", method, path);
    
    // Construct an NSURLRequest from the HTTPRequest:
    NSMutableURLRequest* urlRequest = [NSMutableURLRequest requestWithURL: request.url];
    urlRequest.HTTPMethod = method;
    urlRequest.HTTPBody = request.body;
    NSDictionary* headers = request.allHeaderFields;
    for (NSString* header in headers)
        [urlRequest setValue: headers[header] forHTTPHeaderField: header];
    
    // Create a TDRouter:
    TDRouter* router = [[TDRouter alloc] initWithServer: ((TDHTTPServer*)config.server).tdServer
                                                request: urlRequest
                                                isLocal: NO];
    router.processRanges = NO;  // The HTTP server framework does this already
    TDHTTPResponse* response = [[[TDHTTPResponse alloc] initWithRouter: router
                                                         forConnection: self] autorelease];
    
    [router release];
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
		Warn(@"TDHTTPConnection: couldn't append data chunk");
}


@end
