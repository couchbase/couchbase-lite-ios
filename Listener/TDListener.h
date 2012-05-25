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
    NSString* _realm;
    BOOL _readOnly;
    BOOL _requiresAuth;
    NSDictionary* _passwords;
}

/** Initializes a TDListener.
    @param server  The TDServer whose databases to serve.
    @param port  The TCP port number to listen on. Use 0 to automatically pick an available port (you can get the port number after the server starts by getting the .port property.) */
- (id) initWithTDServer: (TDServer*)server port: (UInt16)port;

/** The TCP port number that the listener is listening on.
    If the listener has not yet started, this will return 0. */
@property (readonly) UInt16 port;


/** The Bonjour service name and type to advertise as.
    @param name  The service name; this can be arbitrary but is generally the device user's name. An empty string will be mapped to the device's name.
    @param type  The service type; the type of a generic HTTP server is "_http._tcp." but you should use something more specific. */
- (void) setBonjourName: (NSString*)name type: (NSString*)type;

/** Bonjour metadata associated with the service. Changes will be visible almost immediately.
    The keys are NSStrings and values are NSData. Total size should be kept small (under 1kbyte if possible) as this data is multicast over UDP. */
@property (copy) NSDictionary* TXTRecordDictionary;


/** If set to YES, remote requests will not be allowed to make any changes to the server or its databases. */
@property BOOL readOnly;

/** If set to YES, all requests will be required to authenticate.
    Setting a .passwords dictionary automatically enables this.*/
@property BOOL requiresAuth;

/** Security realm string to return in authentication challenges. */
@property (copy) NSString* realm;

/** Sets user names and passwords for authentication.
    @param passwords  A dictionary mapping user names to passwords. */
- (void) setPasswords: (NSDictionary*)passwords;

/** Returns the password assigned to a user name, or nil if the name is not recognized. */
- (NSString*) passwordForUser: (NSString*)username;


/** Starts the listener. */
- (BOOL) start;

/** Stops the listener. */
- (void) stop;

@end
