//
//  ConcurrentTest.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/17/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"

#define kDocumentTestBlob @"i'm blob"

@interface ConcurrentTest : CBLTestCase

@end

@implementation ConcurrentTest


- (CBLDocument*) createDocumentWithTag: (NSString*)tag {
    CBLDocument* doc = [[CBLDocument alloc] init];
    
    // Tag:
    [doc setObject: tag forKey: @"tag"];
    
    // String:
    [doc setObject: @"firstName" forKey: @"Daniel"];
    [doc setObject: @"lastName" forKey: @"Tiger"];
    
    // Dictionary:
    CBLDictionary* address = [[CBLDictionary alloc] init];
    [address setObject: @"1 Main street" forKey: @"street"];
    [address setObject: @"Mountain View" forKey: @"city"];
    [address setObject: @"CA" forKey: @"state"];
    [doc setObject: address forKey: @"address"];
    
    // Array:
    CBLArray* phones = [[CBLArray alloc] init];
    [phones addObject: @"650-123-0001"];
    [phones addObject: @"650-123-0002"];
    [doc setObject: phones forKey: @"phones"];
    
    // Date:
    [doc setObject: [NSDate date] forKey: @"updated"];
    
    return doc;
}


- (NSArray*) createDocs: (NSUInteger)nDocs tag: (NSString*)tag {
    NSMutableArray* docs = [NSMutableArray arrayWithCapacity: nDocs];
    for (NSUInteger i = 0; i < nDocs; i++) {
        CBLDocument* doc = [self createDocumentWithTag: tag];
        NSError* error;
        Assert([self.db saveDocument: doc error: &error], @"Error when creating docs: %@", error);
        [docs addObject: doc];
    }
    return docs;
}


- (BOOL) createDocs: (NSUInteger)nDocs tag: (NSString*)tag error: (NSError**)error {
    for (NSUInteger i = 1; i <= nDocs; i++) {
        CBLDocument* doc = [self createDocumentWithTag: tag];
        NSLog(@"[%@] rounds: %lu saving %@", tag, (unsigned long)i, doc.id);
        if (![self.db saveDocument: doc error: error])
            return NO;
    }
    return YES;
}


- (BOOL) updateDocs: (NSArray*)docs rounds: (NSUInteger)rounds tag: (NSString*)tag
              error: (NSError**)error
{
    NSUInteger n = 0;
    for (NSUInteger r = 1; r <= rounds; r++) {
        for (CBLDocument* doc in docs) {
            [doc setObject: tag forKey: @"tag"];
            
            CBLDictionary* address = [doc dictionaryForKey: @"address"];
            Assert(address);
            NSString* street = [NSString stringWithFormat: @"%lu street.", (unsigned long)n];
            [address setObject: street forKey: @"street"];
            
            CBLArray* phones = [doc arrayForKey: @"phones"];
            Assert(phones.count == 2);
            NSString* phone = [NSString stringWithFormat: @"650-000-%lu", (unsigned long)n];
            [phones setObject: phone atIndex: 0];
            
            [doc setObject: [NSDate date] forKey: @"updated"];
            
            NSLog(@"[%@] rounds: %lu updating %@", tag, (unsigned long)r, doc.id);
            if (![self.db saveDocument: doc error: error]) {
                return NO;
            }
        }
    }
    return YES;
}


- (void) readDocIDs: (NSArray<NSString*>*)docIDs rounds: (NSUInteger)rounds {
    for (NSUInteger r = 1; r <= rounds; r++) {
        for (NSString* docID in docIDs) {
            CBLDocument* doc = [_db documentWithID: docID];
            AssertNotNil(doc);
            AssertEqualObjects(doc.id, docID);
        }
    }
}


