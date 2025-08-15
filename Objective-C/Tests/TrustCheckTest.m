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
    NSString* cert1 = @"-----BEGIN CERTIFICATE-----\n"
    "MIIDNjCCAh6gAwIBAgIUSEKVQRJXTLZDc61Yz3mwNPkCQ4AwDQYJKoZIhvcNAQEL\n"
    "BQAwGzEZMBcGA1UEAwwQSW50ZXJtZWRpYXRlMSBDQTAeFw0yNTA0MTgyMDU5NTJa\n"
    "Fw0yNjA0MTgyMDU5NTJaMBQxEjAQBgNVBAMMCUxlYWYgQ2VydDCCASIwDQYJKoZI\n"
    "hvcNAQEBBQADggEPADCCAQoCggEBAI2iEIMjedwzRjiyLrMaJjklwcNHeSh1CIEh\n"
    "eEblXotlhR8Rhs5hTOqyasREy4fyv7VhVzKtVjGDeD0E5rrEhXDVxlLhXcp8n2IA\n"
    "GMgSSvdmFN9GFpgYW6Ln/o7CtdpMSmYYKhUzlzkYq2FfbKhswgq/+14j4yzScgxn\n"
    "kx/yEN+Dr8lQXUuiCN1onfBVdjimhku1Y7eIRnIAAV2IYo9RHoJq6TYqSVdkh1ml\n"
    "M2xXSbeS83gYeeETqD2u2BjIhZM2D6JUu0RrGCNT5R1OpEe9NHPmaUIqG4zI8hal\n"
    "PNeTzrYi2k+FtG4Iukn648O2UVb3nFZSXy18r1heYro6NHy145cCAwEAAaN5MHcw\n"
    "CQYDVR0TBAIwADALBgNVHQ8EBAMCBaAwHQYDVR0lBBYwFAYIKwYBBQUHAwEGCCsG\n"
    "AQUFBwMCMB0GA1UdDgQWBBT7N+cwj4+r45KcMU/yv7xPtjMp0TAfBgNVHSMEGDAW\n"
    "gBTsGfW/AozECLwwqKy4TklKc8P3UDANBgkqhkiG9w0BAQsFAAOCAQEAe1heX+8Q\n"
    "ZSsbPu+VLJj9VaBj9rqlVT7oi+AD5Hxs/NruF8DdOSaYBftH9Z/ZAFqLWm5Gdbn3\n"
    "Uhp3QpVleSWBwMKC5yOTRDxItJoZ6ng6hK5rONw/k3z3lWzHbV5stV8xKKwc5gtz\n"
    "18Fqklfv4ULai1NJPZJO2KSkH98jX5JlCDMvxLllXwJKfRzpAdmmphyzNLEkZvOu\n"
    "H66QsM03v3/8hOU+GDljvyayN7demgTdQ7k9pLVti+3Jw4icw2X0VYn1ql0mXepW\n"
    "+7zStFNlEqixwoJrL2hBmmtQp0k9r0SQKDAYu33MUMx9xrsrqCb3pJ13jvtzKA4w\n"
    "r+WpI4oH5gbfdA==\n"
    "-----END CERTIFICATE-----";
    
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
    NSString* cert1 = @"-----BEGIN CERTIFICATE-----\n"
    "MIIDNjCCAh6gAwIBAgIUSEKVQRJXTLZDc61Yz3mwNPkCQ4AwDQYJKoZIhvcNAQEL\n"
    "BQAwGzEZMBcGA1UEAwwQSW50ZXJtZWRpYXRlMSBDQTAeFw0yNTA0MTgyMDU5NTJa\n"
    "Fw0yNjA0MTgyMDU5NTJaMBQxEjAQBgNVBAMMCUxlYWYgQ2VydDCCASIwDQYJKoZI\n"
    "hvcNAQEBBQADggEPADCCAQoCggEBAI2iEIMjedwzRjiyLrMaJjklwcNHeSh1CIEh\n"
    "eEblXotlhR8Rhs5hTOqyasREy4fyv7VhVzKtVjGDeD0E5rrEhXDVxlLhXcp8n2IA\n"
    "GMgSSvdmFN9GFpgYW6Ln/o7CtdpMSmYYKhUzlzkYq2FfbKhswgq/+14j4yzScgxn\n"
    "kx/yEN+Dr8lQXUuiCN1onfBVdjimhku1Y7eIRnIAAV2IYo9RHoJq6TYqSVdkh1ml\n"
    "M2xXSbeS83gYeeETqD2u2BjIhZM2D6JUu0RrGCNT5R1OpEe9NHPmaUIqG4zI8hal\n"
    "PNeTzrYi2k+FtG4Iukn648O2UVb3nFZSXy18r1heYro6NHy145cCAwEAAaN5MHcw\n"
    "CQYDVR0TBAIwADALBgNVHQ8EBAMCBaAwHQYDVR0lBBYwFAYIKwYBBQUHAwEGCCsG\n"
    "AQUFBwMCMB0GA1UdDgQWBBT7N+cwj4+r45KcMU/yv7xPtjMp0TAfBgNVHSMEGDAW\n"
    "gBTsGfW/AozECLwwqKy4TklKc8P3UDANBgkqhkiG9w0BAQsFAAOCAQEAe1heX+8Q\n"
    "ZSsbPu+VLJj9VaBj9rqlVT7oi+AD5Hxs/NruF8DdOSaYBftH9Z/ZAFqLWm5Gdbn3\n"
    "Uhp3QpVleSWBwMKC5yOTRDxItJoZ6ng6hK5rONw/k3z3lWzHbV5stV8xKKwc5gtz\n"
    "18Fqklfv4ULai1NJPZJO2KSkH98jX5JlCDMvxLllXwJKfRzpAdmmphyzNLEkZvOu\n"
    "H66QsM03v3/8hOU+GDljvyayN7demgTdQ7k9pLVti+3Jw4icw2X0VYn1ql0mXepW\n"
    "+7zStFNlEqixwoJrL2hBmmtQp0k9r0SQKDAYu33MUMx9xrsrqCb3pJ13jvtzKA4w\n"
    "r+WpI4oH5gbfdA==\n"
    "-----END CERTIFICATE-----";
    
    NSString* cert2 = @"-----BEGIN CERTIFICATE-----\n"
    "MIIDGzCCAgOgAwIBAgIUOaHMHeI4Bi1f5qazRfVdwADeSu0wDQYJKoZIhvcNAQEL\n"
    "BQAwFTETMBEGA1UEAwwKTXkgUm9vdCBDQTAeFw0yNTA0MTgyMDU3NDlaFw0yODAx\n"
    "MTMyMDU3NDlaMBsxGTAXBgNVBAMMEEludGVybWVkaWF0ZTEgQ0EwggEiMA0GCSqG\n"
    "SIb3DQEBAQUAA4IBDwAwggEKAoIBAQDjGUNBtkP0K3+pfw3nxSiYFYbM7pJ6vyoy\n"
    "y3eAfm/GBNmN9i6uWwYBtbEkliurwM9usoYlQwKSeYI2NA1PfGabOkra1NUppoJs\n"
    "LmEAqMy9K1x5Os6kU7ye9Yoho+YoqWr4LiYII2ftRUBm3Ns5VJEmx1jIH9zHlDEc\n"
    "KOGQ3KkMAvkFrOkJaPVCTB0iKNcVYCmCmu0GrCU6qsqpBeqqXdGIwVgH0Zg/Nm0R\n"
    "R2jh48fvIpbC3A0BVefLaK8Uhnp8M4QVCcbqJOUsa5R7JBPm78FfqeCEuwQkPXet\n"
    "PEqMAg+BAvwN/+KpyDnX4SldCYyhsf5lU6MBGpgnfv6KTPi0LCJlAgMBAAGjXTBb\n"
    "MAwGA1UdEwQFMAMBAf8wCwYDVR0PBAQDAgEGMB0GA1UdDgQWBBTsGfW/AozECLww\n"
    "qKy4TklKc8P3UDAfBgNVHSMEGDAWgBSNIeGLgFRnq32qpUpIb/V4LpGbJjANBgkq\n"
    "hkiG9w0BAQsFAAOCAQEAiQqURRms+IWk2D6ZiKqJNYeLuqLEebebL6+lwSBrmHXY\n"
    "iO4TxcqYoQ1+xi2jU+IyPWsqSHZOL3lta3pgjyGd6zkO5XsPpnST7SK8v0X2Zmy3\n"
    "SRcVyLKC5zPwz0V7njN9LKhY1iN1gGH6iBoYdRg9urEQWIZ7aSYw7mnhVpacaD9p\n"
    "ugrE/b+278qoBi5Wa4s18nOGW3w98UfkT+u1SqO3Ct9VB8d1t/o5pSY3lScXKu+q\n"
    "zS8WWsTFJ6vYLOPD+4S920+IPwQ9R2AATIHdvIqXKkxzHo9aSKfaXhAra7ujUgII\n"
    "pRv6M27PrBqRfPBsSe3pkN6zGXAzI9FxVL9GW+miMg==\n"
    "-----END CERTIFICATE-----";
    
    NSString* cert3 = @"-----BEGIN CERTIFICATE-----\n"
    "MIIDCzCCAfOgAwIBAgIUceGZZzonOb5Fif74etb5LQSmS1swDQYJKoZIhvcNAQEL\n"
    "BQAwFTETMBEGA1UEAwwKTXkgUm9vdCBDQTAeFw0yNTA0MTgyMDUxNDJaFw0zNTA0\n"
    "MTYyMDUxNDJaMBUxEzARBgNVBAMMCk15IFJvb3QgQ0EwggEiMA0GCSqGSIb3DQEB\n"
    "AQUAA4IBDwAwggEKAoIBAQCdBQWtX6xyi7xg9akgy7MsL1kyRzE2sMz+43fYMqPa\n"
    "/64PlCcNCKuptAYUtHS/8jX3b12j9+uPzkvQOdyZ/8wzEKE5TOZrPspWLSTJii3/\n"
    "MTK6BXEdGiUGVKFTCQ+Rj3LqKbKdGi/ZCHzkRkca4dhpfkKWrcXWhW0n5Knf/vfk\n"
    "rYKfBbyGrsFY8sWfqAznO1p3FxmYlCK+0DZoQlBxs54Ec+Umk2i51/J/mR8Fi71U\n"
    "I7lgwz+ivvjzj96n3lWtMrYAfLAWneHLh9UMDlIaTNki0uLw6HXzxLHv+TcbDCZM\n"
    "O0nKM8f1gZCoeumZxmUC3Km7fDNX8vBcFQUegpF76HpvAgMBAAGjUzBRMB0GA1Ud\n"
    "DgQWBBSNIeGLgFRnq32qpUpIb/V4LpGbJjAfBgNVHSMEGDAWgBSNIeGLgFRnq32q\n"
    "pUpIb/V4LpGbJjAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUAA4IBAQBB\n"
    "PBXFmiwN8HJQfK6qekADWk6qSr+zvSLP8vm6vG5x265iozC5V3BMwBNJYrQ5rGYo\n"
    "SZpNRl31VspwQG8ZA9FAQoc50p4YUL77abJ9okFtm/NT/pmm3NdtSeX0SqZTTF2B\n"
    "dnBHy4vIpOmf+zbExOPMQ0DLZ35+uqknWjUmeydZ5mmnybX3Xx8oIJCuKeBInRQG\n"
    "/I03vUP+P1UksQrVKrmdr4OgHbhRr9czO/ZkX/do88pWk2f8GKyivhnElOIHHosk\n"
    "aeqhq25NXhfjV/FLqIB615Rq1VBKtLDRYxscBwWA5sZMSbjV8Ip9Up41HW7eexQg\n"
    "0pSfRUdNpkoVwOskW1ji\n"
    "-----END CERTIFICATE-----";
    
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
