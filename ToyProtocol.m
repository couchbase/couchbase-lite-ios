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


- (void)startLoading {
    NSAssert(sServer, @"No server");
    [self performSelector: @selector(load) withObject: nil afterDelay: 0.0];
}


- (void) load {
    id<NSURLProtocolClient> client = self.client;
    ToyRouter *router = [[ToyRouter alloc] initWithServer: sServer request: self.request];
    ToyResponse* routerResponse = router.response;
    // NOTE: This initializer is only available in iOS 5 and OS X 10.7.2.
    NSHTTPURLResponse* response = [[NSHTTPURLResponse alloc] initWithURL: self.request.URL
                                                              statusCode: routerResponse.status
                                                             HTTPVersion: @"1.1"
                                                            headerFields: routerResponse.headers];
    [client URLProtocol: self didReceiveResponse: response 
                              cacheStoragePolicy: NSURLCacheStorageNotAllowed];
    [response release];
    NSData* content = router.response.body.asJSON;
    if (content.length)
        [client URLProtocol: self didLoadData: content];
    [client URLProtocolDidFinishLoading: self];
    [router release];
}


- (void)stopLoading {
}


@end



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
