//
//  CBLHTTPConnection.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/29/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "HTTPConnection.h"
@class CBLListener;


/** Custom CouchbaseLite subclass of CocoaHTTPServer's HTTPConnection class. */
@interface CBLHTTPConnection : HTTPConnection

@property (readonly) CBLListener* listener;

- (NSString *)authUsername;
-(void)handleCookieAuthentication;
    
@end
