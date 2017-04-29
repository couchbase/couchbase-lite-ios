//
//  DocumentTest.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/11/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"

#import "CBLBlob.h"
#import "CBLJSON.h"
#import "CBLError.h"


@interface DocumentTest : CBLTestCase

@end


@implementation DocumentTest


- (void) populateData: (CBLDocument*)doc {
    [doc setDictionary: @{@"null": [NSNull null]}];
    [doc setObject: @(YES) forKey: @"true"];
    [doc setObject: @(NO) forKey: @"false"];
    [doc setObject: @"string" forKey: @"string"];
    [doc setObject: @(0) forKey: @"zero"];
    [doc setObject: @(1) forKey: @"one"];
    [doc setObject: @(-1) forKey: @"minus_one"];
    [doc setObject: @(1.1) forKey: @"one_dot_one"];
    [doc setObject: [NSDate date] forKey: @"date"];
    
    // Subdocument:
    CBLSubdocument* subdoc = [[CBLSubdocument alloc] init];
    [subdoc setObject: @"1 Main street" forKey: @"street"];
    [subdoc setObject: @"Mountain View" forKey: @"city"];
    [subdoc setObject: @"CA" forKey: @"state"];
    [doc setObject: subdoc forKey: @"subdoc"];
    
    // Array:
    CBLArray* array = [[CBLArray alloc] init];
    [array addObject: @"650-123-0001"];
    [array addObject: @"650-123-0002"];
    [doc setObject: array forKey: @"array"];
    
    // Blob:
    NSData* content = [@"12345" dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType:@"text/plain" data: content];
    [doc setObject: blob forKey: @"blob"];
}


- (void) testCreateDoc {
    CBLDocument* doc1a = [[CBLDocument alloc] init];
    AssertNotNil(doc1a);
    Assert(doc1a.documentID.length > 0);
    AssertFalse(doc1a.isDeleted);
    AssertEqualObjects([doc1a toDictionary], @{});
    
    NSError* error;
    Assert([_db saveDocument: doc1a error: &error], @"Error saving: %@", error);
    
    CBLDocument* doc1b = [_db documentWithID: doc1a.documentID];
    Assert(doc1b != doc1a);
    AssertNotNil(doc1b);
    AssertEqualObjects(doc1b.documentID, doc1a.documentID);
}


- (void) testCreateDocWithID {
    CBLDocument* doc1a = [[CBLDocument alloc] initWithID: @"doc1"];
    AssertNotNil(doc1a);
    AssertEqualObjects(doc1a.documentID, @"doc1");
    AssertFalse(doc1a.isDeleted);
    AssertEqualObjects([doc1a toDictionary], @{});
    
    NSError* error;
    Assert([_db saveDocument: doc1a error: &error], @"Error saving: %@", error);
    
    CBLDocument* doc1b = [_db documentWithID: doc1a.documentID];
    Assert(doc1b != doc1a);
    AssertNotNil(doc1b);
    AssertEqualObjects(doc1b.documentID, doc1a.documentID);
}


- (void) testCreateDocWithEmptyStringID {
    CBLDocument* doc1a = [[CBLDocument alloc] initWithID: @""];
    AssertNotNil(doc1a);
    AssertEqualObjects(doc1a.documentID, @"");
    AssertFalse(doc1a.isDeleted);
    AssertEqualObjects([doc1a toDictionary], @{});
    
    NSError* error;
    Assert([_db saveDocument: doc1a error: &error], @"Error saving: %@", error);
    
    CBLDocument* doc1b = [_db documentWithID: @""];
    Assert(doc1b != doc1a);
    AssertNotNil(doc1b);
    AssertEqualObjects(doc1b.documentID, doc1a.documentID);
}


- (void) testCreateDocWithNilID {
    CBLDocument* doc1a = [[CBLDocument alloc] initWithID: nil];
    AssertNotNil(doc1a);
    Assert(doc1a.documentID.length > 0);
    AssertFalse(doc1a.isDeleted);
    AssertEqualObjects([doc1a toDictionary], @{});
    
    NSError* error;
    Assert([_db saveDocument: doc1a error: &error], @"Error saving: %@", error);
    
    CBLDocument* doc1b = [_db documentWithID: doc1a.documentID];
    Assert(doc1b != doc1a);
    AssertNotNil(doc1b);
    AssertEqualObjects(doc1b.documentID, doc1a.documentID);
}


- (void) testCreateDocWithDict {
    NSDictionary* dict = @{@"name": @"Scott Tiger",
                           @"age": @(30),
                           @"address": @{
                                   @"street": @"1 Main street.",
                                   @"city": @"Mountain View",
                                   @"state": @"CA"},
                           @"phones": @[@"650-123-0001", @"650-123-0002"]
                           };
    
    CBLDocument* doc1a = [[CBLDocument alloc] initWithDictionary: dict];
    AssertNotNil(doc1a);
    Assert(doc1a.documentID.length > 0);
    AssertFalse(doc1a.isDeleted);
    AssertEqualObjects([doc1a toDictionary], dict);
    
    NSError* error;
    Assert([_db saveDocument: doc1a error: &error], @"Error saving: %@", error);
    
    CBLDocument* doc1b = [_db documentWithID: doc1a.documentID];
    Assert(doc1b != doc1a);
    AssertNotNil(doc1b);
    AssertEqualObjects(doc1b.documentID, doc1a.documentID);
    AssertEqualObjects([doc1b toDictionary], dict);
}


- (void) testCreateDocWithIDAndDict {
    NSDictionary* dict = @{@"name": @"Scott Tiger",
                           @"age": @(30),
                           @"address": @{
                                   @"street": @"1 Main street.",
                                   @"city": @"Mountain View",
                                   @"state": @"CA"},
                           @"phones": @[@"650-123-0001", @"650-123-0002"]
                           };
    
    CBLDocument* doc1a = [[CBLDocument alloc] initWithID: @"doc1" dictionary: dict];
    AssertNotNil(doc1a);
    AssertEqualObjects(doc1a.documentID, @"doc1");
    AssertFalse(doc1a.isDeleted);
    AssertEqualObjects([doc1a toDictionary], dict);
    
    NSError* error;
    Assert([_db saveDocument: doc1a error: &error], @"Error saving: %@", error);
    
    CBLDocument* doc1b = [_db documentWithID: doc1a.documentID];
    Assert(doc1b != doc1a);
    AssertNotNil(doc1b);
    AssertEqualObjects(doc1b.documentID, doc1a.documentID);
    AssertEqualObjects([doc1b toDictionary], dict);
}


- (void) testSetDictionaryContent {
    NSDictionary* dict = @{@"name": @"Scott Tiger",
                           @"age": @(30),
                           @"address": @{
                                   @"street": @"1 Main street.",
                                   @"city": @"Mountain View",
                                   @"state": @"CA"},
                           @"phones": @[@"650-123-0001", @"650-123-0002"]
                           };
    
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc1 setDictionary: dict];
    AssertEqualObjects([doc1 toDictionary], dict);
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    AssertEqualObjects([doc1 toDictionary], dict);
    
    NSDictionary* nuDict = @{@"name": @"Danial Tiger",
                             @"age": @(32),
                             @"address": @{
                                     @"street": @"2 Main street.",
                                     @"city": @"Palo Alto",
                                     @"state": @"CA"},
                             @"phones": @[@"650-234-0001", @"650-234-0002"]
                             };
    [doc1 setDictionary: nuDict];
    AssertEqualObjects([doc1 toDictionary], nuDict);
    
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    AssertEqualObjects([doc1 toDictionary], nuDict);
}


- (void) testGetValueFromNewEmptyDoc {
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    
    AssertEqual([doc1 integerForKey: @"key"], 0);
    AssertEqual([doc1 floatForKey: @"key"], 0.0f);
    AssertEqual([doc1 doubleForKey: @"key"], 0.0);
    AssertEqual([doc1 booleanForKey: @"key"], NO);
    AssertNil([doc1 blobForKey: @"key"]);
    AssertNil([doc1 dateForKey: @"key"]);
    AssertNil([doc1 numberForKey: @"key"]);
    AssertNil([doc1 objectForKey: @"key"]);
    AssertNil([doc1 stringForKey: @"key"]);
    AssertNil([doc1 subdocumentForKey: @"key"]);
    AssertNil([doc1 arrayForKey: @"key"]);
    AssertEqualObjects([doc1 toDictionary], @{});
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    
    AssertEqual([doc1 integerForKey: @"key"], 0);
    AssertEqual([doc1 floatForKey: @"key"], 0.0f);
    AssertEqual([doc1 doubleForKey: @"key"], 0.0);
    AssertEqual([doc1 booleanForKey: @"key"], NO);
    AssertNil([doc1 blobForKey: @"key"]);
    AssertNil([doc1 dateForKey: @"key"]);
    AssertNil([doc1 numberForKey: @"key"]);
    AssertNil([doc1 objectForKey: @"key"]);
    AssertNil([doc1 stringForKey: @"key"]);
    AssertNil([doc1 subdocumentForKey: @"key"]);
    AssertNil([doc1 arrayForKey: @"key"]);
    AssertEqualObjects([doc1 toDictionary], @{});
}


