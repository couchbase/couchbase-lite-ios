//
//  NotificationTest.m
//  CouchbaseLite
//
//  Created by Jim Borden on 2017/01/21.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLInternal.h"

@interface NotificationTest : CBLTestCase <CBLDocumentChangeListener>

@end

@implementation NotificationTest
{
    void* _testContext;
    NSMutableSet* _expectedDocumentChanges;
    XCTestExpectation* _documentChangeExpectation;
}


- (void) setUp {
    [super setUp];
    _testContext = nil;
    _expectedDocumentChanges = nil;
    _expectedDocumentChanges = nil;
    
}


- (void) documentDidChange: (CBLDocumentChange*)change {
    if (_testContext == @selector(testRemoveDocumentChangeListener)) {
        XCTFail(@"Unexpected Document Change Notification");
    } else {
        Assert([_expectedDocumentChanges containsObject: change.documentID]);
        [_expectedDocumentChanges removeObject: change.documentID];
        if (_expectedDocumentChanges.count == 0)
            [_documentChangeExpectation fulfill];
    }
}


- (void) testDatabaseChange {
    [self expectationForNotification: kCBLDatabaseChangeNotification
                              object: self.db
                             handler: ^BOOL(NSNotification *n)
     {
         CBLDatabaseChange* change = n.userInfo[kCBLDatabaseChangesUserInfoKey];
         AssertEqual(change.documentIDs.count, 10ul);
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


- (void) testDocumentChange {
    // Create doc1 and doc2
    CBLDocument *doc1 = [self createDocument: @"doc1"];
    [doc1 setObject: @"Scott" forKey: @"name"];
    [self saveDocument: doc1];
    
    CBLDocument *doc2 = [self createDocument: @"doc2"];
    [doc2 setObject: @"Daniel" forKey: @"name"];
    [self saveDocument: doc2];
    
    // Add change listeners:
    [_db addChangeListener: self forDocumentID: @"doc1"];
    [_db addChangeListener: self forDocumentID: @"doc2"];
    [_db addChangeListener: self forDocumentID: @"doc3"];
    
    _documentChangeExpectation = [self expectationWithDescription: @"document change"];
    
    _expectedDocumentChanges = [NSMutableSet set];
    [_expectedDocumentChanges addObject: @"doc1"];
    [_expectedDocumentChanges addObject: @"doc2"];
    [_expectedDocumentChanges addObject: @"doc3"];
    
    // Update doc1
    [doc1 setObject: @"Scott Tiger" forKey: @"name"];
    [self saveDocument: doc1];
    
    // Delete doc2
    NSError *error;
    Assert([_db deleteDocument: doc2 error: &error], @"Error deleting: %@", error);
    
    // Create doc3
    CBLDocument *doc3 = [self createDocument: @"doc3"];
    [doc3 setObject: @"Jack" forKey: @"name"];
    [self saveDocument: doc3];
    
    [self waitForExpectationsWithTimeout: 5 handler: NULL];
}


- (void) testAddSameChangeListeners {
    CBLDocument *doc1 = [self createDocument: @"doc1"];
    [doc1 setObject: @"Scott" forKey: @"name"];
    [self saveDocument: doc1];
    
    // Add change listeners:
    [_db addChangeListener: self forDocumentID: @"doc1"];
    [_db addChangeListener: self forDocumentID: @"doc1"];
    [_db addChangeListener: self forDocumentID: @"doc1"];
    [_db addChangeListener: self forDocumentID: @"doc1"];
    [_db addChangeListener: self forDocumentID: @"doc1"];
    
    _documentChangeExpectation = [self expectationWithDescription: @"document change"];
    
    _expectedDocumentChanges = [NSMutableSet set];
    [_expectedDocumentChanges addObject: @"doc1"];
    
    // Update doc1:
    [doc1 setObject: @"Scott Tiger" forKey: @"name"];
    [self saveDocument: doc1];
    
    // Let's wait for 0.5 second to make sure that no duplication changes fired which
    // will cause the assertion in documentDidChange: to fail:
    XCTestExpectation *x = [self expectationWithDescription: @"No Changes"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            [x fulfill];
    });
    
    [self waitForExpectationsWithTimeout: 5 handler: NULL];
}


- (void) testRemoveDocumentChangeListener {
    CBLDocument *doc1 = [self createDocument: @"doc1"];
    [doc1 setObject: @"Scott" forKey: @"name"];
    [self saveDocument: doc1];
    
    // Add change listener:
    [_db addChangeListener: self forDocumentID: @"doc1"];
    
    _documentChangeExpectation = [self expectationWithDescription: @"document change"];
    
    _expectedDocumentChanges = [NSMutableSet set];
    [_expectedDocumentChanges addObject: @"doc1"];
    
    // Update doc1:
    [doc1 setObject: @"Scott Tiger" forKey: @"name"];
    [self saveDocument: doc1];
    
    [self waitForExpectationsWithTimeout: 5 handler: NULL];
    
    // Remove change listener:
    [_db removeChangeListener: self forDocumentID: @"doc1"];
    
    // Update doc1 again:
    _testContext = @selector(testRemoveDocumentChangeListener);
    [doc1 setObject: @"Scott Tiger" forKey: @"name"];
    [self saveDocument: doc1];
    
    // Let's wait for 0.5 seconds:
    XCTestExpectation *x = [self expectationWithDescription: @"No Changes"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            [x fulfill];
    });
    [self waitForExpectationsWithTimeout: 5 handler: NULL];
    
    // Remove again:
    [_db removeChangeListener: self forDocumentID: @"doc1"];
    
    // Remove before add:
    [_db removeChangeListener: self forDocumentID: @"doc2"];
}


@end
