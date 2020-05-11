//
//  TLSIdentityTest.m
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

#import "CBLTestCase.h"
#import "CBLTLSIdentity+Internal.h"

API_AVAILABLE(macos(10.12), ios(10.0))
@interface TLSIdentityTest : CBLTestCase

@end

#define kServerCertLabel @"CBL-Server-Cert"
#define kClientCertLabel @"CBL-Client-Cert"

@implementation TLSIdentityTest

- (CFTypeRef) findInKeyChain: (NSDictionary*)params {
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)params, &result);
    if (status != errSecSuccess) {
        if (status == errSecItemNotFound)
            return nil;
        else
            NSLog(@"Couldn't get an item from the Keychain: %@ (error: %d)", params, status);
    }
    Assert(result != nil);
    return result;
}

- (NSData*) publicKeyHashFromCert: (SecCertificateRef)certRef {
    // Get public key from the certificate:
    SecKeyRef publicKeyRef;
    if (@available(iOS 12, macOS 10.14, *)) {
        publicKeyRef = SecCertificateCopyKey(certRef);
    } else {
    #if TARGET_OS_IOS
        if (@available(iOS 10.3, *))
            publicKeyRef = SecCertificateCopyPublicKey(certRef);
        else
            Assert(false, @"Not Supported by this OS version");
    #else
        OSStatus status = SecCertificateCopyPublicKey(certRef, &publicKeyRef);
        Assert(status == errSecSuccess);
    #endif
    }
    Assert(publicKeyRef);
                
    if (@available(iOS 10.0, macOS 10.12, *)) {
        NSDictionary* attrs = CFBridgingRelease(SecKeyCopyAttributes(publicKeyRef));
        return [attrs objectForKey: (id)kSecAttrApplicationLabel];
    } else {
        Assert(false, @"Not Supported by this OS version");
    }
    return nil;
}

- (void) checkIdentityInKeyChain: (CBLTLSIdentity*)identity {
    NSArray* certs = identity.certs;
    Assert(certs.count > 0);
    
    // Check Certificate:
    SecCertificateRef certRef = (__bridge SecCertificateRef)certs[0];

    // Check Private Key:
    NSData* publicKeyHash = [self publicKeyHashFromCert: certRef];
    SecKeyRef privateKeyRef = (SecKeyRef)[self findInKeyChain: @{
        (id)kSecClass:                  (id)kSecClassKey,
        (id)kSecAttrKeyType:            (id)kSecAttrKeyTypeRSA,
        (id)kSecAttrKeyClass:           (id)kSecAttrKeyClassPrivate,
        (id)kSecAttrApplicationLabel:   publicKeyHash,
        (id)kSecReturnRef:              @YES
    }];
    Assert(privateKeyRef != nil);
    
    // Get public key from Cert via Trust:
    SecTrustRef trustRef;
    SecTrustCreateWithCertificates(certRef, SecPolicyCreateBasicX509(), &trustRef);
    SecKeyRef publicKeyRef = SecTrustCopyPublicKey(trustRef);
    Assert(publicKeyRef != nil);
    
    CFErrorRef errRef = nil;
    NSData* publicKeyData = CFBridgingRelease(SecKeyCopyExternalRepresentation(publicKeyRef, &errRef));
    Assert(errRef == nil);
    AssertNotNil(publicKeyData);
    Assert(publicKeyData.length > 0);
    NSLog(@"%lu", (unsigned long)publicKeyData.length);
}

/** For Debugging */
- (void) printItemsInKeyChain {
    NSArray *classes = @[(id)kSecClassKey, (id)kSecClassCertificate, (id)kSecClassIdentity];
    for (id clazz in classes) {
        NSLog(@">>>> Class: %@", clazz);
        CFArrayRef itemsRef = (CFArrayRef)[self findInKeyChain: @{
            (id)kSecClass:              clazz,
            (id)kSecReturnAttributes:   @YES,
            (id)kSecMatchLimit:         (id)kSecMatchLimitAll
        }];
        if (itemsRef == nil)
            NSLog(@" > No Items");
        
        NSArray* items = (NSArray*)CFBridgingRelease(itemsRef);
        NSInteger i = 0;
        for (NSDictionary* dict in items) {
            NSLog(@" >> Item #(%ld): ", (long)(++i));
            for (NSString* key in [dict allKeys]) {
                NSLog(@"     %@ = %@", key, dict[key]);
            }
        }
    }
}

- (void) setUp {
    [super setUp];
    Assert([CBLTLSIdentity deleteIdentityWithLabel: kServerCertLabel error: nil]);
    Assert([CBLTLSIdentity deleteIdentityWithLabel: kClientCertLabel error: nil]);
}

- (void) tearDown {
    [super tearDown];
    Assert([CBLTLSIdentity deleteIdentityWithLabel: kServerCertLabel error: nil]);
    Assert([CBLTLSIdentity deleteIdentityWithLabel: kClientCertLabel error: nil]);
}

