//
//  CBLTrustCheck.m
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
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

#import "CBLTrustCheck.h"
#import "c4.h"

#ifdef COUCHBASE_ENTERPRISE
#import "CBLCert.h"
#endif

extern "C" {
#import "MYErrorUtils.h"
}

@implementation CBLTrustCheck
{
    SecTrustRef _trust;
    NSString* _host;
    uint16_t _port;
}

@synthesize pinnedCertData=_pinnedCertData;

static NSArray* sAnchorCerts;
static BOOL sOnlyTrustAnchorCerts;

+ (void) setAnchorCerts: (NSArray*)certs onlyThese: (BOOL)onlyThese {
    @synchronized(self) {
        sAnchorCerts = certs.copy;
        sOnlyTrustAnchorCerts = onlyThese;
    }
}

- (instancetype) initWithTrust: (SecTrustRef)trust host: (NSString*)host port: (uint16_t)port {
    NSParameterAssert(trust);
    NSParameterAssert(host);
    self = [super init];
    if (self) {
        _trust = (SecTrustRef)CFRetain(trust);
        _host = host;
        _port = port;
    }
    return self;
}

- (instancetype) initWithChallenge: (NSURLAuthenticationChallenge*)challenge {
    NSURLProtectionSpace* space = challenge.protectionSpace;
    return [self initWithTrust: space.serverTrust
                          host: space.host
                          port: (uint16_t)space.port];
}

- (void) dealloc {
    CFRelease(_trust);
}

- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%@:%d]", self.class, _host, _port];
}

// Checks whether the reported problems with a SecTrust are OK for us
- (BOOL) shouldAcceptProblems: (NSError**)outError {
    NSDictionary* resultDict = CFBridgingRelease(SecTrustCopyResult(_trust));
    NSArray* detailsArray = resultDict[@"TrustResultDetails"];
    NSUInteger i = 0;
    for (NSDictionary* details in detailsArray) {
        // Each item in detailsArray corresponds to one certificate in the chain.
        for (NSString* problem in details) {
            // Check each problem with this cert and decide if it's acceptable:
            if ([problem isEqualToString: @"SSLHostname"]
                    || [problem isEqualToString: @"AnchorTrusted"]
#if !TARGET_OS_IPHONE
                    || ([problem isEqualToString: @"StatusCodes"]   // used in older macOS
                         && [details[problem] isEqual: @[@(CSSMERR_APPLETP_HOSTNAME_MISMATCH)]])
#endif
            ) {
                MYReturnError(outError, NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorDomain,
                              @"Server has self-signed or unknown root SSL certificate!!");
                return NO;
            } else {
                // Any other problem:
                MYReturnError(outError, NSURLErrorServerCertificateUntrusted, NSURLErrorDomain,
                              @"Server SSL certificate is untrustworthy");
                return NO;
            }
        }
        i++;
    }
    return YES;
}

// Updates a SecTrust's result to kSecTrustResultProceed
- (BOOL) forceTrusted {
    CFDataRef exception = SecTrustCopyExceptions(_trust);
    if (!exception)
        return NO;
    SecTrustResultType result;
    SecTrustSetExceptions(_trust, exception);
    CFRelease(exception);
    SecTrustEvaluate(_trust, &result);
    return YES;
}


- (NSURLCredential*) checkTrust: (NSError**)outError {
    // Register any global anchor certificates:
    @synchronized(self) {
        if (sAnchorCerts.count > 0) {
            SecTrustSetAnchorCertificates(_trust, (__bridge CFArrayRef)sAnchorCerts);
            SecTrustSetAnchorCertificatesOnly(_trust, sOnlyTrustAnchorCerts);
        }
    }
    
    // Credential:
    NSURLCredential* credential = [NSURLCredential credentialForTrust: _trust];
    
    // Evaluate trust:
    SecTrustResultType result;
    OSStatus err = SecTrustEvaluate(_trust, &result);
    if (err) {
        CBLWarn(Default, @"%@: SecTrustEvaluate failed with err %d", self, (int)err);
        MYReturnError(outError, err, NSOSStatusErrorDomain, @"Error evaluating certificate");
        return nil;
    }
    if (result != kSecTrustResultProceed && result != kSecTrustResultUnspecified
                                         && result != kSecTrustResultRecoverableTrustFailure) {
        MYReturnError(outError, NSURLErrorServerCertificateUntrusted, NSURLErrorDomain,
                      @"Server SSL certificate is untrustworthy");
        return nil;
    }

    // If using cert-pinning, accept cert iff it matches the pin:
    if (_pinnedCertData) {
        SecCertificateRef cert = SecTrustGetCertificateAtIndex(_trust, 0);
        if ([_pinnedCertData isEqual: CFBridgingRelease(SecCertificateCopyData(cert))]) {
            [self forceTrusted];
            return credential;
        } else {
            MYReturnError(outError, NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorDomain,
                          @"Server SSL Certificate does not match pinned cert");
            return nil;
        }
    }

    if (result == kSecTrustResultProceed || result == kSecTrustResultUnspecified) {
        return credential;          // explicitly trusted
    } else if ([self shouldAcceptProblems: outError]) {
        [self forceTrusted];    // self-signed or host mismatch but we'll accept it anyway
        return credential;
    } else {
        return nil;
    }
}

#ifdef COUCHBASE_ENTERPRISE

- (BOOL) isSelfSignedCert: (NSError**)outError {
    CFIndex certCount = SecTrustGetCertificateCount(_trust);
    if (certCount != 1)
        return NO;
    
    SecCertificateRef certRef = SecTrustGetCertificateAtIndex(_trust, 0);
    C4Cert* c4cert = toC4Cert(@[(__bridge id) certRef], outError);
    if (!c4cert)
        return NO;
    
    BOOL isSelfSigned = c4cert_isSelfSigned(c4cert);
    c4cert_release(c4cert);
    return isSelfSigned;
}

- (NSURLCredential*) acceptOnlySelfSignedCert: (NSError**)outError {
    // Credential:
    NSURLCredential* credential = [NSURLCredential credentialForTrust: _trust];
    
    // Check if the certificate is a self-signed cert:
    NSError* error;
    BOOL isSelfSigned = [self isSelfSignedCert: &error];
    if (error) {
        MYReturnError(outError, NSURLErrorServerCertificateUntrusted, NSURLErrorDomain,
                      @"Server SSL certificate is invalid");
        return nil;
    }
    
    if (!isSelfSigned) {
        MYReturnError(outError, NSURLErrorServerCertificateUntrusted, NSURLErrorDomain,
            @"Server SSL certificate is not self-signed");
        return nil;
    }
    
    [self forceTrusted];
    return credential;
}

#endif

@end
