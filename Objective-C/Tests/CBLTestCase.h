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

/** Loads the database with documents read from a JSON resource file in the test bundle.
    Each line of the file should be a complete JSON object, which will become a document.
    The document IDs will be of the form "doc-#" where "#" is the line number, starting at 1. */
- (void) loadJSONResource: (NSString*)resourceName;

@end
