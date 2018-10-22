//
//  ConcurrentTest.m
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
#import "CollectionUtils.h"

#define kDocumentTestBlob @"i'm blob"

@interface ConcurrentTest : CBLTestCase

@end

@implementation ConcurrentTest


- (void) setProperties: (id <CBLMutableDictionary>)dictionary
                custom: (nullable NSDictionary*)custom
{
    [dictionary setValue: @"Daniel" forKey: @"firstName"];
    [dictionary setValue: @"Tiger" forKey: @"lastName"];
    [dictionary setInteger: 10 forKey: @"score"];
    
    NSData* data = [@"Concurrent Test" dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType: @"text/plain" data: data];
    [dictionary setValue: blob forKey: @"blob"];
    
    CBLMutableDictionary* address = [[CBLMutableDictionary alloc] init];
    [dictionary setValue: address forKey: @"address"];
    
    // Array:
    CBLMutableArray* array = array = [[CBLMutableArray alloc] init];
    [array addValue: @"650-123-0001"];
    [array addValue: @"650-123-0002"];
    [dictionary setValue: array forKey: @"phones"];
    
    // Date:
    [dictionary setValue: [NSDate date] forKey: @"date"];
    
    // Custom:
    for (NSString* key in custom) {
        [dictionary setValue: custom[key] forKey: key];
    }
}


- (CBLMutableDocument*) createDoc {
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] init];
    [self setProperties: doc custom: nil];
    return doc;
}


- (NSArray*) createAndSaveDocs: (NSUInteger)nDocs  error: (NSError**)error {
    NSMutableArray* docs = [NSMutableArray arrayWithCapacity: nDocs];
    for (NSUInteger i = 0; i < nDocs; i++) {
        CBLMutableDocument* doc = [self createDoc];
        if (![self.db saveDocument: doc error: error])
            return nil;
        [docs addObject: doc];
    }
    return docs;
}


- (BOOL) updateDoc: (CBLMutableDocument*)doc
            custom: (nullable NSDictionary*)custom
             error: (NSError**)error
{
    [self setProperties: doc custom: custom];
    return [self.db saveDocument: doc error: error];
}


- (BOOL) updateDocIDs: (NSArray*)docIds
               rounds: (NSUInteger)rounds
               custom: (nullable NSDictionary*)custom
                error: (NSError**)error
{
    for (NSUInteger r = 0; r < rounds; r++) {
        for (NSString* docId in docIds) {
            CBLMutableDocument* doc = [[self.db documentWithID: docId] toMutable];
            [self updateDoc: doc custom: custom error: error];
        }
    }
    return YES;
}


- (void) verifyWhere: (nullable CBLQueryExpression*)expr
                test: (void (^)(uint64_t n, CBLQueryResult *row))block {
    CBLQuery* q = [CBLQueryBuilder select: @[[CBLQuerySelectResult expression: [CBLQueryMeta id]]]
                                     from: [CBLQueryDataSource database: self.db]
                                    where: expr];
    NSError* error;
    NSEnumerator* e = [q execute: &error];
    Assert(e, @"Query failed: %@", error);
    uint64_t n = 0;
    for (CBLQueryResult *row in e) {
        block(++n, row);
    }
}


- (void) concurrentRuns: (NSUInteger)nRuns
          waitUntilDone: (BOOL)wait
              withBlock: (void (^)(NSUInteger rIndex))block
{
    NSMutableArray* expects = [NSMutableArray arrayWithCapacity: nRuns];
    for (NSUInteger i = 0; i < nRuns; i++) {
        NSString* name = [NSString stringWithFormat: @"Queue-%ld", (long)i];
        XCTestExpectation* exp = nil;
        if (wait) {
            exp = [self expectationWithDescription: name];
            [expects addObject: exp];
        }
        dispatch_queue_t queue = dispatch_queue_create([name UTF8String],  NULL);
        dispatch_async(queue, ^{
            block(i);
            [exp fulfill];
        });
    }
    
    if (expects.count > 0) {
        [self waitForExpectations: expects timeout: 60.0];
    }
}


