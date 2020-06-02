//
//  CBLKeyChain.mm
//  CouchbaseLite
//
//  Copyright (c) 2020 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Couchbase License Agreement (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//  https://info.couchbase.com/rs/302-GJY-034/images/2017-10-30_License_Agreement.pdf
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLKeyChain.h"
#import "CBLCert.h"
#import "CBLStatus.h"

#pragma mark - Private Declaration

#if TARGET_OS_IPHONE
static bool _storeIdentity(SecIdentityRef identityRef, NSArray* _Nullable certs, NSString* label, NSError* _Nullable * error)
API_AVAILABLE(macos(10.12), ios(10.0));

static bool _storeCert(SecCertificateRef certRef, NSString* _Nullable label, bool ignoreDuplicate, NSError* _Nullable * error)
API_AVAILABLE(macos(10.12), ios(10.0));

static bool _storePrivateKey(SecKeyRef keyRef, NSError* _Nullable * error)
API_AVAILABLE(macos(10.12), ios(10.0));
#endif

#if TARGET_OS_OSX
static bool _updateCertLabel(SecCertificateRef certRef, NSString* label, NSError* _Nullable * error)
API_AVAILABLE(macos(10.12), ios(10.0));
#endif

static bool _keyExists(SecKeyRef keyRef)
API_AVAILABLE(macos(10.12), ios(10.0));

static SecKeyRef __nullable _getPublicKey(SecCertificateRef certRef, NSError* _Nullable * error)
API_AVAILABLE(macos(10.12), ios(10.0));

static NSData* __nullable _getPublicKeyHash(SecCertificateRef certRef, NSError* _Nullable * error)
API_AVAILABLE(macos(10.12), ios(10.0));

static NSData* _getPublicKeyHash(SecKeyRef keyRef)
API_AVAILABLE(macos(10.12), ios(10.0));

static bool _deleteIdentity(SecIdentityRef identityRef, NSError* _Nullable * error)
API_AVAILABLE(macos(10.12), ios(10.0));

static bool _deleteKey(NSData* publicKeyHash, bool isPrivateKey, NSError* _Nullable * error)
API_AVAILABLE(macos(10.12), ios(10.0));

static bool _deleteCert(SecCertificateRef certRef, NSError* _Nullable * error)
API_AVAILABLE(macos(10.12), ios(10.0));

static bool _deleteCert(NSData* publicKeyHash, NSError* _Nullable * error)
API_AVAILABLE(macos(10.12), ios(10.0));

#pragma mark - Implementation

bool importPKCS12(NSData* data, NSString* _Nullable password, NSString* label, NSError* _Nullable * error) {
    // Note:
    // 1. SecPKCS12Import doesn't save the imported item in the Keychain on iOS platform.
    //    So We need to save the imported item.
    // 2. On macOS, we update the imported leaf certificate with the specified label so that
    //    the identity can be referenced by using the label.
    CFArrayRef result = NULL;
    NSDictionary* options = password ?
    [NSDictionary dictionaryWithObjectsAndKeys: password, kSecImportExportPassphrase, nil] :
    [NSDictionary dictionary];
    OSStatus status = SecPKCS12Import((__bridge CFDataRef)data,
                                      (__bridge CFDictionaryRef)options,
                                      &result);
    if (status != errSecSuccess) {
        createSecError(status, @"Couldn't import PKCS12 data", error);
        return false;
    }
    
    NSArray* importedItems = (NSArray*)CFBridgingRelease(result);
    Assert(importedItems.count > 0);
    NSDictionary* item = importedItems[0];
    
#if TARGET_OS_IPHONE
    // Save private key and certs into the Keychain:
    SecIdentityRef identity = (__bridge SecIdentityRef) item[(id)kSecImportItemIdentity];
    Assert(identity);
    
    NSArray* importedCerts = item[(id)kSecImportItemCertChain];
    Assert(importedCerts.count > 0);
    NSArray* certs = importedCerts.count > 1 ?
        [importedCerts subarrayWithRange: NSMakeRange(1, importedCerts.count - 1)] : nil;
    if (!_storeIdentity(identity, certs, label, error))
        return false;
#else
    // Update label to the leaf cert:
    NSArray* certs = item[id(kSecImportItemCertChain)];
    Assert(certs.count > 0);
    if (!_updateCertLabel((__bridge SecCertificateRef)certs[0], label, error))
        return false;
#endif
    return true;
}

