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
#import "CBLTrustCheck.h"

@interface TLSIdentityTest : CBLTestCase

@end

#define kServerCertLabel @"CBL-Server-Cert"
#define kClientCertLabel @"CBL-Client-Cert"
#define kCACertLabel     @"CBL-CA-Cert"

#define kServerCertAttrs @{ kCBLCertAttrCommonName: @"CBL-Server" }
#define kClientCertAttrs @{ kCBLCertAttrCommonName: @"CBL-Client" }

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
    SecKeyRef publicKeyRef = SecCertificateCopyKey(certRef);
    Assert(publicKeyRef);
    NSDictionary* attrs = CFBridgingRelease(SecKeyCopyAttributes(publicKeyRef));
    CFRelease(publicKeyRef);
    return [attrs objectForKey: (id)kSecAttrApplicationLabel];
}

- (void) checkIdentityInKeyChain: (CBLTLSIdentity*)identity {
    Assert(identity != nil);
    
    NSArray* certs = identity.certs;
    Assert(certs.count > 0);
    
    // Check Certificate:
    SecCertificateRef certRef = (__bridge SecCertificateRef)certs[0];
    Assert(certRef != nil);
    
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
}

- (void) storePrivateKey: (SecKeyRef)privateKey certs: (NSArray*)certs label: (NSString*)label {
    Assert(certs.count > 0);
    
    // Private Key:
    [self storePrivateKey: privateKey];
    
    // Certificates:
    int i = 0;
    for (id cert in certs) {
        NSString* certLabel = (i++) == 0 ? label : @"com.couchbase.lite.cert";
        [self storeCertificate: (SecCertificateRef) cert label: certLabel];
    }
}

- (void) updateCert: (SecCertificateRef)cert withLabel: (NSString*)label {
    NSDictionary* query = @{
        (id)kSecClass:              (id)kSecClassCertificate,
        (id)kSecValueRef:           (__bridge id)cert,
    };
    
    NSDictionary* update = @{
        (id)kSecClass:              (id)kSecClassCertificate,
        (id)kSecValueRef:           (__bridge id)cert,
        (id)kSecAttrLabel:          label
    };
    
    OSStatus status = SecItemUpdate((CFDictionaryRef)query, (CFDictionaryRef)update);
    Assert(status == errSecSuccess);
}

- (void) deleteCert: (SecCertificateRef)cert {
    // Build a query dictionary to match the certificate
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassCertificate,
        (__bridge id)kSecValueRef: (__bridge id)cert
    };
    
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    Assert(status == errSecSuccess || status == errSecItemNotFound || status == errSecInvalidItemRef);
}

- (void) deletePrivateKey: (SecKeyRef)key {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassKey,
        (__bridge id)kSecValueRef: (__bridge id)key
    };

    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    Assert(status == errSecSuccess || status == errSecItemNotFound || status == errSecInvalidItemRef);
}

- (void) storePrivateKey: (SecKeyRef)key {
    NSDictionary* params = @{
        (id)kSecClass:              (id)kSecClassKey,
        (id)kSecAttrKeyType:        (id)kSecAttrKeyTypeRSA,
        (id)kSecAttrKeyClass:       (id)kSecAttrKeyClassPrivate,
        (id)kSecReturnRef:          @NO,
        (id)kSecValueRef:           (__bridge id)key
    };
    
    OSStatus status = SecItemAdd((CFDictionaryRef)params, NULL);
    Assert(status == errSecSuccess);
}

- (void) storeCertificate: (SecCertificateRef)cert label: (NSString*)label {
    NSMutableDictionary* params = [NSMutableDictionary dictionaryWithDictionary: @{
        (id)kSecClass:              (id)kSecClassCertificate,
        (id)kSecReturnRef:          @NO,
        (id)kSecValueRef:           (__bridge id)cert
    }];
    if (label)
        params[(id)kSecAttrLabel] = label;
    
    OSStatus status = SecItemAdd((CFDictionaryRef)params, NULL);
    Assert(status == errSecSuccess);
}

#if 0