- (void) testGetValueFromExistingEmptyDoc {
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    
    doc1 = [_db documentWithID: doc1.documentID];
    
    AssertEqual([doc1 integerForKey: @"key"], 0);
    AssertEqual([doc1 floatForKey: @"key"], 0.0f);
    AssertEqual([doc1 doubleForKey: @"key"], 0.0);
    AssertEqual([doc1 booleanForKey: @"key"], NO);
    
    AssertNil([doc1 blobForKey: @"key"]);
    AssertNil([doc1 dateForKey: @"key"]);
    AssertNil([doc1 numberForKey: @"key"]);
    AssertNil([doc1 objectForKey: @"key"]);
    AssertNil([doc1 stringForKey: @"key"]);
    
    AssertNil([doc1 subdocumentForKey: @"key"]);
    AssertNil([doc1 arrayForKey: @"key"]);
    
    AssertEqualObjects([doc1 toDictionary], @{});
}


- (void) testSaveThenGetFromAnotherDB {
    CBLDocument* doc1a = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc1a setObject: @"Scott Tiger" forKey: @"name"];
    
    NSError* error;
    Assert([_db saveDocument: doc1a error: &error], @"Error saving: %@", error);
    
    CBLDatabase* anotherDb = [_db copy];
    CBLDocument* doc1b = [anotherDb documentWithID: doc1a.documentID];
    Assert(doc1b != doc1a);
    AssertEqualObjects(doc1b.documentID, doc1a.documentID);
    AssertEqualObjects([doc1b toDictionary], [doc1a toDictionary]);
}


- (void) testNoCacheNoLive {
    CBLDocument* doc1a = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc1a setObject: @"Scott Tiger" forKey: @"name"];
    
    NSError* error;
    Assert([_db saveDocument: doc1a error: &error], @"Error saving: %@", error);
    
    CBLDocument* doc1b = [_db documentWithID: @"doc1"];
    CBLDocument* doc1c = [_db documentWithID: @"doc1"];
    
    CBLDatabase* anotherDb = [_db copy];
    CBLDocument* doc1d = [anotherDb documentWithID: @"doc1"];
    
    Assert(doc1a != doc1b);
    Assert(doc1a != doc1c);
    Assert(doc1a != doc1d);
    Assert(doc1b != doc1c);
    Assert(doc1b != doc1d);
    Assert(doc1c != doc1d);
    
    AssertEqualObjects([doc1a toDictionary], [doc1b toDictionary]);
    AssertEqualObjects([doc1a toDictionary], [doc1c toDictionary]);
    AssertEqualObjects([doc1a toDictionary], [doc1d toDictionary]);
    
    // Update:
    [doc1b setObject:@"Daniel Tiger" forKey: @"name"];
    Assert([_db saveDocument: doc1b error: &error], @"Error saving: %@", error);
    
    XCTAssertNotEqualObjects([doc1b toDictionary], [doc1a toDictionary]);
    XCTAssertNotEqualObjects([doc1b toDictionary], [doc1c toDictionary]);
    XCTAssertNotEqualObjects([doc1b toDictionary], [doc1d toDictionary]);
}


- (void) testSetString {
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc1 setObject: @"" forKey: @"string1"];
    [doc1 setObject: @"string" forKey: @"string2"];
    
    AssertEqualObjects([doc1 objectForKey: @"string1"], @"");
    AssertEqualObjects([doc1 objectForKey: @"string2"], @"string");
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    
    AssertEqualObjects([doc1 objectForKey: @"string1"], @"");
    AssertEqualObjects([doc1 objectForKey: @"string2"], @"string");
    
    // Update:
    [doc1 setObject: @"string" forKey: @"string1"];
    [doc1 setObject: @"" forKey: @"string2"];
    
    AssertEqualObjects([doc1 objectForKey: @"string1"], @"string");
    AssertEqualObjects([doc1 objectForKey: @"string2"], @"");
    
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    
    AssertEqualObjects([doc1 objectForKey: @"string1"], @"string");
    AssertEqualObjects([doc1 objectForKey: @"string2"], @"");
}


- (void) testGetString {
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    [self populateData: doc1];
    
    AssertNil([doc1 stringForKey: @"null"]);
    AssertNil([doc1 stringForKey: @"true"]);
    AssertNil([doc1 stringForKey: @"false"]);
    AssertEqualObjects([doc1 stringForKey: @"string"], @"string");
    AssertNil([doc1 stringForKey: @"zero"]);
    AssertNil([doc1 stringForKey: @"one"]);
    AssertNil([doc1 stringForKey: @"minus_one"]);
    AssertNil([doc1 stringForKey: @"one_dot_one"]);
    AssertEqualObjects([doc1 stringForKey: @"date"],
                       [CBLJSON JSONObjectWithDate: [doc1 dateForKey: @"date"]]);
    AssertNil([doc1 stringForKey: @"subdoc"]);
    AssertNil([doc1 stringForKey: @"array"]);
    AssertNil([doc1 stringForKey: @"blob"]);
    AssertNil([doc1 stringForKey: @"non_existing_key"]);
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    
    AssertNil([doc1 stringForKey: @"null"]);
    AssertNil([doc1 stringForKey: @"true"]);
    AssertNil([doc1 stringForKey: @"false"]);
    AssertEqualObjects([doc1 stringForKey: @"string"], @"string");
    AssertNil([doc1 stringForKey: @"zero"]);
    AssertNil([doc1 stringForKey: @"one"]);
    AssertNil([doc1 stringForKey: @"minus_one"]);
    AssertNil([doc1 stringForKey: @"one_dot_one"]);
    AssertEqualObjects([doc1 stringForKey: @"date"],
                       [CBLJSON JSONObjectWithDate: [doc1 dateForKey: @"date"]]);
    AssertNil([doc1 stringForKey: @"subdoc"]);
    AssertNil([doc1 stringForKey: @"array"]);
    AssertNil([doc1 stringForKey: @"blob"]);
    AssertNil([doc1 stringForKey: @"non_existing_key"]);
}


- (void) testSetNumber {
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc1 setObject: @(1) forKey: @"number1"];
    [doc1 setObject: @(0) forKey: @"number2"];
    [doc1 setObject: @(-1) forKey: @"number3"];
    [doc1 setObject: @(1.1) forKey: @"number4"];
    
    AssertEqualObjects([doc1 objectForKey: @"number1"], @(1));
    AssertEqualObjects([doc1 objectForKey: @"number2"], @(0));
    AssertEqualObjects([doc1 objectForKey: @"number3"], @(-1));
    AssertEqualObjects([doc1 objectForKey: @"number4"], @(1.1));
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    
    AssertEqualObjects([doc1 objectForKey: @"number1"], @(1));
    AssertEqualObjects([doc1 objectForKey: @"number2"], @(0));
    AssertEqualObjects([doc1 objectForKey: @"number3"], @(-1));
    AssertEqualObjects([doc1 objectForKey: @"number4"], @(1.1));
    
    // Update:
    
    [doc1 setObject: @(0) forKey: @"number1"];
    [doc1 setObject: @(1) forKey: @"number2"];
    [doc1 setObject: @(1.1) forKey: @"number3"];
    [doc1 setObject: @(-1) forKey: @"number4"];
    
    AssertEqualObjects([doc1 objectForKey: @"number1"], @(0));
    AssertEqualObjects([doc1 objectForKey: @"number2"], @(1));
    AssertEqualObjects([doc1 objectForKey: @"number3"], @(1.1));
    AssertEqualObjects([doc1 objectForKey: @"number4"], @(-1));
    
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    
    doc1 = [_db documentWithID: doc1.documentID];
    AssertEqualObjects([doc1 objectForKey: @"number1"], @(0));
    AssertEqualObjects([doc1 objectForKey: @"number2"], @(1));
    AssertEqualObjects([doc1 objectForKey: @"number3"], @(1.1));
    AssertEqualObjects([doc1 objectForKey: @"number4"], @(-1));
}


- (void) testGetNumber {
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    [self populateData: doc1];
    
    AssertNil([doc1 numberForKey: @"null"]);
    AssertEqualObjects([doc1 numberForKey: @"true"], @(1));
    AssertEqualObjects([doc1 numberForKey: @"false"], @(0));
    AssertNil([doc1 numberForKey: @"string"]);
    AssertEqualObjects([doc1 numberForKey: @"zero"], @(0));
    AssertEqualObjects([doc1 numberForKey: @"one"], @(1));
    AssertEqualObjects([doc1 numberForKey: @"minus_one"], @(-1));
    AssertEqualObjects([doc1 numberForKey: @"one_dot_one"], @(1.1));
    AssertNil([doc1 numberForKey: @"date"]);
    AssertNil([doc1 numberForKey: @"subdoc"]);
    AssertNil([doc1 numberForKey: @"array"]);
    AssertNil([doc1 numberForKey: @"blob"]);
    AssertNil([doc1 numberForKey: @"non_existing_key"]);
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    
    AssertNil([doc1 numberForKey: @"null"]);
    AssertEqualObjects([doc1 numberForKey: @"true"], @(1));
    AssertEqualObjects([doc1 numberForKey: @"false"], @(0));
    AssertNil([doc1 numberForKey: @"string"]);
    AssertEqualObjects([doc1 numberForKey: @"zero"], @(0));
    AssertEqualObjects([doc1 numberForKey: @"one"], @(1));
    AssertEqualObjects([doc1 numberForKey: @"minus_one"], @(-1));
    AssertEqualObjects([doc1 numberForKey: @"one_dot_one"], @(1.1));
    AssertNil([doc1 numberForKey: @"date"]);
    AssertNil([doc1 numberForKey: @"non_existing_key"]);
}


