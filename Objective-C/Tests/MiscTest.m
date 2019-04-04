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
#import "CBLParseDate.h"

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

#pragma mark - Parse Date

- (void) testCBLParseISO8601Date {
    AssertEqual(CBLParseISO8601Date("1970-01-01T00:00:01.000Z"), 1.0);
    AssertEqual(CBLParseISO8601Date("1970-01-01T00:00:00Z"), 0.0);
    AssertEqual(CBLParseISO8601Date("2018-10-23T11:33:01-0700"), 1540319581);
    AssertEqual(CBLParseISO8601Date("2020-02-29T23:59:59.000000+0000"), 1583020799);
}

@end
