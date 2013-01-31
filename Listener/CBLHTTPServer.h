//
//  CBLHTTPServer.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/29/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "HTTPServer.h"
@class CBLListener, CBL_Server;


@interface CBLHTTPServer : HTTPServer {
@private
    CBLListener* _listener;
    CBL_Server* _tdServer;
}

@property (retain) CBLListener* listener;
@property (retain) CBL_Server* tdServer;

@end


