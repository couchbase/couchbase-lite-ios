//
//  CBL_URLProtocol.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 11/30/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBL_Server, CBL_Router;

@interface CBL_URLProtocol : NSURLProtocol
{
    @private
    CBL_Router* _router;
}

/** The root URL served by this protocol, "cbl:///". */
+ (NSURL*) rootURL;

/** An alternate root URL with HTTP scheme; use this for CouchApps in UIWebViews.
    (This URL will have the hostname of the cbl: URL with ".cblite." appended.) */
+ (NSURL*) HTTPURLForServerURL: (NSURL*)serverURL;

/** Registers a CBL_Server instance with a URL hostname.
    'cbl:' URLs with that hostname will be routed to that server.
    If the server is nil, that hostname is unregistered, and URLs with that hostname will cause a host-not-found error.
    If the hostname is nil or an empty string, "localhost" is substituted. */
+ (NSURL*) registerServer: (CBL_Server*)server forHostname: (NSString*)hostname;

/** Returns the CBL_Server instance that's been registered with a specific hostname. */
+ (CBL_Server*) serverForHostname: (NSString*)hostname;

/** Registers a CBL_Server instance with a new unique hostname, and returns the root URL at which the server can now be reached. */
+ (NSURL*) registerServer: (CBL_Server*)server;

/** Unregisters a CBL_Server. After this, the server can be safely closed. */
+ (void) unregisterServer: (CBL_Server*)server;

/** A convenience to register a server with the default hostname "localhost". */
+ (void) setServer: (CBL_Server*)server;

/** Returns the server registered with the hostname "localhost". */
+ (CBL_Server*) server;

/** Returns YES if CBL_URLProtocol will handle this URL. */
+ (BOOL) handlesURL: (NSURL*)url;

@end


/** Starts a CBL_Server and registers it with CBL_URLProtocol so you can call it using the CouchDB-compatible REST API.
 @param serverDirectory  The top-level directory where you want the server to store databases. Will be created if it does not already exist.
 @param outError  An error will be stored here if the function returns nil.
 @return  The root URL of the REST API, or nil if the server failed to start. */
NSURL* CBLStartServer(NSString* serverDirectory, NSError** outError);
