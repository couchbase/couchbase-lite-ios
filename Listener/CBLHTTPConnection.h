//
//  CBLHTTPConnection.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/29/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import "HTTPConnection.h"
#import "HTTPServer.h"
@class CBLListener, CBL_Server;


/** Custom CouchbaseLite subclass of CocoaHTTPServer's HTTPConnection class. */
@interface CBLHTTPConnection : HTTPConnection

@property (readonly) CBLListener* listener;
@property (readonly) NSString* username;

@end



/** Trivial HTTPServer subclass that just adds synthesized `listener` and `cblServer` properties. */
@interface CBLHTTPServer : HTTPServer

@property (retain) CBLListener* listener;
@property (retain) CBL_Server* cblServer;

@end
