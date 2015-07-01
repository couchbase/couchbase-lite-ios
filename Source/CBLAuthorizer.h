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
@protocol CBLPasswordAuthorizer <CBLAuthorizer>

@property NSURLCredential* credential;

@end



/** Authorizer that adds custom headers to an HTTP request */
@protocol CBLCustomAuthorizer <CBLAuthorizer>

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
@interface CBLPasswordAuthorizer : NSObject <CBLPasswordAuthorizer>

/** Initialize given a credential object that contains a username and password. */
- (instancetype) initWithCredential: (NSURLCredential*)credential;

/** Initialize given a URL alone -- will use a baked-in username/password in the URL,
    or look up a credential from the keychain. */
- (instancetype) initWithURL: (NSURL*)url;

@end



#if 0 // UNUSED
/** Implementation of CBLAuthorizer that supports MAC authorization as used in OAuth 2. */
@interface CBLMACAuthorizer : NSObject <CBLCustomAuthorizer>
{
@private
    NSString *_key, *_identifier;
    NSDate* _issueTime;
    NSData* (*_hmacFunction)(NSData*, NSData*);

}

/** Initialize given MAC credentials */
- (instancetype) initWithKey: (NSString*)key
                  identifier: (NSString*)identifier
                   algorithm: (NSString*)algorithm
                   issueTime: (NSDate*)issueTime;

@end
#endif



void CBLSetAnchorCerts(NSArray* certs, BOOL onlyThese);
BOOL CBLCheckSSLServerTrust(SecTrustRef trust, NSString* host, UInt16 port);