- (void) verifyByTagName: (NSString*)name test: (void (^)(uint64_t n, CBLQueryRow *row))block {
    CBLQueryExpression* TAG = [CBLQueryExpression property: @"tag"];
    CBLQuerySelectResult* DOCID = [CBLQuerySelectResult expression:
                                   [CBLQueryExpression meta].id];
    CBLQuery* q = [CBLQuery select: @[DOCID]
                              from: [CBLQueryDataSource database: self.db]
                             where: [TAG equalTo: name]];
    NSLog(@"%@", [q explain:nil]);
    
    NSError* error;
    NSEnumerator* e = [q run: &error];
    Assert(e, @"Query failed: %@", error);
    uint64_t n = 0;
    for (CBLQueryRow *row in e) {
        block(++n, row);
    }
}


- (void) verifyByTagName: (NSString*)name numRows: (NSUInteger)nRows {
    __block NSUInteger count = 0;
    [self verifyByTagName: name test: ^(uint64_t n, CBLQueryRow *row) {
        count++;
    }];
    AssertEqual(count, nRows);
}


- (void) testConcurrentCreate {
    const NSUInteger kNDocs = 1000;
    
    NSString* tag1 = @"Create1";
    XCTestExpectation* exp1 = [self expectationWithDescription: tag1];
    dispatch_queue_t queue1 = dispatch_queue_create([tag1 UTF8String],  NULL);
    dispatch_async(queue1, ^{
        NSError* error;
        Assert([self createDocs: kNDocs tag: tag1 error: &error], @"Error creating docs: %@", error);
        [exp1 fulfill];
    });
    
    NSString* tag2 = @"Create2";
    XCTestExpectation* exp2 = [self expectationWithDescription: tag2];
    dispatch_queue_t queue2 = dispatch_queue_create([tag2 UTF8String],  NULL);
    dispatch_async(queue2, ^{
        NSError* error;
        Assert([self createDocs: kNDocs tag: tag2 error: &error], @"Error creating docs: %@", error);
        [exp2 fulfill];
    });
    [self waitForExpectationsWithTimeout: 60.0 handler: NULL];
    
    [self verifyByTagName: tag1 numRows: kNDocs];
    [self verifyByTagName: tag2 numRows: kNDocs];
}


- (void) testConcurrentUpdate {
    const NSUInteger kNDocs = 10;
    const NSUInteger kNRounds = 100;
    
    NSArray* docs = [self createDocs: kNDocs tag: @"Create"];
    AssertEqual(docs.count, kNDocs);
    
    NSString* tag1 = @"Update1";
    XCTestExpectation* exp1 = [self expectationWithDescription: tag1];
    dispatch_queue_t queue1 = dispatch_queue_create([tag1 UTF8String],  NULL);
    dispatch_async(queue1, ^{
        NSError* error;
        Assert([self updateDocs: docs rounds: kNRounds tag: tag1 error: &error],
               @"Error updating doc: %@", error);
        [exp1 fulfill];
    });
    
    NSString* tag2 = @"Update2";
    XCTestExpectation* exp2 = [self expectationWithDescription: tag2];
    dispatch_queue_t queue2 = dispatch_queue_create([tag2 UTF8String],  NULL);
    dispatch_async(queue2, ^{
        NSError* error;
        Assert([self updateDocs: docs rounds: kNRounds tag: tag2 error: &error],
               @"Error updating doc: %@", error);
        [exp2 fulfill];
    });
    
    [self waitForExpectationsWithTimeout: 60.0 handler: NULL];
    
    __block NSUInteger count = 0;
    [self verifyByTagName: tag1 test:^(uint64_t n, CBLQueryRow *row) {
        count++;
    }];
    
    [self verifyByTagName: tag2 test:^(uint64_t n, CBLQueryRow *row) {
        count++;
    }];
    
    AssertEqual(count, kNDocs);
}


