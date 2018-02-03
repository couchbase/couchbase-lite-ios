//
//  CBLClientCertAuthenticator.h
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
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

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