- (void) testGetInteger {
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    [self populateData: doc1];
    
    AssertEqual([doc1 integerForKey: @"null"], 0);
    AssertEqual([doc1 integerForKey: @"true"], 1);
    AssertEqual([doc1 integerForKey: @"false"], 0);
    AssertEqual([doc1 integerForKey: @"string"], 0);
    AssertEqual([doc1 integerForKey: @"zero"], 0);
    AssertEqual([doc1 integerForKey: @"one"], 1);
    AssertEqual([doc1 integerForKey: @"minus_one"], -1);
    AssertEqual([doc1 integerForKey: @"one_dot_one"], 1);
    AssertEqual([doc1 integerForKey: @"date"], 0);
    AssertEqual([doc1 integerForKey: @"subdoc"], 0);
    AssertEqual([doc1 integerForKey: @"array"], 0);
    AssertEqual([doc1 integerForKey: @"blob"], 0);
    AssertEqual([doc1 integerForKey: @"non_existing_key"], 0);
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    
    AssertEqual([doc1 integerForKey: @"null"], 0);
    AssertEqual([doc1 integerForKey: @"true"], 1);
    AssertEqual([doc1 integerForKey: @"false"], 0);
    AssertEqual([doc1 integerForKey: @"string"], 0);
    AssertEqual([doc1 integerForKey: @"zero"], 0);
    AssertEqual([doc1 integerForKey: @"one"], 1);
    AssertEqual([doc1 integerForKey: @"minus_one"], -1);
    AssertEqual([doc1 integerForKey: @"one_dot_one"], 1);
    AssertEqual([doc1 integerForKey: @"date"], 0);
    AssertEqual([doc1 integerForKey: @"subdoc"], 0);
    AssertEqual([doc1 integerForKey: @"array"], 0);
    AssertEqual([doc1 integerForKey: @"blob"], 0);
    AssertEqual([doc1 integerForKey: @"non_existing_key"], 0);
}


- (void) testGetFloat {
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    [self populateData: doc1];
    
    AssertEqual([doc1 floatForKey: @"null"], 0.0f);
    AssertEqual([doc1 floatForKey: @"true"], 1.0f);
    AssertEqual([doc1 floatForKey: @"false"], 0.0f);
    AssertEqual([doc1 floatForKey: @"string"], 0.0f);
    AssertEqual([doc1 floatForKey: @"zero"], 0.0f);
    AssertEqual([doc1 floatForKey: @"one"], 1.0f);
    AssertEqual([doc1 floatForKey: @"minus_one"], -1.0f);
    AssertEqual([doc1 floatForKey: @"one_dot_one"], 1.1f);
    AssertEqual([doc1 floatForKey: @"date"], 0.0f);
    AssertEqual([doc1 floatForKey: @"subdoc"], 0.0f);
    AssertEqual([doc1 floatForKey: @"array"], 0.0f);
    AssertEqual([doc1 floatForKey: @"blob"], 0.0f);
    AssertEqual([doc1 floatForKey: @"non_existing_key"], 0.0f);
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    
    AssertEqual([doc1 floatForKey: @"null"], 0.0f);
    AssertEqual([doc1 floatForKey: @"true"], 1.0f);
    AssertEqual([doc1 floatForKey: @"false"], 0.0f);
    AssertEqual([doc1 floatForKey: @"string"], 0.0f);
    AssertEqual([doc1 floatForKey: @"zero"], 0.0f);
    AssertEqual([doc1 floatForKey: @"one"], 1.0f);
    AssertEqual([doc1 floatForKey: @"minus_one"], -1.0f);
    AssertEqual([doc1 floatForKey: @"one_dot_one"], 1.1f);
    AssertEqual([doc1 floatForKey: @"date"], 0.0f);
    AssertEqual([doc1 floatForKey: @"subdoc"], 0.0f);
    AssertEqual([doc1 floatForKey: @"array"], 0.0f);
    AssertEqual([doc1 floatForKey: @"blob"], 0.0f);
    AssertEqual([doc1 floatForKey: @"non_existing_key"], 0.0f);
}


- (void) testGetDouble {
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    [self populateData: doc1];
    
    AssertEqual([doc1 doubleForKey: @"null"], 0.0);
    AssertEqual([doc1 doubleForKey: @"true"], 1.0);
    AssertEqual([doc1 doubleForKey: @"false"], 0.0);
    AssertEqual([doc1 doubleForKey: @"string"], 0.0);
    AssertEqual([doc1 doubleForKey: @"zero"], 0.0);
    AssertEqual([doc1 doubleForKey: @"one"], 1.0);
    AssertEqual([doc1 doubleForKey: @"minus_one"], -1.0);
    AssertEqual([doc1 doubleForKey: @"one_dot_one"], 1.1);
    AssertEqual([doc1 doubleForKey: @"date"], 0.0);
    AssertEqual([doc1 doubleForKey: @"subdoc"], 0.0);
    AssertEqual([doc1 doubleForKey: @"array"], 0.0);
    AssertEqual([doc1 doubleForKey: @"blob"], 0.0);
    AssertEqual([doc1 doubleForKey: @"non_existing_key"], 0.0);
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    
    AssertEqual([doc1 doubleForKey: @"null"], 0.0);
    AssertEqual([doc1 doubleForKey: @"true"], 1.0);
    AssertEqual([doc1 doubleForKey: @"false"], 0.0);
    AssertEqual([doc1 doubleForKey: @"string"], 0.0);
    AssertEqual([doc1 doubleForKey: @"zero"], 0.0);
    AssertEqual([doc1 doubleForKey: @"one"], 1.0);
    AssertEqual([doc1 doubleForKey: @"minus_one"], -1.0);
    AssertEqual([doc1 doubleForKey: @"one_dot_one"], 1.1);
    AssertEqual([doc1 doubleForKey: @"date"], 0.0);
    AssertEqual([doc1 doubleForKey: @"subdoc"], 0.0);
    AssertEqual([doc1 doubleForKey: @"array"], 0.0);
    AssertEqual([doc1 doubleForKey: @"blob"], 0.0);
    AssertEqual([doc1 doubleForKey: @"non_existing_key"], 0.0);
}


- (void) testSetGetMinMaxNumber {
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc1 setObject: @(NSIntegerMin) forKey: @"min_int"];
    [doc1 setObject: @(NSIntegerMax) forKey: @"max_int"];
    [doc1 setObject: @(FLT_MIN) forKey: @"min_float"];
    [doc1 setObject: @(FLT_MAX) forKey: @"max_float"];
    [doc1 setObject: @(DBL_MIN) forKey: @"min_double"];
    [doc1 setObject: @(DBL_MAX) forKey: @"max_double"];
    
    AssertEqualObjects([doc1 numberForKey: @"min_int"], @(NSIntegerMin));
    AssertEqualObjects([doc1 numberForKey: @"max_int"], @(NSIntegerMax));
    AssertEqualObjects([doc1 objectForKey: @"min_int"], @(NSIntegerMin));
    AssertEqualObjects([doc1 objectForKey: @"max_int"], @(NSIntegerMax));
    AssertEqual([doc1 integerForKey: @"min_int"], NSIntegerMin);
    AssertEqual([doc1 integerForKey: @"max_int"], NSIntegerMax);
    
    AssertEqualObjects([doc1 numberForKey: @"min_float"], @(FLT_MIN));
    AssertEqualObjects([doc1 numberForKey: @"max_float"], @(FLT_MAX));
    AssertEqualObjects([doc1 objectForKey: @"min_float"], @(FLT_MIN));
    AssertEqualObjects([doc1 objectForKey: @"max_float"], @(FLT_MAX));
    AssertEqual([doc1 floatForKey: @"min_float"], FLT_MIN);
    AssertEqual([doc1 floatForKey: @"max_float"], FLT_MAX);
    
    AssertEqualObjects([doc1 numberForKey: @"min_double"], @(DBL_MIN));
    AssertEqualObjects([doc1 numberForKey: @"max_double"], @(DBL_MAX));
    AssertEqualObjects([doc1 objectForKey: @"min_double"], @(DBL_MIN));
    AssertEqualObjects([doc1 objectForKey: @"max_double"], @(DBL_MAX));
    AssertEqual([doc1 doubleForKey: @"min_double"], DBL_MIN);
    AssertEqual([doc1 doubleForKey: @"max_double"], DBL_MAX);
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    
    AssertEqualObjects([doc1 numberForKey: @"min_int"], @(NSIntegerMin));
    AssertEqualObjects([doc1 numberForKey: @"max_int"], @(NSIntegerMax));
    AssertEqualObjects([doc1 objectForKey: @"min_int"], @(NSIntegerMin));
    AssertEqualObjects([doc1 objectForKey: @"max_int"], @(NSIntegerMax));
    AssertEqual([doc1 integerForKey: @"min_int"], NSIntegerMin);
    AssertEqual([doc1 integerForKey: @"max_int"], NSIntegerMax);
    
    AssertEqualObjects([doc1 numberForKey: @"min_float"], @(FLT_MIN));
    AssertEqualObjects([doc1 numberForKey: @"max_float"], @(FLT_MAX));
    AssertEqualObjects([doc1 objectForKey: @"min_float"], @(FLT_MIN));
    AssertEqualObjects([doc1 objectForKey: @"max_float"], @(FLT_MAX));
    AssertEqual([doc1 floatForKey: @"min_float"], FLT_MIN);
    AssertEqual([doc1 floatForKey: @"max_float"], FLT_MAX);
    
    AssertEqualObjects([doc1 numberForKey: @"min_double"], @(DBL_MIN));
    AssertEqualObjects([doc1 numberForKey: @"max_double"], @(DBL_MAX));
    AssertEqualObjects([doc1 objectForKey: @"min_double"], @(DBL_MIN));
    AssertEqualObjects([doc1 objectForKey: @"max_double"], @(DBL_MAX));
    AssertEqual([doc1 doubleForKey: @"min_double"], DBL_MIN);
    AssertEqual([doc1 doubleForKey: @"max_double"], DBL_MAX);
}


