//
//  DocumentTest.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/11/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLJSON.h"


@interface DocumentTest : CBLTestCase

@end


@implementation DocumentTest


- (void) testNewDoc {
    NSError* error;
    
    CBLDocument* doc = [self.db document];
    AssertNotNil(doc);
    AssertNotNil(doc.documentID);
    Assert(doc.documentID.length > 0);
    AssertEqual(doc.database, self.db);
    AssertFalse(doc.exists);
    AssertFalse(doc.isDeleted);
    AssertNil(doc.properties);
    AssertEqual(doc[@"prop"], nil);
    AssertFalse([doc booleanForKey: @"prop"]);
    AssertEqual([doc integerForKey: @"prop"], 0);
    AssertEqual([doc floatForKey: @"prop"], 0.0);
    AssertEqual([doc doubleForKey: @"prop"], 0.0);
    AssertNil([doc dateForKey: @"prop"]);
    AssertNil([doc stringForKey: @"prop"]);
    
    Assert([doc save: &error], @"Error saving: %@", error);
    Assert(doc.exists);
    AssertFalse(doc.isDeleted);
    AssertNil(doc.properties);
}


- (void) testNewDocWithId {
    NSError* error;
    
    CBLDocument* doc = [self.db documentWithID: @"doc1"];
    AssertEqual(doc, self.db[@"doc1"]);
    AssertNotNil(doc);
    AssertEqual(doc.documentID, @"doc1");
    AssertEqual(doc.database, self.db);
    AssertFalse(doc.exists);
    AssertFalse(doc.isDeleted);
    AssertNil(doc.properties);
    AssertEqual(doc[@"prop"], nil);
    AssertFalse([doc booleanForKey: @"prop"]);
    AssertEqual([doc integerForKey: @"prop"], 0);
    AssertEqual([doc floatForKey: @"prop"], 0.0);
    AssertEqual([doc doubleForKey: @"prop"], 0.0);
    AssertNil([doc dateForKey: @"prop"]);
    AssertNil([doc stringForKey: @"prop"]);
    
    Assert([doc save: &error], @"Error saving: %@", error);
    Assert(doc.exists);
    AssertFalse(doc.isDeleted);
    AssertNil(doc.properties);
    AssertEqual(doc, self.db[@"doc1"]);
}


- (void) testPropertyAccessors {
    CBLDocument* doc = [self.db documentWithID: @"doc1"];
    
    // Premitives:
    [doc setBoolean: YES forKey: @"bool"];
    [doc setDouble: 1.1 forKey: @"double"];
    [doc setFloat: 1.2f forKey: @"float"];
    [doc setInteger: 2 forKey: @"integer"];
    
    // Objects:
    [doc setObject: @"str" forKey: @"string"];
    [doc setObject: @(YES) forKey: @"boolObj"];
    [doc setObject: @(1) forKey: @"number"];
    [doc setObject: @[@"1", @"2"] forKey: @"array"];
    
    // Date:
    NSDate* date = [NSDate date];
    [doc setObject: date forKey: @"date"];
    
    NSError* error;
    Assert([doc save: &error], @"Error saving: %@", error);
    
    // Primitives:
    AssertEqual([doc booleanForKey: @"bool"], YES);
    AssertEqual([doc doubleForKey: @"double"], 1.1);
    AssertEqual([doc floatForKey: @"float"], @(1.2).floatValue);
    AssertEqual([doc integerForKey: @"integer"], 2);
    
    // Objects:
    AssertEqualObjects([doc stringForKey: @"string"], @"str");
    AssertEqualObjects([doc objectForKey: @"boolObj"], @(YES));
    AssertEqualObjects([doc objectForKey: @"number"], @(1));
    AssertEqualObjects([doc objectForKey: @"array"], (@[@"1", @"2"]));
    
    // Date:
    AssertEqualObjects([CBLJSON JSONObjectWithDate: [doc dateForKey: @"date"]],
                       [CBLJSON JSONObjectWithDate: date]);
    
    ////// Get the doc from a different database and check again:
    
    CBLDocument* doc1 = [[self.db copy] documentWithID: @"doc1"];
    
    AssertEqual([doc1 booleanForKey: @"bool"], YES);
    AssertEqual([doc1 doubleForKey: @"double"], 1.1);
    AssertEqual([doc1 floatForKey: @"float"], @(1.2).floatValue);
    AssertEqual([doc1 integerForKey: @"integer"], 2);
    
    // Objects:
    AssertEqualObjects([doc1 stringForKey: @"string"], @"str");
    AssertEqualObjects([doc1 objectForKey: @"boolObj"], @(YES));
    AssertEqualObjects([doc1 objectForKey: @"number"], @(1));
    AssertEqualObjects([doc1 objectForKey: @"array"], (@[@"1", @"2"]));
    
    // Date:
    AssertEqualObjects([CBLJSON JSONObjectWithDate: [doc1 dateForKey: @"date"]],
                       [CBLJSON JSONObjectWithDate: date]);
}


