//
//  NotificationTest.m
//  CouchbaseLite
//
//  Created by Jim Borden on 2017/01/21.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLInternal.h"

@interface NotificationTest : CBLTestCase

@end

@implementation NotificationTest
{
    NSUInteger _dbCallbackCalls;
    NSUInteger _docCallbackCalls;
    NSMutableArray* _changes;
    XCTestExpectation* _callbackExpectation;
}

- (void)setUp {
    [super setUp];
    _changes = [NSMutableArray new];
}

- (void)handleDBNotification:(NSNotification *)notification {
    AssertEqualObjects([notification object], self.db);
    _dbCallbackCalls++;
    NSArray* changes = [notification userInfo][kCBLDatabaseChangesUserInfoKey];
    [_changes addObjectsFromArray:changes];
}

- (void)testDatabaseNotification {
    [self expectationForNotification: kCBLDatabaseChangeNotification
                              object: self.db
                             handler: ^BOOL(NSNotification *n)
     {
         NSArray *docIDs = n.userInfo[kCBLDatabaseChangesUserInfoKey];
         AssertEqual(docIDs.count, 10ul);
         return YES;
     }];
    
    __block NSError* error;
    bool ok = [self.db inBatch: &error do: ^{
        for (unsigned i = 0; i < 10; i++) {
            CBLDocument* doc = [[CBLDocument alloc] initWithID: [NSString stringWithFormat: @"doc-%u", i]];
            [doc setObject: @"demo" forKey: @"type"];
            Assert([_db saveDocument: doc error: &error], @"Error saving: %@", error);
        }
    }];
    Assert(ok);
    
    [self waitForExpectationsWithTimeout: 5 handler: NULL];
}

@end
