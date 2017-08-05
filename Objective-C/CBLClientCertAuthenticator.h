//
//  CBLClientCertAuthenticator.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 7/27/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLAuthenticator.h"
#import <Security/Security.h>

NS_ASSUME_NONNULL_BEGIN

/** 
 An authenticator that presents a client certificate to the server during the initial SSL/TLS
 handshake. This requires access to both the X.509 certificate and the matching private key.
 Apple's security APIs refer to such a (certificate, key) pair as an "identity", typed as a
 SecIdentityRef.
 */
@interface CBLClientCertAuthenticator : CBLAuthenticator

/** 
 Looks up an identity with the given ID, in the Keychain. If found, initializes the
 authenticator with it; otherwise returns nil.
 
 @param identityID A string identifying the identity in the Keychain. on iOS this is the
                   Keychain item's "label" property; on macOS it's the preference name as used by
                   SecIdentityCopyPreferred(), etc.
 */
- (nullable instancetype) initWithIdentityID: (NSString*)identityID;

/** The identity reference that will be presented during SSL/TLS authentication. */
@property (readonly, atomic, nullable) SecIdentityRef identity;

@end

NS_ASSUME_NONNULL_END

