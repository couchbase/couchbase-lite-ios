//
//  NotificationTest.m
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
#import "CBLDatabase+Internal.h"

@interface NotificationTest : CBLTestCase

@end

@implementation NotificationTest


- (void) testDatabaseChange {
    XCTestExpectation* x = [self expectationWithDescription:@"change"];
    id token = [self.db addChangeListener: ^(CBLDatabaseChange* change) {
        AssertEqual(change.documentIDs.count, 10ul);
        [x fulfill];
    }];
    AssertNotNil(token);
    
    __block NSError* error;
    bool ok = [self.db inBatch: &error usingBlock: ^{
        for (unsigned i = 0; i < 10; i++) {
            CBLMutableDocument* doc = [[CBLMutableDocument alloc] initWithID: [NSString stringWithFormat: @"doc-%u", i]];
            [doc setValue: @"demo" forKey: @"type"];
            Assert([_db saveDocument: doc error: &error], @"Error saving: %@", error);
        }
    }];
    Assert(ok);
    
    [self waitForExpectationsWithTimeout: 5 handler: NULL];
    
    // Remove listener:
    [self.db removeChangeListenerWithToken: token];
}


- (void) testDocumentChange {
    // Create doc1 and doc2
    CBLMutableDocument *doc1 = [self createDocument: @"doc1"];
    [doc1 setValue: @"Scott" forKey: @"name"];
    doc1 = [[self saveDocument: doc1] toMutable];
    
    CBLMutableDocument *doc2 = [self createDocument: @"doc2"];
    [doc2 setValue: @"Daniel" forKey: @"name"];
    doc2 = [[self saveDocument: doc2] toMutable];
    
    // Expectation:
    XCTestExpectation* x = [self expectationWithDescription: @"document change"];
    NSMutableSet* docs = [NSMutableSet setWithObjects:@"doc1", @"doc2", @"doc3", nil];
    
    // Add change listeners:
    id block = ^void(CBLDocumentChange* change) {
        [docs removeObject:change.documentID];
        if (docs.count == 0)
            [x fulfill];
    };
    
    id listener1 = [_db addDocumentChangeListenerWithID: @"doc1" listener: block];
    id listener2 = [_db addDocumentChangeListenerWithID: @"doc2" listener: block];
    id listener3 = [_db addDocumentChangeListenerWithID: @"doc3" listener: block];
    
    // Update doc1
    [doc1 setValue: @"Scott Tiger" forKey: @"name"];
    [self saveDocument: doc1];
    
    // Delete doc2
    NSError *error;
    Assert([_db deleteDocument: doc2 error: &error], @"Error deleting: %@", error);
    
    // Create doc3
    CBLMutableDocument *doc3 = [self createDocument: @"doc3"];
    [doc3 setValue: @"Jack" forKey: @"name"];
    [self saveDocument: doc3];
    
    [self waitForExpectationsWithTimeout: 5 handler: NULL];
    
    // Remove listeners:
    [_db removeChangeListenerWithToken:listener1];
    [_db removeChangeListenerWithToken:listener2];
    [_db removeChangeListenerWithToken:listener3];
}


- (void) testAddSameChangeListeners {
    CBLMutableDocument *doc1 = [self createDocument: @"doc1"];
    [doc1 setValue: @"Scott" forKey: @"name"];
    doc1 = [[self saveDocument: doc1] toMutable];
    
    // Add change listeners:
    XCTestExpectation* x = [self expectationWithDescription: @"document change"];
    __block NSInteger count = 0;
    id block = ^void(CBLDocumentChange* change) {
        count++;
    };
   
    id listener1 = [_db addDocumentChangeListenerWithID: @"doc1" listener: block];
    id listener2 = [_db addDocumentChangeListenerWithID: @"doc1" listener: block];
    id listener3 = [_db addDocumentChangeListenerWithID: @"doc1" listener: block];
    
    // Update doc1:
    [doc1 setValue: @"Scott Tiger" forKey: @"name"];
    [self saveDocument: doc1];
    
    // Let's wait for 0.5 second to make sure that no more changes fired:
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            if (count == 3)
                [x fulfill];
    });
    
    [self waitForExpectationsWithTimeout: 5 handler: NULL];
    
    // Remove listeners:
    [_db removeChangeListenerWithToken:listener1];
    [_db removeChangeListenerWithToken:listener2];
    [_db removeChangeListenerWithToken:listener3];
}


- (void) testRemoveDocumentChangeListener {
    CBLMutableDocument *doc1 = [self createDocument: @"doc1"];
    [doc1 setValue: @"Scott" forKey: @"name"];
    doc1 = [[self saveDocument: doc1] toMutable];
    
    // Add change listener:
    XCTestExpectation* x1 = [self expectationWithDescription: @"document change"];
    id block = ^void(CBLDocumentChange* change) {
        [x1 fulfill];
    };
    
    id listener1 = [_db addDocumentChangeListenerWithID: @"doc1" listener: block];
    AssertNotNil(listener1);
    
    // Update doc1:
    [doc1 setValue: @"Scott Tiger" forKey: @"name"];
    doc1 = [[self saveDocument: doc1] toMutable];
    
    [self waitForExpectationsWithTimeout: 5 handler: NULL];
    
    // Remove change listener:
    [_db removeChangeListenerWithToken:listener1];
    
    // Update doc1 again:
    [doc1 setValue: @"Scott Tiger" forKey: @"name"];
    [self saveDocument: doc1];
    
    // Let's wait for 0.5 seconds:
    XCTestExpectation *x2 = [self expectationWithDescription: @"No Changes"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            [x2 fulfill];
    });
    [self waitForExpectationsWithTimeout: 5 handler: NULL];
    
    // Remove again:
    [_db removeChangeListenerWithToken:listener1];
}


@end
