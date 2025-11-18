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

#ifdef COUCHBASE_ENTERPRISE
@synthesize acceptOnlySelfSignedCert=_acceptOnlySelfSignedCert, rootCerts=_rootCerts;
#endif

static NSArray* sAnchorCerts;
static BOOL sOnlyTrustAnchorCerts;

+ (void) setAnchorCerts: (NSArray*)certs onlyThese: (BOOL)onlyThese {
    @synchronized(self) {
        sAnchorCerts = certs.copy;
        sOnlyTrustAnchorCerts = onlyThese;
    }
}

- (instancetype) initWithTrust: (SecTrustRef)trust host: (nullable NSString*)host port: (uint16_t)port {
    NSParameterAssert(trust);
    self = [super init];
    if (self) {
        _trust = (SecTrustRef)CFRetain(trust);
        _host = host;
        _port = port;
    }
    return self;
}

- (instancetype) initWithTrust: (SecTrustRef)trust {
    return [self initWithTrust: trust host: nil port: 0];
}

- (instancetype) initWithChallenge: (NSURLAuthenticationChallenge*)challenge {
    NSURLProtectionSpace* space = challenge.protectionSpace;
    return [self initWithTrust: space.serverTrust host: space.host port: (uint16_t)space.port];
}

- (void) dealloc {
    CFRelease(_trust);
}

- (NSString*) description {
    NSString* port = _port > 0 ? [NSString stringWithFormat: @"%d", _port] : @"";
    return [NSString stringWithFormat: @"%@[%@:%@]", self.class, (_host ?: @""), port];
}

/**
 Validates whether the issues reported by SecTrust are acceptable if trust validation
 result is not kSecTrustResultProceed or kSecTrustResultUnspecified.
 Note: Used only when no pinned certificate or self-signed certificate restriction is set.
 */
- (BOOL) shouldAcceptProblems: (NSError**)outError {
    NSDictionary* resultDict = CFBridgingRelease(SecTrustCopyResult(_trust));
    NSArray* detailsArray = resultDict[@"TrustResultDetails"];
    for (NSDictionary* details in detailsArray) {
        // Each item in detailsArray corresponds to one certificate in the chain.
        for (NSString* problem in details) {
            // Check each problem with this cert and decide if it's acceptable:
            if ([problem isEqualToString: @"SSLHostname"]
        #if !TARGET_OS_IPHONE
                || ([problem isEqualToString: @"StatusCodes"] &&
                    [details[problem] isEqual: @[@(CSSMERR_APPLETP_HOSTNAME_MISMATCH)]])
        #endif
            ) {
                if (!_host) {
                    continue; // When no host specified, accept and check next problem
                }
                MYReturnError(outError, NSURLErrorServerCertificateUntrusted, NSURLErrorDomain,
                                  @"Server TLS certificate has a hostname mismatch.");
                return NO;
            } else {
                if ([problem isEqualToString: @"AnchorTrusted"]) {
                    MYReturnError(outError, NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorDomain,
                                  @"Server TLS certificate has an unknown root or is self-signed.");
                } else {
                    // Any other problem:
                    MYReturnError(outError, NSURLErrorServerCertificateUntrusted, NSURLErrorDomain,
                                  @"Server TLS certificate is untrusted (problem = %@)", problem);
                }
                return NO;
            }
        }
    }
    return YES;
}

// Updates a SecTrust's result to kSecTrustResultProceed
- (void) forceTrusted {
    CFDataRef exception = SecTrustCopyExceptions(_trust);
    if (!exception) {
        return; // Already trust
    }
    SecTrustSetExceptions(_trust, exception);
    CFRelease(exception);
    
    CFErrorRef error;
    BOOL trusted = SecTrustEvaluateWithError(_trust, &error);
    if (!trusted) {
        CBLWarnError(Sync, @"Failed to force trust");
    }
}

