//
//  CBLTestCase.h
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

#import <XCTest/XCTest.h>
#import "CouchbaseLite.h"
#import <stdatomic.h>

#define Assert             XCTAssert
#define AssertNil          XCTAssertNil
#define AssertNotNil       XCTAssertNotNil
#define AssertEqual        XCTAssertEqual
#define AssertEqualObjects XCTAssertEqualObjects
#define AssertFalse        XCTAssertFalse

#define Log                NSLog
#define Warn(FMT, ...)     NSLog(@"WARNING: " FMT, ##__VA_ARGS__)

// Query:
#define EXPR_PROP(P)            [CBLQueryExpression property: (P)]
#define EXPR_VAL(V)             [CBLQueryExpression value: (V)]
#define EXPR_STR(STR)           [CBLQueryExpression string: (STR)]
#define SEL_EXPR(EXPR)          [CBLQuerySelectResult expression: (EXPR)]
#define SEL_EXPR_AS(EXPR, AS)   [CBLQuerySelectResult expression: (EXPR) as: (AS)]
#define SEL_PROP(P)             [CBLQuerySelectResult property: (P)]
#define kMETA_ID                [CBLQuerySelectResult expression: [CBLQueryMeta id]]
#define kMETA_SEQ               [CBLQuerySelectResult expression: [CBLQueryMeta sequence]]
#define kDATA_SRC_DB            [CBLQueryDataSource database: self.db]

extern atomic_int gC4ExpectExceptions;

NS_ASSUME_NONNULL_BEGIN

@interface CBLTestCase : XCTestCase {
@protected
    CBLDatabase* _db;
}

@property (readonly, nonatomic) CBLDatabase* db;

@property (readonly, nonatomic) NSString* directory;

/** Open a database with the given name for testing. Note that the database will be opened at 
    the temp directory to avoid no bundle id issue when running the unit tests on Mac. */
- (nullable CBLDatabase*) openDBNamed: (NSString*)name error: (NSError**)error;

/** Reopen the default test database (.db property). */
- (void) reopenDB;

/** Clean the default test database (.db property) */
- (void) cleanDB;

/** Delete the database with the given name. */
- (BOOL) deleteDBNamed: (NSString*)name error: (NSError**)error;

/** Delete the database and verify success. */
- (void) deleteDatabase: (CBLDatabase*)database;

/** Close the database and verify success. */
- (void) closeDatabase: (CBLDatabase*)database;

/** Create a new document */
- (CBLMutableDocument*) createDocument;

/** Create a new document with the given document ID. */
- (CBLMutableDocument*) createDocument: (nullable NSString*)documentID;

/** Create a new document with the given document ID and data. */
- (CBLMutableDocument*) createDocument:(nullable NSString *)documentID data: (NSDictionary*)data;

/** Create a simple document with the given document ID and save */
- (CBLMutableDocument*) generateDocumentWithID: (nullable NSString*)documentID;

/** Save a document in the database. */
- (void) saveDocument: (CBLMutableDocument*)document;

/** Save a document in the database. The eval block
    will be called three times, before save, after save with the given document
    object and after save with a new document objct getting from the database. */
- (void) saveDocument: (CBLMutableDocument*)doc eval: (void(^)(CBLDocument*))block;

/** Reads a bundle resource file into an NSData. */
- (NSData*) dataFromResource: (NSString*)resourceName ofType: (NSString*)type;

/** Reads a bundle resource file into an NSString. */
- (NSString*) stringFromResource: (NSString*)resourceName ofType: (NSString*)type;

/** Generates a random string with the given length. */
- (NSString*) randomStringWithLength: (NSUInteger)length;

/** Loads the database with documents read from a multiline JSON string.
    Each line of the string should be a complete JSON object, which will become a document.
    The document IDs will be of the form "doc-#" where "#" is the line number, starting at 1. */
- (void) loadJSONString: (NSString*)contents named: (NSString*)resourceName;

/** Loads the database with documents read from a JSON resource file in the test bundle,
    using -loadJSONString:named:.*/
- (void) loadJSONResource: (NSString*)resourceName;

/** Creates blob object from string. */
- (CBLBlob*) blobForString: (NSString*)string;

/** Utility to check a failure case. This method asserts that the block returns NO, and that
    it sets the NSError to the given domain and code. */
- (void) expectError: (NSErrorDomain)domain code: (NSInteger)code in: (BOOL (^)(NSError**))block;

/** Utility to check exception. This method asserts that the block has thrown the exception of the
    given name or not. */
- (void) expectException: (NSString*)name in: (void (^) (void))block;

- (void) mayHaveException: (NSString*)name in: (void (^) (void))block;

- (uint64_t) verifyQuery: (CBLQuery*)query
            randomAccess: (BOOL)randomAccess
                    test: (void (^)(uint64_t n, CBLQueryResult *result))block;

@end

NS_ASSUME_NONNULL_END
