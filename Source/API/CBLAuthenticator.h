//
//  CBLAuthenticator.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 4/11/14.
//  Copyright (c) 2014 Couchbase, Inc. All rights reserved.


#import "CBLBase.h"

NS_ASSUME_NONNULL_BEGIN


/** The CBLAuthenticator protocol defines objects that can authenticate a user to a remote database
    server. An object conforming to this protocol is acquired from the CBLAuthenticator _class_'s
    factory methods, and is used by setting it as a CBLReplication's .authenticator property.
    This protocol is currently entirely opaque and not intended for applications to implement.
    The authenticator types are limited to those createable by factory methods. */
@protocol CBLAuthenticator <NSObject>
@end


/** The CBLAuthenticator class provides factory methods for creating authenticator objects, for use
    with the .authenticator property of a CBLReplication. */
@interface CBLAuthenticator : NSObject

/** Creates an authenticator that will log in using HTTP Basic auth with the given user name and
    password. This should only be used over an SSL/TLS connection, as otherwise it's very easy for
    anyone sniffing network traffic to read the password. */
+ (id<CBLAuthenticator>) basicAuthenticatorWithName: (NSString*)name
                                           password: (NSString*)password;

/** Creates an authenticator that will authenticate to a Couchbase Sync Gateway server using
    Facebook credentials. The token string must be an active Facebook login token. On iOS you can
    acquire one from the Accounts framework, or you can use Facebook's SDK to implement the
    login process. */
+ (id<CBLAuthenticator>) facebookAuthenticatorWithToken: (NSString*)token;

/** Creates an authenticator that will authenticate to a Couchbase Sync Gateway server using the
    user's email address, with the Persona protocol (http://persona.org). The "assertion" token
    must have been acquired using the client-side Persona auth procedure; you can use the library
    https://github.com/couchbaselabs/browserid-ios to do this. */
+ (id<CBLAuthenticator>) personaAuthenticatorWithAssertion: (NSString*)assertion;

/** Creates an authenticator that will authenticate to a CouchDB server using OAuth version 1.
    The parameters must have been acquired using the client-side OAuth login procedure. There are
    several iOS and Mac implementations of this, such as
    https://github.com/couchbaselabs/ios-oauthconsumer */
+ (id<CBLAuthenticator>) OAuth1AuthenticatorWithConsumerKey: (NSString*)consumerKey
                                             consumerSecret: (NSString*)consumerSecret
                                                      token: (NSString*)token
                                                tokenSecret: (NSString*)tokenSecret
                                            signatureMethod: (NSString*)signatureMethod;

/** Creates an authenticator that uses an SSL/TLS client certificate.
    @param identity  The identity certificate plus private key
    @param certs  Any additional CA certs needed to establish the chain of authority. */
+ (id<CBLAuthenticator>) SSLClientCertAuthenticatorWithIdentity: (SecIdentityRef)identity
                                                supportingCerts: (nullable NSArray*)certs;

+ (nullable id<CBLAuthenticator>) SSLClientCertAuthenticatorWithAnonymousIdentity: (NSString*)label;

- (instancetype) init NS_UNAVAILABLE;

@end



NS_ASSUME_NONNULL_END
