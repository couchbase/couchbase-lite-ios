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
    bool ok = [self.db inBatch: &error do: ^BOOL {
        for (unsigned i = 0; i < 10; i++) {
            CBLDocument* doc = self.db[[NSString stringWithFormat: @"doc-%u", i]];
            doc[@"type"] = @"demo";
            Assert([doc save: &error], @"Error saving: %@", error);
        }
        return YES;
    }];
    XCTAssert(ok);
    
    [self waitForExpectationsWithTimeout: 5 handler: NULL];
}

- (void)testDocumentNotification {
    CBLDocument* docA = self.db[@"A"];
    CBLDocument* docB = self.db[@"B"];
    __block BOOL callbackCalled = NO;
    [self expectationForNotification:kCBLDocumentSavedNotification object:docA handler:^BOOL(NSNotification * _Nonnull notification) {
        BOOL external = [notification.userInfo[kCBLDocumentIsExternalUserInfoKey] boolValue];
        Assert(!external);
        Assert(!callbackCalled);
        callbackCalled = YES;
        
        return YES;
    }];
    
    NSError* err;
    [docB setInteger:18 forKey:@"thewronganswer"];
    Assert([docB save:&err]);
    
    [docA setInteger:42 forKey:@"theanswer"];
    Assert([docA save:&err]);

    callbackCalled = NO;
    [self waitForExpectationsWithTimeout: 5 handler: NULL];
    [self expectationForNotification:kCBLDocumentChangeNotification object:docA handler:^BOOL(NSNotification * _Nonnull notification) {
        BOOL external = [notification.userInfo[kCBLDocumentIsExternalUserInfoKey] boolValue];
        Assert(!external);
        Assert(!callbackCalled);
        callbackCalled = YES;
        
        return YES;
    }];
    
    [docA setInteger:18 forKey:@"thewronganswer"];
    Assert([docA save:&err]);
    [self waitForExpectationsWithTimeout: 5 handler: NULL];
}

- (void)testExternalChanges {
    CBLDatabase* db2 = [self.db copy];
    Assert(db2);
    
    [self expectationForNotification: kCBLDatabaseChangeNotification
                              object: db2
                             handler: ^BOOL(NSNotification *n)
     {
         NSArray *docIDs = n.userInfo[kCBLDatabaseChangesUserInfoKey];
         AssertEqual(docIDs.count, 10ul);
         AssertEqualObjects(n.userInfo[kCBLDatabaseIsExternalUserInfoKey], @YES);
         return YES;
     }];
    
    CBLDocument* db2doc6 = db2[@"doc-6"];
    [self expectationForNotification: kCBLDocumentSavedNotification
                              object: db2doc6
                             handler: ^BOOL(NSNotification *n)
     {
         AssertEqualObjects(n.userInfo[kCBLDocumentIsExternalUserInfoKey], @YES);
         AssertEqualObjects(db2doc6[@"type"], @"demo");
         return YES;
     }];
    
    __block NSError* error;
    BOOL ok = [self.db inBatch: &error do: ^BOOL {
        for (unsigned i = 0; i < 10; i++) {
            CBLDocument* doc = self.db[[NSString stringWithFormat: @"doc-%u", i]];
            doc[@"type"] = @"demo";
            Assert([doc save: &error], @"Error saving: %@", error);
        }
        return YES;
    }];
    Assert(ok);
    
    [self waitForExpectationsWithTimeout: 5 handler: NULL];
    [db2 close:nil];
}

@end