- (void) testConcurrentRead {
    const NSUInteger kNDocs = 10;
    const NSUInteger kNRounds = 1000;
   
    NSArray* docs = [self createDocs: kNDocs tag: @"Create"];
    AssertEqual(docs.count, kNDocs);
    
    NSMutableArray* docIDs = [NSMutableArray arrayWithCapacity: kNDocs];
    [docs enumerateObjectsUsingBlock: ^(CBLDocument* doc, NSUInteger idx, BOOL* stop) {
        [docIDs addObject: doc.id];
    }];
    
    XCTestExpectation* exp1 = [self expectationWithDescription: @"Read1"];
    dispatch_queue_t queue1 = dispatch_queue_create("Read1",  NULL);
    dispatch_async(queue1, ^{
        [self readDocIDs: docIDs rounds:kNRounds];
        [exp1 fulfill];
    });
    
    XCTestExpectation* exp2 = [self expectationWithDescription: @"Read2"];
    dispatch_queue_t queue2 = dispatch_queue_create("Read2",  NULL);
    dispatch_async(queue2, ^{
        [self readDocIDs: docIDs rounds:kNRounds];
        [exp2 fulfill];
    });

    [self waitForExpectationsWithTimeout: 60.0 handler: NULL];
}


- (void) testConcurrentReadNUpdate {
    const NSUInteger kNDocs = 10;
    const NSUInteger kNRounds = 100;
    
    NSArray* docs = [self createDocs: kNDocs tag: @"Create"];
    AssertEqual(docs.count, kNDocs);
    
    NSMutableArray* docIDs = [NSMutableArray arrayWithCapacity: kNDocs];
    [docs enumerateObjectsUsingBlock: ^(CBLDocument* doc, NSUInteger idx, BOOL* stop) {
        [docIDs addObject: doc.id];
    }];
    
    // Read:
    XCTestExpectation* exp1 = [self expectationWithDescription: @"Read1"];
    dispatch_queue_t queue1 = dispatch_queue_create("Read1",  NULL);
    dispatch_async(queue1, ^{
        [self readDocIDs: docIDs rounds: kNRounds];
        [exp1 fulfill];
    });
    
    // Update:
    NSString* tag = @"Update";
    XCTestExpectation* exp2 = [self expectationWithDescription: tag];
    dispatch_queue_t queue2 = dispatch_queue_create([tag UTF8String],  NULL);
    dispatch_async(queue2, ^{
        NSError* error;
        Assert([self updateDocs: docs rounds: kNRounds tag: tag error: &error],
               @"Error updating doc: %@", error);
        [exp2 fulfill];
    });
    
    [self waitForExpectationsWithTimeout: 60.0 handler: NULL];
    
    [self verifyByTagName: tag numRows: kNDocs];
}


- (void) testConcurrentDelete {
    const NSUInteger kNDocs = 1000;
    
    NSArray* docs = [self createDocs: kNDocs tag: @"Create"];
    AssertEqual(docs.count, kNDocs);
    
    XCTestExpectation* exp1 = [self expectationWithDescription: @"Delete1"];
    dispatch_queue_t queue1 = dispatch_queue_create("Delete1",  NULL);
    dispatch_async(queue1, ^{
        for (CBLDocument* doc in docs) {
            NSError* error;
            Assert([self.db deleteDocument: doc error: &error], @"Error when delete: %@", error);
        }
        [exp1 fulfill];
    });
    
    XCTestExpectation* exp2 = [self expectationWithDescription: @"Delete2"];
    dispatch_queue_t queue2 = dispatch_queue_create("Delete2",  NULL);
    dispatch_async(queue2, ^{
        for (CBLDocument* doc in docs) {
            NSError* error;
            Assert([self.db deleteDocument: doc error: &error], @"Error when delete: %@", error);
        }
        [exp2 fulfill];
    });
    
    [self waitForExpectationsWithTimeout: 60.0 handler: NULL];
    AssertEqual(self.db.count, 0u);
}


- (void) testConcurrentPurge {
    const NSUInteger kNDocs = 1000;
    
    NSArray* docs = [self createDocs: kNDocs tag: @"Create"];
    AssertEqual(docs.count, kNDocs);
    
    XCTestExpectation* exp1 = [self expectationWithDescription: @"Purge1"];
    dispatch_queue_t queue1 = dispatch_queue_create("Purge1",  NULL);
    dispatch_async(queue1, ^{
        for (CBLDocument* doc in docs) {
            NSError* error;
            if (![self.db purgeDocument: doc error: &error])
                AssertEqual(error.code, 404);
        }
        [exp1 fulfill];
    });
    
    XCTestExpectation* exp2 = [self expectationWithDescription: @"Purge2"];
    dispatch_queue_t queue2 = dispatch_queue_create("Purge2",  NULL);
    dispatch_async(queue2, ^{
        for (CBLDocument* doc in docs) {
            NSError* error;
            if (![self.db purgeDocument: doc error: &error])
                AssertEqual(error.code, 404);
        }
        [exp2 fulfill];
    });
    
    [self waitForExpectationsWithTimeout: 60.0 handler: NULL];
    AssertEqual(self.db.count, 0u);
}


