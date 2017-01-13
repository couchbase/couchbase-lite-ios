//
//  CBLTestCase.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "CouchbaseLite.h"

#define Assert             XCTAssert
#define AssertNil          XCTAssertNil
#define AssertNotNil       XCTAssertNotNil
#define AssertEqual        XCTAssertEqual
#define AssertEqualObjects XCTAssertEqualObjects
#define AssertFalse        XCTAssertFalse

#define Log                NSLog
#define Warn(FMT, ...)     NSLog(@"WARNING: " FMT, ##__VA_ARGS__)

@interface CBLTestCase : XCTestCase {
@protected
    CBLDatabase* _db;
}

@property (readonly) CBLDatabase* db;

@end
