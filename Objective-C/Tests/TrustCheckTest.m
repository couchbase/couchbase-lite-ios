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
    SecCertificateRef certificate = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certData);
    return (SecCertificateRef) CFAutorelease(certificate);
}

- (SecTrustRef) getSecTrust: (SecPolicyRef)policy {
    SecTrustRef trust;
    NSArray* certArray = @[(__bridge id)[self getSelfSignedCertificate]];
    OSStatus status = SecTrustCreateWithCertificates((__bridge CFTypeRef)certArray, policy, &trust);
    AssertEqual(status, errSecSuccess);
    
    return (SecTrustRef) CFAutorelease(trust);
}

- (NSArray*) getAnchorCerts {
    SecCertificateRef certificate = [self getSelfSignedCertificate];
    NSArray* certArray = @[ (__bridge id)certificate ];
    return certArray;
}

- (void) testTrustCheckWithBasicPolicy {
    [CBLTrustCheck setAnchorCerts: [self getAnchorCerts] onlyThese: NO];
    
    SecPolicyRef policy = SecPolicyCreateBasicX509();
    CBLTrustCheck* trustCheck = [[CBLTrustCheck alloc] initWithTrust: [self getSecTrust: policy]
                                                                host: _host
                                                                port: 443];
    
    NSError* error;
    NSURLCredential* credential = [trustCheck checkTrust: &error];
    AssertNotNil(credential, @"Credentials is empty, certificate is expired or is invalid.");
    
    CFRelease(policy);
}

- (void) testTrustCheckWithSSLPolicy {
    [CBLTrustCheck setAnchorCerts: [self getAnchorCerts] onlyThese: NO];
    
    SecPolicyRef policy = SecPolicyCreateSSL(true, (__bridge CFStringRef)_host);
    CBLTrustCheck* trustCheck = [[CBLTrustCheck alloc] initWithTrust: [self getSecTrust: policy]
                                                                host: _host
                                                                port: 443];
    
    NSError* error;
    NSURLCredential* credential = [trustCheck checkTrust: &error];
    AssertNil(credential);
    
    CFRelease(policy);
}

- (void) testTrustCheckWithPinnedCert {
    SecPolicyRef policy = SecPolicyCreateSSL(true, (__bridge CFStringRef)_host);
    CBLTrustCheck* trustCheck = [[CBLTrustCheck alloc] initWithTrust: [self getSecTrust: policy]
                                                                host: _host
                                                                port: 443];
    
    NSError* error;
    NSURLCredential* credential = [trustCheck checkTrust: &error];
    AssertNil(credential);
    
    trustCheck.pinnedCertData = [self dataFromResource: @"SelfSigned" ofType: @"cer"];;
    credential = [trustCheck checkTrust: &error];
    AssertNotNil(credential);
    
    CFRelease(policy);
}

- (void) testTrustCheckWithAcceptOnlySelfSignedCert {
    SecPolicyRef policy = SecPolicyCreateSSL(true, (__bridge CFStringRef)_host);
    CBLTrustCheck* trustCheck = [[CBLTrustCheck alloc] initWithTrust: [self getSecTrust: policy]
                                                                host: _host
                                                                port: 443];
    
    NSError* error;
    NSURLCredential* credential = [trustCheck checkTrust: &error];
    AssertNil(credential);
    
    trustCheck.acceptOnlySelfSignedCert = true;
    credential = [trustCheck checkTrust: &error];
    AssertNotNil(credential);
    
    CFRelease(policy);
}

