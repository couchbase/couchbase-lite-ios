//
//  CBL_URLProtocol.m
//  CouchbaseLite
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

#import "CBL_URLProtocol.h"
#import "CBL_Router.h"
#import "CBL_Server.h"
#import "CBLInternal.h"
#import "MYBlockUtils.h"
#import "CollectionUtils.h"
#import "Logging.h"
#import "Test.h"


#define kScheme @"cbl"


@implementation CBL_URLProtocol


static NSMutableDictionary* sHostMap;


+ (void) initialize {
    if (self == [CBL_URLProtocol class])
        [NSURLProtocol registerClass: self];
}


#pragma mark - REGISTERING SERVERS:


+ (void) setServer: (CBL_Server*)server {
    @synchronized(self) {
        [self registerServer: server forHostname: nil];
    }
}


+ (CBL_Server*) server {
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


+ (NSURL*) registerServer: (CBL_Server*)server forHostname: (NSString*)hostname {
    @synchronized(self) {
        if (!sHostMap)
            sHostMap = [[NSMutableDictionary alloc] init];
        [sHostMap setValue: server forKey: normalizeHostname(hostname)];
        return [self rootURLForHostname: hostname];
    }
}


+ (NSURL*) registerServer: (CBL_Server*)server {
    @synchronized(self) {
        NSString* hostname = [[sHostMap allKeysForObject: server] lastObject];
        if (!hostname) {
            int count = 0;
            hostname = @"lite";
            while (sHostMap[hostname]) {
                hostname = $sprintf(@"lite%d", ++count);
            };
        }
        [self registerServer: server forHostname: hostname];
        return [self rootURLForHostname: hostname];
    }
}


+ (void) unregisterServer: (CBL_Server*)server {
    @synchronized(self) {
        [sHostMap removeObjectsForKeys: [sHostMap allKeysForObject: server]];
    }
}


+ (CBL_Server*) serverForHostname: (NSString*)hostname {
    @synchronized(self) {
        return sHostMap[normalizeHostname(hostname)];
    }
}


+ (CBL_Server*) serverForURL: (NSURL*)url {
    NSString* scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString: kScheme])
        return [self serverForHostname: url.host];
    if ([scheme isEqualToString: @"http"] || [scheme isEqualToString: @"https"]) {
        NSString* host = url.host;
        if ([host hasSuffix: @".couchbase."]) {
            host = [host substringToIndex: host.length - 11];
            return [self serverForHostname: host];
        }
    }
    return nil;
}


+ (NSURL*) rootURL {
    return [NSURL URLWithString: kScheme ":///"];
}

+ (NSURL*) HTTPURLForServerURL: (NSURL*)serverURL {
    return [NSURL URLWithString: $sprintf(@"http://%@.couchbase./",
                                          normalizeHostname(serverURL.host))];
}


+ (BOOL) handlesURL: (NSURL*)url {
    if ([url.scheme caseInsensitiveCompare: kScheme] == 0)
        return YES;
    else
        return [self serverForURL: url] != nil;
}


#pragma mark - INITIALIZATION:


+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    return [self handlesURL: request.URL];
}


+ (NSURLRequest*) canonicalRequestForRequest: (NSURLRequest*)request {
    return request;
}


- (void) dealloc {
    [_router stop];
}


#pragma mark - LOADING:


- (void) startLoading {
    LogTo(CBL_URLProtocol, @"Loading <%@>", self.request.URL);
    CBL_Server* server = [[self class] serverForURL: self.request.URL];
    if (!server) {
        NSError* error = [NSError errorWithDomain: NSURLErrorDomain
                                             code: NSURLErrorCannotFindHost userInfo: nil];
        [self.client URLProtocol: self didFailWithError: error];
        return;
    }
    
    NSThread* loaderThread = [NSThread currentThread];
    _router = [[CBL_Router alloc] initWithServer: server request: self.request isLocal: YES];
    
    __weak id weakSelf = self;
    
    _router.onResponseReady = ^(CBLResponse* routerResponse) {
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


- (void) onResponseReady: (CBLResponse*)routerResponse {
    LogTo(CBL_URLProtocol, @"response ready for <%@> (%d %@)",
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
    LogTo(CBL_URLProtocol, @"data available from <%@>", self.request.URL);
    if (data.length)
        [self.client URLProtocol: self didLoadData: data];
}


- (void) onFinished {
    LogTo(CBL_URLProtocol, @"finished response <%@>", self.request.URL);
    [self.client URLProtocolDidFinishLoading: self];
}


- (void)stopLoading {
    LogTo(CBL_URLProtocol, @"Stop <%@>", self.request.URL);
    [_router stop];
}


@end



NSURL* CBLStartServer(NSString* serverDirectory, NSError** outError) {
    CAssert(![CBL_URLProtocol server], @"A CBL_Server is already running");
    CBL_Server* tdServer = [[CBL_Server alloc] initWithDirectory: serverDirectory
                                                       error: outError];
    if (!tdServer)
        return nil;
    return [CBL_URLProtocol registerServer: tdServer forHostname: nil];
}



#pragma mark - TESTS
#if DEBUG

TestCase(CBL_URLProtocol_Registration) {
    [CBL_URLProtocol forgetServers];
    CAssertNil([CBL_URLProtocol serverForHostname: @"some.hostname"]);
    
    NSURL* url = [NSURL URLWithString: @"cbl://some.hostname/"];
    NSURLRequest* req = [NSURLRequest requestWithURL: url];
    NSHTTPURLResponse* response = nil;
    NSError* error = nil;
    NSData* body = [NSURLConnection sendSynchronousRequest: req 
                                         returningResponse: &response 
                                                     error: &error];
    CAssertNil(body);
    CAssertEqual(error.domain, NSURLErrorDomain);
    CAssertEq(error.code, NSURLErrorCannotFindHost);
    
    CBL_Server* server = [CBL_Server createEmptyAtTemporaryPath: @"CBL_URLProtocolTest"];
    NSURL* root = [CBL_URLProtocol registerServer: server forHostname: @"some.hostname"];
    CAssertEqual(root, url);
    CAssertEq([CBL_URLProtocol serverForHostname: @"some.hostname"], server);
    
    body = [NSURLConnection sendSynchronousRequest: req 
                                 returningResponse: &response 
                                             error: &error];
    CAssert(body != nil);
    CAssert(response != nil);
    CAssertEq(response.statusCode, kCBLStatusOK);
    
    [server close];
    [CBL_URLProtocol registerServer: nil forHostname: @"some.hostname"];
    body = [NSURLConnection sendSynchronousRequest: req 
                                 returningResponse: &response 
                                             error: &error];
    CAssertNil(body);
    CAssertEqual(error.domain, NSURLErrorDomain);
    CAssertEq(error.code, NSURLErrorCannotFindHost);
}


TestCase(CBL_URLProtocol) {
    RequireTestCase(CBL_Router);
    [CBL_URLProtocol forgetServers];
    CBL_Server* server = [CBL_Server createEmptyAtTemporaryPath: @"CBL_URLProtocolTest"];
    [CBL_URLProtocol setServer: server];
    
    NSURL* url = [NSURL URLWithString: @"cbl:///"];
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
    CAssertEq(response.statusCode, kCBLStatusOK);
    CAssertEqual((response.allHeaderFields)[@"Content-Type"], @"application/json");
    CAssert([bodyStr rangeOfString: @"\"CouchbaseLite\":\"Welcome\""].length > 0
            || [bodyStr rangeOfString: @"\"CouchbaseLite\": \"Welcome\""].length > 0);
    [server close];
    [CBL_URLProtocol setServer: nil];
}

#endif
