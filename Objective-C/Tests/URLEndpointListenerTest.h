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
#import "CBLURLEndpointListener+Internal.h"

#define kWsPort 4084
#define kWssPort 4085

#define kServerCertLabel @"CBL-Server-Cert"
#define kClientCertLabel @"CBL-Client-Cert"

typedef CBLURLEndpointListenerConfiguration Config;

typedef CBLURLEndpointListener Listener;

NS_ASSUME_NONNULL_BEGIN

@interface URLEndpointListenerTest : ReplicatorTest {
    CBLURLEndpointListener* _listener;
}

// listener management methods
- (Listener*) listen;
- (Listener*) listen: (Config*)config;
- (Listener*) listenWithTLS: (BOOL)tls;
- (Listener*) listenWithTLS: (BOOL)tls auth: (nullable id<CBLListenerAuthenticator>)auth;
- (Listener*) listen: (Config*)config errorCode: (NSInteger)code errorDomain: (nullable NSString*)domain;

- (void) stopListen;
- (void) stopListener: (CBLURLEndpointListener*)listener;

// TLS Identity management
- (CBLTLSIdentity*) tlsIdentity: (BOOL)isServer;
- (void) cleanupTLSIdentity: (BOOL)isServer;
- (void) deleteFromKeyChain: (CBLTLSIdentity*)identity;

// replicator methods
- (CBLReplicator*) replicator: (CBLDatabase*)db
                    continous: (BOOL)continous
                       target: (id<CBLEndpoint>)target
                   serverCert: (nullable SecCertificateRef)cert;

// helpers
- (void) checkEqualForCert: (SecCertificateRef)cert1 andCert: (SecCertificateRef)cert2;
- (void) releaseCF: (CFTypeRef)ref;

@end

@interface CBLURLEndpointListener (Test)

- (NSURL*) localURL;
- (CBLURLEndpoint*) localEndpoint;

@end

NS_ASSUME_NONNULL_END
