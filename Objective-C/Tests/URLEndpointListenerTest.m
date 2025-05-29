//
//  URLEndpointListenerTest.m
//  CouchbaseLite
//
//  Copyright (c) 2020 Couchbase, Inc All rights reserved.
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
#import "CBLTLSIdentity+Internal.h"
#import "CBLURLEndpointListener+Internal.h"
#import "CBLURLEndpointListenerConfiguration.h"
#import "CollectionUtils.h"
#import "URLEndpointListenerTest.h"

@implementation CBLURLEndpointListener (Test)

// TODO: Remove https://issues.couchbase.com/browse/CBL-3206
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

- (NSURL*) localURL {
    assert(self.port > 0);
    NSURLComponents* comps = [[NSURLComponents alloc] init];
    comps.scheme = self.config.disableTLS ? @"ws" : @"wss";
    comps.host = @"localhost";
    comps.port = @(self.port);
    comps.path = $sprintf(@"/%@",self.config.database.name);
    return comps.URL;
}

- (CBLURLEndpoint*) localEndpoint {
    return [[CBLURLEndpoint alloc] initWithURL: self.localURL];
}

@end

@implementation URLEndpointListenerTest

- (void) setUp {
    [super setUp];
    
    XCTSkip(@"CBL-7038 : Stop URLEndpointListener may crash as recursive_mutex lock failed");
    
    timeout = 15.0;
    [self cleanUpIdentities];
}

- (void) tearDown {
    [self stopListen];
    [self cleanUpIdentities];
    
    [super tearDown];
}

#pragma mark - Helper methods

- (Listener*) listen {
    return [self listenWithTLS: YES];
}

- (Listener*) listenWithTLS: (BOOL)tls {
    return [self listenWithTLS: tls auth: nil];
}

- (Listener*) listenWithTLS: (BOOL)tls auth: (id<CBLListenerAuthenticator>)auth {
    // Stop:
    if (_listener) {
        [_listener stop];
    }
    
    // Listener:
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    config.port = tls ? kWssPort : kWsPort;
    config.disableTLS = !tls;
    config.authenticator = auth;
    
    return [self listen: config];
}

- (Listener*) listen: (Config*)config {
    return [self listen: config errorCode: 0 errorDomain: nil];
}

- (Listener*) listen: (Config*)config errorCode: (NSInteger)code errorDomain: (nullable NSString*)domain  {
    // Stop:
    if (_listener) {
        [_listener stop];
    }
    
    _listener = [[Listener alloc] initWithConfig: config];
    
    // Start:
    NSError* err = nil;
    BOOL success = [_listener startWithError: &err];
    Assert(success == (code == 0));
    if (code != 0) {
        AssertEqual(err.code, code);
        if (domain)
            AssertEqualObjects(err.domain, domain);
    } else
        AssertNil(err);
    
    return _listener;
}

- (void) stopListen {
    if (_listener) {
        [self stopListener: _listener];
    }
    _listener = nil;
}

- (void) stopListener: (CBLURLEndpointListener*)listener {
    CBLTLSIdentity* identity = listener.tlsIdentity;
    [listener stop];
    if (identity && self.keyChainAccessAllowed) {
        [self deleteFromKeyChain: identity];
    }
}

- (void) deleteFromKeyChain: (CBLTLSIdentity*)identity {
    [self ignoreException:^{
        NSError* error;
        Assert([identity deleteFromKeyChainWithError: &error],
               @"Couldn't delete identity: %@", error);
    }];
}

- (CBLReplicator*) replicator: (CBLDatabase*)db
                    continous: (BOOL)continous
                       target: (id<CBLEndpoint>)target
                   serverCert: (nullable SecCertificateRef)cert {
    CBLReplicatorConfiguration* c;
    c = [[CBLReplicatorConfiguration alloc] initWithDatabase: db target: target];
    c.continuous = continous;
    c.pinnedServerCertificate = cert;
    return [[CBLReplicator alloc] initWithConfig: c];
}

- (void) checkEqualForCert: (SecCertificateRef)cert1 andCert: (SecCertificateRef)cert2 {
    if (@available(macOS 10.5, *)) {
        CFStringRef cnRef1, cnRef2;
        AssertEqual(SecCertificateCopyCommonName(cert1, &cnRef1), errSecSuccess);
        AssertEqual(SecCertificateCopyCommonName(cert2, &cnRef2), errSecSuccess);
        
        NSString* cn1 = (NSString*)CFBridgingRelease(cnRef1);
        NSString* cn2 = (NSString*)CFBridgingRelease(cnRef2);
        AssertEqualObjects(cn1, cn2);
    }
}

- (CBLTLSIdentity*) tlsIdentity: (BOOL)isServer {
    if (!self.keyChainAccessAllowed) return nil;
    
    // Cleanup:
    [self cleanupTLSIdentity: isServer];
    
    // Create server/client identity:
    NSError* err;
    NSString* label = isServer ? kServerCertLabel : kClientCertLabel;
    NSDictionary* attrs = @{ kCBLCertAttrCommonName: isServer ? @"CBL-Server" : @"daniel" };
    CBLKeyUsages keyUsages = isServer ? kCBLKeyUsagesServerAuth : kCBLKeyUsagesClientAuth;
    CBLTLSIdentity* identity = [CBLTLSIdentity createIdentityForKeyUsages: keyUsages
                                                               attributes: attrs
                                                               expiration: nil
                                                                   issuer: nil
                                                                    label: label
                                                                    error: &err];
    AssertNotNil(identity);
    AssertNil(err);
    return identity;
}

- (void) cleanupTLSIdentity: (BOOL)isServer {
    if (!self.keyChainAccessAllowed) return;
    
    NSError* err;
    NSString* label = isServer ? kServerCertLabel : kClientCertLabel;
    Assert([CBLTLSIdentity deleteIdentityWithLabel: label error: &err]);
}

- (void) releaseCF: (CFTypeRef)ref {
    if (ref != NULL) CFRelease(ref);
}

- (void) cleanUpIdentities {
    if (self.keyChainAccessAllowed) {
        [self ignoreException: ^{
            NSError* error;
            Assert([CBLURLEndpointListener deleteAnonymousIdentitiesWithError: &error],
                   @"Cannot delete anonymous identity: %@", error);
        }];
    }
}

#pragma clang diagnostic pop

@end
