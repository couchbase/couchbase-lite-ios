//
//  MiscTest.m
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
#import "CBLJSON.h"
#import "CBLTrustCheck.h"

@interface MiscTest : CBLTestCase

@end

@implementation MiscTest

// Verify that round trip NSString -> NSDate -> NSString conversion doesn't alter the string (#1611)
- (void) testJSONDateRoundTrip {
    NSString* dateStr1 = @"2017-02-05T18:14:06.347Z";
    NSDate* date1 = [CBLJSON dateWithJSONObject: dateStr1];
    NSString* dateStr2 = [CBLJSON JSONObjectWithDate: date1];
    NSDate* date2 = [CBLJSON dateWithJSONObject: dateStr2];
    XCTAssertEqualWithAccuracy(date2.timeIntervalSinceReferenceDate,
                               date1.timeIntervalSinceReferenceDate, 0.0001);
    AssertEqualObjects(dateStr2, dateStr1);
}

- (void) testTrustCheckSelfSignedCertificate {
    NSError* error;
    SecTrustRef trust;
    
    NSData* certData = [self dataFromResource: @"SelfSigned" ofType: @"cer"];
    SecCertificateRef certificate = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certData);
    NSArray* certArray = @[ (__bridge id)certificate ];
    if (certificate) { CFRelease(certificate); }
    
    SecPolicyRef policy = SecPolicyCreateBasicX509();
    OSStatus status = SecTrustCreateWithCertificates((__bridge CFTypeRef)certArray,
                                                     policy,
                                                     &trust);
    if (policy) { CFRelease(policy); }
    AssertEqual(status, errSecSuccess);
    
    [CBLTrustCheck setAnchorCerts: certArray onlyThese: NO];
    CBLTrustCheck* trustCheck = [[CBLTrustCheck alloc] initWithTrust: trust
                                                                host: @"https://www.couchbase.com/"
                                                                port: 443];
    
    if (trust) { CFRelease(trust); }
    NSURLCredential* credential = [trustCheck checkTrust: &error];
    AssertNotNil(credential);
}

@end