- (void) testSetBoolean {
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc1 setObject: @(YES) forKey: @"boolean1"];
    [doc1 setObject: @(NO) forKey: @"boolean2"];
    
    AssertEqualObjects([doc1 objectForKey: @"boolean1"], @(1));
    AssertEqualObjects([doc1 objectForKey: @"boolean2"], @(0));
    AssertEqual([doc1 booleanForKey: @"boolean1"], YES);
    AssertEqual([doc1 booleanForKey: @"boolean2"], NO);
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    
    AssertEqualObjects([doc1 objectForKey: @"boolean1"], @(1));
    AssertEqualObjects([doc1 objectForKey: @"boolean2"], @(0));
    AssertEqual([doc1 booleanForKey: @"boolean1"], YES);
    AssertEqual([doc1 booleanForKey: @"boolean2"], NO);
    
    // Update:
    
    [doc1 setObject: @(NO) forKey: @"boolean1"];
    [doc1 setObject: @(YES) forKey: @"boolean2"];
    
    AssertEqualObjects([doc1 objectForKey: @"boolean1"], @(0));
    AssertEqualObjects([doc1 objectForKey: @"boolean2"], @(1));
    AssertEqual([doc1 booleanForKey: @"boolean1"], NO);
    AssertEqual([doc1 booleanForKey: @"boolean2"], YES);
    
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    
    AssertEqualObjects([doc1 objectForKey: @"boolean1"], @(0));
    AssertEqualObjects([doc1 objectForKey: @"boolean2"], @(1));
    AssertEqual([doc1 booleanForKey: @"boolean1"], NO);
    AssertEqual([doc1 booleanForKey: @"boolean2"], YES);
}


- (void) testGetBoolean {
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    [self populateData: doc1];
    
    AssertEqual([doc1 booleanForKey: @"null"], NO);
    AssertEqual([doc1 booleanForKey: @"true"], YES);
    AssertEqual([doc1 booleanForKey: @"false"], NO);
    AssertEqual([doc1 booleanForKey: @"string"], YES);
    AssertEqual([doc1 booleanForKey: @"zero"], NO);
    AssertEqual([doc1 booleanForKey: @"one"], YES);
    AssertEqual([doc1 booleanForKey: @"minus_one"], YES);
    AssertEqual([doc1 booleanForKey: @"one_dot_one"], YES);
    AssertEqual([doc1 booleanForKey: @"date"], YES);
    AssertEqual([doc1 booleanForKey: @"subdoc"], YES);
    AssertEqual([doc1 booleanForKey: @"array"], YES);
    AssertEqual([doc1 booleanForKey: @"blob"], YES);
    AssertEqual([doc1 booleanForKey: @"non_existing_key"], NO);
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    
    AssertEqual([doc1 booleanForKey: @"null"], NO);
    AssertEqual([doc1 booleanForKey: @"true"], YES);
    AssertEqual([doc1 booleanForKey: @"false"], NO);
    AssertEqual([doc1 booleanForKey: @"string"], YES);
    AssertEqual([doc1 booleanForKey: @"zero"], NO);
    AssertEqual([doc1 booleanForKey: @"one"], YES);
    AssertEqual([doc1 booleanForKey: @"minus_one"], YES);
    AssertEqual([doc1 booleanForKey: @"one_dot_one"], YES);
    AssertEqual([doc1 booleanForKey: @"date"], YES);
    AssertEqual([doc1 booleanForKey: @"subdoc"], YES);
    AssertEqual([doc1 booleanForKey: @"array"], YES);
    AssertEqual([doc1 booleanForKey: @"blob"], YES);
    AssertEqual([doc1 booleanForKey: @"non_existing_key"], NO);
}


- (void) testSetDate {
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    NSDate* date = [NSDate date];
    NSString* dateStr = [CBLJSON JSONObjectWithDate: date];
    Assert(dateStr.length > 0);
    [doc1 setObject: date forKey: @"date"];
    
    AssertEqualObjects([doc1 objectForKey: @"date"], dateStr);
    AssertEqualObjects([doc1 stringForKey: @"date"], dateStr);
    AssertEqualObjects([CBLJSON JSONObjectWithDate: [doc1 dateForKey: @"date"]], dateStr);
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    
    AssertEqualObjects([doc1 objectForKey: @"date"], dateStr);
    AssertEqualObjects([doc1 stringForKey: @"date"], dateStr);
    AssertEqualObjects([CBLJSON JSONObjectWithDate: [doc1 dateForKey: @"date"]], dateStr);
    
    // Update:
    
    NSDate* nuDate = [NSDate dateWithTimeInterval: 60.0 sinceDate: date];
    NSString* nuDateStr = [CBLJSON JSONObjectWithDate: nuDate];
    [doc1 setObject: nuDate forKey: @"date"];
    
    AssertEqualObjects([doc1 objectForKey: @"date"], nuDateStr);
    AssertEqualObjects([doc1 stringForKey: @"date"], nuDateStr);
    AssertEqualObjects([CBLJSON JSONObjectWithDate: [doc1 dateForKey: @"date"]], nuDateStr);
    
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    
    AssertEqualObjects([doc1 objectForKey: @"date"], nuDateStr);
    AssertEqualObjects([doc1 stringForKey: @"date"], nuDateStr);
    AssertEqualObjects([CBLJSON JSONObjectWithDate: [doc1 dateForKey: @"date"]], nuDateStr);
}


- (void) testGetDate {
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    [self populateData: doc1];
    
    AssertNil([doc1 dateForKey: @"null"]);
    AssertNil([doc1 dateForKey: @"true"]);
    AssertNil([doc1 dateForKey: @"false"]);
    AssertNil([doc1 dateForKey: @"string"]);
    AssertNil([doc1 dateForKey: @"zero"]);
    AssertNil([doc1 dateForKey: @"one"]);
    AssertNil([doc1 dateForKey: @"minus_one"]);
    AssertNil([doc1 dateForKey: @"one_dot_one"]);
    AssertNotNil([doc1 dateForKey: @"date"]);
    AssertEqualObjects([CBLJSON JSONObjectWithDate: [doc1 dateForKey: @"date"]],
                       [doc1 stringForKey: @"date"]);
    AssertNil([doc1 dateForKey: @"subdoc"]);
    AssertNil([doc1 dateForKey: @"array"]);
    AssertNil([doc1 dateForKey: @"blob"]);
    AssertNil([doc1 dateForKey: @"non_existing_key"]);
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    
    AssertNil([doc1 dateForKey: @"null"]);
    AssertNil([doc1 dateForKey: @"true"]);
    AssertNil([doc1 dateForKey: @"false"]);
    AssertNil([doc1 dateForKey: @"string"]);
    AssertNil([doc1 dateForKey: @"zero"]);
    AssertNil([doc1 dateForKey: @"one"]);
    AssertNil([doc1 dateForKey: @"minus_one"]);
    AssertNil([doc1 dateForKey: @"one_dot_one"]);
    AssertNotNil([doc1 dateForKey: @"date"]);
    AssertEqualObjects([CBLJSON JSONObjectWithDate: [doc1 dateForKey: @"date"]],
                       [doc1 stringForKey: @"date"]);
    AssertNil([doc1 dateForKey: @"subdoc"]);
    AssertNil([doc1 dateForKey: @"array"]);
    AssertNil([doc1 dateForKey: @"blob"]);
    AssertNil([doc1 dateForKey: @"non_existing_key"]);
}


