//
//  CBLTestCase.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
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

extern atomic_int gC4ExpectExceptions;

NS_ASSUME_NONNULL_BEGIN

@interface CBLTestCase : XCTestCase {
@protected
    CBLDatabase* _db;
}

@property (readonly, nonatomic) CBLDatabase* db;

@property (readonly, nonatomic) NSString* directory;

/** Default conflict resolver set to the database configuration when (re)opening 
    the default test database (.db property) or when calling the -openDBNamed:error: mehtod. */
@property (nonatomic, nullable) id <CBLConflictResolver> conflictResolver;

/** Open a database with the given name for testing. Note that the database will be opened at 
    the temp directory to avoid no bundle id issue when running the unit tests on Mac. */
- (CBLDatabase*) openDBNamed: (NSString*)name error: (NSError**)error;

/** Reopen the default test database (.db property). */
- (void) reopenDB;

/** Create a new document */
- (CBLMutableDocument*) createDocument;

/** Create a new document with the given document ID. */
- (CBLMutableDocument*) createDocument: (nullable NSString*)documentID;

/** Create a new document with the given document ID and data. */
- (CBLMutableDocument*) createDocument:(nullable NSString *)documentID data: (NSDictionary*)data;

/** Save a document return a new instance of the document from the database. */
- (CBLDocument*) saveDocument: (CBLMutableDocument*)document;

/** Save a document return a new instance of the document from the database. The eval block
 will be called twice before save and after save. When calling the eval block after save, 
 the new instance of the document will be given. */
- (CBLDocument*) saveDocument: (CBLMutableDocument*)doc eval: (void(^)(CBLDocument*))block;

/** Reads a bundle resource file into an NSData. */
- (NSData*) dataFromResource: (NSString*)resourceName ofType: (NSString*)type;

/** Reads a bundle resource file into an NSString. */
- (NSString*) stringFromResource: (NSString*)resourceName ofType: (NSString*)type;

/** Loads the database with documents read from a JSON resource file in the test bundle.
    Each line of the file should be a complete JSON object, which will become a document.
    The document IDs will be of the form "doc-#" where "#" is the line number, starting at 1. */
- (void) loadJSONResource: (NSString*)resourceName;

/** Utility to check a failure case. This method asserts that the block returns NO, and that
    it sets the NSError to the given domain and code. */
- (void) expectError: (NSErrorDomain)domain code: (NSInteger)code in: (BOOL (^)(NSError**))block;

/** Utility to check exception. This method asserts that the block has thrown the exception of the
    given name or not. */
- (void) expectException: (NSString*)name in: (void (^) (void))block;

@end

NS_ASSUME_NONNULL_END