#if TARGET_OS_IPHONE
bool _storeIdentity(SecIdentityRef identityRef, NSArray* _Nullable certs, NSString* label, NSError* _Nullable * error) {
    // Private Key:
    SecKeyRef privateKey;
    OSStatus status = SecIdentityCopyPrivateKey(identityRef, &privateKey);
    if (status != errSecSuccess) {
        return createSecError(status, @"Couldn't copy private key from identity", error);
    }
    CFAutorelease(privateKey);
    if (!_storePrivateKey(privateKey, error)) {
        return false;
    }
    
    // Leaf Cert:
    SecCertificateRef leafCertRef;
    status = SecIdentityCopyCertificate(identityRef, &leafCertRef);
    if (status != errSecSuccess) {
        return createSecError(status, @"Couldn't get certificate from identity", error);
    }
    CFAutorelease(leafCertRef);
    if (!_storeCert(leafCertRef, label, false, error)) {
        return false;
    }
    
    // Root Certs:
    for (NSUInteger i = 0; i < certs.count; i++) {
        SecCertificateRef rootCertRef = (__bridge SecCertificateRef)certs[i];
        if (!_storeCert(rootCertRef, nil, true, error)) {
            return false;
        }
    }
    return true;
}

bool _storePrivateKey(SecKeyRef keyRef, NSError* _Nullable * error) {
    NSDictionary* keyParams = @{
        (id)kSecClass:              (id)kSecClassKey,
        (id)kSecAttrKeyType:        (id)kSecAttrKeyTypeRSA,
        (id)kSecAttrKeyClass:       (id)kSecAttrKeyClassPrivate,
        (id)kSecReturnRef:          @YES,
        (id)kSecValueRef:           (__bridge id)keyRef
    };
    
    CFTypeRef savedKey = NULL;
    OSStatus status = SecItemAdd((CFDictionaryRef)keyParams, &savedKey);
    if (status != errSecSuccess) {
        createSecError(status, @"Couldn't save the private key into the Keychain", error);
    }
    return (SecKeyRef)savedKey;
}

bool _storeCert(SecCertificateRef certRef, NSString* _Nullable label, bool ignoreDuplicate, NSError* _Nullable * error) {
    NSMutableDictionary* params = [NSMutableDictionary dictionaryWithDictionary: @{
        (id)kSecClass:              (id)kSecClassCertificate,
        (id)kSecValueRef:           (__bridge id)certRef,
        (id)kSecReturnRef:          @YES
    }];
    
    if (label) {
        params[id(kSecAttrLabel)] = label;
    }
    
    CFTypeRef result;
    OSStatus status = SecItemAdd((CFDictionaryRef)params, &result);
    if (result)
        CFAutorelease(result);
    
    if (status != errSecSuccess) {
        if (status != errSecDuplicateItem || !ignoreDuplicate) {
            return createSecError(status, @"Couldn't store certificate", error);
        }
    }
    return true;
}
#endif

#if TARGET_OS_OSX
bool _updateCertLabel(SecCertificateRef certRef, NSString* label, NSError* _Nullable * error) {
    NSDictionary* query = @{
        (id)kSecClass:              (id)kSecClassCertificate,
        (id)kSecValueRef:           (__bridge id)certRef,
    };
    
    NSDictionary* update = @{
        (id)kSecClass:              (id)kSecClassCertificate,
        (id)kSecValueRef:           (__bridge id)certRef,
        (id)kSecAttrLabel:          label
    };
    
    OSStatus status = SecItemUpdate((CFDictionaryRef)query, (CFDictionaryRef)update);
    if (status != errSecSuccess)
        return createSecError(status, @"Couldn't update the certificate with the label", error);
    return true;
}
#endif

bool identityExists(SecIdentityRef identityRef) {
    SecKeyRef keyRef;
    OSStatus status = SecIdentityCopyPrivateKey(identityRef, &keyRef);
    CFAutorelease(keyRef);
    return status == errSecSuccess && _keyExists(keyRef);
}

bool _keyExists(SecKeyRef keyRef) {
    NSDictionary* params = @{
        (id)kSecClass:              (id)kSecClassKey,
        (id)kSecValueRef:           (__bridge id)keyRef
    };
    OSStatus status = SecItemCopyMatching((CFDictionaryRef)params, nullptr);
    return status == errSecSuccess;
}

SecIdentityRef __nullable getIdentity(SecCertificateRef certRef, NSError* _Nullable * error) {
    // Public key hash:
    NSData* publicKeyHash = _getPublicKeyHash(certRef, error);
    if (!publicKeyHash) {
        return nil;
    }
    
    // Lookup identity using the public key hash:
    NSDictionary* params = @{
        (id)kSecClass:                  (id)kSecClassIdentity,
        (id)kSecAttrApplicationLabel:   publicKeyHash,
        (id)kSecReturnRef:              @YES
    };
    
    CFTypeRef identityRef;
    OSStatus status = SecItemCopyMatching((CFDictionaryRef)params, &identityRef);
    if (status != errSecSuccess) {
        createSecError(status, @"Couldn't lookup identity from the KeyChain", error);
        return nil;
    }
    return (SecIdentityRef)identityRef;
}

