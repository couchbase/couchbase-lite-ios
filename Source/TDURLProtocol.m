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
#import "TD_Server.h"
#import "TDInternal.h"
#import "MYBlockUtils.h"


#define kScheme @"touchdb"


@implementation TDURLProtocol


static NSMutableDictionary* sHostMap;


+ (void) initialize {
    if (self == [TDURLProtocol class])
        [NSURLProtocol registerClass: self];
}


#pragma mark - REGISTERING SERVERS:


+ (void) setServer: (TD_Server*)server {
    @synchronized(self) {
        [self registerServer: server forHostname: nil];
    }
}


+ (TD_Server*) server {
    @synchronized(self) {
        return [self serverForHostname: nil];
    }
}


static NSString* normalizeHostname( NSString* hostname ) {
    return hostname.length > 0 ? hostname.lowercaseString : @"localhost";
}


+ (void) forgetServers {
    @synchronized(self) {
        sHostMap = nil;
    }
}


+ (NSURL*) rootURLForHostname: (NSString*)hostname {
    if (!hostname || $equal(hostname, @"localhost"))
        hostname = @"";
    return [NSURL URLWithString: $sprintf(@"%@://%@/", kScheme, hostname)];
}


+ (NSURL*) registerServer: (TD_Server*)server forHostname: (NSString*)hostname {
    @synchronized(self) {
        if (!sHostMap)
            sHostMap = [[NSMutableDictionary alloc] init];
        [sHostMap setValue: server forKey: normalizeHostname(hostname)];
        return [self rootURLForHostname: hostname];
    }
}


+ (NSURL*) registerServer: (TD_Server*)server {
    @synchronized(self) {
        NSString* hostname = [[sHostMap allKeysForObject: server] lastObject];
        if (!hostname) {
            int count = 0;
            do {
                hostname = $sprintf(@"server%d", ++count);
            } while (sHostMap[hostname]);
        }
        [self registerServer: server forHostname: hostname];
        return [self rootURLForHostname: hostname];
    }
}


+ (void) unregisterServer: (TD_Server*)server {
    @synchronized(self) {
        [sHostMap removeObjectsForKeys: [sHostMap allKeysForObject: server]];
    }
}


+ (TD_Server*) serverForHostname: (NSString*)hostname {
    @synchronized(self) {
        return sHostMap[normalizeHostname(hostname)];
    }
}


+ (TD_Server*) serverForURL: (NSURL*)url {
    NSString* scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString: kScheme])
        return [self serverForHostname: url.host];
    if ([scheme isEqualToString: @"http"] || [scheme isEqualToString: @"https"]) {
        NSString* host = url.host;
        if ([host hasSuffix: @".touchdb."]) {
            host = [host substringToIndex: host.length - 9];
            return [self serverForHostname: host];
        }
    }
    return nil;
}


+ (NSURL*) rootURL {
    return [NSURL URLWithString: kScheme ":///"];
}

+ (NSURL*) HTTPURLForServerURL: (NSURL*)serverURL {
    return [NSURL URLWithString: $sprintf(@"http://%@.touchdb./", normalizeHostname(serverURL.host))];
}


#pragma mark - INITIALIZATION:


+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSURL* url = request.URL;
    if ([url.scheme caseInsensitiveCompare: kScheme] == 0)
        return YES;
    else
        return [self serverForURL: url] != nil;
}


+ (NSURLRequest*) canonicalRequestForRequest: (NSURLRequest*)request {
    return request;
}


- (void) dealloc {
    [_router stop];
}


#pragma mark - LOADING:


- (void) startLoading {
    LogTo(TDURLProtocol, @"Loading <%@>", self.request.URL);
    TD_Server* server = [[self class] serverForURL: self.request.URL];
    if (!server) {
        NSError* error = [NSError errorWithDomain: NSURLErrorDomain
                                             code: NSURLErrorCannotFindHost userInfo: nil];
        [self.client URLProtocol: self didFailWithError: error];
        return;
    }
    
    NSThread* loaderThread = [NSThread currentThread];
    _router = [[TDRouter alloc] initWithServer: server request: self.request isLocal: YES];
    
    __weak id weakSelf = self;
    
    _router.onResponseReady = ^(TDResponse* routerResponse) {
        id strongSelf = weakSelf;
        [strongSelf performSelector: @selector(onResponseReady:)
                           onThread: loaderThread
                         withObject: routerResponse
                      waitUntilDone: NO];
    };
    _router.onDataAvailable = ^(NSData* data, BOOL finished) {
        id strongSelf = weakSelf;
        [strongSelf performSelector: @selector(onDataAvailable:)
                           onThread: loaderThread
                         withObject: data
                      waitUntilDone: NO];
    };
    _router.onFinished = ^{
        id strongSelf = weakSelf;
        [strongSelf performSelector: @selector(onFinished)
                           onThread: loaderThread
                         withObject: nil
                      waitUntilDone: NO];
    };
    [_router start];
}


