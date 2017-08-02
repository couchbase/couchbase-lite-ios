//
//  ConcurrentTest.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/17/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#import "CollectionUtils.h"

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


- (BOOL) updateDocs: (NSArray*)docIds rounds: (NSUInteger)rounds tag: (NSString*)tag
              error: (NSError**)error
{
    NSUInteger n = 0;
    for (NSUInteger r = 1; r <= rounds; r++) {
        for (NSString* docId in docIds) {
            CBLDocument* doc = [self.db documentWithID: docId];
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


- (void) concurrentRuns: (NSUInteger)nRuns withBlock: (void (^)(NSUInteger rIndex))block {
    for (NSUInteger i = 0; i < nRuns; i++) {
        NSString* name = [NSString stringWithFormat: @"Queue-%ld", (long)i];
        XCTestExpectation* exp = [self expectationWithDescription: name];
        dispatch_queue_t queue = dispatch_queue_create([name UTF8String],  NULL);
        dispatch_async(queue, ^{
            block(i);
            [exp fulfill];
        });
    }
    
    [self waitForExpectationsWithTimeout: 60.0 handler: NULL];
}


- (void) testConcurrentCreate {
    const NSUInteger kNDocs = 1000;
    const NSUInteger kNConcurrents = 10;
    
    [self concurrentRuns: kNConcurrents withBlock: ^(NSUInteger rIndex) {
        NSError* error;
        NSString* tag = [NSString stringWithFormat:@"Create%ld", (long)rIndex];
        Assert([self createDocs: kNDocs tag: tag error: &error], @"Error creating docs: %@", error);
    }];
    
    for (NSUInteger i = 0; i < kNConcurrents; i++) {
        NSString* tag = [NSString stringWithFormat:@"Create%ld", (long)i];
        [self verifyByTagName: tag numRows: kNDocs];
    }
}


- (void) testConcurrentUpdate {
    const NSUInteger kNDocs = 10;
    const NSUInteger kNRounds = 10;
    const NSUInteger kNConcurrents = 10;
    
    NSArray* docs = [self createDocs: kNDocs tag: @"Create"];
    NSArray* docIDs = [docs my_map: ^id(CBLDocument* doc) {
        return doc.id;
    }];
    
    [self concurrentRuns: kNConcurrents withBlock: ^(NSUInteger rIndex) {
        NSString* tag = [NSString stringWithFormat:@"Update%ld", (long)rIndex];
        NSError* error;
        Assert([self updateDocs: docIDs rounds: kNRounds tag: tag error: &error],
               @"Error updating doc: %@", error);
    }];
    
    __block NSUInteger count = 0;
    
    for (NSUInteger i = 0; i < kNConcurrents; i++) {
        NSString* tag = [NSString stringWithFormat:@"Update%ld", (long)i];
        [self verifyByTagName: tag test:^(uint64_t n, CBLQueryRow *row) {
            count++;
        }];
    }
    
    AssertEqual(count, kNDocs);
}


- (void) testConcurrentRead {
    const NSUInteger kNDocs = 10;
    const NSUInteger kNRounds = 100;
    const NSUInteger kNConcurrents = 10;
   
    NSArray* docs = [self createDocs: kNDocs tag: @"Create"];
    NSArray* docIDs = [docs my_map: ^id(CBLDocument* doc) {
        return doc.id;
    }];
    
    [self concurrentRuns: kNConcurrents withBlock: ^(NSUInteger rIndex) {
        [self readDocIDs: docIDs rounds: kNRounds];
    }];
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


- (void) testConcurrentInBatch {
    const NSUInteger kNDocs = 1000;
    const NSUInteger kNConcurrents = 10;
    
    [self concurrentRuns: kNConcurrents withBlock: ^(NSUInteger rIndex) {
        NSError* error;
        [self.db inBatch: &error do:^{
            NSString* tag = [NSString stringWithFormat:@"Create%ld", (long)rIndex];
            NSError* err;
            Assert([self createDocs: kNDocs tag: tag error: &err], @"Error creating docs: %@", err);
        }];
    }];
    
    for (NSUInteger i = 0; i < kNConcurrents; i++) {
        NSString* tag = [NSString stringWithFormat:@"Create%ld", (long)i];
        [self verifyByTagName: tag numRows: kNDocs];
    }
}


- (void) testConcurrentPurge {
    const NSUInteger kNDocs = 1000;
    const NSUInteger kNConcurrents = 10;
    
    NSArray* docs = [self createDocs: kNDocs tag: @"Create"];
    AssertEqual(docs.count, kNDocs);
    
    [self concurrentRuns: kNConcurrents withBlock: ^(NSUInteger rIndex) {
        for (CBLDocument* doc in docs) {
            NSError* error;
            if (![self.db purgeDocument: doc error: &error])
                AssertEqual(error.code, 404);
        }
    }];
    AssertEqual(self.db.count, 0u);
}


- (void) testConcurrentCompact {
    const NSUInteger kNDocs = 1000;
    const NSUInteger kNRounds = 10;
    const NSUInteger kNConcurrents = 10;
    
    [self createDocs: kNDocs tag: @"Create"];
    
    [self concurrentRuns: kNConcurrents withBlock: ^(NSUInteger rIndex) {
        for (NSUInteger i = 0; i < kNRounds; i++) {
            NSError* error;
            Assert([self.db compact: &error], @"Error when compact: %@", error);
        }
    }];
}


- (void) testConcurrentCreateAndCloseDB {
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


- (void) testConcurrentCreateAndDeleteDB {
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


- (void) testDatabaseChange {
    XCTestExpectation* exp1 = [self expectationWithDescription: @"Create"];
    XCTestExpectation* exp2 = [self expectationWithDescription: @"Change"];
    [self.db addChangeListener:^(CBLDatabaseChange *change) {
        [self waitForExpectations: @[exp1] timeout: 20.0]; // Test deadlock
        [exp2 fulfill];
    }];
    
    dispatch_queue_t queue1 = dispatch_queue_create("Create",  NULL);
    dispatch_async(queue1, ^{
        [_db saveDocument: [[CBLDocument alloc] initWithID: @"doc1"]  error: nil];
        [exp1 fulfill];
    });
    
    [self waitForExpectationsWithTimeout: 10.0 handler: NULL];
}


- (void) testDocumentChange {
    XCTestExpectation* exp1 = [self expectationWithDescription: @"Create"];
    XCTestExpectation* exp2 = [self expectationWithDescription: @"Change"];
    [self.db addChangeListenerForDocumentID: @"doc1" usingBlock:^(CBLDocumentChange *change) {
        [self waitForExpectations: @[exp1] timeout: 20.0]; // Test deadlock
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
