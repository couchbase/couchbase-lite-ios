//
//  NotificationTest.m
//  CouchbaseLite
//
//  Created by Jim Borden on 2017/01/21.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLDatabase+Internal.h"

@interface NotificationTest : CBLTestCase

@end

@implementation NotificationTest


- (void) testDatabaseChange {
    XCTestExpectation* x = [self expectationWithDescription:@"change"];
    id listener = [self.db addChangeListener: ^(CBLDatabaseChange* change) {
        AssertEqual(change.documentIDs.count, 10ul);
        [x fulfill];
    }];
    AssertNotNil(listener);
    
    __block NSError* error;
    bool ok = [self.db inBatch: &error do: ^{
        for (unsigned i = 0; i < 10; i++) {
            CBLMutableDocument* doc = [[CBLMutableDocument alloc] initWithID: [NSString stringWithFormat: @"doc-%u", i]];
            [doc setObject: @"demo" forKey: @"type"];
            Assert([_db saveDocument: doc error: &error], @"Error saving: %@", error);
        }
    }];
    Assert(ok);
    
    [self waitForExpectationsWithTimeout: 5 handler: NULL];
    
    // Remove listener:
    [self.db removeChangeListener:listener];
}


- (void) testDocumentChange {
    // Create doc1 and doc2
    CBLMutableDocument *doc1 = [self createDocument: @"doc1"];
    [doc1 setObject: @"Scott" forKey: @"name"];
    [self saveDocument: doc1];
    
    CBLMutableDocument *doc2 = [self createDocument: @"doc2"];
    [doc2 setObject: @"Daniel" forKey: @"name"];
    [self saveDocument: doc2];
    
    // Expectation:
    XCTestExpectation* x = [self expectationWithDescription: @"document change"];
    NSMutableSet* docs = [NSMutableSet setWithObjects:@"doc1", @"doc2", @"doc3", nil];
    
    // Add change listeners:
    id block = ^void(CBLDocumentChange* change) {
        [docs removeObject:change.documentID];
        if (docs.count == 0)
            [x fulfill];
    };
    
    id listener1 = [_db addChangeListenerForDocumentID:@"doc1" usingBlock:block];
    id listener2 = [_db addChangeListenerForDocumentID:@"doc2" usingBlock:block];
    id listener3 = [_db addChangeListenerForDocumentID:@"doc3" usingBlock:block];
    
    // Update doc1
    [doc1 setObject: @"Scott Tiger" forKey: @"name"];
    [self saveDocument: doc1];
    
    // Delete doc2
    NSError *error;
    Assert([_db deleteDocument: doc2 error: &error], @"Error deleting: %@", error);
    
    // Create doc3
    CBLMutableDocument *doc3 = [self createDocument: @"doc3"];
    [doc3 setObject: @"Jack" forKey: @"name"];
    [self saveDocument: doc3];
    
    [self waitForExpectationsWithTimeout: 5 handler: NULL];
    
    // Remove listeners:
    [_db removeChangeListener:listener1];
    [_db removeChangeListener:listener2];
    [_db removeChangeListener:listener3];
}


- (void) testAddSameChangeListeners {
    CBLMutableDocument *doc1 = [self createDocument: @"doc1"];
    [doc1 setObject: @"Scott" forKey: @"name"];
    [self saveDocument: doc1];
    
    // Add change listeners:
    XCTestExpectation* x = [self expectationWithDescription: @"document change"];
    __block NSInteger count = 0;
    id block = ^void(CBLDocumentChange* change) {
        count++;
    };
   
    id listener1 = [_db addChangeListenerForDocumentID:@"doc1" usingBlock:block];
    id listener2 = [_db addChangeListenerForDocumentID:@"doc1" usingBlock:block];
    id listener3 = [_db addChangeListenerForDocumentID:@"doc1" usingBlock:block];
    
    // Update doc1:
    [doc1 setObject: @"Scott Tiger" forKey: @"name"];
    [self saveDocument: doc1];
    
    // Let's wait for 0.5 second to make sure that no more changes fired:
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            if (count == 3)
                [x fulfill];
    });
    
    [self waitForExpectationsWithTimeout: 5 handler: NULL];
    
    // Remove listeners:
    [_db removeChangeListener:listener1];
    [_db removeChangeListener:listener2];
    [_db removeChangeListener:listener3];
}


- (void) testRemoveDocumentChangeListener {
    CBLMutableDocument *doc1 = [self createDocument: @"doc1"];
    [doc1 setObject: @"Scott" forKey: @"name"];
    [self saveDocument: doc1];
    
    // Add change listener:
    XCTestExpectation* x1 = [self expectationWithDescription: @"document change"];
    id block = ^void(CBLDocumentChange* change) {
        [x1 fulfill];
    };
    
    id listener1 = [_db addChangeListenerForDocumentID:@"doc1" usingBlock:block];
    AssertNotNil(listener1);
    
    // Update doc1:
    [doc1 setObject: @"Scott Tiger" forKey: @"name"];
    [self saveDocument: doc1];
    
    [self waitForExpectationsWithTimeout: 5 handler: NULL];
    
    // Remove change listener:
    [_db removeChangeListener:listener1];
    
    // Update doc1 again:
    [doc1 setObject: @"Scott Tiger" forKey: @"name"];
    [self saveDocument: doc1];
    
    // Let's wait for 0.5 seconds:
    XCTestExpectation *x2 = [self expectationWithDescription: @"No Changes"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            [x2 fulfill];
    });
    [self waitForExpectationsWithTimeout: 5 handler: NULL];
    
    // Remove again:
    [_db removeChangeListener:listener1];
}


@end