#pragma mark - Database


- (void) testConcurrentCreateDocs {
    const NSUInteger kNDocs = 100;
    const NSUInteger kNConcurrents = 5;
    
    [self concurrentRuns: kNConcurrents waitUntilDone: YES withBlock: ^(NSUInteger rIndex) {
        NSError* error;
        Assert([self createAndSaveDocs: kNDocs error: &error],
               @"Error creating docs: %@", error);
    }];
    
    AssertEqual(self.db.count, kNDocs * kNConcurrents);
}


- (void) testConcurrentReadDocs {
    const NSUInteger kNDocs = 100;
    const NSUInteger kNRounds = 20;
    const NSUInteger kNConcurrents = 5;
    
    
    NSArray* docs = [self createAndSaveDocs: kNDocs error: nil];
    NSArray* docIds = [docs my_map: ^id(CBLDocument* doc) {
        return doc.id;
    }];
    
    [self concurrentRuns: kNConcurrents waitUntilDone: YES withBlock: ^(NSUInteger rIndex) {
        for (NSUInteger r = 0; r < kNRounds; r++) {
            for (NSString* docId in docIds) {
                @autoreleasepool {
                    CBLDocument* doc = [self.db documentWithID: docId];
                    Assert(doc != nil);
                }
            }
        }
    }];
}


// https://github.com/couchbase/couchbase-lite-ios/issues/1967
- (void) testConcurrentReadForUpdatesDocs {
    const NSUInteger kNDocs = 100;
    const NSUInteger kNRounds = 10;
    const NSUInteger kNConcurrents = 5;
    
    NSArray* docs = [self createAndSaveDocs: kNDocs error: nil];
    NSArray* docIds = [docs my_map: ^id(CBLDocument* doc) {
        return doc.id;
    }];
    
    [self concurrentRuns: kNConcurrents waitUntilDone: YES withBlock: ^(NSUInteger rIndex) {
        for (NSUInteger r = 0; r < kNRounds; r++) {
            for (NSString* docId in docIds) {
                CBLMutableDocument* mDoc = [[self.db documentWithID: docId] toMutable];
                Assert(mDoc != nil);
            }
        }
    }];
}


// https://github.com/couchbase/couchbase-lite-ios/issues/1967
- (void) testConcurrentUpdateSeperateDocInstances {
    const NSUInteger kNDocs = 1;
    const NSUInteger kNRounds = 10;
    const NSUInteger kNConcurrents = 5;
    
    NSArray* docs = [self createAndSaveDocs: kNDocs error: nil];
    NSArray* docIds = [docs my_map: ^id(CBLDocument* doc) {
        return doc.id;
    }];
    
    [self concurrentRuns: kNConcurrents waitUntilDone: YES withBlock: ^(NSUInteger rIndex) {
        NSString* tag = [NSString stringWithFormat:@"Update%ld", (long)rIndex];
        NSError* error;
        Assert([self updateDocIDs: docIds rounds: kNRounds custom: @{@"tag": tag} error: &error],
               @"Error updating doc: %@", error);
    }];
    
    __block NSUInteger count = 0;
    
    for (NSUInteger i = 0; i < kNConcurrents; i++) {
        NSString* tag = [NSString stringWithFormat:@"Update%ld", (long)i];
        CBLQueryExpression* expr = [[CBLQueryExpression property: @"tag"]
                                    equalTo: [CBLQueryExpression string: tag]];
        [self verifyWhere: expr test: ^(uint64_t n, CBLQueryResult *row) {
            count++;
        }];
    }
    
    AssertEqual(count, kNDocs);
}


