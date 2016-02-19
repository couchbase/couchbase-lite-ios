//
//  CBLAuthorizer.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/21/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import <CouchbaseLite/CBLAuthenticator.h>
#import <Security/SecBase.h>


/** Internal protocol for authenticating a user to a server.
    (The word "authorization" here is a misnomer, but HTTP uses it for historical reasons.) */
@protocol CBLAuthorizer <CBLAuthenticator>
@end



/** Authorizer that uses a username/password (i.e. HTTP Basic or Digest auth) */
@protocol CBLCredentialAuthorizer <CBLAuthorizer>

@property (readonly) NSURLCredential* credential;

@end



/** Authorizer that adds custom headers to an HTTP request */
@protocol CBLCustomHeadersAuthorizer <CBLAuthorizer>

/** Should add a header to the request to convey the authorization token. */
- (void) authorizeURLRequest: (NSMutableURLRequest*)request;

/** Should add a header to the message to convey the authorization token. */
- (void) authorizeHTTPMessage: (CFHTTPMessageRef)message;

@end



/** Authorizer that sends a login request that sets a session cookie. */
@protocol CBLLoginAuthorizer <CBLAuthorizer>

- (NSString*) loginPathForSite: (NSURL*)site;
- (NSDictionary*) loginParametersForSite: (NSURL*)site;

@end



/** Simple implementation of CBLPasswordAuthorizer. */
@interface CBLPasswordAuthorizer : NSObject <CBLCredentialAuthorizer, CBLCustomHeadersAuthorizer>

- (instancetype) initWithUser: (NSString*)user password: (NSString*)password;

/** Initialize given a credential object that contains a username and password. */
- (instancetype) initWithCredential: (NSURLCredential*)credential;

/** Initialize given a URL alone -- will use a baked-in username/password in the URL,
    or look up a credential from the keychain. */
- (instancetype) initWithURL: (NSURL*)url;

@end



/** Sets the global list of anchor certs to be used by CBLCheckSSLServerTrust. */
void CBLSetAnchorCerts(NSArray* certs, BOOL onlyThese);

/** Checks server trust, using the global list of anchor certs. */
BOOL CBLCheckSSLServerTrust(SecTrustRef trust, NSString* host, UInt16 port, NSData *pinned);

/** Forces a SecTrustRef's result to be a success. */
BOOL CBLForceTrusted(SecTrustRef trust);