- (void) testSetBlob {
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    NSData* content = [@"12345" dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType: @"text/plain" data: content];
    [doc1 setObject: blob forKey: @"blob"];
    
    AssertEqual([doc1 objectForKey: @"blob"], blob);
    AssertEqualObjects(((CBLBlob*)[doc1 objectForKey: @"blob"]).properties, blob.properties);
    AssertEqualObjects([doc1 blobForKey: @"blob"].properties, blob.properties);
    AssertEqualObjects([doc1 blobForKey: @"blob"].content, content);
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    
    Assert([[doc1 objectForKey: @"blob"] isKindOfClass: [CBLBlob class]]);
    AssertEqualObjects(((CBLBlob*)[doc1 objectForKey: @"blob"]).properties, blob.properties);
    AssertEqualObjects([doc1 blobForKey: @"blob"].properties, blob.properties);
    AssertEqualObjects([doc1 blobForKey: @"blob"].content, content);
    
    // Update:
    
    NSData* nuContent = [@"1234567890" dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlob* nuBlob = [[CBLBlob alloc] initWithContentType: @"text/plain" data: nuContent];
    [doc1 setObject: nuBlob forKey: @"blob"];
    
    AssertEqual([doc1 objectForKey: @"blob"], nuBlob);
    AssertEqualObjects(((CBLBlob*)[doc1 objectForKey: @"blob"]).properties, nuBlob.properties);
    AssertEqualObjects([doc1 blobForKey: @"blob"].properties, nuBlob.properties);
    AssertEqualObjects([doc1 blobForKey: @"blob"].content, nuContent);
    
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    
    Assert([[doc1 objectForKey: @"blob"] isKindOfClass: [CBLBlob class]]);
    AssertEqualObjects(((CBLBlob*)[doc1 objectForKey: @"blob"]).properties, nuBlob.properties);
    AssertEqualObjects([doc1 blobForKey: @"blob"].properties, nuBlob.properties);
    AssertEqualObjects([doc1 blobForKey: @"blob"].content, nuContent);
}


- (void) testGetBlob {
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    [self populateData: doc1];
    
    AssertNil([doc1 blobForKey: @"null"]);
    AssertNil([doc1 blobForKey: @"true"]);
    AssertNil([doc1 blobForKey: @"false"]);
    AssertNil([doc1 blobForKey: @"string"]);
    AssertNil([doc1 blobForKey: @"zero"]);
    AssertNil([doc1 blobForKey: @"one"]);
    AssertNil([doc1 blobForKey: @"minus_one"]);
    AssertNil([doc1 blobForKey: @"one_dot_one"]);
    AssertNil([doc1 blobForKey: @"date"]);
    AssertNil([doc1 dateForKey: @"subdoc"]);
    AssertNil([doc1 dateForKey: @"array"]);
    AssertEqualObjects([doc1 blobForKey: @"blob"].content,
                       [@"12345" dataUsingEncoding: NSUTF8StringEncoding]);
    AssertNil([doc1 dateForKey: @"non_existing_key"]);
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    
    AssertNil([doc1 blobForKey: @"null"]);
    AssertNil([doc1 blobForKey: @"true"]);
    AssertNil([doc1 blobForKey: @"false"]);
    AssertNil([doc1 blobForKey: @"string"]);
    AssertNil([doc1 blobForKey: @"zero"]);
    AssertNil([doc1 blobForKey: @"one"]);
    AssertNil([doc1 blobForKey: @"minus_one"]);
    AssertNil([doc1 blobForKey: @"one_dot_one"]);
    AssertNil([doc1 dateForKey: @"subdoc"]);
    AssertNil([doc1 dateForKey: @"array"]);
    AssertNil([doc1 blobForKey: @"date"]);
    AssertEqualObjects([doc1 blobForKey: @"blob"].content,
                       [@"12345" dataUsingEncoding: NSUTF8StringEncoding]);
    AssertNil([doc1 dateForKey: @"non_existing_key"]);
}


- (void) testSetSubdocument {
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    CBLSubdocument* subdoc = [[CBLSubdocument alloc] init];
    [subdoc setObject: @"1 Main street" forKey: @"street"];
    [doc1 setObject: subdoc forKey: @"subdoc"];
    
    AssertEqual([doc1 objectForKey: @"subdoc"], subdoc);
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    
    Assert([doc1 objectForKey: @"subdoc"] != subdoc);
    AssertEqual([doc1 objectForKey: @"subdoc"], [doc1 subdocumentForKey: @"subdoc"]);
    AssertEqualObjects([[doc1 subdocumentForKey: @"subdoc"] toDictionary], [subdoc toDictionary]);
    
    // Update:
    
    subdoc = [doc1 subdocumentForKey: @"subdoc"];
    [subdoc setObject: @"Mountain View" forKey: @"city"];
    
    AssertEqual([doc1 objectForKey: @"subdoc"], subdoc);
    AssertEqual([doc1 objectForKey: @"subdoc"], [doc1 subdocumentForKey: @"subdoc"]);
    NSDictionary* dict = @{@"street": @"1 Main street", @"city": @"Mountain View"};
    AssertEqualObjects([[doc1 subdocumentForKey: @"subdoc"] toDictionary], dict);
    
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    
    Assert([doc1 objectForKey: @"subdoc"] != subdoc);
    AssertEqual([doc1 objectForKey: @"subdoc"], [doc1 subdocumentForKey: @"subdoc"]);
    AssertEqualObjects([[doc1 subdocumentForKey: @"subdoc"] toDictionary], dict);
}


- (void) testGetSubdocument {
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    [self populateData: doc1];
    
    AssertNil([doc1 subdocumentForKey: @"null"]);
    AssertNil([doc1 subdocumentForKey: @"true"]);
    AssertNil([doc1 subdocumentForKey: @"false"]);
    AssertNil([doc1 subdocumentForKey: @"string"]);
    AssertNil([doc1 subdocumentForKey: @"zero"]);
    AssertNil([doc1 subdocumentForKey: @"one"]);
    AssertNil([doc1 subdocumentForKey: @"minus_one"]);
    AssertNil([doc1 subdocumentForKey: @"one_dot_one"]);
    AssertNil([doc1 subdocumentForKey: @"date"]);
    AssertNotNil([doc1 subdocumentForKey: @"subdoc"]);
    NSDictionary* dict = @{@"street": @"1 Main street", @"city": @"Mountain View", @"state": @"CA"};
    AssertEqualObjects([[doc1 subdocumentForKey: @"subdoc"] toDictionary], dict);
    AssertNil([doc1 subdocumentForKey: @"array"]);
    AssertNil([doc1 subdocumentForKey: @"blob"]);
    AssertNil([doc1 subdocumentForKey: @"non_existing_key"]);
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    
    AssertNil([doc1 subdocumentForKey: @"null"]);
    AssertNil([doc1 subdocumentForKey: @"true"]);
    AssertNil([doc1 subdocumentForKey: @"false"]);
    AssertNil([doc1 subdocumentForKey: @"string"]);
    AssertNil([doc1 subdocumentForKey: @"zero"]);
    AssertNil([doc1 subdocumentForKey: @"one"]);
    AssertNil([doc1 subdocumentForKey: @"minus_one"]);
    AssertNil([doc1 subdocumentForKey: @"one_dot_one"]);
    AssertNil([doc1 subdocumentForKey: @"date"]);
    AssertNotNil([doc1 subdocumentForKey: @"subdoc"]);
    AssertEqualObjects([[doc1 subdocumentForKey: @"subdoc"] toDictionary], dict);
    AssertNil([doc1 subdocumentForKey: @"array"]);
    AssertNil([doc1 subdocumentForKey: @"blob"]);
    AssertNil([doc1 subdocumentForKey: @"non_existing_key"]);
}


- (void) testSetArrayObject {
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    CBLArray* array = [[CBLArray alloc] init];
    [array addObject: @"item1"];
    [array addObject: @"item2"];
    [array addObject: @"item3"];
    [doc1 setObject: array forKey: @"array"];
    
    AssertEqual([doc1 objectForKey: @"array"], array);
    AssertEqual([doc1 arrayForKey: @"array"], array);
    AssertEqualObjects([[doc1 arrayForKey: @"array"] toArray], (@[@"item1", @"item2", @"item3"]));
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    
    Assert([doc1 objectForKey: @"array"] != array);
    AssertEqual([doc1 objectForKey: @"array"], [doc1 arrayForKey: @"array"]);
    AssertEqualObjects([[doc1 arrayForKey: @"array"] toArray], (@[@"item1", @"item2", @"item3"]));
    
    // Update:
    array = [doc1 arrayForKey: @"array"];
    [array addObject: @"item4"];
    [array addObject: @"item5"];
    
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    
    Assert([doc1 objectForKey: @"array"] != array);
    AssertEqual([doc1 objectForKey: @"array"], [doc1 arrayForKey: @"array"]);
    AssertEqualObjects([[doc1 arrayForKey: @"array"] toArray],
                       (@[@"item1", @"item2", @"item3", @"item4", @"item5"]));
}


- (void) testGetArray {
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    [self populateData: doc1];
    
    AssertNil([doc1 arrayForKey: @"null"]);
    AssertNil([doc1 arrayForKey: @"true"]);
    AssertNil([doc1 arrayForKey: @"false"]);
    AssertNil([doc1 arrayForKey: @"string"]);
    AssertNil([doc1 arrayForKey: @"zero"]);
    AssertNil([doc1 arrayForKey: @"one"]);
    AssertNil([doc1 arrayForKey: @"minus_one"]);
    AssertNil([doc1 arrayForKey: @"one_dot_one"]);
    AssertNil([doc1 arrayForKey: @"date"]);
    AssertNil([doc1 arrayForKey: @"subdoc"]);
    AssertNotNil([doc1 arrayForKey: @"array"]);
    AssertEqualObjects([[doc1 arrayForKey: @"array"] toArray],
                       (@[@"650-123-0001", @"650-123-0002"]));
    AssertNil([doc1 arrayForKey: @"blob"]);
    AssertNil([doc1 arrayForKey: @"non_existing_key"]);
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    
    AssertNil([doc1 arrayForKey: @"null"]);
    AssertNil([doc1 arrayForKey: @"true"]);
    AssertNil([doc1 arrayForKey: @"false"]);
    AssertNil([doc1 arrayForKey: @"string"]);
    AssertNil([doc1 arrayForKey: @"zero"]);
    AssertNil([doc1 arrayForKey: @"one"]);
    AssertNil([doc1 arrayForKey: @"minus_one"]);
    AssertNil([doc1 arrayForKey: @"one_dot_one"]);
    AssertNil([doc1 arrayForKey: @"date"]);
    AssertNil([doc1 arrayForKey: @"subdoc"]);
    AssertNotNil([doc1 arrayForKey: @"array"]);
    AssertEqualObjects([[doc1 arrayForKey: @"array"] toArray],
                       (@[@"650-123-0001", @"650-123-0002"]));
    AssertNil([doc1 arrayForKey: @"blob"]);
    AssertNil([doc1 arrayForKey: @"non_existing_key"]);
}


- (void) testSetNSNull {
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc1 setObject: [NSNull null] forKey: @"null"];
    
    AssertEqual([doc1 objectForKey: @"null"], [NSNull null]);
    AssertEqual(doc1.count, 1u);
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    
    AssertEqual([doc1 objectForKey: @"null"], [NSNull null]);
    AssertEqual(doc1.count, 1u);
}