- (void) testConcurrentCreateNCloseDB {
    const NSUInteger kNDocs = 1000;
    
    NSString* tag1 = @"Create";
    XCTestExpectation* exp1 = [self expectationWithDescription: tag1];
    dispatch_queue_t queue1 = dispatch_queue_create([tag1 UTF8String],  NULL);
    dispatch_async(queue1, ^{
        ++gC4ExpectExceptions;
        XCTAssertThrowsSpecificNamed([self createDocs: kNDocs tag: tag1 error: nil],
                                     NSException, NSInternalInconsistencyException);
        --gC4ExpectExceptions;
        [exp1 fulfill];
    });
    
    // Sleep for 0.1 seconds:
    [NSThread sleepForTimeInterval: 0.1];
    
    NSError* error;
    Assert([self.db close: &error], @"Error when closing the database: %@", error);
    
    [self waitForExpectationsWithTimeout: 60.0 handler: NULL];
}


- (void) testConcurrentCreateNDeleteDB {
    const NSUInteger kNDocs = 1000;
    
    NSString* tag1 = @"Create";
    XCTestExpectation* exp1 = [self expectationWithDescription: tag1];
    dispatch_queue_t queue1 = dispatch_queue_create([tag1 UTF8String],  NULL);
    dispatch_async(queue1, ^{
        ++gC4ExpectExceptions;
        XCTAssertThrowsSpecificNamed([self createDocs: kNDocs tag: tag1 error: nil],
                                     NSException, NSInternalInconsistencyException);
        --gC4ExpectExceptions;
        [exp1 fulfill];
    });
    
    // Sleep for 0.1 seconds:
    [NSThread sleepForTimeInterval: 0.1];
    
    NSError* error;
    Assert([self.db deleteDatabase: &error], @"Error when closing the database: %@", error);
    
    [self waitForExpectationsWithTimeout: 60.0 handler: NULL];
}


- (void) testBlockDatabaseChange {
    XCTestExpectation* exp1 = [self expectationWithDescription: @"Create"];
    XCTestExpectation* exp2 = [self expectationWithDescription: @"Change"];
    [self.db addChangeListener:^(CBLDatabaseChange *change) {
        [self waitForExpectations: @[exp1] timeout: 20.0];
        [exp2 fulfill];
    }];
    
    dispatch_queue_t queue1 = dispatch_queue_create("Create",  NULL);
    dispatch_async(queue1, ^{
        [_db saveDocument: [[CBLDocument alloc] initWithID: @"doc1"]  error: nil];
        [exp1 fulfill];
    });
    
    [self waitForExpectationsWithTimeout: 10.0 handler: NULL];
}


- (void) testBlockDocumentChange {
    XCTestExpectation* exp1 = [self expectationWithDescription: @"Create"];
    XCTestExpectation* exp2 = [self expectationWithDescription: @"Change"];
    [self.db addChangeListenerForDocumentID: @"doc1" usingBlock:^(CBLDocumentChange *change) {
        [self waitForExpectations: @[exp1] timeout: 20.0];
        [exp2 fulfill];
    }];
    
    dispatch_queue_t queue1 = dispatch_queue_create("Create",  NULL);
    dispatch_async(queue1, ^{
        [_db saveDocument: [[CBLDocument alloc] initWithID: @"doc1"]  error: nil];
        [exp1 fulfill];
    });
    
    [self waitForExpectationsWithTimeout: 10.0 handler: NULL];
}


@end
