//
//  CBLAuthorizer.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/21/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import <CouchbaseLite/CBLAuthenticator.h>
#import "CBLStatus.h"
#import <Security/SecBase.h>


/** Internal protocol for authenticating a user to a server.
    (The word "authorization" here is a misnomer, but HTTP uses it for historical reasons.) */
@protocol CBLAuthorizer <CBLAuthenticator>
/** The base URL of the remote service. The replicator sets this property when it starts up. */
@property NSURL* remoteURL;
/** The unique ID of the local database. The replicator sets this property when it starts up. */
@property NSString* localUUID;
- (BOOL) removeStoredCredentials: (NSError**)outError;
@optional
@property (readonly, atomic) NSString* username;
@end


/** Base implementation of CBLAuthorizer protocol that synthesizes the remoteURL property. */
@interface CBLAuthorizer : NSObject <CBLAuthorizer>
@end



/** Authorizer that uses a username/password (i.e. HTTP Basic or Digest auth) */
@protocol CBLCredentialAuthorizer <CBLAuthorizer>

@property (readonly) NSURLCredential* credential;

@end



/** Authorizer that adds custom headers to an HTTP request */
@protocol CBLCustomHeadersAuthorizer <CBLAuthorizer>

/** May add a header to the request (usually "Authorization:") to convey the authorization token.
    @param request  The URL request to authenticate.
    @return YES if it added authorization. */
- (BOOL) authorizeURLRequest: (NSMutableURLRequest*)request;

@end


/** Authorizer that sends a login request. */
@protocol CBLLoginAuthorizer <CBLAuthorizer>

/** Returns the HTTP method, URL, and body of the login request to send, or nil for no login.
    @return  An array of the form @[method, path, body]. The path may be absolute, or relative to
                the authorizer's remote URL. Return nil to skip the login. */
- (NSArray*) loginRequest;

@optional

/** The replicator calls this method with the response to the login request. It then waits for the
    authorizer to call the continuation callback, before proceeding.
    @param jsonResponse  The parsed JSON body of the response.
    @param headers  The HTTP response headers.
    @param error  The error, if the request failed.
    @param continuationBlock  The authorizer must call this block at some future time. If the
            `loginAgain` parameter is YES, the login will be repeated, with another call to
            -loginRequestForSite:. If the NSError* parameter is non-nil, replication stops. */
- (void) loginResponse: (NSDictionary*)jsonResponse
               headers: (NSDictionary*)headers
                 error: (NSError*)error
          continuation: (void (^)(BOOL loginAgain, NSError*))continuationBlock;

@end


/** This protocol is just a marker that the authorizer uses a session cookie. */
@protocol CBLSessionCookieAuthorizer <CBLLoginAuthorizer>
@end


/** Simple implementation of CBLCredentialAuthorizer that supports HTTP Basic auth. */
@interface CBLPasswordAuthorizer : CBLAuthorizer <CBLCredentialAuthorizer, CBLCustomHeadersAuthorizer>

- (instancetype) initWithUser: (NSString*)user password: (NSString*)password;

/** Initialize given a credential object that contains a username and password. */
- (instancetype) initWithCredential: (NSURLCredential*)credential;

/** Initialize given a URL alone -- will use a baked-in username/password in the URL,
    or look up a credential from the keychain. */
- (instancetype) initWithURL: (NSURL*)url;

@end



#pragma mark - SSL CERT/TRUST UTILITIES:

/** Sets the global list of anchor certs to be used by CBLCheckSSLServerTrust. */
void CBLSetAnchorCerts(NSArray* certs, BOOL onlyThese);

/** Checks server trust, using the global list of anchor certs. */
BOOL CBLCheckSSLServerTrust(SecTrustRef trust, NSString* host, UInt16 port, NSData *pinned);

/** Forces a SecTrustRef's result to be a success. */
BOOL CBLForceTrusted(SecTrustRef trust);
