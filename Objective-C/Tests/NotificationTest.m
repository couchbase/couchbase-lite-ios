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

- (void) testDocumentChange {
    // Create doc1 and doc2
    CBLMutableDocument *doc1 = [self createDocument: @"doc1"];
    [doc1 setValue: @"Scott" forKey: @"name"];
    [self saveDocument: doc1 collection: self.defaultCollection];
    
    CBLMutableDocument *doc2 = [self createDocument: @"doc2"];
    [doc2 setValue: @"Daniel" forKey: @"name"];
    [self saveDocument: doc2 collection: self.defaultCollection];
    
    // Expectation:
    XCTestExpectation* x = [self expectationWithDescription: @"document change"];
    NSMutableSet* docs = [NSMutableSet setWithObjects:@"doc1", @"doc2", @"doc3", nil];
    
    // Add change listeners:
    id block = ^void(CBLDocumentChange* change) {
        [docs removeObject:change.documentID];
        if (docs.count == 0)
            [x fulfill];
    };
    
    id listener1 = [self.defaultCollection addDocumentChangeListenerWithID: @"doc1" listener: block];
    id listener2 = [self.defaultCollection addDocumentChangeListenerWithID: @"doc2" listener: block];
    id listener3 = [self.defaultCollection addDocumentChangeListenerWithID: @"doc3" listener: block];
    
    // Update doc1
    [doc1 setValue: @"Scott Tiger" forKey: @"name"];
    [self saveDocument: doc1 collection: self.defaultCollection];
    
    // Delete doc2
    NSError *error;
    Assert([self.defaultCollection deleteDocument: doc2 error: &error], @"Error deleting: %@", error);
    
    // Create doc3
    CBLMutableDocument *doc3 = [self createDocument: @"doc3"];
    [doc3 setValue: @"Jack" forKey: @"name"];
    [self saveDocument: doc3 collection: self.defaultCollection];
    
    [self waitForExpectationsWithTimeout: kExpTimeout handler: NULL];
    
    // Remove listeners:
    [listener1 remove];
    [listener2 remove];
    [listener3 remove];
}

- (void) testAddSameChangeListeners {
    CBLMutableDocument* doc1 = [self createDocument: @"doc1"];
    [doc1 setValue: @"Scott" forKey: @"name"];
    [self saveDocument: doc1 collection: self.defaultCollection];
    
    // Add change listeners:
    XCTestExpectation* x = [self expectationWithDescription: @"document change"];
    __block NSInteger count = 0;
    id block = ^void(CBLDocumentChange* change) {
        count++;
    };
   
    id listener1 = [self.defaultCollection addDocumentChangeListenerWithID: @"doc1" listener: block];
    id listener2 = [self.defaultCollection addDocumentChangeListenerWithID: @"doc1" listener: block];
    id listener3 = [self.defaultCollection addDocumentChangeListenerWithID: @"doc1" listener: block];
    
    // Update doc1:
    [doc1 setValue: @"Scott Tiger" forKey: @"name"];
    [self saveDocument: doc1 collection: self.defaultCollection];
    
    // Let's wait for 0.5 second to make sure that no more changes fired:
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            if (count == 3)
                [x fulfill];
    });
    
    [self waitForExpectationsWithTimeout: kExpTimeout handler: NULL];
    
    // Remove listeners:
    [listener1 remove];
    [listener2 remove];
    [listener3 remove];
}

- (void) testRemoveDocumentChangeListener {
    CBLMutableDocument *doc1 = [self createDocument: @"doc1"];
    [doc1 setValue: @"Scott" forKey: @"name"];
    [self saveDocument: doc1 collection: self.defaultCollection];
    
    // Add change listener:
    XCTestExpectation* x1 = [self expectationWithDescription: @"document change"];
    id block = ^void(CBLDocumentChange* change) {
        [x1 fulfill];
    };
    
    id listener1 = [self.defaultCollection addDocumentChangeListenerWithID: @"doc1" listener: block];
    AssertNotNil(listener1);
    
    // Update doc1:
    [doc1 setValue: @"Scott Tiger" forKey: @"name"];
    [self saveDocument: doc1 collection: self.defaultCollection];
    
    [self waitForExpectationsWithTimeout: kExpTimeout handler: NULL];
    
    // Remove change listener:
    [listener1 remove];
    
    // Update doc1 again:
    [doc1 setValue: @"Scott Tiger" forKey: @"name"];
    [self saveDocument: doc1 collection: self.defaultCollection];
    
    // Let's wait for 0.5 seconds:
    XCTestExpectation *x2 = [self expectationWithDescription: @"No Changes"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            [x2 fulfill];
    });
    [self waitForExpectationsWithTimeout: kExpTimeout handler: NULL];
    
    // Remove again:
    [listener1 remove];
}

@end