- (void) testTrustCheckWithAcceptOnlySelfSignedCertOnNonSelfSignedCert {
    // Note: Use Support/identity/gen_cert_chain.sh to regenerate the cert.
    NSString* cert1 = @"-----BEGIN CERTIFICATE-----\n"
    "MIIDOTCCAiGgAwIBAgIUfGHt2OKiOhe1TZ5dppfR9TH2B3IwDQYJKoZIhvcNAQEL\n"
    "BQAwGzEZMBcGA1UEAwwQSW50ZXJtZWRpYXRlMSBDQTAeFw0yNjA0MjEwMzQwMDVa\n"
    "Fw00NjA0MTYwMzQwMDVaMBQxEjAQBgNVBAMMCUxlYWYgQ2VydDCCASIwDQYJKoZI\n"
    "hvcNAQEBBQADggEPADCCAQoCggEBAI28+Lw0H55PyEvjXG7JwR2xUCqvXrNOZ35L\n"
    "ub6pdqmeOoZNE9ZsaAnncta5oFJzpGBLWCtuX6aJLfm/RJHhkRXUnVHC5hq1guVg\n"
    "tED5vdOrMOqqmQbBuQ17l9osuLlb0yWeT7M7L+LnuLGq5JvtKOVnTj9j9F7e3HD7\n"
    "vfNiiWxkDnfgt+3dG8xJ90dGSRrG6JPG/PU5dwlX2m2XwDdcD1M3yankIxo6cKKG\n"
    "+jb/noVoxHcmu1jdtH7bW37nsbrlDKeoyGHNUXbpMBjl97KBsfP0JFsotwdphTb3\n"
    "CFOsWCfz5WgYZBTFUm9sMVaeOO284VjAvVtyLXlRwoh3jZCPs3MCAwEAAaN8MHow\n"
    "CQYDVR0TBAIwADAOBgNVHQ8BAf8EBAMCBaAwHQYDVR0lBBYwFAYIKwYBBQUHAwEG\n"
    "CCsGAQUFBwMCMB0GA1UdDgQWBBT38n25EiWbtlb/OqIRaejegMDaYjAfBgNVHSME\n"
    "GDAWgBTspKsaXBRKzFl1WuNd98VlMJTpWzANBgkqhkiG9w0BAQsFAAOCAQEAnqa3\n"
    "/y7R1TrKHCXmi7UsiF8AdcEibqcnlYM7kruZbx0t3clLCCfSCrWj3mdmmWVY0yvP\n"
    "ddbTr/W2vTHyFXjdi5X3iK99xv4/Zdd5q0zQVMdNt7UvdeW4JS+1pROPu4EwibOA\n"
    "ywf7DrtQf42qWgZg998rf8d4k9VH9aNjnfjqOdNCUd6QiGBklxqVRF2EkQ0NarAy\n"
    "+NQb6lOHX2dg2qUmmiTEOwaPpoi4j1T+n2Zovpsq4/CfJ1EfYNbFtzyF5Sr9kIjh\n"
    "YEwVcrsidWLvS2BpahFlTan3yqcw6/Bu/rYJwM4bG1AaTScrs8zeGrcE4a2dwZms\n"
    "E0yZ88PX4uiZBCUcVQ==\n"
    "-----END CERTIFICATE-----\n";

    SecCertificateRef secCert1 = [self createSecCertFromPEM: cert1];
    NSArray* certs = @[(__bridge id) secCert1];
    
    SecTrustRef trust;
    SecPolicyRef policy = SecPolicyCreateSSL(YES, (__bridge CFStringRef)_host);
    
    OSStatus status = SecTrustCreateWithCertificates((__bridge CFTypeRef)certs, policy, &trust);
    AssertEqual(status, errSecSuccess);
    
    CBLTrustCheck* trustCheck = [[CBLTrustCheck alloc] initWithTrust: trust host: _host port: 443];
    trustCheck.acceptOnlySelfSignedCert = true;
    
    NSError* error;
    NSURLCredential* credential = [trustCheck checkTrust: &error];
    AssertNil(credential);
 
    CFRelease(policy);
    CFRelease(secCert1);
}

