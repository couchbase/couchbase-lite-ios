//
//  CBLClientCertAuthorizer.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/23/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import "CBLClientCertAuthorizer.h"

@implementation CBLClientCertAuthorizer

@synthesize credential=_credential, certificateChain=_certificateChain;

- (instancetype) initWithIdentity: (SecIdentityRef)identity
                  supportingCerts: (NSArray*)certs
{
    self = [super init];
    if (self) {
        _credential = [NSURLCredential credentialWithIdentity: identity
                                                 certificates: certs
                                                  persistence:NSURLCredentialPersistenceNone];
        _certificateChain = @[(__bridge id)identity];
        if (certs)
            _certificateChain = [_certificateChain arrayByAddingObjectsFromArray: certs];
    }
    return self;
}

- (NSString *)description {
    NSString* name = nil;
    SecCertificateRef cert = NULL;
    SecIdentityCopyCertificate(_credential.identity, &cert);
    if (cert) {
        name = CFBridgingRelease(SecCertificateCopySubjectSummary(cert));
        CFRelease(cert);
    }
    return $sprintf(@"%@[%@]", self.class, name);
}

@end
