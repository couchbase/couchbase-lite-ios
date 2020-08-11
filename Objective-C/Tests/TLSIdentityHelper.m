//
//  TLSIdentityHelper.m
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

#import "TLSIdentityHelper.h"

@implementation TLSIdentityHelper

+ (BOOL) storePrivateKey: (SecKeyRef)privateKey certs: (NSArray*)certs label: (NSString*)label {
    if (certs.count == 0) {
        NSLog(@"*** Certs empty");
        return NO;
    }
    
    // Private Key:
    OSStatus status = [TLSIdentityHelper storePrivateKey: privateKey];
    if (status != errSecSuccess) {
        NSLog(@"*** Failed to save Private Key %d", status);
        return NO;
    }
        
    
    // Certificates:
    int i = 0;
    for (id cert in certs) {
        status = [TLSIdentityHelper storeCertificate: (SecCertificateRef) cert
                                               label: (i++) == 0 ? label : nil];
        if (status != errSecSuccess){
            NSLog(@"*** Failed to save Certificate %@ %d", cert, status);
            return NO;
        }
    }
    
    return YES;
}

+ (OSStatus) updateCert: (SecCertificateRef)cert withLabel: (NSString*)label {
    NSDictionary* query = @{
        (id)kSecClass:              (id)kSecClassCertificate,
        (id)kSecValueRef:           (__bridge id)cert,
    };
    
    NSDictionary* update = @{
        (id)kSecClass:              (id)kSecClassCertificate,
        (id)kSecValueRef:           (__bridge id)cert,
        (id)kSecAttrLabel:          label
    };
    
    return SecItemUpdate((CFDictionaryRef)query, (CFDictionaryRef)update);
}

+ (OSStatus) storePrivateKey: (SecKeyRef)key {
    NSDictionary* params = @{
        (id)kSecClass:              (id)kSecClassKey,
        (id)kSecAttrKeyType:        (id)kSecAttrKeyTypeRSA,
        (id)kSecAttrKeyClass:       (id)kSecAttrKeyClassPrivate,
        (id)kSecReturnRef:          @NO,
        (id)kSecValueRef:           (__bridge id)key
    };
    
    return SecItemAdd((CFDictionaryRef)params, NULL);
}

+ (OSStatus) storeCertificate: (SecCertificateRef)cert label: (NSString*)label {
    NSMutableDictionary* params = [NSMutableDictionary dictionaryWithDictionary: @{
        (id)kSecClass:              (id)kSecClassCertificate,
        (id)kSecReturnRef:          @NO,
        (id)kSecValueRef:           (__bridge id)cert
    }];
    if (label)
        params[(id)kSecAttrLabel] = label;
    
    return SecItemAdd((CFDictionaryRef)params, NULL);
}

@end
