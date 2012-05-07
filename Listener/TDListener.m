//
//  TDListener.m
//  TouchDBListener
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

#import "TDListener.h"
#import "TDHTTPServer.h"
#import "TDHTTPConnection.h"
#import "TDServer.h"

#import "HTTPServer.h"


@implementation TDListener


@synthesize readOnly=_readOnly;


- (id) initWithTDServer: (TDServer*)server port: (UInt16)port {
    self = [super init];
    if (self) {
        _tdServer = [server retain];
        _httpServer = [[TDHTTPServer alloc] init];
        _httpServer.listener = self;
        _httpServer.tdServer = _tdServer;
        _httpServer.port = port;
        _httpServer.connectionClass = [TDHTTPConnection class];
    }
    return self;
}


- (void)dealloc
{
    [self stop];
    [_tdServer release];
    [_httpServer release];
    [super dealloc];
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