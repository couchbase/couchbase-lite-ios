//
//  CBLCert.mm
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

#import "CBLCert.h"
#import "CBLCoreBridge.h"
#import "CBLKeyChain.h"
#import "CBLStatus.h"

static C4SliceResult _toPEM(SecCertificateRef certRef, NSError* _Nullable * error);

C4Cert* __nullable toC4Cert(NSArray* secCerts, NSError* _Nullable * error) {
    NSError* e;
    NSData* certData = toPEM(secCerts, error);
    if (!certData)
        return nullptr;
    
    C4Error err = {};
    C4Cert* c4cert = c4cert_fromData(data2slice(certData), &err);
    if (!c4cert) {
        convertError(err, &e);
        if (error) *error = e;
        CBLWarnError(Listener, @"Couldn't convert certs to C4Cert: %@", e);
        return nullptr;
    }
    return c4cert;
}

C4Cert* __nullable toC4Cert(SecIdentityRef identity, NSArray* _Nullable certs, NSError* _Nullable * error) {
    SecCertificateRef certRef;
    OSStatus status = SecIdentityCopyCertificate(identity, &certRef);
    if (status != errSecSuccess) {
        createSecError(status, @"Couldn't get certificate from the identity", error);
        return nullptr;
    }
    
    NSMutableArray* certChain = [NSMutableArray arrayWithObject: CFBridgingRelease(certRef)];
    if (certs) {
        [certChain addObjectsFromArray: certs];
    }
    return toC4Cert(certChain, error);
}

NSData* __nullable toPEM(NSArray* secCerts, NSError* _Nullable * error) {
    NSMutableData* data = [NSMutableData data];
    for (NSUInteger i = 0; i < secCerts.count; i++) {
        SecCertificateRef certRef = (__bridge SecCertificateRef)[secCerts objectAtIndex: i];
        C4SliceResult pem = _toPEM(certRef, error);
        if (!pem.buf)
            return nil;
        [data appendData: sliceResult2data(pem)];
        c4slice_free(pem);
    }
    return data;
}

C4SliceResult _toPEM(SecCertificateRef certRef, NSError* _Nullable * error) {
    NSData* data = (NSData*)CFBridgingRelease(SecCertificateCopyData(certRef));
    C4Error err = {};
    C4Cert* c4cert = c4cert_fromData(data2slice(data), &err);
    if (!c4cert) {
        convertError(err, error);
        return C4SliceResult{};
    }
    C4SliceResult pem = c4cert_copyData(c4cert, true /* PEM Format */);
    c4cert_release(c4cert);
    return pem;
}

SecCertificateRef __nullable toSecCert(C4Cert* c4cert, NSError* _Nullable * error) {
    NSData* data = sliceResult2data(c4cert_copyData(c4cert, false));
    SecCertificateRef certRef = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)data);
    if (certRef == NULL) {
        createSecError(errSecUnknownFormat, @"Couldn't create certificate from data", error);
        return nil;
    }
    return certRef;
}

NSArray* __nullable toSecCertChain(C4Cert* c4cert, NSError* _Nullable * error) {
    NSMutableArray* certs = [NSMutableArray array];
    for (C4Cert* cert = c4cert; cert; cert = c4cert_nextInChain(cert)) {
        NSData* data = sliceResult2data(c4cert_copyData(cert, false));
        SecCertificateRef certRef = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)data);
        if (certRef == NULL) {
            createSecError(errSecUnknownFormat, @"Couldn't create certificate from data", error);
            return nil;
        }
        [certs addObject: CFBridgingRelease(certRef)];
    }
    return certs;
}

NSArray* __nullable toSecIdentityWithCertChain(C4Cert* c4cert, NSError* _Nullable * error) {
    NSArray* certs = toSecCertChain(c4cert, error);
    if (!certs)
        return nil;
    Assert(certs.count > 0);
        
    // Leaf cert:
    SecCertificateRef certRef = (__bridge SecCertificateRef)certs[0];
        
    // Identity:
    SecIdentityRef identityRef = getIdentity(certRef, error);
    if (!identityRef)
        return nil;
        
#if DEBUG
    // Sanity verify the identity:
    SecCertificateRef xCertRef;
    OSStatus status = SecIdentityCopyCertificate(identityRef, &xCertRef);
    Assert(status == errSecSuccess);
    NSString* summary = (NSString*) CFBridgingRelease(SecCertificateCopySubjectSummary(certRef));
    NSString* xSummary = (NSString*) CFBridgingRelease(SecCertificateCopySubjectSummary(xCertRef));
    Assert([summary isEqualToString: xSummary], @"Invalid Identity");
#endif
        
    // Create result array:
    NSMutableArray* result = [NSMutableArray arrayWithObject: (id)CFBridgingRelease(identityRef)];
    if (certs.count > 1)
        [result addObjectsFromArray: [certs subarrayWithRange: NSMakeRange(1, certs.count - 1)]];
    return result;
}