- (nullable NSURLCredential*) checkTrust: (NSError**)outError {
    // Register any global anchor certificates:
    @synchronized(self) {
        if (sAnchorCerts.count > 0) {
            SecTrustSetAnchorCertificates(_trust, (__bridge CFArrayRef)sAnchorCerts);
            SecTrustSetAnchorCertificatesOnly(_trust, sOnlyTrustAnchorCerts);
        }
    }
    
#ifdef COUCHBASE_ENTERPRISE
    if (_rootCerts.count > 0) {
        SecTrustSetAnchorCertificates(_trust, (__bridge CFArrayRef)_rootCerts);
        SecTrustSetAnchorCertificatesOnly(_trust, true);
    }
#endif
    
    // Credential:
    NSURLCredential* credential = [NSURLCredential credentialForTrust: _trust];
    
    // Evaluate trust:
    SecTrustResultType result;
    OSStatus osStatus;
    CFErrorRef cferr;
    BOOL trusted = SecTrustEvaluateWithError(_trust, &cferr);
    if (!trusted) {
        NSError* error = (__bridge NSError*)cferr;
        CBLLogVerbose(Sync, @"%@: Trust evaluation returned (continuing checks) (%ld) : %@",
                      self, (long)error.code, error.localizedDescription);
    }
    
    osStatus = SecTrustGetTrustResult(_trust, &result);
    if (osStatus) {
        CBLWarn(Default, @"%@: Failed to get trust result (%d)", self, (int)osStatus);
        MYReturnError(outError, osStatus, NSOSStatusErrorDomain, @"Failed to get trust result.");
        return nil;
    }
    
    if (result != kSecTrustResultProceed &&
        result != kSecTrustResultUnspecified &&
        result != kSecTrustResultRecoverableTrustFailure) {
        MYReturnError(outError, NSURLErrorServerCertificateUntrusted, NSURLErrorDomain,
                      @"Server TLS certificate is untrusted.");
        return nil;
    }
    
    // If using pinned cert, accept cert if it matches the pinned cert:
    if (_pinnedCertData) {
        CFArrayRef certs = SecTrustCopyCertificateChain(_trust);
        CFIndex count = CFArrayGetCount(certs);
        for (CFIndex i = 0; i < count; i++) {
            SecCertificateRef cert = (SecCertificateRef)CFArrayGetValueAtIndex(certs, i);
            NSData* certData = CFBridgingRelease(SecCertificateCopyData(cert));
            if ([_pinnedCertData isEqual:certData]) {
                CFRelease(certs);
                [self forceTrusted];
                return credential;
            }
        }

        CFRelease(certs);
        MYReturnError(outError,
                      NSURLErrorServerCertificateHasUnknownRoot,
                      NSURLErrorDomain,
                      @"Server TLS Certificate does not match the pinned cert.");
        return nil;
    }
    
#ifdef COUCHBASE_ENTERPRISE
    else if (_acceptOnlySelfSignedCert) {
        NSError* err;
        BOOL isSelfSigned = [self isSelfSignedCert: &err];
        if (err) {
            MYReturnError(outError, NSURLErrorServerCertificateUntrusted, NSURLErrorDomain,
                          @"Invalid server TLS certificate.");
            return nil;
        }
        
        if (!isSelfSigned) {
            MYReturnError(outError, NSURLErrorServerCertificateUntrusted, NSURLErrorDomain,
                @"Server TLS certificate is not self-signed as required.");
            return nil;
        }
        [self forceTrusted];
        return credential;
    }
#endif
    
    if (result == kSecTrustResultProceed || result == kSecTrustResultUnspecified) {
        return credential;          // Explicitly trusted
    } else if ([self shouldAcceptProblems: outError]) {
        [self forceTrusted];        // Allow hostname mismatched when verifying with root certs
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
    
    C4Cert* c4cert = nil;
#if __IPHONE_OS_VERSION_MAX_REQUIRED >= 150000
    if (@available(iOS 15.0, *)) {
        CFArrayRef certs = SecTrustCopyCertificateChain(_trust);
        SecCertificateRef certRef = (SecCertificateRef)CFArrayGetValueAtIndex(certs, 0);
        c4cert = toC4Cert(@[(__bridge id) certRef], outError);
        CFRelease(certs);
    } else
#endif
    {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        SecCertificateRef certRef = SecTrustGetCertificateAtIndex(_trust, 0);
#pragma clang diagnostic pop
        c4cert = toC4Cert(@[(__bridge id) certRef], outError);
    }
    
    if (!c4cert)
        return NO;
    
    BOOL isSelfSigned = c4cert_isSelfSigned(c4cert);
    c4cert_release(c4cert);
    return isSelfSigned;
}

#endif

@end