- (void) testUnsupportedDataType {
    CBLDocument* doc = [self.db documentWithID: @"doc1"];
    XCTAssertThrows([doc setObject: [[NSMapTable alloc] init] forKey: @"table"]);
    XCTAssertThrows([doc setObject: [[NSMapTable alloc] init] forKey: @"table"]);
    XCTAssertThrows([doc setObject: @[[NSDate date]] forKey: @"dates"]);
    XCTAssertThrows([doc setObject: @[[CBLSubdocument subdocument]] forKey: @"subdocs"]);
}


- (void) testProperties {
    CBLDocument* doc = self.db[@"doc1"];
    doc[@"type"] = @"demo";
    doc[@"weight"] = @12.5;
    doc[@"tags"] = @[@"useless", @"temporary"];
    
    AssertEqualObjects(doc[@"type"], @"demo");
    AssertEqual([doc doubleForKey: @"weight"], 12.5);
    AssertEqualObjects(doc.properties,
        (@{@"type": @"demo", @"weight": @12.5, @"tags": @[@"useless", @"temporary"]}));
}


- (void) testDelete {
    CBLDocument* doc = [self.db documentWithID: @"doc1"];
    doc[@"type"] = @"profile";
    doc[@"name"] = @"Scott";
    AssertFalse([doc exists]);
    AssertFalse(doc.isDeleted);
    
    // Delete before save:
    AssertFalse([doc deleteDocument: nil]);
    AssertEqualObjects(doc[@"type"], @"profile");
    AssertEqualObjects(doc[@"name"], @"Scott");
    
    // Save:
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);
    Assert([doc exists]);
    AssertFalse(doc.isDeleted);
    
    doc[@"address"] = @"1 Street";
    AssertEqualObjects(doc[@"type"], @"profile");
    AssertEqualObjects(doc[@"name"], @"Scott");
    AssertEqualObjects(doc[@"address"], @"1 Street");
    
    // Delete:
    Assert([doc deleteDocument: &error], @"Deleting error: %@", error);
    Assert([doc exists]);
    Assert(doc.isDeleted);
    AssertNil(doc.properties);
}


- (void) testPurge {
    CBLDocument* doc = [self.db documentWithID: @"doc1"];
    doc[@"type"] = @"profile";
    doc[@"name"] = @"Scott";
    AssertFalse([doc exists]);
    AssertFalse(doc.isDeleted);
    
    // Purge before save:
    AssertFalse([doc purge: nil]);
    AssertEqualObjects(doc[@"type"], @"profile");
    AssertEqualObjects(doc[@"name"], @"Scott");
    
    // Save:
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);
    Assert([doc exists]);
    AssertFalse(doc.isDeleted);
    
    // Purge:
    Assert([doc purge: &error], @"Purging error: %@", error);
    AssertFalse([doc exists]);
    AssertFalse(doc.isDeleted);
}


- (void) testRevert {
    CBLDocument* doc = [self.db documentWithID: @"doc1"];
    doc[@"type"] = @"profile";
    doc[@"name"] = @"Scott";
    
    // Revert before save:
    [doc revert];
    AssertNil(doc[@"type"]);
    AssertNil(doc[@"name"]);
    
    // Save:
    doc[@"type"] = @"profile";
    doc[@"name"] = @"Scott";
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);
    AssertEqualObjects(doc[@"type"], @"profile");
    AssertEqualObjects(doc[@"name"], @"Scott");
    
    // Make some changes:
    doc[@"type"] = @"user";
    doc[@"name"] = @"Scottie";
    
    // Revert:
    [doc revert];
    AssertEqualObjects(doc[@"type"], @"profile");
    AssertEqualObjects(doc[@"name"], @"Scott");
}


@end
