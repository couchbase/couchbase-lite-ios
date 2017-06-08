//
//  CBLTrustUtils.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/6/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTrustCheck.h"
#import "MYErrorUtils.h"


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
    BOOL localDomain = ([_host hasSuffix: @".local"] || [_host hasSuffix: @".local."]);
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
                // This is a self-signed cert, or an unknown root cert:
                if (localDomain && i == 0 && SecTrustGetCertificateCount(_trust) == 1) {
                    // Accept a self-signed cert from a local host (".local" domain)
                    continue;
                } else {
                    MYReturnError(outError,
                                  NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorDomain,
                                  @"Server has self-signed or unknown root SSL certificate");
                    return NO;
                }
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

    NSURLCredential* credential = [NSURLCredential credentialForTrust: _trust];

    // If using cert-pinning, accept cert iff it matches the pin:
    if (_pinnedCertData) {
        SecCertificateRef cert = SecTrustGetCertificateAtIndex(_trust, 0);
        if ([_pinnedCertData isEqual: CFBridgingRelease(SecCertificateCopyData(cert))]) {
            [self forceTrusted];
            return credential;
        } else {
            MYReturnError(outError, NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorDomain,
                          @"Certificate does not match pinned cert");
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


@end
