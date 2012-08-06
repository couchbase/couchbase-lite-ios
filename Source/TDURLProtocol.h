//
//  TDURLProtocol.h
//  TouchDB
//
//  Created by Jens Alfke on 11/30/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class TDServer, TDRouter;

@interface TDURLProtocol : NSURLProtocol
{
    @private
    TDRouter* _router;
}

/** The root URL served by this protocol, "touchdb:///". */
+ (NSURL*) rootURL;

/** An alternate root URL with HTTP scheme; use this for CouchApps in UIWebViews.
    (This URL will have the hostname of the touchdb: URL with ".touchdb." appended.) */
+ (NSURL*) HTTPURLForServerURL: (NSURL*)serverURL;

/** Registers a TDServer instance with a URL hostname.
    'touchdb:' URLs with that hostname will be routed to that server.
    If the server is nil, that hostname is unregistered, and URLs with that hostname will cause a host-not-found error.
    If the hostname is nil or an empty string, "localhost" is substituted. */
+ (NSURL*) registerServer: (TDServer*)server forHostname: (NSString*)hostname;

/** Returns the TDServer instance that's been registered with a specific hostname. */
+ (TDServer*) serverForHostname: (NSString*)hostname;

/** Registers a TDServer instance with a new unique hostname, and returns the root URL at which the server can now be reached. */
+ (NSURL*) registerServer: (TDServer*)server;

/** Unregisters a TDServer. After this, the server can be safely closed. */
+ (void) unregisterServer: (TDServer*)server;

/** A convenience to register a server with the default hostname "localhost". */
+ (void) setServer: (TDServer*)server;

/** Returns the server registered with the hostname "localhost". */
+ (TDServer*) server;

@end