- (void) testCreateGetDeleteServerIdentity {
    if (!self.hasHostApp) return;
    
    NSError* error;
    CBLTLSIdentity* identity;
    
    // Delete:
    Assert([CBLTLSIdentity deleteIdentityWithLabel: kServerCertLabel error: &error]);
    AssertNil(error);
    
    // Get:
    identity = [CBLTLSIdentity identityWithLabel: kServerCertLabel error: &error];
    AssertNil(identity);
    AssertNil(error);
    
    // Create:
    NSDictionary* attrs = @{ kCBLCertAttrCommonName: @"CBL-Server" };
    identity = [CBLTLSIdentity createIdentityForServer: YES
                                            attributes: attrs
                                            expiration: nil
                                                 label: kServerCertLabel
                                                 error: &error];
    AssertNotNil(identity);
    AssertNil(error);
    AssertEqual(identity.certs.count, 1);
    [self checkIdentityInKeyChain: identity];
    
    // Get:
    identity = [CBLTLSIdentity identityWithLabel: kServerCertLabel error: &error];
    AssertNotNil(identity);
    AssertNil(error);
    AssertEqual(identity.certs.count, 1);
    [self checkIdentityInKeyChain: identity];
    
    // Delete:
    Assert([CBLTLSIdentity deleteIdentityWithLabel: kServerCertLabel error: &error]);
    AssertNil(error);
    
    // Get:
    identity = [CBLTLSIdentity identityWithLabel: kServerCertLabel error: &error];
    AssertNil(identity);
    AssertNil(error);
}

- (void) testCreateDuplicateServerIdentity {
    if (!self.hasHostApp) return;
    
    NSError* error;
    __block CBLTLSIdentity* identity;
    
    // Create:
    NSDictionary* attrs = @{ kCBLCertAttrCommonName: @"CBL-Server" };
    identity = [CBLTLSIdentity createIdentityForServer: YES
                                            attributes: attrs
                                            expiration: nil
                                                 label: kServerCertLabel
                                                 error: &error];
    AssertNotNil(identity);
    AssertNil(error);
    [self checkIdentityInKeyChain: identity];
    
    // Get:
    identity = [CBLTLSIdentity identityWithLabel: kServerCertLabel error: &error];
    AssertNotNil(identity);
    AssertNil(error);
    [self checkIdentityInKeyChain: identity];
    
    // Create again with the same label:
    identity = [CBLTLSIdentity createIdentityForServer: YES
                                            attributes: attrs
                                            expiration: nil
                                                 label: kServerCertLabel
                                                 error: &error];
    AssertNil(identity);
    AssertEqual(error.domain, CBLErrorDomain);
    AssertEqual(error.code, CBLErrorCrypto);
    Assert([error.localizedDescription containsString: @"-25299"]);
}

- (void) testCreateGetDeleteClientIdentity {
    if (!self.hasHostApp) return;
    
    NSError* error;
    CBLTLSIdentity* identity;
    
    // Delete:
    Assert([CBLTLSIdentity deleteIdentityWithLabel: kClientCertLabel error: &error]);
    AssertNil(error);
    
    // Get:
    identity = [CBLTLSIdentity identityWithLabel: kClientCertLabel error: &error];
    AssertNil(identity);
    AssertNil(error);
    
    // Create:
    NSDictionary* attrs = @{ kCBLCertAttrCommonName: @"CBL-Client" };
    identity = [CBLTLSIdentity createIdentityForServer: NO
                                            attributes: attrs
                                            expiration: nil
                                                 label: kClientCertLabel
                                                 error: &error];
    AssertNotNil(identity);
    AssertNil(error);
    AssertEqual(identity.certs.count, 1);
    [self checkIdentityInKeyChain: identity];
    
    // Get:
    identity = [CBLTLSIdentity identityWithLabel: kClientCertLabel error: &error];
    AssertNotNil(identity);
    AssertNil(error);
    AssertEqual(identity.certs.count, 1);
    [self checkIdentityInKeyChain: identity];
    
    // Delete:
    Assert([CBLTLSIdentity deleteIdentityWithLabel: kClientCertLabel error: &error]);
    AssertNil(error);
    
    // Get:
    identity = [CBLTLSIdentity identityWithLabel: kClientCertLabel error: &error];
    AssertNil(identity);
    AssertNil(error);
}

- (void) testCreateDuplicateClientIdentity {
    if (!self.hasHostApp) return;
    
    NSError* error;
    CBLTLSIdentity* identity;
    
    // Create:
    NSDictionary* attrs = @{ kCBLCertAttrCommonName: @"CBL-Client" };
    identity = [CBLTLSIdentity createIdentityForServer: NO
                                            attributes: attrs
                                            expiration: nil
                                                 label: kClientCertLabel
                                                 error: &error];
    AssertNotNil(identity);
    AssertNil(error);
    [self checkIdentityInKeyChain: identity];
    
    // Get:
    identity = [CBLTLSIdentity identityWithLabel: kClientCertLabel error: &error];
    AssertNotNil(identity);
    AssertNil(error);
    [self checkIdentityInKeyChain: identity];
    
    // Create again with the same label:
    identity = [CBLTLSIdentity createIdentityForServer: YES
                                            attributes: attrs
                                            expiration: nil
                                                 label: kClientCertLabel
                                                 error: &error];
    AssertNil(identity);
    AssertEqual(error.domain, CBLErrorDomain);
    AssertEqual(error.code, CBLErrorCrypto);
    Assert([error.localizedDescription containsString: @"-25299"]);
}

