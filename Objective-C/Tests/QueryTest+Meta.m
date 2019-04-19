//
//  QueryTest+Meta.m
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

#import "QueryTest.m"

@interface QueryTestWithMeta: QueryTest

@end

@implementation QueryTestWithMeta

#pragma mark - id & isDeleted

- (void) testMeta {
    [self loadNumbers: 5];
    
    CBLQueryExpression* DOC_ID  = [CBLQueryMeta id];
    CBLQueryExpression* DOC_SEQ = [CBLQueryMeta sequence];
    CBLQueryExpression* NUMBER1  = [CBLQueryExpression property: @"number1"];
    
    CBLQuerySelectResult* S_DOC_ID = [CBLQuerySelectResult expression: DOC_ID];
    CBLQuerySelectResult* S_DOC_SEQ = [CBLQuerySelectResult expression: DOC_SEQ];
    CBLQuerySelectResult* S_NUMBER1 = [CBLQuerySelectResult expression: NUMBER1];
    
    CBLQuery* q = [CBLQueryBuilder select: @[S_DOC_ID, S_DOC_SEQ, S_NUMBER1]
                                     from: [CBLQueryDataSource database: self.db]
                                    where: nil
                                  orderBy: @[[CBLQueryOrdering expression: DOC_SEQ]]];
    
    NSArray* expectedDocIDs  = @[@"doc1", @"doc2", @"doc3", @"doc4", @"doc5"];
    NSArray* expectedSeqs    = @[@1, @2, @3, @4, @5];
    NSArray* expectedNumbers = @[@1, @2, @3, @4, @5];
    
    uint64_t numRows = [self verifyQuery: q randomAccess: YES test: ^(uint64_t n, CBLQueryResult* r) {
        NSString* id1 = [r stringAtIndex: 0];
        NSString* id2 = [r stringForKey: @"id"];
        
        NSInteger sequence1 = [r integerAtIndex: 1];
        NSInteger sequence2 = [r integerForKey: @"sequence"];
        
        NSInteger number = [[r valueAtIndex: 2] integerValue];
        
        AssertEqualObjects(id1,  id2);
        AssertEqualObjects(id1,  expectedDocIDs[(NSUInteger)(n-1)]);
        
        AssertEqual(sequence1, sequence2);
        AssertEqual(sequence1, [expectedSeqs[(NSUInteger)(n-1)] integerValue]);
        
        AssertEqual(number, [expectedNumbers[(NSUInteger)(n-1)] integerValue]);
    }];
    AssertEqual(numRows, 5u);
}

- (void) testIsDeletedExpressionEmpty {
    // fetch is-deleted condition should return empty
    CBLQuery* q = [CBLQueryBuilder select: @[kDOCID]
                                     from: [CBLQueryDataSource database: self.db]
                                    where: [CBLQueryMeta isDeleted]];
    
    AssertNotNil(q);
    NSError* error;
    NSEnumerator* rs = [q execute:&error];
    AssertNil(error);
    AssertEqual([[rs allObjects] count], 0u);
}

- (void) testDeleteSingleDocumentForIsDeletedExpression {
    // save a new doc
    NSError* error;
    CBLMutableDocument* documentToSave = [[CBLMutableDocument alloc] init];
    [documentToSave setValue: @"string" forKey: @"string"];
    Assert([self.db saveDocument: documentToSave error: &error], @"Error when creating a document: %@", error);
    AssertNil(error);
    
    // get no-of-deleted docs & make sure its empty
    CBLQuery* q = [CBLQueryBuilder select: @[kDOCID]
                                     from: [CBLQueryDataSource database: self.db]
                                    where: [CBLQueryMeta isDeleted]];
    
    AssertNotNil(q);
    NSEnumerator* rs = [q execute:&error];
    AssertNil(error);
    AssertEqual([[rs allObjects] count], 0u);
    rs = nil;
    q = nil;
    
    // delete the doc
    [self.db deleteDocument:documentToSave error:&error];
    AssertNil(error);
    
    // get no-of-deleted docs & make sure its NOT empty
    q = [CBLQueryBuilder select: @[kDOCID]
                           from: [CBLQueryDataSource database: self.db]
                          where: [CBLQueryMeta isDeleted]];
    
    AssertNotNil(q);
    rs = [q execute:&error];
    AssertNil(error);
    AssertEqual([[rs allObjects] count], 1u);
}