- (void) testSetNSDictionary {
    NSDictionary* dict = @{@"street": @"1 Main street",
                           @"city": @"Mountain View",
                           @"state": @"CA"};
    
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc1 setObject: dict forKey: @"address"];
    
    CBLSubdocument* address = [doc1 subdocumentForKey: @"address"];
    AssertNotNil(address);
    AssertEqual(address, [doc1 objectForKey: @"address"]);
    AssertEqualObjects([address stringForKey: @"street"], @"1 Main street");
    AssertEqualObjects([address stringForKey: @"city"], @"Mountain View");
    AssertEqualObjects([address stringForKey: @"state"], @"CA");
    AssertEqualObjects([address toDictionary], dict);
    
    // Update with a new dictionary:
    NSDictionary* nuDict = @{@"street": @"1 Second street",
                             @"city": @"Palo Alto",
                             @"state": @"CA"};
    [doc1 setObject: nuDict forKey: @"address"];
    
    // Check whether the old address subdocument is still accessible:
    Assert(address != [doc1 subdocumentForKey: @"address"]);
    AssertEqualObjects([address stringForKey: @"street"], @"1 Main street");
    AssertEqualObjects([address stringForKey: @"city"], @"Mountain View");
    AssertEqualObjects([address stringForKey: @"state"], @"CA");
    AssertEqualObjects([address toDictionary], dict);
    
    // The old address subdocument should be detached:
    CBLSubdocument* nuAddress = [doc1 subdocumentForKey: @"address"];
    Assert(address != nuAddress);
    
    // Update nuAddress:
    [nuAddress setObject: @"94302" forKey: @"zip"];
    AssertEqualObjects([nuAddress stringForKey: @"zip"], @"94302");
    AssertNil([address stringForKey: @"zip"]);
    
    // Save:
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    
    AssertEqualObjects([doc1 toDictionary], (@{@"address": @{@"street": @"1 Second street",
                                                             @"city": @"Palo Alto",
                                                             @"state": @"CA",
                                                             @"zip": @"94302"}}));
}


- (void) testSetNSArray {
    NSArray* array = @[@"a", @"b", @"c"];
    
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc1 setObject: array forKey: @"members"];
    
    CBLArray* members = [doc1 arrayForKey: @"members"];
    AssertNotNil(members);
    AssertEqual(members, [doc1 objectForKey: @"members"]);
    
    AssertEqual(members.count, 3u);
    AssertEqualObjects([members objectAtIndex: 0], @"a");
    AssertEqualObjects([members objectAtIndex: 1], @"b");
    AssertEqualObjects([members objectAtIndex: 2], @"c");
    AssertEqualObjects([members toArray], (@[@"a", @"b", @"c"]));
    
    // Update with a new array:
    NSArray* nuArray = @[@"d", @"e", @"f"];
    [doc1 setObject: nuArray forKey: @"members"];
    
    // Check whether the old members array is still accessible:
    AssertEqual(members.count, 3u);
    AssertEqualObjects([members objectAtIndex: 0], @"a");
    AssertEqualObjects([members objectAtIndex: 1], @"b");
    AssertEqualObjects([members objectAtIndex: 2], @"c");
    AssertEqualObjects([members toArray], (@[@"a", @"b", @"c"]));
    
    // The old address subdocument should be detached:
    CBLArray* nuMembers = [doc1 arrayForKey: @"members"];
    Assert(members != nuMembers);
    
    // Update nuAddress:
    [nuMembers addObject: @"g"];
    AssertEqual(nuMembers.count, 4u);
    AssertEqualObjects([nuMembers objectAtIndex: 3], @"g");
    AssertEqual(members.count, 3u);
    
    // Save:
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: doc1.documentID];
    
    AssertEqualObjects([doc1 toDictionary], (@{@"members": @[@"d", @"e", @"f", @"g"]}));
}


- (void) testUpdateNestedSubdocument {
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    CBLSubdocument* addresses = [[CBLSubdocument alloc] init];
    [doc1 setObject: addresses forKey: @"addresses"];
    
    CBLSubdocument* shipping = [[CBLSubdocument alloc] init];
    [shipping setObject: @"1 Main street" forKey: @"street"];
    [shipping setObject: @"Mountain View" forKey: @"city"];
    [shipping setObject: @"CA" forKey: @"state"];
    [addresses setObject: shipping forKey: @"shipping"];
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: @"doc1"];
    
    shipping = [[doc1 subdocumentForKey: @"addresses"] subdocumentForKey: @"shipping"];
    [shipping setObject: @"94042" forKey: @"zip"];
    
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: @"doc1"];
    
    NSDictionary* result = @{@"addresses":
                                 @{@"shipping":
                                       @{@"street": @"1 Main street",
                                         @"city": @"Mountain View",
                                         @"state": @"CA",
                                         @"zip": @"94042"}}};
    AssertEqualObjects([doc1 toDictionary], result);
}


- (void) testUpdateSubdocumentInArray {
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    CBLArray* addresses = [[CBLArray alloc] init];
    [doc1 setObject: addresses forKey: @"addresses"];
    
    CBLSubdocument* address1 = [[CBLSubdocument alloc] init];
    [address1 setObject: @"1 Main street" forKey: @"street"];
    [address1 setObject: @"Mountain View" forKey: @"city"];
    [address1 setObject: @"CA" forKey: @"state"];
    [addresses addObject: address1];
    
    CBLSubdocument* address2 = [[CBLSubdocument alloc] init];
    [address2 setObject: @"1 Second street" forKey: @"street"];
    [address2 setObject: @"Palo Alto" forKey: @"city"];
    [address2 setObject: @"CA" forKey: @"state"];
    [addresses addObject: address2];
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: @"doc1"];
    
    address1 = [[doc1 arrayForKey: @"addresses"] subdocumentAtIndex: 0];
    [address1 setObject: @"2 Main street" forKey: @"street"];
    [address1 setObject: @"94042" forKey: @"zip"];
    
    address2 = [[doc1 arrayForKey: @"addresses"] subdocumentAtIndex: 1];
    [address2 setObject: @"2 Second street" forKey: @"street"];
    [address2 setObject: @"94302" forKey: @"zip"];
    
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: @"doc1"];
    
    NSDictionary* result = @{@"addresses": @[
                                     @{@"street": @"2 Main street",
                                       @"city": @"Mountain View",
                                       @"state": @"CA",
                                       @"zip": @"94042"},
                                     @{@"street": @"2 Second street",
                                       @"city": @"Palo Alto",
                                       @"state": @"CA",
                                       @"zip": @"94302"}
                                     ]};
    AssertEqualObjects([doc1 toDictionary], result);
}


- (void) testUpdateNestedArray {
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    CBLArray* groups = [[CBLArray alloc] init];
    [doc1 setObject: groups forKey: @"groups"];
    
    CBLArray* group1 = [[CBLArray alloc] init];
    [group1 addObject: @"a"];
    [group1 addObject: @"b"];
    [group1 addObject: @"c"];
    [groups addObject: group1];
    
    CBLArray* group2 = [[CBLArray alloc] init];
    [group2 addObject: @(1)];
    [group2 addObject: @(2)];
    [group2 addObject: @(3)];
    [groups addObject: group2];
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: @"doc1"];
    
    group1 = [[doc1 arrayForKey: @"groups"] arrayAtIndex: 0];
    [group1 setObject: @"d" atIndex: 0];
    [group1 setObject: @"e" atIndex: 1];
    [group1 setObject: @"f" atIndex: 2];
    
    group2 = [[doc1 arrayForKey: @"groups"] arrayAtIndex: 1];
    [group2 setObject: @(4) atIndex: 0];
    [group2 setObject: @(5) atIndex: 1];
    [group2 setObject: @(6) atIndex: 2];
    
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: @"doc1"];
    
    NSDictionary* result = @{@"groups": @[@[@"d", @"e", @"f"], @[@(4), @(5), @(6)]]};
    AssertEqualObjects([doc1 toDictionary], result);
}