- (void) testTrustCHeckWithRootCerts {
    // Note: Use Support/identity/gen_cert_chain.sh to regenerate the certs.
    NSString* cert1 = @"-----BEGIN CERTIFICATE-----\n"
    "MIIDOTCCAiGgAwIBAgIUfGHt2OKiOhe1TZ5dppfR9TH2B3IwDQYJKoZIhvcNAQEL\n"
    "BQAwGzEZMBcGA1UEAwwQSW50ZXJtZWRpYXRlMSBDQTAeFw0yNjA0MjEwMzQwMDVa\n"
    "Fw00NjA0MTYwMzQwMDVaMBQxEjAQBgNVBAMMCUxlYWYgQ2VydDCCASIwDQYJKoZI\n"
    "hvcNAQEBBQADggEPADCCAQoCggEBAI28+Lw0H55PyEvjXG7JwR2xUCqvXrNOZ35L\n"
    "ub6pdqmeOoZNE9ZsaAnncta5oFJzpGBLWCtuX6aJLfm/RJHhkRXUnVHC5hq1guVg\n"
    "tED5vdOrMOqqmQbBuQ17l9osuLlb0yWeT7M7L+LnuLGq5JvtKOVnTj9j9F7e3HD7\n"
    "vfNiiWxkDnfgt+3dG8xJ90dGSRrG6JPG/PU5dwlX2m2XwDdcD1M3yankIxo6cKKG\n"
    "+jb/noVoxHcmu1jdtH7bW37nsbrlDKeoyGHNUXbpMBjl97KBsfP0JFsotwdphTb3\n"
    "CFOsWCfz5WgYZBTFUm9sMVaeOO284VjAvVtyLXlRwoh3jZCPs3MCAwEAAaN8MHow\n"
    "CQYDVR0TBAIwADAOBgNVHQ8BAf8EBAMCBaAwHQYDVR0lBBYwFAYIKwYBBQUHAwEG\n"
    "CCsGAQUFBwMCMB0GA1UdDgQWBBT38n25EiWbtlb/OqIRaejegMDaYjAfBgNVHSME\n"
    "GDAWgBTspKsaXBRKzFl1WuNd98VlMJTpWzANBgkqhkiG9w0BAQsFAAOCAQEAnqa3\n"
    "/y7R1TrKHCXmi7UsiF8AdcEibqcnlYM7kruZbx0t3clLCCfSCrWj3mdmmWVY0yvP\n"
    "ddbTr/W2vTHyFXjdi5X3iK99xv4/Zdd5q0zQVMdNt7UvdeW4JS+1pROPu4EwibOA\n"
    "ywf7DrtQf42qWgZg998rf8d4k9VH9aNjnfjqOdNCUd6QiGBklxqVRF2EkQ0NarAy\n"
    "+NQb6lOHX2dg2qUmmiTEOwaPpoi4j1T+n2Zovpsq4/CfJ1EfYNbFtzyF5Sr9kIjh\n"
    "YEwVcrsidWLvS2BpahFlTan3yqcw6/Bu/rYJwM4bG1AaTScrs8zeGrcE4a2dwZms\n"
    "E0yZ88PX4uiZBCUcVQ==\n"
    "-----END CERTIFICATE-----\n";
    

    NSString* cert2 = @"-----BEGIN CERTIFICATE-----\n"
    "MIIDITCCAgmgAwIBAgIUF38/yepjEesMLkI0Efq28/L/otMwDQYJKoZIhvcNAQEL\n"
    "BQAwFTETMBEGA1UEAwwKTXkgUm9vdCBDQTAeFw0yNjA0MjEwMzQwMDVaFw00NjA0\n"
    "MTYwMzQwMDVaMBsxGTAXBgNVBAMMEEludGVybWVkaWF0ZTEgQ0EwggEiMA0GCSqG\n"
    "SIb3DQEBAQUAA4IBDwAwggEKAoIBAQDHkZNCO4kCpdrS88Q4IycqaFfQxySojYL1\n"
    "bHD5spFEM4SOqqFhbGIw+S+rSVWbHS576EbGfWspZKyek6rzrqDHWX0/ArlVg419\n"
    "iiv3av+gZyy6Eka9bWUg3UQG5A8xetXlcw0OiWc0ZHnU73DHQFTZyYK/qEN2SKTu\n"
    "G8MThnNMNN/UuRiN2rVLTyObey+WSva3dw3z38QViWV0jdCvI5NPPDeN2e8sdtvH\n"
    "6mBuqsDjlqr4VRefsJZOpKccT7CGXlLbnzWraV37pZs+iyuMKjgfzxJYMXwHktHs\n"
    "BaPZZXF3c+qRRshXeCtCQjpR0qP9d9mwaTbEw8969IIPuQR1AR/3AgMBAAGjYzBh\n"
    "MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMB0GA1UdDgQWBBTspKsa\n"
    "XBRKzFl1WuNd98VlMJTpWzAfBgNVHSMEGDAWgBRTvqDx9JEHzShYKU0IgbCfCtQF\n"
    "dzANBgkqhkiG9w0BAQsFAAOCAQEAAzpj4T5knFZmuIFGIsZAT28ckFH0zUsiEPMh\n"
    "jG8FKKldncJ8iZdGRStXsaLfqBwuvWcxo64nhDSxNqCVrw8ESiDz40EXBKUDxqUa\n"
    "5U29wGG5fXR5ds00BoWpHcBBH3MHaxxKt3pIEaZIN/5q6DbftqE6eaSgakpPcXdL\n"
    "CNH+7+dIlHj9K6gc+yyw5eJkiOB+3ooJQ9sIdfHkVHhh+p+C3RIy/uhPd0PAr2FW\n"
    "ZZK01p3tGVThCYXg7/6sAoV4F3tQB68lhVqSJ5khLfAVhU9G0ADZsu8myJx4IJP7\n"
    "MIbBKciERRz0R1wcmg3dF+RxINqv8N2CidK8XxT6HVHRZy32uA==\n"
    "-----END CERTIFICATE-----\n";

    NSString* cert3 = @"-----BEGIN CERTIFICATE-----\n"
    "MIIDHTCCAgWgAwIBAgIUAqX+3wUmGFBTIEMq7LrRMLvD0RQwDQYJKoZIhvcNAQEL\n"
    "BQAwFTETMBEGA1UEAwwKTXkgUm9vdCBDQTAgFw0yNjA0MjEwMzQwMDVaGA8yMDY2\n"
    "MDQxMTAzNDAwNVowFTETMBEGA1UEAwwKTXkgUm9vdCBDQTCCASIwDQYJKoZIhvcN\n"
    "AQEBBQADggEPADCCAQoCggEBAKe0OZQt7Qgfups5LNduBZ/9CS+A4UAmDAeLH3Nd\n"
    "xewTrh03c3/2A7Ue7tPulaVZPjtQK3yrQ3BMnzdlC5hVZZveyEgo9Pyroo0t4vGk\n"
    "eA0x2uxm6nFA5aqOYRnFvo8CyTZPv/onqrZ3SryN6mu/KgvwM/adh8x7PyuXVtij\n"
    "jrVU60yKWo7geY6U4SX6dH13Wr6W8dUGYUhpdgW1/A6PFl1ZjfxemGgO2WcOY5SI\n"
    "Pn5KrqI6FNepHnehXWuIrNe0/FJx9btuAVwZzE0fE1TPZrRsKK50Z06m7k3DysDu\n"
    "j5ruCSrCZ7rVYw7elvAEFwSp4vp1Nbqjfl50RI760fBhsWsCAwEAAaNjMGEwHQYD\n"
    "VR0OBBYEFFO+oPH0kQfNKFgpTQiBsJ8K1AV3MB8GA1UdIwQYMBaAFFO+oPH0kQfN\n"
    "KFgpTQiBsJ8K1AV3MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMA0G\n"
    "CSqGSIb3DQEBCwUAA4IBAQBCekp/3rCvDE6tArDbJkTNhGZ9VtCQINrxtZdVjm5p\n"
    "MGSZi5E/fLcccUUw7eIrYB95p7/CMLVP8ygP7lnjzScHce/Ep/0htvqU0sm+P/v1\n"
    "z1deizChuIIHWf1IFpBMzFpNmEVwcOv8gj+WsTMKs+tHUR6yhbxH+smDCO4Qm5bL\n"
    "CHBZ0B20J7Rx281U4XncyHSQbsnWhuG7C9q8q+itCxKTkIbFSoc4EUuxqjMVWWoz\n"
    "hEJ4U/fPs8I5XdLzvd47cq4JywkAiFBo1Em8kLKQAijEI1ZYNb1sq40iQo07U32Q\n"
    "+r6qcFWMzBr3FCfbSUX2BP0xzGQp5jkDOxdE3+XnDY8k\n"
    "-----END CERTIFICATE-----\n";
    
    SecCertificateRef secCert1 = [self createSecCertFromPEM: cert1];
    SecCertificateRef secCert2 = [self createSecCertFromPEM: cert2];
    SecCertificateRef secCert3 = [self createSecCertFromPEM: cert3];
    
    SecTrustRef trust;
    SecPolicyRef policy = SecPolicyCreateBasicX509();
    
    // Validate leaf cert:
    
    NSArray* certs = @[(__bridge id) secCert1];
    OSStatus status = SecTrustCreateWithCertificates((__bridge CFTypeRef)certs, policy, &trust);
    AssertEqual(status, errSecSuccess);
    
    NSError* error;
    NSURLCredential* credential;
    
    CBLTrustCheck* trustCheck = [[CBLTrustCheck alloc] initWithTrust: trust];
    credential = [trustCheck checkTrust: &error];
    AssertNil(credential);
    
    trustCheck.rootCerts = @[(__bridge id) secCert3];
    credential = [trustCheck checkTrust: &error];
    AssertNil(credential);
    
    trustCheck.rootCerts = @[(__bridge id) secCert2];
    credential = [trustCheck checkTrust: &error];
    AssertNotNil(credential);
    
    CFRelease(trust);
    trust = nil;
    
    // Validate cert chain:
    
    certs = @[(__bridge id) secCert1, (__bridge id) secCert2];
    status = SecTrustCreateWithCertificates((__bridge CFTypeRef)certs, policy, &trust);
    AssertEqual(status, errSecSuccess);
    
    trustCheck = [[CBLTrustCheck alloc] initWithTrust: trust];
    credential = [trustCheck checkTrust: &error];
    AssertNil(credential);
    
    trustCheck.rootCerts = @[(__bridge id) secCert3];
    credential = [trustCheck checkTrust: &error];
    AssertNotNil(credential);
    
    CFRelease(policy);
    CFRelease(secCert1);
    CFRelease(secCert2);
    CFRelease(secCert3);
}

@end