- (void) testConcurrentDeleteDocs {
    const NSUInteger kNDocs = 5;
    const NSUInteger kNConcurrents = 5;
    
    NSArray* docs = [self createAndSaveDocs: kNDocs error: nil];
    [self concurrentRuns: kNConcurrents waitUntilDone: YES withBlock: ^(NSUInteger rIndex) {
        for (CBLDocument* doc in docs) {
            NSError* error;
            Assert([self.db deleteDocument: doc error: &error], @"Error when delete: %@", error);
        }
    }];
    
    AssertEqual(self.db.count, 0u);
}


- (void) testConcurrentInBatch {
    const NSUInteger kNDocs = 100;
    const NSUInteger kNConcurrents = 5;
    
    [self concurrentRuns: kNConcurrents waitUntilDone: YES withBlock: ^(NSUInteger rIndex) {
        NSError* error;
        [self.db inBatch: &error usingBlock: ^{
            NSError* err;
            Assert([self createAndSaveDocs: kNDocs error: &err],
                   @"Error creating docs: %@", err);
        }];
    }];
    
    AssertEqual(self.db.count, kNDocs * kNConcurrents);
}


- (void) testConcurrentPurgeDocs {
    const NSUInteger kNDocs = 100;
    const NSUInteger kNConcurrents = 5;
    
    NSArray* docs = [self createAndSaveDocs: kNDocs error: nil];
    
    [self concurrentRuns: kNConcurrents waitUntilDone: YES withBlock: ^(NSUInteger rIndex) {
        for (CBLDocument* doc in docs) {
            NSError* error;
            if (![self.db purgeDocument: doc error: &error]) {
                AssertEqualObjects(error.domain, CBLErrorDomain);
                AssertEqual(error.code, CBLErrorNotFound);
            }
        }
    }];
    AssertEqual(self.db.count, 0u);
}


- (void) testConcurrentCompact {
    const NSUInteger kNDocs = 100;
    const NSUInteger kNRounds = 10;
    const NSUInteger kNConcurrents = 5;
    
    [self createAndSaveDocs: kNDocs error: nil];
    [self concurrentRuns: kNConcurrents waitUntilDone: YES withBlock: ^(NSUInteger rIndex) {
        for (NSUInteger i = 0; i < kNRounds; i++) {
            NSError* error;
            Assert([self.db compact: &error], @"Error when compact: %@", error);
        }
    }];
}

#if 0
- (void) testDatabaseChange {
    XCTestExpectation* exp1 = [self expectationWithDescription: @"Create"];
    XCTestExpectation* exp2 = [self expectationWithDescription: @"Change"];
    [self.db addChangeListener: ^(CBLDatabaseChange *change) {
        [self waitForExpectations: @[exp1] timeout: 5.0]; // Test deadlock
        [exp2 fulfill];
    }];
    
    [self concurrentRuns: 1 waitUntilDone: NO withBlock: ^(NSUInteger rIndex) {
        [_db saveDocument: [[CBLMutableDocument alloc] initWithID: @"doc1"]  error: nil];
        [exp1 fulfill];
    }];
    
    [self waitForExpectations: @[exp2] timeout: 10.0]; // Test deadlock
}
#endif //TEMP

#if 0 //TEMP
- (void) testDocumentChange {
    XCTestExpectation* exp1 = [self expectationWithDescription: @"Create"];
    XCTestExpectation* exp2 = [self expectationWithDescription: @"Change"];
    [self.db addDocumentChangeListenerWithID: @"doc1" listener: ^(CBLDocumentChange *change) {
        [self waitForExpectations: @[exp1] timeout: 5.0]; // Test deadlock
        [exp2 fulfill];
    }];
    
    [self concurrentRuns: 1 waitUntilDone: NO withBlock: ^(NSUInteger rIndex) {
        [_db saveDocument: [[CBLMutableDocument alloc] initWithID: @"doc1"]  error: nil];
        [exp1 fulfill];
    }];
    
    [self waitForExpectations: @[exp2] timeout: 10.0]; // Test deadlock
}
#endif

@end