- (void) testUpdateArrayInSubdocument {
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    
    CBLSubdocument* group1 = [[CBLSubdocument alloc] init];
    CBLArray* member1 = [[CBLArray alloc] init];
    [member1 addObject: @"a"];
    [member1 addObject: @"b"];
    [member1 addObject: @"c"];
    [group1 setObject: member1 forKey: @"member"];
    [doc1 setObject: group1 forKey: @"group1"];
    
    CBLSubdocument* group2 = [[CBLSubdocument alloc] init];
    CBLArray* member2 = [[CBLArray alloc] init];
    [member2 addObject: @(1)];
    [member2 addObject: @(2)];
    [member2 addObject: @(3)];
    [group2 setObject: member2 forKey: @"member"];
    [doc1 setObject: group2 forKey: @"group2"];
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: @"doc1"];
    
    member1 = [[doc1 subdocumentForKey: @"group1"] arrayForKey: @"member"];
    [member1 setObject: @"d" atIndex: 0];
    [member1 setObject: @"e" atIndex: 1];
    [member1 setObject: @"f" atIndex: 2];
    
    member2 = [[doc1 subdocumentForKey: @"group2"] arrayForKey: @"member"];
    [member2 setObject: @(4) atIndex: 0];
    [member2 setObject: @(5) atIndex: 1];
    [member2 setObject: @(6) atIndex: 2];
    
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: @"doc1"];
    
    NSDictionary* result = @{@"group1": @{@"member": @[@"d", @"e", @"f"]},
                             @"group2": @{@"member": @[@(4), @(5), @(6)]}};
    AssertEqualObjects([doc1 toDictionary], result);
}


- (void) testSetSubdocToMultipleKeys {
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    
    CBLSubdocument* address = [[CBLSubdocument alloc] init];
    [address setObject: @"1 Main street" forKey: @"street"];
    [address setObject: @"Mountain View" forKey: @"city"];
    [address setObject: @"CA" forKey: @"state"];
    [doc1 setObject: address forKey: @"shipping"];
    [doc1 setObject: address forKey: @"billing"];
    
    AssertEqual([doc1 objectForKey: @"shipping"], address);
    AssertEqual([doc1 objectForKey: @"billing"], address);
    
    // Update address: both shipping and billing should get the update.
    [address setObject: @"94042" forKey: @"zip"];
    AssertEqualObjects([[doc1 subdocumentForKey: @"shipping"] stringForKey: @"zip"], @"94042");
    AssertEqualObjects([[doc1 subdocumentForKey: @"billing"] stringForKey: @"zip"], @"94042");
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: @"doc1"];
    
    CBLSubdocument* shipping = [doc1 subdocumentForKey: @"shipping"];
    CBLSubdocument* billing = [doc1 subdocumentForKey: @"billing"];
    
    // After save: both shipping and billing address are now independent to each other
    Assert(shipping != address);
    Assert(billing != address);
    Assert(shipping != address);
    
    [shipping setObject: @"2 Main street" forKey: @"street"];
    [billing setObject: @"3 Main street" forKey: @"street"];
    
    // Save update:
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: @"doc1"];
    
    AssertEqualObjects([[doc1 subdocumentForKey: @"shipping"] stringForKey: @"street"], @"2 Main street");
    AssertEqualObjects([[doc1 subdocumentForKey: @"billing"] stringForKey: @"street"], @"3 Main street");
}


- (void) testSetArrayObjectToMultipleKeys {
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    
    CBLArray* phones = [[CBLArray alloc] init];
    [phones addObject: @"650-000-0001"];
    [phones addObject: @"650-000-0002"];
    
    [doc1 setObject: phones forKey: @"mobile"];
    [doc1 setObject: phones forKey: @"home"];
    
    AssertEqual([doc1 objectForKey:@"mobile"], phones);
    AssertEqual([doc1 objectForKey:@"home"], phones);
    
    // Update phones: both mobile and home should get the update
    [phones addObject: @"650-000-0003"];
    AssertEqualObjects([[doc1 arrayForKey: @"mobile"] toArray],
                       (@[@"650-000-0001", @"650-000-0002", @"650-000-0003"]));
    AssertEqualObjects([[doc1 arrayForKey: @"home"] toArray],
                       (@[@"650-000-0001", @"650-000-0002", @"650-000-0003"]));
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: @"doc1"];
    
    // After save: both mobile and home are not independent to each other
    CBLArray* mobile = [doc1 arrayForKey: @"mobile"];
    CBLArray* home = [doc1 arrayForKey: @"home"];
    Assert(mobile != phones);
    Assert(home != phones);
    Assert(mobile != home);
    
    // Update mobile and home:
    [mobile addObject: @"650-000-1234"];
    [home addObject: @"650-000-5678"];
    
    // Save update:
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: @"doc1"];
    
    AssertEqualObjects([[doc1 arrayForKey: @"mobile"] toArray],
                       (@[@"650-000-0001", @"650-000-0002", @"650-000-0003", @"650-000-1234"]));
    AssertEqualObjects([[doc1 arrayForKey: @"home"] toArray],
                       (@[@"650-000-0001", @"650-000-0002", @"650-000-0003", @"650-000-5678"]));
}


- (void) failingTestToDictionary {
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    [self populateData: doc1];
    // TODO: Should blob be serialized into JSON dictionary?
}


- (void) testCount {
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    [self populateData: doc1];
    
    AssertEqual(doc1.count, 12u);
    AssertEqual(doc1.count, [doc1 toDictionary].count);
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Error saving: %@", error);
    doc1 = [_db documentWithID: @"doc1"];
    
    AssertEqual(doc1.count, 12u);
    AssertEqual([doc1 toDictionary].count, doc1.count);
}


- (void) testRemoveKeys {
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc setDictionary: @{ @"type": @"profile",
                           @"name": @"Jason",
                           @"weight": @130.5,
                           @"active": @YES,
                           @"age": @30,
                           @"address": @{
                                   @"street": @"1 milky way.",
                                   @"city": @"galaxy city",
                                   @"zip" : @12345
                                   }
                           }];
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Error saving: %@", error);
    
    [doc setObject: nil forKey: @"name"];
    [doc setObject: nil forKey: @"weight"];
    [doc setObject: nil forKey: @"age"];
    [doc setObject: nil forKey: @"active"];;
    [[doc subdocumentForKey: @"address"] setObject: nil forKey: @"city"];
    
    AssertNil([doc stringForKey: @"name"]);
    AssertEqual([doc floatForKey: @"weight"], 0.0);
    AssertEqual([doc doubleForKey: @"weight"], 0.0);
    AssertEqual([doc integerForKey: @"age"], 0);
    AssertEqual([doc booleanForKey: @"active"], NO);
    
    AssertNil([doc objectForKey: @"name"]);
    AssertNil([doc objectForKey: @"weight"]);
    AssertNil([doc objectForKey: @"age"]);
    AssertNil([doc objectForKey: @"active"]);
    AssertNil([[doc subdocumentForKey: @"address"] objectForKey: @"city"]);
    
    CBLSubdocument* address = [doc subdocumentForKey: @"address"];
    AssertEqualObjects([doc toDictionary], (@{ @"type": @"profile",
                                               @"address": @{
                                                       @"street": @"1 milky way.",
                                                       @"zip" : @12345
                                                       }
                                               }));
    AssertEqualObjects([address toDictionary], (@{ @"street": @"1 milky way.", @"zip" : @12345 }));
    
    // Remove the rest:
    [doc setObject: nil forKey: @"type"];
    [doc setObject: nil forKey: @"address"];
    AssertNil([doc objectForKey: @"type"]);
    AssertNil([doc objectForKey: @"address"]);
    AssertEqualObjects([doc toDictionary], @{});
}


- (void) testContainsKey {
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc setDictionary: @{ @"type": @"profile",
                           @"name": @"Jason",
                           @"age": @"30",
                           @"address": @{
                                   @"street": @"1 milky way.",
                                   }
                           }];
    
    Assert([doc containsObjectForKey: @"type"]);
    Assert([doc containsObjectForKey: @"name"]);
    Assert([doc containsObjectForKey: @"address"]);
    AssertFalse([doc containsObjectForKey: @"weight"]);
}


- (void) failingTestDeleteNewDocument {
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc setObject: @"Scott Tiger" forKey: @"name"];
    AssertFalse(doc.isDeleted);
    
    NSError* error;
    AssertFalse([_db deleteDocument: doc error: &error]);
    AssertEqual(error.code, kCBLErrorStatusNotFound);
    AssertFalse(doc.isDeleted);
    AssertEqualObjects([doc objectForKey: @"name"], @"Scott Tiger");
    
}


