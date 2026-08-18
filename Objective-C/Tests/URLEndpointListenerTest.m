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
#import <Security/Security.h>
#import "CollectionUtils.h"
#import "URLEndpointListenerTest.h"

@implementation CBLURLEndpointListener (Test)

- (NSURL*) localURL {
    assert(self.port > 0);
    NSURLComponents* comps = [[NSURLComponents alloc] init];
    comps.scheme = self.config.disableTLS ? @"ws" : @"wss";
    comps.host = @"localhost";
    comps.port = @(self.port);
    comps.path = $sprintf(@"/%@",((CBLCollection*)self.config.collections.firstObject).database.name);
    return comps.URL;
}

- (CBLURLEndpoint*) localEndpoint {
    return [[CBLURLEndpoint alloc] initWithURL: self.localURL];
}

@end

@implementation URLEndpointListenerTest

- (void) setUp {
    [super setUp];

    [self cleanUpAnonymousIdentities];
}

- (void) tearDown {
    [self stopListen];
    [self cleanUpAnonymousIdentities];
    [self cleanUpTLSIdentityForServer: YES];
    [self cleanUpTLSIdentityForServer: NO];
    
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
    Config* config = [[Config alloc] initWithCollections: @[self.otherDBDefaultCollection]];
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
    [listener stop];
}

- (CBLReplicator*) replicator: (CBLDatabase*)db
                    continous: (BOOL)continous
                       target: (id<CBLEndpoint>)target
                   serverCert: (nullable SecCertificateRef)cert {
    CBLReplicatorConfiguration* c;
    CBLCollectionConfiguration* defaultConfig = [[CBLCollectionConfiguration alloc] initWithCollection: self.defaultCollection];
    c = [[CBLReplicatorConfiguration alloc] initWithCollections: @[defaultConfig] target: target];
    c.continuous = continous;
    c.pinnedServerCertificate = cert;
    return [[CBLReplicator alloc] initWithConfig: c];
}

- (CBLReplicatorConfiguration*) configForCollection:(CBLCollection*)collection
                                             target:(id<CBLEndpoint>)target
                                        configBlock:(nullable void (^)(CBLCollectionConfiguration *config))block {
    
    CBLCollectionConfiguration* colConfig = [[CBLCollectionConfiguration alloc] initWithCollection:collection];
    
    if (block) {
        block(colConfig);
    }
    
    return [[CBLReplicatorConfiguration alloc] initWithCollections:@[colConfig] target:target];
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
    [self cleanUpTLSIdentityForServer: isServer];
    
    // Create server/client identity:
    NSError* err;
    NSString* label = isServer ? kServerCertLabel : kClientCertLabel;
    NSDictionary* attrs = @{ kCBLCertAttrCommonName: isServer ? @"CBL-Server" : @"daniel" };
    CBLKeyUsages keyUsages = isServer ? kCBLKeyUsagesServerAuth : kCBLKeyUsagesClientAuth;
    CBLTLSIdentity* identity = [CBLTLSIdentity createIdentityForKeyUsages: keyUsages
                                                               attributes: attrs
                                                               expiration: nil
                                                                    label: label
                                                                    error: &err];
    AssertNotNil(identity);
    AssertNil(err);
    return identity;
}

- (void) cleanUpTLSIdentityForServer: (BOOL)isServer {
    if (!self.keyChainAccessAllowed) return;
    
    // Delete directly from the keychain by label so that partial identities
    // (e.g. a leftover certificate without its key) get cleaned up as well:
    NSString* label = isServer ? kServerCertLabel : kClientCertLabel;
    for (id itemClass in @[(id)kSecClassIdentity, (id)kSecClassCertificate]) {
        NSDictionary* query = @{(id)kSecClass: itemClass,
                                (id)kSecAttrLabel: label};
        OSStatus status = SecItemDelete((CFDictionaryRef)query);
        Assert(status == errSecSuccess || status == errSecItemNotFound || status == errSecInvalidItemRef ||
               status == errSecWrPerm /* items in a keychain that tests cannot modify (e.g. Local Items) */,
               @"Couldn't delete keychain items with label %@ (OSStatus = %d)", label, (int)status);
    }
}

- (void) releaseCF: (CFTypeRef)ref {
    if (ref != NULL) CFRelease(ref);
}

