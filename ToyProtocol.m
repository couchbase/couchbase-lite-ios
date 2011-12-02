//
//  ToyProtocol.m
//  ToyCouch
//
//  Created by Jens Alfke on 11/30/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "ToyProtocol.h"
#import "ToyRouter.h"
#import "ToyServer.h"
#import "ToyDocument.h"
#import "Test.h"


@implementation ToyProtocol


static ToyServer* sServer;


+ (void) initialize {
    if (self == [ToyProtocol class])
        [NSURLProtocol registerClass: self];
}


+ (void) setServer: (ToyServer*)server {
    [sServer autorelease];
    sServer = [server retain];
}


+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    return [request.URL.scheme caseInsensitiveCompare: @"toy"] == 0;
}


+ (NSURLRequest*) canonicalRequestForRequest: (NSURLRequest*)request {
    return request;
}


- (void)dealloc {
    [_router release];
    [super dealloc];
}


- (void)startLoading {
    NSAssert(sServer, @"No server");
    [self performSelector: @selector(load) withObject: nil afterDelay: 0.0];
}


- (void) load {
    id<NSURLProtocolClient> client = self.client;
    _router = [[ToyRouter alloc] initWithServer: sServer request: self.request];
    _router.onResponseReady = ^(ToyResponse* routerResponse) {
        // NOTE: This initializer is only available in iOS 5 and OS X 10.7.2.
        NSHTTPURLResponse* response = [[NSHTTPURLResponse alloc] initWithURL: self.request.URL
                                                                  statusCode: routerResponse.status
                                                                 HTTPVersion: @"1.1"
                                                                headerFields: routerResponse.headers];
        [client URLProtocol: self didReceiveResponse: response 
                                  cacheStoragePolicy: NSURLCacheStorageNotAllowed];
        [response release];
    };
    _router.onDataAvailable = ^(NSData* content) {
        if (content.length)
            [client URLProtocol: self didLoadData: content];
    };
    _router.onFinished = ^{
        [client URLProtocolDidFinishLoading: self];
    };
    [_router start];
}


- (void)stopLoading {
    [_router stop];
}


@end



#pragma mark - TESTS

TestCase(ToyProtocol) {
    [ToyProtocol setServer: [ToyServer createEmptyAtPath: @"/tmp/ToyProtocolTest"]];
    
    NSURL* url = [NSURL URLWithString: @"toy:///"];
    NSURLRequest* req = [NSURLRequest requestWithURL: url];
    NSHTTPURLResponse* response = nil;
    NSError* error = nil;
    NSData* body = [NSURLConnection sendSynchronousRequest: req 
                                         returningResponse: &response 
                                                     error: &error];
    NSString* bodyStr = [[[NSString alloc] initWithData: body encoding: NSUTF8StringEncoding] autorelease];
    Log(@"Response = %@", response);
    Log(@"MIME Type = %@", response.MIMEType);
    Log(@"Body = %@", bodyStr);
    CAssert(body != nil);
    CAssert(response != nil);
    CAssertNil(error);
    CAssertEq(response.statusCode, 200);
    CAssertEqual([response.allHeaderFields objectForKey: @"Content-Type"], @"application/json");
    CAssert([bodyStr hasPrefix: @"{\"ToyCouch\":\"welcome\",\"version\":"]);
}
