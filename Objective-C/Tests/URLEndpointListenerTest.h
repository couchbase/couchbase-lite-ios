//
//  URLEndpointListenerTest.h
//  CouchbaseLite
//
//  Copyright (c) 2022 Couchbase, Inc All rights reserved.
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

#import "ReplicatorTest.h"
#import "CBLURLEndpointListenerConfiguration.h"
#import "CBLURLEndpointListener.h"

#define kWsPort 4984
#define kWssPort 4985

#define kServerCertLabel @"CBL-Server-Cert"
#define kClientCertLabel @"CBL-Client-Cert"

NS_ASSUME_NONNULL_BEGIN

@interface CBLURLEndpointListener (Test)

@property (nonatomic, readonly) NSURL* localURL;
@property (nonatomic, readonly) CBLURLEndpoint* localEndpoint;

@end

API_AVAILABLE(macos(10.12), ios(10.0))
typedef CBLURLEndpointListenerConfiguration Config;

API_AVAILABLE(macos(10.12), ios(10.0))
typedef CBLURLEndpointListener Listener;

API_AVAILABLE(macos(10.12), ios(10.0))
@interface URLEndpointListenerTest : ReplicatorTest {
    CBLURLEndpointListener* _listener;
}

@property (nonatomic, readonly) NSURL* localURL;
@property (nonatomic, readonly) CBLURLEndpoint* localEndpoint;

/**
 Create a Listener with the passed in configuration.
 \Note Use `_listener` handle for accessing newly created listener
 @param config Configuration used to create the listener.
 @param code Expected error code
 @param domain Expected error domain */
- (Listener*) listen: (Config*)config errorCode: (NSInteger)code errorDomain: (nullable NSString*)domain;

/**
 Create a Listener
 \Note Use `_listener` handle for accessing newly created listener
 @param tls enable/disable TLS 
 @param auth pass the Authenticator if necessary, else nil.*/
- (Listener*) listenWithTLS: (BOOL)tls auth: (nullable id<CBLListenerAuthenticator>)auth;

/**
 Stops the listener. */
- (void) stopListen;

/**
 Stops the passed in listener. */
- (void) stopListener: (CBLURLEndpointListener*)listener;

/**
 Deletes the passed in identity from the keychain  */
- (void) deleteFromKeyChain: (CBLTLSIdentity*)identity;

@end

NS_ASSUME_NONNULL_END