static NSString* sDiscoveredAnonymousIdentityCommonName;

- (nullable NSString*) anonymousIdentityCommonName {
    if (sDiscoveredAnonymousIdentityCommonName)
        return sDiscoveredAnonymousIdentityCommonName;
    if (!self.keyChainAccessAllowed)
        return nil;

    // Start a TLS listener without an identity on an ephemeral port; the product
    // mints an anonymous identity whose certificate carries the common name. The
    // autorelease pool ensures that the listener's transient objects are freed
    // before the LiteCore object leak check runs at tearDown:
    NSString* name = nil;
    @autoreleasepool {
        Config* config = [[Config alloc] initWithCollections: @[self.otherDBDefaultCollection]];
        Listener* listener = [[Listener alloc] initWithConfig: config];
        NSError* error;
        if ([listener startWithError: &error]) {
            NSArray* certs = listener.tlsIdentity.certs;
            if (certs.count > 0) {
                name = CFBridgingRelease(SecCertificateCopySubjectSummary((__bridge SecCertificateRef)certs[0]));
            }
            [listener stop];
        }
    }
    if (!name)
        return nil;

    sDiscoveredAnonymousIdentityCommonName = name;
    return name;
}

- (void) cleanUpAnonymousIdentities {
    if (!self.keyChainAccessAllowed)
        return;

    NSString* anonymousIdentityCommonName = [self anonymousIdentityCommonName];
    if (!anonymousIdentityCommonName)
        return;

    [self ignoreException: ^{
        NSDictionary* query = @{(id)kSecClass: (id)kSecClassIdentity,
                                (id)kSecMatchLimit: (id)kSecMatchLimitAll,
                                (id)kSecReturnRef: @YES};
        CFTypeRef result = NULL;
        OSStatus status = SecItemCopyMatching((CFDictionaryRef)query, &result);
        if (status == errSecItemNotFound)
            return;
        Assert(status == errSecSuccess, @"Cannot query identities (OSStatus = %d)", (int)status);
        NSArray* identities = CFBridgingRelease(result);
        for (id identityObj in identities) {
            SecIdentityRef identityRef = (__bridge SecIdentityRef)identityObj;
            SecCertificateRef certRef = NULL;
            if (SecIdentityCopyCertificate(identityRef, &certRef) != errSecSuccess || !certRef)
                continue;
            NSString* name = CFBridgingRelease(SecCertificateCopySubjectSummary(certRef));
            CFRelease(certRef);
            if ([name isEqualToString: anonymousIdentityCommonName]) {
                NSDictionary* del = @{(id)kSecClass: (id)kSecClassIdentity,
                                      (id)kSecValueRef: identityObj};
                status = SecItemDelete((CFDictionaryRef)del);
                Assert(status == errSecSuccess || status == errSecItemNotFound || status == errSecInvalidItemRef,
                       @"Cannot delete anonymous identity (OSStatus = %d)", (int)status);
            }
        }

        // Deleting an identity doesn't remove its certificate; sweep the anonymous
        // certificates (including any orphaned by previously interrupted test runs):
        query = @{(id)kSecClass: (id)kSecClassCertificate,
                  (id)kSecMatchLimit: (id)kSecMatchLimitAll,
                  (id)kSecReturnRef: @YES};
        result = NULL;
        status = SecItemCopyMatching((CFDictionaryRef)query, &result);
        if (status == errSecItemNotFound)
            return;
        Assert(status == errSecSuccess, @"Cannot query certificates (OSStatus = %d)", (int)status);
        NSArray* certs = CFBridgingRelease(result);
        for (id certObj in certs) {
            NSString* name = CFBridgingRelease(
                SecCertificateCopySubjectSummary((__bridge SecCertificateRef)certObj));
            if ([name isEqualToString: anonymousIdentityCommonName]) {
                NSDictionary* del = @{(id)kSecClass: (id)kSecClassCertificate,
                                      (id)kSecValueRef: certObj};
                status = SecItemDelete((CFDictionaryRef)del);
                Assert(status == errSecSuccess || status == errSecItemNotFound || status == errSecInvalidItemRef,
                       @"Cannot delete anonymous certificate (OSStatus = %d)", (int)status);
            }
        }
    }];
}

@end
