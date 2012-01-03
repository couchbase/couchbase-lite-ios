//
//  TDHTTPConnection.m
//  TouchDB
//
//  Created by Jens Alfke on 12/29/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
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


- (BOOL)supportsMethod:(NSString *)method atPath:(NSString *)path {
    return $equal(method, @"POST") || $equal(method, @"PUT") || $equal(method,  @"DELETE")
        || [super supportsMethod: method atPath: path];
}


- (NSObject<HTTPResponse>*)httpResponseForMethod:(NSString *)method URI:(NSString *)path {
    LogTo(TDListener, @"%@ %@ {+%u}", method, path, (unsigned)request.body.length);
    AssertEq(request.body.length, requestContentLength);
    
    // Construct an NSURLRequest from the HTTPRequest:
    NSMutableURLRequest* urlRequest = [NSMutableURLRequest requestWithURL: request.url];
    urlRequest.HTTPMethod = method;
    urlRequest.HTTPBody = request.body;
    NSDictionary* headers = request.allHeaderFields;
    for (NSString* header in headers)
        [urlRequest setValue: [headers objectForKey: header] forHTTPHeaderField: header];
    
    // Create a TDRouter:
    TDRouter* router = [[TDRouter alloc] initWithServer: ((TDHTTPServer*)config.server).tdServer
                                                request: urlRequest];
    __block bool finished = false;
    __block TDResponse* routerResponse = nil;
    NSMutableData* data = [NSMutableData data];
    router.onResponseReady = ^(TDResponse* r) {
        routerResponse = r;
    };
    router.onDataAvailable = ^(NSData* content) {
        [data appendData: content];
    };
    router.onFinished = ^{
        finished = true;
    };
    
    // Run the router, synchronously:
    [((TDHTTPServer*)config.server).listener onServerThread: ^{[router start];}];
    NSAssert(finished, @"Router didn't finish");
    
    LogTo(TDListener, @"%@ %@ --> %i", method, path, routerResponse.status);

    // Return the response:
#if DEBUG
    BOOL pretty = YES;
#else
    BOOL pretty = [router boolQuery: @"pretty"];
#endif
    TDHTTPResponse* response = [[[TDHTTPResponse alloc] initWithTDResponse: routerResponse
                                                                    pretty: pretty] autorelease];
    
    [router release];
    return response;
}


- (BOOL)expectsRequestBodyFromMethod:(NSString *)method atPath:(NSString *)path {
	return $equal(method, @"POST") || $equal(method, @"PUT")
		|| [super expectsRequestBodyFromMethod:method atPath:path];
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
