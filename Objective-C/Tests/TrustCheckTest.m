//
//  TrustCheckTest.m
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

#import "CBLTestCase.h"
#import "CBLTrustCheck.h"

@interface TrustCheckTest : CBLTestCase

@end

@implementation TrustCheckTest {
    NSString* _host;
}

- (void) setUp {
    [super setUp];
    
    _host = @"https://www.couchbase.com/";
}

- (SecCertificateRef) getSelfSignedCertificate {
    NSData* certData = [self dataFromResource: @"SelfSigned" ofType: @"cer"];
    SecCertificateRef certificate = SecCertificateCreateWithData(NULL,
                                                                 (__bridge CFDataRef)certData);
    return (SecCertificateRef) CFAutorelease(certificate);
}

- (SecTrustRef) getSecTrust: (SecPolicyRef) policy {
    SecTrustRef trust;
    NSArray* certArray = @[ (__bridge id)[self getSelfSignedCertificate] ];
    OSStatus status = SecTrustCreateWithCertificates((__bridge CFTypeRef)certArray,
                                                     policy,
                                                     &trust);
    AssertEqual(status, errSecSuccess);
    
    return (SecTrustRef) CFAutorelease(trust);
}

- (NSArray*) getAnchorCerts {
    SecCertificateRef certificate = [self getSelfSignedCertificate];
    NSArray* certArray = @[ (__bridge id)certificate ];
    return certArray;
}

- (void) testTrustCheckSelfSignedCertificateBasicPolicy {
    NSError* error;
    
    [CBLTrustCheck setAnchorCerts: [self getAnchorCerts] onlyThese: NO];
    SecPolicyRef policy = SecPolicyCreateBasicX509();
    CBLTrustCheck* trustCheck = [[CBLTrustCheck alloc] initWithTrust: [self getSecTrust: policy]
                                                                host: _host
                                                                port: 443];
    if (policy) { CFRelease(policy); }
    NSURLCredential* credential = [trustCheck checkTrust: &error];
    AssertNotNil(credential, @"Credentials is empty, certificate is expired or is invalid.");
}

- (void) testTrustCheckSelfSignedCertificateWithSSLPolicy {
    NSError* error;
    
    [CBLTrustCheck setAnchorCerts: [self getAnchorCerts] onlyThese: NO];
    SecPolicyRef policy = SecPolicyCreateSSL(YES, (__bridge CFStringRef)_host);
    CBLTrustCheck* trustCheck = [[CBLTrustCheck alloc] initWithTrust: [self getSecTrust: policy]
                                                                host: _host
                                                                port: 443];
    if (policy) { CFRelease(policy); }
    NSURLCredential* credential = [trustCheck checkTrust: &error];
    AssertNil(credential);
}

- (void) testTrustCheckSelfSignedCertificateWithPinnedCertificate {
    NSError* error;
    NSData* certData = [self dataFromResource: @"SelfSigned" ofType: @"cer"];
    
    [CBLTrustCheck setAnchorCerts: [self getAnchorCerts] onlyThese: NO];
    SecPolicyRef policy = SecPolicyCreateSSL(YES, (__bridge CFStringRef)_host);
    CBLTrustCheck* trustCheck = [[CBLTrustCheck alloc] initWithTrust: [self getSecTrust: policy]
                                                                host: _host
                                                                port: 443];
    if (policy) { CFRelease(policy); }
    trustCheck.pinnedCertData = certData;
    NSURLCredential* credential = [trustCheck checkTrust: &error];
    AssertNotNil(credential);
}

@end
