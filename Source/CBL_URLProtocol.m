//
//  CBL_URLProtocol.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 11/30/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
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
#import "MYLogging.h"
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
    NSHTTPURLResponse* response = [[NSHTTPURLResponse alloc] initWithURL: self.request.URL
                                                              statusCode: routerResponse.status
                                                             HTTPVersion: @"1.1"
                                                            headerFields: routerResponse.headers];
    [self.client URLProtocol: self didReceiveResponse: response 
          cacheStoragePolicy: NSURLCacheStorageNotAllowed];
}


- (void) onDataAvailable: (NSData*)data {
    if (data.length)
        [self.client URLProtocol: self didLoadData: data];
}


- (void) onFinished {
    [self.client URLProtocolDidFinishLoading: self];
}


- (void)stopLoading {
    [_router stop];
}


@end



NSURL* CBLStartServer(NSString* serverDirectory, NSError** outError) {
    CAssert(![CBL_URLProtocol server], @"A CBL_Server is already running");
    CBLManager* manager = [[CBLManager alloc] initWithDirectory: serverDirectory
                                                        options: nil
                                                          error: outError];
    if (!manager)
        return nil;
    CBL_Server* tdServer = [[CBL_Server alloc] initWithManager: manager];
    if (!tdServer)
        return nil;
    return [CBL_URLProtocol registerServer: tdServer forHostname: nil];
}
