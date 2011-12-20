//
//  TDURLProtocol.m
//  TouchDB
//
//  Created by Jens Alfke on 11/30/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TDURLProtocol.h"
#import "TDRouter.h"
#import "TDServer.h"
#import "TDInternal.h"


#define kScheme @"touchdb"


@implementation TDURLProtocol


static TDServer* sServer;


+ (void) initialize {
    if (self == [TDURLProtocol class])
        [NSURLProtocol registerClass: self];
}


+ (NSURL*) rootURL {
    return [NSURL URLWithString: kScheme ":///"];
}


+ (void) setServer: (TDServer*)server {
    @synchronized(self) {
        [sServer autorelease];
        sServer = [server retain];
    }
}


+ (TDServer*) server {
    @synchronized(self) {
        return [[sServer retain] autorelease];
    }
}


+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    return [request.URL.scheme caseInsensitiveCompare: kScheme] == 0;
}


+ (NSURLRequest*) canonicalRequestForRequest: (NSURLRequest*)request {
    return request;
}


- (void)dealloc {
    [_router stop];
    [_router release];
    [super dealloc];
}


- (void)startLoading {
    [self performSelector: @selector(load) withObject: nil afterDelay: 0.0];
}


- (void) load {
    LogTo(TDURLProtocol, @"Loading <%@>", self.request.URL);
    TDServer* server = [[self class] server];
    NSAssert(server, @"No server");
    id<NSURLProtocolClient> client = self.client;
    _router = [[TDRouter alloc] initWithServer: server request: self.request];
    _router.onResponseReady = ^(TDResponse* routerResponse) {
        LogTo(TDURLProtocol, @"response ready for <%@> (%d)",
              self.request.URL, routerResponse.status);
        // NOTE: This initializer is only available in iOS 5 and OS X 10.7.2.
        // TODO: Find a way to work around this; it'd be nice to support 10.6 or iOS 4.x.
        NSHTTPURLResponse* response = [[NSHTTPURLResponse alloc] initWithURL: self.request.URL
                                                                  statusCode: routerResponse.status
                                                                 HTTPVersion: @"1.1"
                                                                headerFields: routerResponse.headers];
        [client URLProtocol: self didReceiveResponse: response 
                                  cacheStoragePolicy: NSURLCacheStorageNotAllowed];
        [response release];
    };
    _router.onDataAvailable = ^(NSData* content) {
        LogTo(TDURLProtocol, @"data available from <%@>", self.request.URL);
        if (content.length)
            [client URLProtocol: self didLoadData: content];
    };
    _router.onFinished = ^{
        LogTo(TDURLProtocol, @"finished response <%@>", self.request.URL);
        [client URLProtocolDidFinishLoading: self];
    };
    [_router start];
}


- (void)stopLoading {
    LogTo(TDURLProtocol, @"Stop <%@>", self.request.URL);
    [_router stop];
}


@end



#pragma mark - TESTS
#if DEBUG

TestCase(TDURLProtocol) {
    RequireTestCase(TDRouter);
    [TDURLProtocol setServer: [TDServer createEmptyAtPath: @"/tmp/TDURLProtocolTest"]];
    
    NSURL* url = [NSURL URLWithString: @"touchdb:///"];
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
    CAssert([bodyStr rangeOfString: @"\"TouchDB\":\"welcome\""].length > 0);
}

#endif