/** For Debugging */
- (void) dumpItemsInKeyChain {
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

// For Debugging: Dump all certificates in the Keychain
- (void) dumpCertsInKeyChain {
    NSDictionary *query = @{
        (__bridge id)kSecClass:               (__bridge id)kSecClassCertificate,
        (__bridge id)kSecMatchLimit:          (__bridge id)kSecMatchLimitAll,
        (__bridge id)kSecReturnRef:           @YES,
        (__bridge id)kSecReturnAttributes:    @YES
    };

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess) {
        NSLog(@"Failed to query certificates: %d", (int)status);
        return;
    }
    
    NSLog(@"Certificates in Keychain:");
    
    NSArray *items = (__bridge_transfer NSArray *)result;
    for (NSDictionary *item in items) {
        NSString *label = item[(__bridge id)kSecAttrLabel] ?: @"<no label>";
        SecCertificateRef certRef = (__bridge SecCertificateRef)item[(__bridge id)kSecValueRef];
        
        NSString *commonName = @"<unknown>";
        CFStringRef cn = NULL;
        if (SecCertificateCopyCommonName(certRef, &cn) == errSecSuccess && cn) {
            commonName = (__bridge_transfer NSString *)cn;
        }

        NSLog(@"Label: %@\nCommon Name: %@", label, commonName);
    }
}

#endif

- (void) setUp {
    [super setUp];
    
    if (!self.keyChainAccessAllowed) return;
    
    [self ignoreExceptionBreakPoint: ^{
        Assert([CBLTLSIdentity deleteIdentityWithLabel: kServerCertLabel error: nil]);
    }];
    [self ignoreExceptionBreakPoint: ^{
        Assert([CBLTLSIdentity deleteIdentityWithLabel: kClientCertLabel error: nil]);
    }];
    [self ignoreExceptionBreakPoint: ^{
        Assert([CBLTLSIdentity deleteIdentityWithLabel: kCACertLabel error: nil]);
    }];
}

- (void) tearDown {
    [super tearDown];
    
    if (!self.keyChainAccessAllowed) return;
    
    [self ignoreExceptionBreakPoint: ^{
        Assert([CBLTLSIdentity deleteIdentityWithLabel: kServerCertLabel error: nil]);
    }];
    [self ignoreExceptionBreakPoint: ^{
        Assert([CBLTLSIdentity deleteIdentityWithLabel: kClientCertLabel error: nil]);
    }];
    [self ignoreExceptionBreakPoint: ^{
        Assert([CBLTLSIdentity deleteIdentityWithLabel: kCACertLabel error: nil]);
    }];
}

