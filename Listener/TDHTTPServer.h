//
//  TDHTTPServer.h
//  TouchDB
//
//  Created by Jens Alfke on 12/29/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "HTTPServer.h"
@class TDListener, TD_Server;


@interface TDHTTPServer : HTTPServer {
@private
    TDListener* _listener;
    TD_Server* _tdServer;
}

@property (retain) TDListener* listener;
@property (retain) TD_Server* tdServer;

@end


