//
//  CBLListener.h
//  CouchbaseLiteListener
//
//  Created by Jens Alfke on 12/29/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Security/SecBase.h>
@class CBLManager;
@protocol CBLListenerDelegate;


#if __has_feature(nullability)
#  ifndef NS_ASSUME_NONNULL_BEGIN
// Xcode 6.3:
#    define NS_ASSUME_NONNULL_BEGIN _Pragma("clang assume_nonnull begin")
#    define NS_ASSUME_NONNULL_END   _Pragma("clang assume_nonnull end")
#  endif
#else
// Xcode 6.2 and earlier:
#  define NS_ASSUME_NONNULL_BEGIN
#  define NS_ASSUME_NONNULL_END
#  define nullable
#  define __nullable
#endif


NS_ASSUME_NONNULL_BEGIN


/** A simple HTTP server that provides remote access to the CouchbaseLite REST API. */
@interface CBLListener : NSObject

/** Initializes a CBLListener.
    @param manager  The CBLManager whose databases to serve.
    @param port  The TCP port number to listen on. Use 0 to automatically pick an available port (you can get the port number after the server starts by getting the .port property.) */
- (instancetype) initWithManager: (CBLManager*)manager port: (UInt16)port;

/** The TCP port number that the listener is listening on.
    If the listener has not yet started, this will return 0. */
@property (readonly) UInt16 port;

@property (weak, nullable) id<CBLListenerDelegate> delegate;


/** Sets the Bonjour service name and type to advertise as.
    @param name  The service name; this can be arbitrary but is generally the device user's name. An empty string will be mapped to the device's name.
    @param type  The service type; the type of a generic HTTP server is "_http._tcp." but you should use something more specific. */
- (void) setBonjourName: (nullable NSString*)name type: (nullable NSString*)type;

/** The published Bonjour service name. Nil until the server has started. Usually this is the same
    as the name you specified in -setBonjourName:type:, but if there's
    already a service with the same name on the network, your name may have a suffix appended. */
@property (readonly, nullable) NSString* bonjourName;

/** Bonjour metadata associated with the service. Changes will be visible almost immediately.
    The keys are NSStrings and values are NSData. Total size should be kept small (under 1kbyte if possible) as this data is multicast over UDP. */
@property (copy, nullable) NSDictionary* TXTRecordDictionary;

/** The URL at which the listener can be reached from another computer/device.
    This URL will only work for _local_ clients, i.e. over the same WiFi LAN or over Bluetooth.
    Allowing remote clients to connect is a difficult task that involves traversing routers or
    firewalls and translating local to global IP addresses, and it's generally impossible over
    cell networks because telcos don't allow incoming IP connections to mobile devices. */
@property (readonly, nullable) NSURL* URL;


/** If set to YES, remote requests will not be allowed to make any changes to the server or its databases. */
@property BOOL readOnly;


#pragma mark - AUTHENTICATION:

/** If set to YES, all requests will be required to authenticate.
    Setting the .passwords property automatically enables this.*/
@property BOOL requiresAuth;

/** Security realm string to return in authentication challenges. */
@property (copy, nullable) NSString* realm;

/** Sets user names and passwords for authentication.
    @param passwords  A dictionary mapping user names to passwords. */
- (void) setPasswords: (nullable NSDictionary*)passwords;

/** Returns the password assigned to a user name, or nil if the name is not recognized. */
- (nullable NSString*) passwordForUser: (NSString*)username;


#pragma mark - SSL:

/** Private key and certificate to use for incoming SSL connections.
    If nil (the default) SSL connections are not accepted. */
@property (nonatomic, nullable) SecIdentityRef SSLIdentity;

/** Supporting certificates to use along with the SSLIdentity. Necessary if the SSL certificate
    is not directly signed by a CA cert known to the OS. */
@property (strong, nonatomic, nullable) NSArray* SSLExtraCertificates;

/** The SHA-1 digest of the SSL identity's certificate, which can be used as a unique 'fingerprint'
    of the identity. For example, you can send this digest to someone else over an existing secure
    channel (like iMessage or a QR code) and the recipient can then make an SSL connection to this
    listener and verify its identity by comparing digests. */
@property (readonly, nullable) NSData* SSLIdentityDigest;

/** Generates an anonymous identity with a 2048-bit RSA key-pair and sets it as the SSL identity.
    It's anonymous in that it's self-signed and the "subject" and "issuer" strings are just fixed
    placeholders; this makes it less useful for identification, but it still provides encryption
    of the HTTP traffic.
    The certificate and key are stored in the keychain under the given label; if they already exist
    and haven't expired, the existing identity will be used instead of creating a new one. */
- (BOOL) setAnonymousSSLIdentityWithLabel: (NSString*)label
                                    error: (NSError**)outError;


#pragma mark - START / STOP:

/** Starts the listener. */
- (BOOL) start: (NSError**)outError;

/** Stops the listener. */
- (void) stop;

@end



@protocol CBLListenerDelegate <NSObject>
@optional

/** Authenticates a connection with an SSL client certificate.
    If this method is not implemented, any client cert is accepted.
    @param address  The IP address of the peer.
    @param trust  An already-evaluated SecTrustRef. You can look at its result and certificate
                    chain to make your decision.
    @return  A user name, or nil to reject the connection. If you don't use user names in your
                    app, just return an empty string. */
- (nullable NSString*) authenticateConnectionFromAddress: (NSData*)address
                                               withTrust: (nullable SecTrustRef)trust;

/** Authenticates a request that uses Basic or Digest authentication.
    If this method is not implemented, the `passwords` dictionary registered with the CBLListener
    is consulted instead.
    @param username  The user name presented by the client.
    @return  The password for this user, or nil to reject the request. */
- (nullable NSString*) passwordForUser: (NSString*)username;

@end


NS_ASSUME_NONNULL_END