#ifdef COUCHBASE_ENTERPRISE
- (void) testCreateGetDeleteServerIdentity {
    XCTSkipUnless(self.keyChainAccessAllowed);
    
    NSError* error;
    CBLTLSIdentity* identity;
    
    // Get:
    identity = [CBLTLSIdentity identityWithLabel: kServerCertLabel error: &error];
    AssertNil(identity);
    AssertNil(error);
    
    // Create:
    error = nil;
    identity = [CBLTLSIdentity createIdentityForKeyUsages: kCBLKeyUsagesServerAuth
                                               attributes: kServerCertAttrs
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
    XCTSkipUnless(self.keyChainAccessAllowed);
    
    NSError* error;
    CBLTLSIdentity* identity;
    
    // Create:
    identity = [CBLTLSIdentity createIdentityForKeyUsages: kCBLKeyUsagesServerAuth
                                               attributes: kServerCertAttrs
                                               expiration: nil
                                                    label: kServerCertLabel
                                                    error: &error];
    AssertNotNil(identity);
    AssertNil(error);
    
    // Get:
    error = nil;
    identity = [CBLTLSIdentity identityWithLabel: kServerCertLabel error: &error];
    AssertNotNil(identity);
    AssertNil(error);
    
    // Create again with the same label:
    identity = [CBLTLSIdentity createIdentityForKeyUsages: kCBLKeyUsagesServerAuth
                                               attributes: kServerCertAttrs
                                               expiration: nil
                                                    label: kServerCertLabel
                                                    error: &error];
    AssertNil(identity);
    AssertEqual(error.domain, CBLErrorDomain);
    AssertEqual(error.code, CBLErrorCrypto);
    Assert([error.localizedDescription containsString: @"-25299"]);
}

- (void) testCreateGetDeleteClientIdentity {
    XCTSkipUnless(self.keyChainAccessAllowed);
    
    NSError* error;
    CBLTLSIdentity* identity;
    
    // Get:
    identity = [CBLTLSIdentity identityWithLabel: kClientCertLabel error: &error];
    AssertNil(identity);
    AssertNil(error);
    
    // Create:
    error = nil;
    identity = [CBLTLSIdentity createIdentityForKeyUsages: kCBLKeyUsagesClientAuth
                                               attributes: kClientCertAttrs
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
    XCTSkipUnless(self.keyChainAccessAllowed);
    
    NSError* error;
    CBLTLSIdentity* identity;
    
    // Create:
    identity = [CBLTLSIdentity createIdentityForKeyUsages: kCBLKeyUsagesClientAuth
                                               attributes: kClientCertAttrs
                                               expiration: nil
                                                    label: kClientCertLabel
                                                    error: &error];
    AssertNotNil(identity);
    AssertNil(error);
    
    // Get:
    identity = [CBLTLSIdentity identityWithLabel: kClientCertLabel error: &error];
    AssertNotNil(identity);
    AssertNil(error);
    
    // Create again with the same label:
    identity = [CBLTLSIdentity createIdentityForKeyUsages: kCBLKeyUsagesClientAuth
                                               attributes: kClientCertAttrs
                                               expiration: nil
                                                    label: kClientCertLabel
                                                    error: &error];
    AssertNil(identity);
    AssertEqual(error.domain, CBLErrorDomain);
    AssertEqual(error.code, CBLErrorCrypto);
    Assert([error.localizedDescription containsString: @"-25299"]);
}

- (void) testGetIdentityWithIdentity {
    XCTSkipUnless(self.keyChainAccessAllowed);
    
    // Use SecPKCS12Import to import the PKCS12 data:
    __block CFArrayRef result = NULL;
    __block OSStatus status;
    NSData* data = [self dataFromResource: @"identity/certs" ofType: @"p12"];
    NSDictionary* options = @{ (id)kSecImportExportPassphrase: @"123" };
    [self ignoreException:^{
        status = SecPKCS12Import((__bridge CFDataRef)data, (__bridge CFDictionaryRef)options, &result);
    }];
    AssertEqual(status, errSecSuccess);
    
    // Identity:
    NSArray* importedItems = (NSArray*)CFBridgingRelease(result);
    Assert(importedItems.count > 0);
    NSDictionary* item = importedItems[0];
    SecIdentityRef identityRef = (__bridge SecIdentityRef) item[(id)kSecImportItemIdentity];
    Assert(identityRef);
    
    // Private Key:
    SecKeyRef privateKeyRef;
    status = SecIdentityCopyPrivateKey(identityRef, &privateKeyRef);
    AssertEqual(status, errSecSuccess);
    CFAutorelease(privateKeyRef);
    
    // Certs:
    NSArray* certs = item[(id)kSecImportItemCertChain];
    Assert(certs.count == 2);
    
    // For iOS, need to explicitly store the identity into the KeyChain as SecPKCS12Import doesn't do it.
#if TARGET_OS_IPHONE
    // Clean up first:
    [self deletePrivateKey: privateKeyRef];
    for (id cert in certs) {
        [self deleteCert: (SecCertificateRef)cert];
    }
    [self storePrivateKey: privateKeyRef certs: certs label: kServerCertLabel];
#endif
    
    // Get identity:
    NSError* error;
    CBLTLSIdentity* identity = [CBLTLSIdentity identityWithIdentity: identityRef
                                                              certs: @[certs[1]]
                                                              error: &error];
    AssertNotNil(identity);
    AssertNil(error);
    AssertEqual(identity.certs.count, 2u);
    
#if TARGET_OS_OSX
    // Cleanup: remove the certificate and private key from the keychain
    [self deletePrivateKey: privateKeyRef];
    
    for (id cert in certs) {
        [self deleteCert: (SecCertificateRef)cert];
    }
#endif
}

- (void) testImportIdentity {
#if TARGET_OS_OSX
    XCTSkip(@"CBL-7005 : importIdentityWithData not working on newer macOS");
#endif
    
    XCTSkipUnless(self.keyChainAccessAllowed);
    
    //@autoreleasepool {
    
    NSData* data = [self dataFromResource: @"identity/certs" ofType: @"p12"];
    
    // When importing P12 file on macOS unit test, there is an internal exception thrown
    // inside SecPKCS12Import() which doesn't actually cause anything. Ignore the exception
    // so that the exception breakpoint will not be triggered.
    __block NSError* error;
    __block CBLTLSIdentity* identity;
    [self ignoreException: ^{
        identity = [CBLTLSIdentity importIdentityWithData: data
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
    
    // Delete:
    [self ignoreExceptionBreakPoint: ^{
        Assert([CBLTLSIdentity deleteIdentityWithLabel: kServerCertLabel error: &error]);
    }];
    AssertNil(error);
    
    // Get:
    identity = [CBLTLSIdentity identityWithLabel: kServerCertLabel error: &error];
    AssertNil(identity);
    AssertNil(error);
}

- (void) testCreateIdentityWithNoAttributes {
    XCTSkipUnless(self.keyChainAccessAllowed);
    
    NSError* error;
    CBLTLSIdentity* identity;
    
    // Get:
    identity = [CBLTLSIdentity identityWithLabel: kServerCertLabel error: &error];
    AssertNil(identity);
    AssertNil(error);
    
    // Create:
    error = nil; // reset the error
    identity = [CBLTLSIdentity createIdentityForKeyUsages: kCBLKeyUsagesServerAuth
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
    XCTSkipUnless(self.keyChainAccessAllowed);
    
    NSError* error;
    CBLTLSIdentity* identity;
    
    // Get:
    identity = [CBLTLSIdentity identityWithLabel: kServerCertLabel error: &error];
    AssertNil(identity);
    AssertNil(error);
    
    // Create:
    error = nil; // reset the error
    NSDate* expiration = [NSDate dateWithTimeIntervalSinceNow: 300];
    identity = [CBLTLSIdentity createIdentityForKeyUsages: kCBLKeyUsagesServerAuth
                                               attributes: kServerCertAttrs
                                               expiration: expiration
                                                    label: kServerCertLabel
                                                    error: &error];
    AssertNotNil(identity);
    AssertNil(error);
    AssertEqual(identity.certs.count, 1);
    
    // The actual expiration will be slightly less than the set expiration time:
    Assert(ABS(expiration.timeIntervalSince1970 - identity.expiration.timeIntervalSince1970) < 5.0);
    
#if TARGET_OS_OSX
    SecCertificateRef cert = (__bridge SecCertificateRef)(identity.certs[0]);
    NSDictionary* certAttrs = CFBridgingRelease(SecCertificateCopyValues(cert, NULL, NULL));
    NSDictionary* expInfo = certAttrs[(id)kSecOIDX509V1ValidityNotAfter];
    NSNumber* expValue = expInfo[(id)kSecPropertyKeyValue];
    NSDate* certExpiration = [NSDate dateWithTimeIntervalSinceReferenceDate: [expValue doubleValue]];
    Assert(ABS(expiration.timeIntervalSince1970 - certExpiration.timeIntervalSince1970) < 5.0);
#endif
}

- (void) testCreateIdentitySignedWithIssuer {
    XCTSkipUnless(self.keyChainAccessAllowed);
    
    NSData* caKeyData = [self dataFromResource: @"identity/ca-key" ofType: @"der"];
    NSData* caCertData = [self dataFromResource: @"identity/ca-cert" ofType: @"der"];
    
    
    NSError* error;
    CBLTLSIdentity* issuer = [CBLTLSIdentity createIssuerWithPrivateKey: caKeyData
                                                            certificate: caCertData
                                                                  error: &error];
    AssertNotNil(issuer);
    AssertNil(error);
    
    CBLTLSIdentity* identity = [CBLTLSIdentity createIdentityForKeyUsages: kCBLKeyUsagesServerAuth
                                                               attributes: kServerCertAttrs
                                                               expiration: nil
                                                                   issuer: issuer
                                                                    label: kServerCertLabel
                                                                    error: &error];
    AssertNotNil(identity);
    AssertNil(error);
    AssertEqual(identity.certs.count, 2);
    
    // Validate the identity is signed by the issuer's cert using trust check:
    SecTrustRef trust;
    SecPolicyRef policy = SecPolicyCreateBasicX509();
    OSStatus status = SecTrustCreateWithCertificates((__bridge CFTypeRef)identity.certs, policy, &trust);
    AssertEqual(status, errSecSuccess);
    
    CBLTrustCheck* trustCheck = [[CBLTrustCheck alloc] initWithTrust: trust];
    trustCheck.rootCerts = issuer.certs;
    NSURLCredential* credential = [trustCheck checkTrust: &error];
    AssertNotNil(credential);
    AssertNil(error);

    CFRelease(policy);
    
    // Check the identity in KeyChain:
    identity = [CBLTLSIdentity identityWithLabel: kServerCertLabel error: &error];
    AssertNotNil(identity);
    AssertNil(error);
    AssertEqual(identity.certs.count, 2);
    
    // Delete the identity which is a cert chain:
    Assert([CBLTLSIdentity deleteIdentityWithLabel: kServerCertLabel error: &error]);
    AssertNil(error);
    
    // Check the identity in KeyChain:
    identity = [CBLTLSIdentity identityWithLabel: kServerCertLabel error: &error];
    AssertNil(identity);
    AssertNil(error);
}

- (void) testCreateIdentitySignedWithImportedIssuer {
#if TARGET_OS_OSX
    XCTSkip(@"CBL-7005 : importIdentityWithData not working on newer macOS");
#endif
    
    XCTSkipUnless(self.keyChainAccessAllowed);
    
    NSData* data = [self dataFromResource: @"identity/ca" ofType: @"p12"];
    
    NSError* error;
    CBLTLSIdentity* issuer = [CBLTLSIdentity importIdentityWithData: data
                                                           password: @"123"
                                                              label: kCACertLabel
                                                              error: &error];
    
    AssertNotNil(issuer);
    AssertNil(error);
    
    CBLTLSIdentity* identity = [CBLTLSIdentity createIdentityForKeyUsages: kCBLKeyUsagesServerAuth
                                                               attributes: kServerCertAttrs
                                                               expiration: nil
                                                                   issuer: issuer
                                                                    label: kServerCertLabel
                                                                    error: &error];
    AssertNotNil(identity);
    AssertNil(error);
    AssertEqual(identity.certs.count, 2);
    
    // Validate the identity is signed by the issuer's cert using trust check:
    SecTrustRef trust;
    SecPolicyRef policy = SecPolicyCreateBasicX509();
    OSStatus status = SecTrustCreateWithCertificates((__bridge CFTypeRef)identity.certs, policy, &trust);
    AssertEqual(status, errSecSuccess);
    
    CBLTrustCheck* trustCheck = [[CBLTrustCheck alloc] initWithTrust: trust];
    trustCheck.rootCerts = identity.certs;
    NSURLCredential* credential = [trustCheck checkTrust: &error];
    AssertNotNil(credential);
    AssertNil(error);
    
    CFRelease(policy);
    
    identity = [CBLTLSIdentity identityWithLabel: kServerCertLabel error: &error];
    AssertNotNil(identity);
    AssertNil(error);
    AssertEqual(identity.certs.count, 2);
    
    Assert([CBLTLSIdentity deleteIdentityWithLabel: kServerCertLabel error: &error]);
    AssertNil(error);
    
    identity = [CBLTLSIdentity identityWithLabel: kServerCertLabel error: &error];
    AssertNil(identity);
    AssertNil(error);
}

#endif

@end
