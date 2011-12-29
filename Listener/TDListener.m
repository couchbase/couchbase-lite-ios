//
//  TDListener.m
//  TouchDBListener
//
//  Created by Jens Alfke on 12/29/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TDListener.h"
#import "TDHTTPServer.h"
#import "TDHTTPConnection.h"
#import "TDServer.h"

#import "HTTPServer.h"


@implementation TDListener


- (id) initWithTDServer: (TDServer*)server port: (UInt16)port {
    self = [super init];
    if (self) {
        _tdServer = [server retain];
        _httpServer = [[TDHTTPServer alloc] init];
        _httpServer.listener = self;
        _httpServer.tdServer = _tdServer;
        _httpServer.port = port;
        _httpServer.connectionClass = [TDHTTPConnection class];
        _queue = dispatch_queue_create("TDListener", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}


- (void)dealloc
{
    [self stop];
    [_tdServer release];
    [_httpServer release];
    dispatch_release(_queue);
    [super dealloc];
}


- (void) onServerThread: (void(^)())block {
    dispatch_sync(_queue, block);
}


- (BOOL) start {
    NSError* error;
    return [_httpServer start: &error];
}

- (void) stop {
    [_httpServer stop];
}


@end



@implementation TDHTTPServer

@synthesize listener=_listener, tdServer=_tdServer;

@end