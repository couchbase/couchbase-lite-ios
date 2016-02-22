//
//  CBLAuthorizer.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/21/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLAuthorizer.h"
#import "CBLMisc.h"
#import "CBLBase64.h"
#import "MYAnonymousIdentity.h"
#import "MYURLUtils.h"
#import <Security/Security.h>


@implementation CBLPasswordAuthorizer
{
    NSString* _basicAuthorization;
}

@synthesize credential=_credential;


- (instancetype) initWithCredential: (NSURLCredential*)credential {
    self = [super init];
    if (self) {
        if (!credential)
            return nil;
        Assert(credential.hasPassword);
        _credential = credential;
    }
    return self;
}


- (instancetype) initWithUser: (NSString*)user password: (NSString*)password {
    return [self initWithCredential: [NSURLCredential credentialWithUser: user
                                                                password: password
                                                     persistence: NSURLCredentialPersistenceNone]];
}


- (instancetype) initWithURL: (NSURL*)url {
    return [self initWithCredential: [url my_credentialForRealm: nil
                                      authenticationMethod: NSURLAuthenticationMethodHTTPBasic]];
}


- (NSString*) description {
    return $sprintf(@"%@[%@/****]", self.class, _credential.user);
}


- (NSString*) basicAuthorization {
    if (!_basicAuthorization) {
        NSString* username = _credential.user;
        NSString* password = _credential.password;
        if (username && password) {
            NSString* seekrit = $sprintf(@"%@:%@", username, password);
            seekrit = [CBLBase64 encode: [seekrit dataUsingEncoding: NSUTF8StringEncoding]];
            _basicAuthorization = [@"Basic " stringByAppendingString: seekrit];
        }
    }
    return _basicAuthorization;
}


- (void) authorizeURLRequest: (NSMutableURLRequest*)request {
    NSString* auth = self.basicAuthorization;
    if (auth)
        [request setValue: auth forHTTPHeaderField: @"Authorization"];
}


- (void) authorizeHTTPMessage: (CFHTTPMessageRef)message {
    NSString* auth = self.basicAuthorization;
    if (auth)
        CFHTTPMessageSetHeaderFieldValue(message, CFSTR("Authorization"),
                                         (__bridge CFStringRef)auth);
}


@end


#pragma mark - ANCHOR CERTS:


static NSArray* sAnchorCerts;
static BOOL sOnlyTrustAnchorCerts;


void CBLSetAnchorCerts(NSArray* certs, BOOL onlyThese) {
    @synchronized([CBLPasswordAuthorizer class]) {
        sAnchorCerts = certs.copy;
        sOnlyTrustAnchorCerts = onlyThese;
    }
}


static BOOL certMatchesPinned(SecCertificateRef cert, NSData* pinnedCertData, NSString* host) {
    if (!pinnedCertData)
        return NO;
    if (pinnedCertData.length == 20) {
        NSData* certDigest = MYGetCertificateDigest(cert);
        if (![certDigest isEqual: pinnedCertData]) {
            Warn(@"SSL cert for %@'s digest %@ doesn't match pinnedCert %@",
                 host, certDigest, pinnedCertData);
            return NO;
        }
    } else {
        NSData* certData = CFBridgingRelease(SecCertificateCopyData(cert));
        if (![certData isEqual: pinnedCertData]) {
            Warn(@"SSL cert for %@ does not equal pinnedCert", host);
            return NO;
        }
    }
    return YES;
}


// Checks whether the reported problems with a SecTrust are OK for us
static BOOL acceptProblems(SecTrustRef trust, NSString* host) {
    BOOL localDomain = ([host hasSuffix: @".local"] || [host hasSuffix: @".local."]);
    NSDictionary* resultDict = CFBridgingRelease(SecTrustCopyResult(trust));
    NSArray* detailsArray = resultDict[@"TrustResultDetails"];
    NSUInteger i = 0;
    for (NSDictionary* details in detailsArray) {
        // Each item in detailsArray corresponds to one certificate in the chain.
        for (NSString* problem in details) {
            // Check each problem with this cert and decide if it's acceptable:
            BOOL accept = NO;
            if ([problem isEqualToString: @"SSLHostname"] ||
                        [problem isEqualToString: @"AnchorTrusted"])
            {
                // Accept a self-signed cert from a local host (".local" domain)
                accept = (i == 0 && SecTrustGetCertificateCount(trust) == 1 && localDomain);
            }
#if !TARGET_OS_IPHONE
            else if ([problem isEqualToString: @"StatusCodes"]) {
                // Same thing, but on Mac they express the problem differently :-p
                if ([details[problem] isEqual: @[@(CSSMERR_APPLETP_HOSTNAME_MISMATCH)]])
                    accept = (i == 0 && SecTrustGetCertificateCount(trust) == 1 && localDomain);
            }
#endif
            if (!accept)
                return NO;
        }
        i++;
    }
    return YES;
}


// Updates a SecTrust's result to kSecTrustResultProceed
BOOL CBLForceTrusted(SecTrustRef trust) {
    CFDataRef exception = SecTrustCopyExceptions(trust);
    if (!exception)
        return NO;
    SecTrustResultType result;
    SecTrustSetExceptions(trust, exception);
    CFRelease(exception);
    SecTrustEvaluate(trust, &result);
    return YES;
}


BOOL CBLCheckSSLServerTrust(SecTrustRef trust, NSString* host, UInt16 port, NSData* pinned) {
    // Evaluate trust, using any global anchor certificates:
    @synchronized([CBLPasswordAuthorizer class]) {
        if (sAnchorCerts.count > 0) {
            SecTrustSetAnchorCertificates(trust, (__bridge CFArrayRef)sAnchorCerts);
            SecTrustSetAnchorCertificatesOnly(trust, sOnlyTrustAnchorCerts);
        }
    }
    SecTrustResultType result;
    OSStatus err = SecTrustEvaluate(trust, &result);
    if (err) {
        Warn(@"CBLCheckSSLServerTrust: SecTrustEvaluate failed with err %d", (int)err);
        return NO;
    }
    if (result != kSecTrustResultProceed && result != kSecTrustResultUnspecified &&
                result != kSecTrustResultRecoverableTrustFailure) {
        Warn(@"CBLCheckSSLServerTrust: SSL cert for %@ is not trustworthy (result=%d)",
             host, result);
        return NO;
    }

    // If using cert-pinning, accept cert iff it matches the pin:
    if (pinned) {
        if (certMatchesPinned(SecTrustGetCertificateAtIndex(trust, 0), pinned, host)) {
            CBLForceTrusted(trust);
            return YES;
        } else {
            return NO;
        }
    }

    if (result == kSecTrustResultProceed || result == kSecTrustResultUnspecified) {
        return YES;             // explicitly trusted
    } else if (acceptProblems(trust, host)) {
        CBLForceTrusted(trust);     // self-signed or host mismatch but we'll accept it anyway
        return YES;
    } else {
        return NO;              // nope
    }
}