- (void) onResponseReady: (TDResponse*)routerResponse {
    LogTo(TDURLProtocol, @"response ready for <%@> (%d %@)",
          self.request.URL, routerResponse.status, routerResponse.statusMsg);
    // NOTE: This initializer is only available in iOS 5 and OS X 10.7.2.
    // TODO: Find a way to work around this; it'd be nice to support 10.6 or iOS 4.x.
    NSHTTPURLResponse* response = [[NSHTTPURLResponse alloc] initWithURL: self.request.URL
                                                              statusCode: routerResponse.status
                                                             HTTPVersion: @"1.1"
                                                            headerFields: routerResponse.headers];
    [self.client URLProtocol: self didReceiveResponse: response 
          cacheStoragePolicy: NSURLCacheStorageNotAllowed];
}


- (void) onDataAvailable: (NSData*)data {
    LogTo(TDURLProtocol, @"data available from <%@>", self.request.URL);
    if (data.length)
        [self.client URLProtocol: self didLoadData: data];
}


- (void) onFinished {
    LogTo(TDURLProtocol, @"finished response <%@>", self.request.URL);
    [self.client URLProtocolDidFinishLoading: self];
}


- (void)stopLoading {
    LogTo(TDURLProtocol, @"Stop <%@>", self.request.URL);
    [_router stop];
}


@end



#pragma mark - TESTS
#if DEBUG

TestCase(TDURLProtocol_Registration) {
    [TDURLProtocol forgetServers];
    CAssertNil([TDURLProtocol serverForHostname: @"some.hostname"]);
    
    NSURL* url = [NSURL URLWithString: @"touchdb://some.hostname/"];
    NSURLRequest* req = [NSURLRequest requestWithURL: url];
    NSHTTPURLResponse* response = nil;
    NSError* error = nil;
    NSData* body = [NSURLConnection sendSynchronousRequest: req 
                                         returningResponse: &response 
                                                     error: &error];
    CAssertNil(body);
    CAssertEqual(error.domain, NSURLErrorDomain);
    CAssertEq(error.code, NSURLErrorCannotFindHost);
    
    TD_Server* server = [TD_Server createEmptyAtTemporaryPath: @"TDURLProtocolTest"];
    NSURL* root = [TDURLProtocol registerServer: server forHostname: @"some.hostname"];
    CAssertEqual(root, url);
    CAssertEq([TDURLProtocol serverForHostname: @"some.hostname"], server);
    
    body = [NSURLConnection sendSynchronousRequest: req 
                                 returningResponse: &response 
                                             error: &error];
    CAssert(body != nil);
    CAssert(response != nil);
    CAssertEq(response.statusCode, kTDStatusOK);
    
    [server close];
    [TDURLProtocol registerServer: nil forHostname: @"some.hostname"];
    body = [NSURLConnection sendSynchronousRequest: req 
                                 returningResponse: &response 
                                             error: &error];
    CAssertNil(body);
    CAssertEqual(error.domain, NSURLErrorDomain);
    CAssertEq(error.code, NSURLErrorCannotFindHost);
}


TestCase(TDURLProtocol) {
    RequireTestCase(TDRouter);
    [TDURLProtocol forgetServers];
    TD_Server* server = [TD_Server createEmptyAtTemporaryPath: @"TDURLProtocolTest"];
    [TDURLProtocol setServer: server];
    
    NSURL* url = [NSURL URLWithString: @"touchdb:///"];
    NSURLRequest* req = [NSURLRequest requestWithURL: url];
    NSHTTPURLResponse* response = nil;
    NSError* error = nil;
    NSData* body = [NSURLConnection sendSynchronousRequest: req 
                                         returningResponse: &response 
                                                     error: &error];
    NSString* bodyStr = [[NSString alloc] initWithData: body encoding: NSUTF8StringEncoding];
    Log(@"Response = %@", response);
    Log(@"MIME Type = %@", response.MIMEType);
    Log(@"Body = %@", bodyStr);
    CAssert(body != nil);
    CAssert(response != nil);
    CAssertEq(response.statusCode, kTDStatusOK);
    CAssertEqual((response.allHeaderFields)[@"Content-Type"], @"application/json");
    CAssert([bodyStr rangeOfString: @"\"TouchDB\":\"Welcome\""].length > 0
            || [bodyStr rangeOfString: @"\"TouchDB\": \"Welcome\""].length > 0);
    [server close];
    [TDURLProtocol setServer: nil];
}

#endif
