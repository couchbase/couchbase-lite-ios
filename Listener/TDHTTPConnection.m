//
//  TDHTTPConnection.m
//  TouchDB
//
//  Created by Jens Alfke on 12/29/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TDHTTPConnection.h"
#import "TDHTTPServer.h"
#import "TDHTTPResponse.h"
#import "TDListener.h"
#import "TDServer.h"
#import "TDRouter.h"
#import "HTTPMessage.h"
#import "HTTPDataResponse.h"


@implementation TDHTTPConnection


- (BOOL)supportsMethod:(NSString *)method atPath:(NSString *)path
{
    return YES;
}


- (NSObject<HTTPResponse>*)httpResponseForMethod:(NSString *)method URI:(NSString *)path {
    NSLog(@"TDListener: %@ %@", method, path); //TEMP
    NSURL* url = [NSURL URLWithString: [@"touchdb://" stringByAppendingString: path]];
    NSMutableURLRequest* urlRequest = [NSMutableURLRequest requestWithURL: url];
    urlRequest.HTTPMethod = method;
    urlRequest.HTTPBody = request.body;
    NSDictionary* headers = request.allHeaderFields;
    for (NSString* header in headers) {
        [urlRequest setValue: [headers objectForKey: header] forHTTPHeaderField: header];
    }
    
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
    
    [((TDHTTPServer*)config.server).listener onServerThread: ^{[router start];}];
    NSAssert(finished, @"Router didn't finish");
    
    BOOL pretty = [router boolQuery: @"pretty"];
#if DEBUG
    pretty = YES;
#endif
    TDHTTPResponse* response = [[[TDHTTPResponse alloc] initWithTDResponse: routerResponse
                                                                    pretty: pretty] autorelease];
    
    [router release];
    return response;
}


@end