- (void) testDeleteMultipleDocumentForIsDeletedExpression {
    // create
    NSUInteger documentsCount = 10;
    NSError* batchError;
    NSTimeInterval timeInterval = [[NSDate date] timeIntervalSince1970];
    NSMutableArray* docs = [[NSMutableArray alloc] init];
    [self.db inBatch:&batchError usingBlock:^{
        for (NSUInteger i = 0; i < documentsCount; i++) {
            NSError* saveDocError;
            CBLMutableDocument* doc = [[CBLMutableDocument alloc] init];
            [doc setValue: [NSString stringWithFormat:@"%0.0f-%lu", timeInterval, (unsigned long)i]
                   forKey: @"timestamp"];
            [docs addObject:doc];
            [self.db saveDocument:doc error:&saveDocError];
            AssertNil(saveDocError, @"%@", saveDocError);
        }
    }];
    AssertNil(batchError, @"%@", batchError);
    
    // validate deleted docs are empty
    CBLQuery* q = [CBLQueryBuilder select: @[kDOCID]
                                     from: [CBLQueryDataSource database: self.db]
                                    where: [CBLQueryMeta isDeleted]];
    AssertNotNil(q);
    NSError* error;
    NSEnumerator* rs = [q execute:&error];
    AssertNil(error, @"%@", error);
    AssertEqual([[rs allObjects] count], 0u);
    rs = nil;
    q = nil;
    
    // delete all the docs
    [self.db inBatch:&batchError usingBlock:^{
        for (NSUInteger i = 0; i < docs.count; i++) {
            NSError* saveDocError;
            CBLDocument* doc = [docs objectAtIndex:i];
            [self.db deleteDocument:doc error:&saveDocError];
            AssertNil(saveDocError, @"%@", saveDocError);
        }
    }];
    AssertNil(batchError, @"%@", batchError);
    
    // validate the total deleted doc count
    q = [CBLQueryBuilder select: @[kDOCID]
                           from: [CBLQueryDataSource database: self.db]
                          where: [CBLQueryMeta isDeleted]];
    
    AssertNotNil(q);
    rs = [q execute:&error];
    AssertNil(error);
    AssertEqual([[rs allObjects] count], documentsCount);
}

#pragma mark - expired

- (void) testExpiredExpressionOnEmptyDB {
    CBLQuery* q = [CBLQueryBuilder select: @[kDOCID]
                                     from: [CBLQueryDataSource database: self.db]
                                    where: [[CBLQueryMeta expiration]
                                            greaterThan: [CBLQueryExpression double: 0]]];
    
    AssertNotNil(q);
    NSError* error;
    NSEnumerator* rs = [q execute:&error];
    AssertNil(error);
    AssertEqual([[rs allObjects] count], 0u);
}

- (void) testExpiryLessThanDate {
    NSError* error;
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] init];
    NSString* docID = doc.id;
    [doc setValue: @"string" forKey: @"string"];
    Assert([self.db saveDocument: doc error: &error], @"Error when creating a document: %@", error);
    AssertNil(error);
    
    NSTimeInterval expiryTime = 120;
    NSDate* expiryDate = [NSDate dateWithTimeIntervalSinceNow: expiryTime];
    NSError* err;
    Assert([self.db setDocumentExpirationWithID: docID expiration: expiryDate error: &err]);
    AssertNil(error);
    
    NSTimeInterval future = [expiryDate dateByAddingTimeInterval: 1].timeIntervalSince1970 * 1000;
    CBLQuery* q = [CBLQueryBuilder select: @[kDOCID]
                                     from: [CBLQueryDataSource database: self.db]
                                    where: [[CBLQueryMeta expiration]
                                            lessThan: [CBLQueryExpression double: future]]];
    
    AssertNotNil(q);
    NSEnumerator* rs = [q execute:&error];
    AssertNil(error);
    AssertEqual([[rs allObjects] count], 1u);
}