NSData* __nullable _getPublicKeyHash(SecCertificateRef certRef, NSError* _Nullable * error) {
    SecKeyRef publicKeyRef = _getPublicKey(certRef, error);
    if (!publicKeyRef)
        return nil;
    return _getPublicKeyHash(publicKeyRef);
}

SecKeyRef __nullable _getPublicKey(SecCertificateRef certRef, NSError* _Nullable * error) {
    SecTrustRef trustRef;
    SecPolicyRef policyRef = SecPolicyCreateBasicX509();
    CFAutorelease(policyRef);
    
    OSStatus status = SecTrustCreateWithCertificates(certRef, policyRef, &trustRef);
    if (status != errSecSuccess) {
        createSecError(status,
            @"Couldn't create trust from certificate", error);
        return nil;
    }
    
    SecKeyRef publicKeyRef = SecTrustCopyPublicKey(trustRef);
    CFRelease(trustRef);
    if (!publicKeyRef) {
        createSecError(errSecUnsupportedFormat,
            @"Couldn't extract public key from trust", error);
        return nil;
    }
    return publicKeyRef;
}

NSData* _getPublicKeyHash(SecKeyRef keyRef) {
    NSDictionary* publicKeyAttrs = (NSDictionary*)CFBridgingRelease(SecKeyCopyAttributes(keyRef));
    NSData* publicKeyHash = (NSData*)publicKeyAttrs[(id)kSecAttrApplicationLabel];
    Assert(publicKeyHash);
    return publicKeyHash;
}

bool deleteIdentity(NSArray* identityChain, NSError* _Nullable * error) {
    for (NSUInteger i = 0; i < identityChain.count; i++) {
        if (i == 0) {
            SecIdentityRef identityRef = (__bridge SecIdentityRef)identityChain[0];
            if (!_deleteIdentity(identityRef, error))
                return false;
        } else {
            SecCertificateRef certRef = (__bridge SecCertificateRef)identityChain[i];
            if (!_deleteCert(certRef, error))
                return false;
        }
    }
    return true;
}

bool _deleteIdentity(SecIdentityRef identityRef, NSError* _Nullable * error) {
    SecCertificateRef certRef;
    OSStatus status = SecIdentityCopyCertificate(identityRef, &certRef);
    if (status != errSecSuccess)
        return createSecError(status, @"Couldn't get certificate from identity", error);
    
    NSData* publicKeyHash = _getPublicKeyHash(certRef, error);
    if (!publicKeyHash)
        return false;
    
    if (!_deleteKey(publicKeyHash, false, error))
        return false;
    
    if (!_deleteKey(publicKeyHash, true, error))
        return false;
    
    if (!_deleteCert(publicKeyHash, error))
        return false;
    
    return true;
}

bool _deleteKey(NSData* publicKeyHash, bool isPrivateKey, NSError* _Nullable * error) {
    id keyClass = isPrivateKey ? (id)kSecAttrKeyClassPrivate : (id)kSecAttrKeyClassPublic;
    NSDictionary* params = @{
        (id)kSecClass:                  (id)kSecClassKey,
        (id)kSecAttrKeyClass:           keyClass,
        (id)kSecAttrApplicationLabel:   publicKeyHash
    };
    OSStatus status = SecItemDelete((CFDictionaryRef)params);
    if (status != errSecSuccess && status != errSecInvalidItemRef && status != errSecItemNotFound) {
        return createSecError(status, @"Couldn't delete the public key from the KeyChain", error);
    }
    return true;
}

bool _deleteCert(SecCertificateRef certRef, NSError* _Nullable * error) {
    NSData* publicKeyHash = _getPublicKeyHash(certRef, error);
    return _deleteCert(publicKeyHash, error);
}

bool _deleteCert(NSData* publicKeyHash, NSError* _Nullable * error) {
    NSDictionary* params = @{
        (id)kSecClass:                  (__bridge id)kSecClassCertificate,
        (id)kSecAttrPublicKeyHash:      publicKeyHash
    };
    OSStatus status = SecItemDelete((CFDictionaryRef)params);
    if (status != errSecSuccess && status != errSecInvalidItemRef && status != errSecItemNotFound) {
        return createSecError(status, @"Couldn't delete the certificate from the KeyChain", error);
    }
    return true;
}

bool deletePublicKey(SecCertificateRef certRef, NSError* _Nullable * error) {
    NSData* publicKeyHash = _getPublicKeyHash(certRef, error);
    if (!publicKeyHash)
        return false;
    return _deleteKey(publicKeyHash, false, error);
}