- (void) testCreateIdentityFromData {
    if (!self.hasHostApp) return;
    
    NSData* data = [self dataFromResource: @"identity/certs" ofType: @"p12"];
    
    // When importing P12 file on macOS unit test, there is an internal exception thrown
    // inside SecPKCS12Import() which doesn't actually cause anything. Ignore the exception
    // so that the exception breakpoint will not be triggered.
    __block NSError* error;
    __block CBLTLSIdentity* identity;
    [self ignoreException: ^{
        identity = [CBLTLSIdentity createIdentityWithData: data
        password: @"123"
           label: kServerCertLabel
           error: &error];
    }];
    
    AssertNotNil(identity);
    AssertNil(error);
    AssertEqual(identity.certs.count, 2);
    [self checkIdentityInKeyChain: identity];
    
    // Get:
    identity = [CBLTLSIdentity identityWithLabel: kServerCertLabel error: &error];
    AssertNotNil(identity);
    AssertNil(error);
    AssertEqual(identity.certs.count, 2);
    
    [self printItemsInKeyChain];
    
    // Delete:
    Assert([CBLTLSIdentity deleteIdentityWithLabel: kServerCertLabel error: &error]);
    AssertNil(error);
    
    // Get:
    identity = [CBLTLSIdentity identityWithLabel: kServerCertLabel error: &error];
    AssertNil(identity);
    AssertNil(error);
}

- (void) testCreateIdentityWithNoAttributes {
    if (!self.hasHostApp) return;
    
    NSError* error;
    CBLTLSIdentity* identity;
    
    // Delete:
    Assert([CBLTLSIdentity deleteIdentityWithLabel: kServerCertLabel error: &error]);
    AssertNil(error);
    
    // Get:
    identity = [CBLTLSIdentity identityWithLabel: kServerCertLabel error: &error];
    AssertNil(identity);
    AssertNil(error);
    
    // Create:
    identity = [CBLTLSIdentity createIdentityForServer: YES
                                            attributes: @{ }
                                            expiration: nil
                                                 label: kServerCertLabel
                                                 error: &error];
    AssertNil(identity);
    AssertEqual(error.domain, CBLErrorDomain);
    AssertEqual(error.code, CBLErrorCrypto);
    Assert([error.localizedDescription containsString: @"-67655"]);
}

- (void) testCertificateExpiration {
    if (!self.hasHostApp) return;

    NSError* error;
    CBLTLSIdentity* identity;
    
    // Delete:
    Assert([CBLTLSIdentity deleteIdentityWithLabel: kServerCertLabel error: &error]);
    AssertNil(error);
    
    // Get:
    identity = [CBLTLSIdentity identityWithLabel: kServerCertLabel error: &error];
    AssertNil(identity);
    AssertNil(error);
    
    // Create:
    NSDate* expiration = [NSDate dateWithTimeIntervalSinceNow: 300];
    NSDictionary* attrs = @{ kCBLCertAttrCommonName: @"CBL-Server" };
    identity = [CBLTLSIdentity createIdentityForServer: YES
                                            attributes: attrs
                                            expiration: expiration
                                                 label: kServerCertLabel
                                                 error: &error];
    AssertNotNil(identity);
    AssertNil(error);
    AssertEqual(identity.certs.count, 1);
    
    /* Lite-Core minus 60 seconds to the setup expiration time to allow some clock diff b/w devices. */
    NSDate* certExpiration = [NSDate dateWithTimeIntervalSince1970: (identity.expiration / 1000.0) + 60];
    Assert(ABS(certExpiration.timeIntervalSince1970 - expiration.timeIntervalSince1970) < 5);
    
#if TARGET_OS_OSX
    SecCertificateRef cert = (__bridge SecCertificateRef)(identity.certs[0]);
    
    // ONLY Available on macOS:
    NSDictionary* certAttrs = CFBridgingRelease(SecCertificateCopyValues(cert, NULL, NULL));
    NSDictionary* expInfo = certAttrs[(id)kSecOIDX509V1ValidityNotAfter];
    NSNumber *expValue = expInfo[(id)kSecPropertyKeyValue];
    certExpiration = [NSDate dateWithTimeIntervalSinceReferenceDate: [expValue doubleValue] + 60];
    Assert(ABS(certExpiration.timeIntervalSince1970 - expiration.timeIntervalSince1970) < 5);
#endif
}

@end