- (void) testDeleteDocument {
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc setObject: @"Scott Tiger" forKey: @"name"];
    AssertFalse(doc.isDeleted);
    
    // Save:
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Error saving: %@", error);
    
    // Delete:
    Assert([_db deleteDocument: doc error: &error]);
    AssertNil(error);
    AssertNil([doc objectForKey: @"name"]);
    AssertEqualObjects([doc toDictionary], @{});
    Assert(doc.isDeleted);
}


- (void) testSubdocumentAfterDeleteDocument {
    NSDictionary* dict = @{@"address": @{
                                   @"street": @"1 Main street",
                                   @"city": @"Mountain View",
                                   @"state": @"CA"}
                           };
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1" dictionary: dict];
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Error saving: %@", error);
    
    CBLSubdocument* address = [doc subdocumentForKey: @"address"];
    AssertEqualObjects([address objectForKey: @"street"], @"1 Main street");
    AssertEqualObjects([address objectForKey: @"city"], @"Mountain View");
    AssertEqualObjects([address objectForKey: @"state"], @"CA");
    
    Assert([_db deleteDocument: doc error: &error]);
    AssertNil(error);
    AssertNil([doc subdocumentForKey: @"address"]);
    AssertEqualObjects([doc toDictionary], @{});
    
    // The subdocument still has data but is detached:
    AssertEqualObjects([address objectForKey: @"street"], @"1 Main street");
    AssertEqualObjects([address objectForKey: @"city"], @"Mountain View");
    AssertEqualObjects([address objectForKey: @"state"], @"CA");
    
    // Make changes to the subdocument shouldn't affect the document.
    [address setObject: @"94042" forKey: @"zip"];
    AssertNil([doc subdocumentForKey: @"address"]);
    AssertEqualObjects([doc toDictionary], @{});
}


- (void) testArrayAfterDeleteDocument {
    NSDictionary* dict = @{@"members": @[@"a", @"b", @"c"]};
    
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1" dictionary: dict];
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Error saving: %@", error);
    
    CBLArray* members = [doc arrayForKey: @"members"];
    AssertEqual(members.count, 3u);
    AssertEqualObjects([members objectAtIndex: 0], @"a");
    AssertEqualObjects([members objectAtIndex: 1], @"b");
    AssertEqualObjects([members objectAtIndex: 2], @"c");
    
    Assert([_db deleteDocument: doc error: &error]);
    AssertNil(error);
    AssertNil([doc subdocumentForKey: @"members"]);
    AssertEqualObjects([doc toDictionary], @{});
    
    // The array still has data but is detached:
    AssertEqual(members.count, 3u);
    AssertEqualObjects([members objectAtIndex: 0], @"a");
    AssertEqualObjects([members objectAtIndex: 1], @"b");
    AssertEqualObjects([members objectAtIndex: 2], @"c");
    
    // Make changes to the array shouldn't affect the document.
    [members setObject: @"1" atIndex:2];
    [members addObject: @"2"];
    
    AssertNil([doc arrayForKey: @"members"]);
    AssertEqualObjects([doc toDictionary], @{});
}


- (void) testPurgeDocument {
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc setObject: @"profile" forKey: @"type"];
    [doc setObject: @"Scott" forKey: @"name"];
    AssertFalse(doc.isDeleted);
 
    // Purge before save:
    NSError* error;
    AssertFalse([_db purgeDocument: doc error: &error]);
    AssertEqualObjects([doc objectForKey: @"type"], @"profile");
    AssertEqualObjects([doc objectForKey: @"name"], @"Scott");
    
    // Save:
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    AssertFalse(doc.isDeleted);
    
    // Purge:
    Assert([_db purgeDocument: doc error: &error], @"Purging error: %@", error);
    AssertFalse(doc.isDeleted);
}


- (void) testReopenDB {
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc setObject: @"str" forKey: @"string"];
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Error saving: %@", error);

    [self reopenDB];

    doc = [self.db documentWithID: @"doc1"];
    AssertEqualObjects([doc stringForKey: @"string"], @"str");
    AssertEqualObjects([doc toDictionary], @{@"string": @"str"});
}


- (void)testBlob {
    NSData* content = [@"12345" dataUsingEncoding:NSUTF8StringEncoding];
    NSError* error;
    CBLBlob *data = [[CBLBlob alloc] initWithContentType:@"text/plain" data:content];
    Assert(data, @"Failed to create blob: %@", error);
    
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc setObject: data forKey: @"data"];
    [doc setObject: @"Jim" forKey: @"name"];
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    
    CBLDocument* doc1 = [[self.db copy] documentWithID: @"doc1"];
    AssertEqualObjects([doc objectForKey: @"name"], @"Jim");
    Assert([[doc1 objectForKey: @"data"] isKindOfClass:[CBLBlob class]]);
    data = [doc1 objectForKey: @"data"];
    AssertEqual(data.length, 5ull);
    AssertEqualObjects(data.content, content);
    NSInputStream *contentStream = data.contentStream;
    [contentStream open];
    uint8_t buffer[10];
    NSInteger bytesRead = [contentStream read:buffer maxLength:10];
    [contentStream close];
    AssertEqual(bytesRead, 5);
}


- (void)testEmptyBlob {
    NSData* content = [@"" dataUsingEncoding:NSUTF8StringEncoding];
    NSError* error;
    CBLBlob *data = [[CBLBlob alloc] initWithContentType:@"text/plain" data:content];
    Assert(data, @"Failed to create blob: %@", error);
    
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc setObject: data forKey: @"data"];
    
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    CBLDocument* doc1 = [[self.db copy] documentWithID: @"doc1"];
    Assert([[doc1 objectForKey: @"data"] isKindOfClass:[CBLBlob class]]);
    data = [doc1 objectForKey: @"data"];
    AssertEqual(data.length, 0ull);
    AssertEqualObjects(data.content, content);
    NSInputStream *contentStream = data.contentStream;
    [contentStream open];
    uint8_t buffer[10];
    NSInteger bytesRead = [contentStream read:buffer maxLength:10];
    [contentStream close];
    AssertEqual(bytesRead, 0);
}


- (void)testBlobWithStream {
    NSData* content = [@"" dataUsingEncoding:NSUTF8StringEncoding];
    NSInputStream *contentStream = [[NSInputStream alloc] initWithData:content];
    NSError* error;
    CBLBlob *data = [[CBLBlob alloc] initWithContentType:@"text/plain" contentStream:contentStream];
    Assert(data, @"Failed to create blob: %@", error);
    
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc setObject: data forKey: @"data"];
    
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    CBLDocument* doc1 = [[self.db copy] documentWithID: @"doc1"];
    Assert([[doc1 objectForKey: @"data"] isKindOfClass:[CBLBlob class]]);
    data = [doc1 objectForKey: @"data"];
    AssertEqual(data.length, 0ull);
    AssertEqualObjects(data.content, content);
    contentStream = data.contentStream;
    [contentStream open];
    uint8_t buffer[10];
    NSInteger bytesRead = [contentStream read:buffer maxLength:10];
    [contentStream close];
    AssertEqual(bytesRead, 0);
}


- (void)testMultipleBlobRead {
    NSData* content = [@"12345" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error;
    
    CBLBlob* data = [[CBLBlob alloc] initWithContentType:@"text/plain" data:content];
    Assert(data, @"Failed to create blob: %@", error);
    
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc setObject: data forKey: @"data"];
    
    data = [doc objectForKey: @"data"];
    for(int i = 0; i < 5; i++) {
        AssertEqualObjects(data.content, content);
        NSInputStream *contentStream = data.contentStream;
        [contentStream open];
        uint8_t buffer[10];
        NSInteger bytesRead = [contentStream read:buffer maxLength:10];
        [contentStream close];
        AssertEqual(bytesRead, 5);
    }
   
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    CBLDocument* doc1 = [[self.db copy] documentWithID: @"doc1"];
    Assert([[doc1 objectForKey: @"data"] isKindOfClass:[CBLBlob class]]);
    data = [doc1 objectForKey: @"data"];
    for(int i = 0; i < 5; i++) {
        AssertEqualObjects(data.content, content);
        NSInputStream *contentStream = data.contentStream;
        [contentStream open];
        uint8_t buffer[10];
        NSInteger bytesRead = [contentStream read:buffer maxLength:10];
        [contentStream close];
        AssertEqual(bytesRead, 5);
    }
}


- (void)testReadExistingBlob {
    NSData* content = [@"12345" dataUsingEncoding:NSUTF8StringEncoding];
    NSError* error;
    CBLBlob *data = [[CBLBlob alloc] initWithContentType:@"text/plain" data:content];
    Assert(data, @"Failed to create blob: %@", error);
    
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc setObject: data forKey: @"data"];
    [doc setObject: @"Jim" forKey: @"name"];
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);

    [self reopenDB];

    doc = [_db documentWithID: @"doc1"];
    Assert([[doc objectForKey: @"data"] isKindOfClass:[CBLBlob class]]);
    data = [doc objectForKey: @"data"];
    AssertEqualObjects(data.content, content);
    
    [self reopenDB];
    
    doc = [_db documentWithID: @"doc1"];
    [doc setObject: @"bar" forKey: @"foo"];
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    Assert([[doc objectForKey: @"data"] isKindOfClass:[CBLBlob class]]);
    data = [doc objectForKey: @"data"];
    AssertEqualObjects(data.content, content);
}


@end