- (void) testExpiryNoLessThanDate {
    NSError* error;
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] init];
    NSString* docID = doc.id;
    [doc setValue: @"someValue" forKey: @"someKey"];
    Assert([self.db saveDocument: doc error: &error], @"Error when creating a document: %@", error);
    AssertNil(error);
    
    NSTimeInterval expiryTime = 120;
    NSDate* expiryDate = [NSDate dateWithTimeIntervalSinceNow: expiryTime];
    Assert([self.db setDocumentExpirationWithID: docID expiration: expiryDate error: &error]);
    AssertNil(error);
    
    NSTimeInterval earlier = [expiryDate dateByAddingTimeInterval: -1].timeIntervalSince1970 * 1000;
    CBLQuery* q = [CBLQueryBuilder select: @[kDOCID]
                                     from: [CBLQueryDataSource database: self.db]
                                    where: [[CBLQueryMeta expiration]
                                            lessThan: [CBLQueryExpression double: earlier]]];
    
    AssertNotNil(q);
    NSEnumerator* rs = [q execute:&error];
    AssertNil(error);
    AssertEqual([[rs allObjects] count], 0u);
}

- (void) testExpiryGreaterThanDate {
    NSError* error;
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] init];
    NSString* docID = doc.id;
    [doc setValue: @"someValue" forKey: @"someKey"];
    Assert([self.db saveDocument: doc error: &error], @"Error when creating a document: %@", error);
    AssertNil(error);
    
    NSTimeInterval expiryTime = 120;
    NSDate* expiryDate = [NSDate dateWithTimeIntervalSinceNow: expiryTime];
    Assert([self.db setDocumentExpirationWithID: docID expiration: expiryDate error: &error]);
    AssertNil(error);
    
    NSTimeInterval earlier = [expiryDate dateByAddingTimeInterval: -1].timeIntervalSince1970 * 1000;
    CBLQuery* q = [CBLQueryBuilder select: @[kDOCID]
                                     from: [CBLQueryDataSource database: self.db]
                                    where: [[CBLQueryMeta expiration]
                                            greaterThan: [CBLQueryExpression double: earlier]]];
    
    AssertNotNil(q);
    NSEnumerator* rs = [q execute:&error];
    AssertNil(error);
    AssertEqual([[rs allObjects] count], 1u);
}

- (void) testExpiryNoGreaterThanDate {
    NSError* error;
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] init];
    NSString* docID = doc.id;
    [doc setValue: @"someValue" forKey: @"someKey"];
    Assert([self.db saveDocument: doc error: &error], @"Error when creating a document: %@", error);
    AssertNil(error);
    
    NSTimeInterval expiryTime = 120;
    NSDate* expiryDate = [NSDate dateWithTimeIntervalSinceNow: expiryTime];
    Assert([self.db setDocumentExpirationWithID: docID expiration: expiryDate error: &error]);
    AssertNil(error);
    
    NSTimeInterval future = expiryDate.timeIntervalSince1970 * 1000;
    CBLQuery* q = [CBLQueryBuilder select: @[kDOCID]
                                     from: [CBLQueryDataSource database: self.db]
                                    where: [[CBLQueryMeta expiration]
                                            greaterThan: [CBLQueryExpression double: future]]];
    
    AssertNotNil(q);
    NSEnumerator* rs = [q execute:&error];
    AssertNil(error);
    AssertEqual([[rs allObjects] count], 0u);
}

@end
