//
//  TDListener.h
//  TouchDBListener
//
//  Created by Jens Alfke on 12/29/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class TDHTTPServer, TDServer;


/** A simple HTTP server that provides remote access to the TouchDB REST API. */
@interface TDListener : NSObject
{
    TDHTTPServer* _httpServer;
    TDServer* _tdServer;
    dispatch_queue_t _queue;
}

- (id) initWithTDServer: (TDServer*)server port: (UInt16)port;

- (BOOL) start;
- (void) stop;

/** Runs the block *synchronously* on the single server thread. */
- (void) onServerThread: (void(^)())block;

@end
