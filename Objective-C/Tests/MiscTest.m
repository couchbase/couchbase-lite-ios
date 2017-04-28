//
//  MiscTest.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/26/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLJSON.h"

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


@end
