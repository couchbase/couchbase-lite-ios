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


#define kDocumentTestDate @"2017-01-01T00:00:00.000Z"
#define kDocumentTestBlob @"i'm blob"

@interface DocumentTest : CBLTestCase

@end


@implementation DocumentTest


- (void) populateData: (CBLMutableDocument*)doc {
    [doc setValue: @(YES) forKey: @"true"];
    [doc setValue: @(NO) forKey: @"false"];
    [doc setValue: @"string" forKey: @"string"];
    [doc setValue: @(0) forKey: @"zero"];
    [doc setValue: @(1) forKey: @"one"];
    [doc setValue: @(-1) forKey: @"minus_one"];
    [doc setValue: @(1.1) forKey: @"one_dot_one"];
    [doc setValue: [CBLJSON dateWithJSONObject: kDocumentTestDate] forKey: @"date"];
    [doc setValue: [NSNull null] forKey: @"null"];
    
    // Dictionary:
    CBLMutableDictionary* dict = [[CBLMutableDictionary alloc] init];
    [dict setValue: @"1 Main street" forKey: @"street"];
    [dict setValue: @"Mountain View" forKey: @"city"];
    [dict setValue: @"CA" forKey: @"state"];
    [doc setValue: dict forKey: @"dict"];
    
    // Array:
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    [array addValue: @"650-123-0001"];
    [array addValue: @"650-123-0002"];
    [doc setValue: array forKey: @"array"];
    
    // Blob:
    NSData* content = [kDocumentTestBlob dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType:@"text/plain" data: content];
    [doc setValue: blob forKey: @"blob"];
}


- (void) testCreateDoc {
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] init];
    AssertNotNil(doc);
    Assert(doc.id.length > 0);
    AssertFalse(doc.isDeleted);
    AssertEqualObjects([doc toDictionary], @{});
    
    CBLDocument* savedDoc = [self saveDocument: doc];
    Assert(savedDoc != doc);
    AssertNotNil(savedDoc);
    AssertEqualObjects(savedDoc.id, doc.id);
}


- (void) testCreateDocWithID {
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    AssertNotNil(doc);
    AssertEqualObjects(doc.id, @"doc1");
    AssertFalse(doc.isDeleted);
    AssertEqualObjects([doc toDictionary], @{});
    
    CBLDocument* savedDoc = [self saveDocument: doc];
    Assert(savedDoc != doc);
    AssertNotNil(savedDoc);
    AssertEqualObjects(savedDoc.id, doc.id);
}


- (void) testCreateDocWithEmptyStringID {
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] initWithID: @""];
    AssertNotNil(doc);
    
    NSError *error;
    AssertFalse([_db saveDocument: doc error: &error]);
    AssertEqual(error.code, 38); // Invalid docID
    AssertEqualObjects(error.domain, @"LiteCore");
}


- (void) testCreateDocWithNilID {
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] initWithID: nil];
    AssertNotNil(doc);
    Assert(doc.id.length > 0);
    AssertFalse(doc.isDeleted);
    AssertEqualObjects([doc toDictionary], @{});
    
    CBLDocument* savedDoc = [self saveDocument: doc];
    Assert(savedDoc != doc);
    AssertNotNil(savedDoc);
    AssertEqualObjects(savedDoc.id, doc.id);
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
    
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] initWithData: dict];
    AssertNotNil(doc);
    Assert(doc.id.length > 0);
    AssertFalse(doc.isDeleted);
    AssertEqualObjects([doc toDictionary], dict);
    
    CBLDocument* savedDoc = [self saveDocument: doc];
    Assert(savedDoc != doc);
    AssertNotNil(savedDoc);
    AssertEqualObjects(savedDoc.id, doc.id);
    AssertEqualObjects([savedDoc toDictionary], dict);
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
    
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] initWithID: @"doc1"
                                                          data: dict];
    AssertNotNil(doc);
    AssertEqualObjects(doc.id, @"doc1");
    AssertFalse(doc.isDeleted);
    AssertEqualObjects([doc toDictionary], dict);
    
    CBLDocument* savedDoc = [self saveDocument: doc];;
    Assert(savedDoc != doc);
    AssertNotNil(savedDoc);
    AssertEqualObjects(savedDoc.id, doc.id);
    AssertEqualObjects([savedDoc toDictionary], dict);
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
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setData: dict];
    AssertEqualObjects([doc toDictionary], dict);
    
    CBLDocument* savedDoc = [self saveDocument: doc];
    AssertEqualObjects([savedDoc toDictionary], dict);
    
    NSDictionary* nuDict = @{@"name": @"Danial Tiger",
                             @"age": @(32),
                             @"address": @{
                                     @"street": @"2 Main street.",
                                     @"city": @"Palo Alto",
                                     @"state": @"CA"},
                             @"phones": @[@"650-234-0001", @"650-234-0002"]
                             };
    
    doc = [savedDoc toMutable];
    [doc setData: nuDict];
    AssertEqualObjects([doc toDictionary], nuDict);
    
    savedDoc  = [self saveDocument: doc];
    AssertEqualObjects([savedDoc toDictionary], nuDict);
}


- (void) testGetValueFromDocument {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqual([d integerForKey: @"key"], 0);
        AssertEqual([d floatForKey: @"key"], 0.0f);
        AssertEqual([d doubleForKey: @"key"], 0.0);
        AssertEqual([d booleanForKey: @"key"], NO);
        AssertNil([d blobForKey: @"key"]);
        AssertNil([d dateForKey: @"key"]);
        AssertNil([d numberForKey: @"key"]);
        AssertNil([d valueForKey: @"key"]);
        AssertNil([d stringForKey: @"key"]);
        AssertNil([d dictionaryForKey: @"key"]);
        AssertNil([d arrayForKey: @"key"]);
        AssertEqualObjects([d toDictionary], @{});
    }];
}


- (void) testSaveThenGetFromAnotherDB {
    CBLMutableDocument* doc1a = [self createDocument: @"doc1"];
    [doc1a setValue: @"Scott Tiger" forKey: @"name"];
    
    [self saveDocument: doc1a];
    
    CBLDatabase* anotherDb = [_db copy];
    CBLDocument* doc1b = [anotherDb documentWithID: doc1a.id];
    Assert(doc1b != doc1a);
    AssertEqualObjects(doc1b.id, doc1a.id);
    AssertEqualObjects([doc1b toDictionary], [doc1a toDictionary]);
    
    [anotherDb close: nil];
}


- (void) testNoCacheNoLive {
    CBLMutableDocument* doc1a = [self createDocument: @"doc1"];
    [doc1a setValue: @"Scott Tiger" forKey: @"name"];
    [self saveDocument: doc1a];
    
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
    CBLMutableDocument* updatedDoc1b = [doc1b toMutable];
    [updatedDoc1b setValue: @"Daniel Tiger" forKey: @"name"];
    doc1b = [self saveDocument: updatedDoc1b];
    
    XCTAssertNotEqualObjects([doc1b toDictionary], [doc1a toDictionary]);
    XCTAssertNotEqualObjects([doc1b toDictionary], [doc1c toDictionary]);
    XCTAssertNotEqualObjects([doc1b toDictionary], [doc1d toDictionary]);
    
    [anotherDb close: nil];
}


- (void) testSetString {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setValue: @"" forKey: @"string1"];
    [doc setValue: @"string" forKey: @"string2"];
    
    __block CBLDocument* savedDoc;
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects([d valueForKey: @"string1"], @"");
        AssertEqualObjects([d valueForKey: @"string2"], @"string");
        savedDoc = d;
    }];
    
    // Update:
    doc = [savedDoc toMutable];
    [doc setValue: @"string" forKey: @"string1"];
    [doc setValue: @"" forKey: @"string2"];
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects([d valueForKey: @"string1"], @"string");
        AssertEqualObjects([d valueForKey: @"string2"], @"");
    }];
}


- (void) testGetString {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [self populateData: doc];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertNil([d stringForKey: @"null"]);
        AssertNil([d stringForKey: @"true"]);
        AssertNil([d stringForKey: @"false"]);
        AssertEqualObjects([d stringForKey: @"string"], @"string");
        AssertNil([d stringForKey: @"zero"]);
        AssertNil([d stringForKey: @"one"]);
        AssertNil([d stringForKey: @"minus_one"]);
        AssertNil([d stringForKey: @"one_dot_one"]);
        AssertEqualObjects([d stringForKey: @"date"], kDocumentTestDate);
        AssertNil([d stringForKey: @"dict"]);
        AssertNil([d stringForKey: @"array"]);
        AssertNil([d stringForKey: @"blob"]);
        AssertNil([d stringForKey: @"non_existing_key"]);
    }];
}


- (void) testSetNumber {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setValue: @(1) forKey: @"number1"];
    [doc setValue: @(0) forKey: @"number2"];
    [doc setValue: @(-1) forKey: @"number3"];
    [doc setValue: @(1.1) forKey: @"number4"];
    [doc setValue: @(12345678) forKey: @"number5"];
    
    __block CBLDocument* savedDoc;
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects([d valueForKey: @"number1"], @(1));
        AssertEqualObjects([d valueForKey: @"number2"], @(0));
        AssertEqualObjects([d valueForKey: @"number3"], @(-1));
        AssertEqualObjects([d valueForKey: @"number4"], @(1.1));
        AssertEqualObjects([d valueForKey: @"number5"], @(12345678));
        savedDoc = d;
    }];
    
    // Update:
    doc = [savedDoc toMutable];
    [doc setValue: @(0) forKey: @"number1"];
    [doc setValue: @(1) forKey: @"number2"];
    [doc setValue: @(1.1) forKey: @"number3"];
    [doc setValue: @(-1) forKey: @"number4"];
    [doc setValue: @(-12345678) forKey: @"number5"];
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects([d valueForKey: @"number1"], @(0));
        AssertEqualObjects([d valueForKey: @"number2"], @(1));
        AssertEqualObjects([d valueForKey: @"number3"], @(1.1));
        AssertEqualObjects([d valueForKey: @"number4"], @(-1));
        AssertEqualObjects([d valueForKey: @"number5"], @(-12345678));
    }];
}


- (void) testGetNumber {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [self populateData: doc];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertNil([d numberForKey: @"null"]);
        AssertEqualObjects([d numberForKey: @"true"], @(1));
        AssertEqualObjects([d numberForKey: @"false"], @(0));
        AssertNil([d numberForKey: @"string"]);
        AssertEqualObjects([d numberForKey: @"zero"], @(0));
        AssertEqualObjects([d numberForKey: @"one"], @(1));
        AssertEqualObjects([d numberForKey: @"minus_one"], @(-1));
        AssertEqualObjects([d numberForKey: @"one_dot_one"], @(1.1));
        AssertNil([d numberForKey: @"date"]);
        AssertNil([d numberForKey: @"dict"]);
        AssertNil([d numberForKey: @"array"]);
        AssertNil([d numberForKey: @"blob"]);
        AssertNil([d numberForKey: @"non_existing_key"]);
    }];
}


- (void) testGetInteger {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [self populateData: doc];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqual([d integerForKey: @"null"], 0);
        AssertEqual([d integerForKey: @"true"], 1);
        AssertEqual([d integerForKey: @"false"], 0);
        AssertEqual([d integerForKey: @"string"], 0);
        AssertEqual([d integerForKey: @"zero"], 0);
        AssertEqual([d integerForKey: @"one"], 1);
        AssertEqual([d integerForKey: @"minus_one"], -1);
        AssertEqual([d integerForKey: @"one_dot_one"], 1);
        AssertEqual([d integerForKey: @"date"], 0);
        AssertEqual([d integerForKey: @"dict"], 0);
        AssertEqual([d integerForKey: @"array"], 0);
        AssertEqual([d integerForKey: @"blob"], 0);
        AssertEqual([d integerForKey: @"non_existing_key"], 0);
    }];
}


- (void) testGetFloat {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [self populateData: doc];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqual([d floatForKey: @"null"], 0.0f);
        AssertEqual([d floatForKey: @"true"], 1.0f);
        AssertEqual([d floatForKey: @"false"], 0.0f);
        AssertEqual([d floatForKey: @"string"], 0.0f);
        AssertEqual([d floatForKey: @"zero"], 0.0f);
        AssertEqual([d floatForKey: @"one"], 1.0f);
        AssertEqual([d floatForKey: @"minus_one"], -1.0f);
        AssertEqual([d floatForKey: @"one_dot_one"], 1.1f);
        AssertEqual([d floatForKey: @"date"], 0.0f);
        AssertEqual([d floatForKey: @"dict"], 0.0f);
        AssertEqual([d floatForKey: @"array"], 0.0f);
        AssertEqual([d floatForKey: @"blob"], 0.0f);
        AssertEqual([d floatForKey: @"non_existing_key"], 0.0f);
    }];
}


- (void) testGetDouble {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [self populateData: doc];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqual([d doubleForKey: @"null"], 0.0);
        AssertEqual([d doubleForKey: @"true"], 1.0);
        AssertEqual([d doubleForKey: @"false"], 0.0);
        AssertEqual([d doubleForKey: @"string"], 0.0);
        AssertEqual([d doubleForKey: @"zero"], 0.0);
        AssertEqual([d doubleForKey: @"one"], 1.0);
        AssertEqual([d doubleForKey: @"minus_one"], -1.0);
        AssertEqual([d doubleForKey: @"one_dot_one"], 1.1);
        AssertEqual([d doubleForKey: @"date"], 0.0);
        AssertEqual([d doubleForKey: @"dict"], 0.0);
        AssertEqual([d doubleForKey: @"array"], 0.0);
        AssertEqual([d doubleForKey: @"blob"], 0.0);
        AssertEqual([d doubleForKey: @"non_existing_key"], 0.0);
    }];
}


- (void) testSetGetMinMaxNumbers {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setValue: @(NSIntegerMin) forKey: @"min_int"];
    [doc setValue: @(NSIntegerMax) forKey: @"max_int"];
    [doc setValue: @(FLT_MIN) forKey: @"min_float"];
    [doc setValue: @(FLT_MAX) forKey: @"max_float"];
    [doc setValue: @(DBL_MIN) forKey: @"min_double"];
    [doc setValue: @(DBL_MAX) forKey: @"max_double"];
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects([d numberForKey: @"min_int"], @(NSIntegerMin));
        AssertEqualObjects([d numberForKey: @"max_int"], @(NSIntegerMax));
        AssertEqualObjects([d valueForKey: @"min_int"], @(NSIntegerMin));
        AssertEqualObjects([d valueForKey: @"max_int"], @(NSIntegerMax));
        AssertEqual([d integerForKey: @"min_int"], NSIntegerMin);
        AssertEqual([d integerForKey: @"max_int"], NSIntegerMax);
        
        AssertEqualObjects([d numberForKey: @"min_float"], @(FLT_MIN));
        AssertEqualObjects([d numberForKey: @"max_float"], @(FLT_MAX));
        AssertEqualObjects([d valueForKey: @"min_float"], @(FLT_MIN));
        AssertEqualObjects([d valueForKey: @"max_float"], @(FLT_MAX));
        AssertEqual([d floatForKey: @"min_float"], FLT_MIN);
        AssertEqual([d floatForKey: @"max_float"], FLT_MAX);
        
        AssertEqualObjects([d numberForKey: @"min_double"], @(DBL_MIN));
        AssertEqualObjects([d numberForKey: @"max_double"], @(DBL_MAX));
        AssertEqualObjects([d valueForKey: @"min_double"], @(DBL_MIN));
        AssertEqualObjects([d valueForKey: @"max_double"], @(DBL_MAX));
        AssertEqual([d doubleForKey: @"min_double"], DBL_MIN);
        AssertEqual([d doubleForKey: @"max_double"], DBL_MAX);
    }];
}


- (void) testSetGetFloatNumbers {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setValue: @(1.00) forKey: @"number1"];
    [doc setValue: @(1.49) forKey: @"number2"];
    [doc setValue: @(1.50) forKey: @"number3"];
    [doc setValue: @(1.51) forKey: @"number4"];
    [doc setValue: @(1.99) forKey: @"number5"];
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects([d valueForKey: @"number1"], @(1.00));
        AssertEqualObjects([d numberForKey: @"number1"], @(1.00));
        AssertEqual([d integerForKey: @"number1"], 1);
        AssertEqual([d floatForKey: @"number1"], 1.00f);
        AssertEqual([d doubleForKey: @"number1"], 1.00);
        
        AssertEqualObjects([d valueForKey: @"number2"], @(1.49));
        AssertEqualObjects([d numberForKey: @"number2"], @(1.49));
        AssertEqual([d integerForKey: @"number2"], 1);
        AssertEqual([d floatForKey: @"number2"], 1.49f);
        AssertEqual([d doubleForKey: @"number2"], 1.49);
        
        AssertEqualObjects([d valueForKey: @"number3"], @(1.50));
        AssertEqualObjects([d numberForKey: @"number3"], @(1.50));
        AssertEqual([d integerForKey: @"number3"], 1);
        AssertEqual([d floatForKey: @"number3"], 1.50f);
        AssertEqual([d doubleForKey: @"number3"], 1.50);
        
        AssertEqualObjects([d valueForKey: @"number4"], @(1.51));
        AssertEqualObjects([d numberForKey: @"number4"], @(1.51));
        AssertEqual([d integerForKey: @"number4"], 1);
        AssertEqual([d floatForKey: @"number4"], 1.51f);
        AssertEqual([d doubleForKey: @"number4"], 1.51);
        
        AssertEqualObjects([d valueForKey: @"number5"], @(1.99));
        AssertEqualObjects([d numberForKey: @"number5"], @(1.99));
        AssertEqual([d integerForKey: @"number5"], 1);
        AssertEqual([d floatForKey: @"number5"], 1.99f);
        AssertEqual([d doubleForKey: @"number5"], 1.99);
    }];
}


- (void) testSetBoolean {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setValue: @(YES) forKey: @"boolean1"];
    [doc setValue: @(NO) forKey: @"boolean2"];
    
    __block CBLDocument* savedDoc;
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects([d valueForKey: @"boolean1"], @(1));
        AssertEqualObjects([d valueForKey: @"boolean2"], @(0));
        AssertEqual([d booleanForKey: @"boolean1"], YES);
        AssertEqual([d booleanForKey: @"boolean2"], NO);
        savedDoc = d;
    }];
    
    // Update:
    doc = [savedDoc toMutable];
    [doc setValue: @(NO) forKey: @"boolean1"];
    [doc setValue: @(YES) forKey: @"boolean2"];
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects([d valueForKey: @"boolean1"], @(0));
        AssertEqualObjects([d valueForKey: @"boolean2"], @(1));
        AssertEqual([d booleanForKey: @"boolean1"], NO);
        AssertEqual([d booleanForKey: @"boolean2"], YES);
    }];
}


- (void) testGetBoolean {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [self populateData: doc];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqual([d booleanForKey: @"null"], NO);
        AssertEqual([d booleanForKey: @"true"], YES);
        AssertEqual([d booleanForKey: @"false"], NO);
        AssertEqual([d booleanForKey: @"string"], YES);
        AssertEqual([d booleanForKey: @"zero"], NO);
        AssertEqual([d booleanForKey: @"one"], YES);
        AssertEqual([d booleanForKey: @"minus_one"], YES);
        AssertEqual([d booleanForKey: @"one_dot_one"], YES);
        AssertEqual([d booleanForKey: @"date"], YES);
        AssertEqual([d booleanForKey: @"dict"], YES);
        AssertEqual([d booleanForKey: @"array"], YES);
        AssertEqual([d booleanForKey: @"blob"], YES);
        AssertEqual([d booleanForKey: @"non_existing_key"], NO);
    }];
}


- (void) testSetDate {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    NSDate* date = [NSDate date];
    NSString* dateStr = [CBLJSON JSONObjectWithDate: date];
    Assert(dateStr.length > 0);
    [doc setValue: date forKey: @"date"];
    
    __block CBLDocument* savedDoc;
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects([d valueForKey: @"date"], dateStr);
        AssertEqualObjects([d stringForKey: @"date"], dateStr);
        AssertEqualObjects([CBLJSON JSONObjectWithDate: [d dateForKey: @"date"]], dateStr);
        savedDoc = d;
    }];
    
    // Update:
    doc = [savedDoc toMutable];
    NSDate* nuDate = [NSDate dateWithTimeInterval: 60.0 sinceDate: date];
    NSString* nuDateStr = [CBLJSON JSONObjectWithDate: nuDate];
    [doc setValue: nuDate forKey: @"date"];
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects([d valueForKey: @"date"], nuDateStr);
        AssertEqualObjects([d stringForKey: @"date"], nuDateStr);
        AssertEqualObjects([CBLJSON JSONObjectWithDate: [d dateForKey: @"date"]], nuDateStr);
    }];
}


- (void) testGetDate {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [self populateData: doc];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertNil([d dateForKey: @"null"]);
        AssertNil([d dateForKey: @"true"]);
        AssertNil([d dateForKey: @"false"]);
        AssertNil([d dateForKey: @"string"]);
        AssertNil([d dateForKey: @"zero"]);
        AssertNil([d dateForKey: @"one"]);
        AssertNil([d dateForKey: @"minus_one"]);
        AssertNil([d dateForKey: @"one_dot_one"]);
        AssertNotNil([d dateForKey: @"date"]);
        AssertEqualObjects([CBLJSON JSONObjectWithDate: [d dateForKey: @"date"]], kDocumentTestDate);
        AssertNil([d dateForKey: @"dict"]);
        AssertNil([d dateForKey: @"array"]);
        AssertNil([d dateForKey: @"blob"]);
        AssertNil([d dateForKey: @"non_existing_key"]);
    }];
}


- (void) testSetBlob {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    NSData* content = [kDocumentTestBlob dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType: @"text/plain" data: content];
    [doc setValue: blob forKey: @"blob"];
    
    doc = [[self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects(((CBLBlob*)[d valueForKey: @"blob"]).properties, blob.properties);
        AssertEqualObjects([d blobForKey: @"blob"].properties, blob.properties);
        AssertEqualObjects([d blobForKey: @"blob"].content, content);
    }] toMutable];
    
    // Update:
    
    NSData* nuContent = [@"1234567890" dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlob* nuBlob = [[CBLBlob alloc] initWithContentType: @"text/plain" data: nuContent];
    [doc setValue: nuBlob forKey: @"blob"];
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects(((CBLBlob*)[d valueForKey: @"blob"]).properties, nuBlob.properties);
        AssertEqualObjects([d blobForKey: @"blob"].properties, nuBlob.properties);
        AssertEqualObjects([d blobForKey: @"blob"].content, nuContent);
    }];
}


- (void) testGetBlob {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [self populateData: doc];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertNil([d blobForKey: @"null"]);
        AssertNil([d blobForKey: @"true"]);
        AssertNil([d blobForKey: @"false"]);
        AssertNil([d blobForKey: @"string"]);
        AssertNil([d blobForKey: @"zero"]);
        AssertNil([d blobForKey: @"one"]);
        AssertNil([d blobForKey: @"minus_one"]);
        AssertNil([d blobForKey: @"one_dot_one"]);
        AssertNil([d blobForKey: @"date"]);
        AssertNil([d dateForKey: @"dict"]);
        AssertNil([d dateForKey: @"array"]);
        AssertEqualObjects([d blobForKey: @"blob"].content,
                           [kDocumentTestBlob dataUsingEncoding: NSUTF8StringEncoding]);
        AssertNil([d dateForKey: @"non_existing_key"]);
    }];
}


- (void) testSetDictionary {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    CBLMutableDictionary* dict = [[CBLMutableDictionary alloc] init];
    [dict setValue: @"1 Main street" forKey: @"street"];
    [doc setValue: dict forKey: @"dict"];
    
    AssertEqual([doc valueForKey: @"dict"], dict);
    CBLDocument* savedDoc = [self saveDocument: doc];
    
    Assert([savedDoc valueForKey: @"dict"] != dict);
    AssertEqual([savedDoc valueForKey: @"dict"], [savedDoc dictionaryForKey: @"dict"]);
    AssertEqualObjects([[savedDoc dictionaryForKey: @"dict"] toDictionary], [dict toDictionary]);
    
    // Update:
    doc = [savedDoc toMutable];
    dict = [doc dictionaryForKey: @"dict"];
    [dict setValue: @"Mountain View" forKey: @"city"];
    
    AssertEqual([doc valueForKey: @"dict"], [doc dictionaryForKey: @"dict"]);
    NSDictionary* nsdict = @{@"street": @"1 Main street", @"city": @"Mountain View"};
    AssertEqualObjects([[doc dictionaryForKey: @"dict"] toDictionary], nsdict);
    
    savedDoc = [self saveDocument: doc];
    
    Assert([savedDoc valueForKey: @"dict"] != dict);
    AssertEqual([savedDoc valueForKey: @"dict"], [savedDoc dictionaryForKey: @"dict"]);
    AssertEqualObjects([[savedDoc dictionaryForKey: @"dict"] toDictionary], nsdict);
}


- (void) testGetDictionary {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [self populateData: doc];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertNil([d dictionaryForKey: @"null"]);
        AssertNil([d dictionaryForKey: @"true"]);
        AssertNil([d dictionaryForKey: @"false"]);
        AssertNil([d dictionaryForKey: @"string"]);
        AssertNil([d dictionaryForKey: @"zero"]);
        AssertNil([d dictionaryForKey: @"one"]);
        AssertNil([d dictionaryForKey: @"minus_one"]);
        AssertNil([d dictionaryForKey: @"one_dot_one"]);
        AssertNil([d dictionaryForKey: @"date"]);
        AssertNotNil([d dictionaryForKey: @"dict"]);
        NSDictionary* dict = @{@"street": @"1 Main street", @"city": @"Mountain View", @"state": @"CA"};
        AssertEqualObjects([[d dictionaryForKey: @"dict"] toDictionary], dict);
        AssertNil([d dictionaryForKey: @"array"]);
        AssertNil([d dictionaryForKey: @"blob"]);
        AssertNil([d dictionaryForKey: @"non_existing_key"]);
    }];
}


- (void) testSetArray {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    [array addValue: @"item1"];
    [array addValue: @"item2"];
    [array addValue: @"item3"];
    [doc setValue: array forKey: @"array"];
    
    AssertEqual([doc valueForKey: @"array"], array);
    AssertEqual([doc arrayForKey: @"array"], array);
    AssertEqualObjects([[doc arrayForKey: @"array"] toArray], (@[@"item1", @"item2", @"item3"]));
    
    CBLDocument* savedDoc = [self saveDocument: doc];
    
    Assert([savedDoc valueForKey: @"array"] != array);
    AssertEqual([savedDoc valueForKey: @"array"], [savedDoc arrayForKey: @"array"]);
    AssertEqualObjects([[savedDoc arrayForKey: @"array"] toArray], (@[@"item1", @"item2", @"item3"]));
    
    // Update:
    doc = [savedDoc toMutable];
    array = [doc arrayForKey: @"array"];
    [array addValue: @"item4"];
    [array addValue: @"item5"];
    
    savedDoc = [self saveDocument: doc];
    
    Assert([savedDoc valueForKey: @"array"] != array);
    AssertEqual([savedDoc valueForKey: @"array"], [savedDoc arrayForKey: @"array"]);
    AssertEqualObjects([[savedDoc arrayForKey: @"array"] toArray],
                       (@[@"item1", @"item2", @"item3", @"item4", @"item5"]));
}


- (void) testGetArray {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [self populateData: doc];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertNil([d arrayForKey: @"null"]);
        AssertNil([d arrayForKey: @"true"]);
        AssertNil([d arrayForKey: @"false"]);
        AssertNil([d arrayForKey: @"string"]);
        AssertNil([d arrayForKey: @"zero"]);
        AssertNil([d arrayForKey: @"one"]);
        AssertNil([d arrayForKey: @"minus_one"]);
        AssertNil([d arrayForKey: @"one_dot_one"]);
        AssertNil([d arrayForKey: @"date"]);
        AssertNil([d arrayForKey: @"dict"]);
        AssertNotNil([d arrayForKey: @"array"]);
        AssertEqualObjects([[d arrayForKey: @"array"] toArray],
                           (@[@"650-123-0001", @"650-123-0002"]));
        AssertNil([d arrayForKey: @"blob"]);
        AssertNil([d arrayForKey: @"non_existing_key"]);
    }];
}


- (void) testSetNSNull {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setValue: [NSNull null] forKey: @"null"];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqual([d valueForKey: @"null"], [NSNull null]);
        AssertEqual(d.count, 1u);
    }];
}


- (void) testSetNil {
    // Note:
    // * As of Oct 2017, we've decided to change the behavior of storing nil into a CBLMutableDictionary
    //   to make it correspond to Cocoa idioms, i.e. it removes the value, instead of storing NSNull.
    // * As of Nov 2017, after API review, we've decided to revert the behavior to allow the API to
    //   be the same across platform. This means that setting nil value will be converted to NSNull
    //   instead of removing the value.
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setValue: @"something" forKey: @"nil"];
    [doc setValue: nil forKey: @"nil"];
    [doc setValue: [NSNull null] forKey: @"null"];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects([d valueForKey: @"nil"], [NSNull null]);
        AssertEqualObjects([d valueForKey: @"null"], [NSNull null]);
        AssertEqual(d.count, 2u);
    }];
}


- (void) testSetNSDictionary {
    NSDictionary* dict = @{@"street": @"1 Main street",
                           @"city": @"Mountain View",
                           @"state": @"CA"};
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setValue: dict forKey: @"address"];
    
    CBLMutableDictionary* address = [doc dictionaryForKey: @"address"];
    AssertNotNil(address);
    AssertEqual(address, [doc valueForKey: @"address"]);
    AssertEqualObjects([address stringForKey: @"street"], @"1 Main street");
    AssertEqualObjects([address stringForKey: @"city"], @"Mountain View");
    AssertEqualObjects([address stringForKey: @"state"], @"CA");
    AssertEqualObjects([address toDictionary], dict);
    
    // Update with a new dictionary:
    NSDictionary* nuDict = @{@"street": @"1 Second street",
                             @"city": @"Palo Alto",
                             @"state": @"CA"};
    [doc setValue: nuDict forKey: @"address"];
    
    // Check whether the old address dictionary is still accessible:
    Assert(address != [doc dictionaryForKey: @"address"]);
    AssertEqualObjects([address stringForKey: @"street"], @"1 Main street");
    AssertEqualObjects([address stringForKey: @"city"], @"Mountain View");
    AssertEqualObjects([address stringForKey: @"state"], @"CA");
    AssertEqualObjects([address toDictionary], dict);
    
    // The old address dictionary should be detached:
    CBLMutableDictionary* nuAddress = [doc dictionaryForKey: @"address"];
    Assert(address != nuAddress);
    
    // Update nuAddress:
    [nuAddress setValue: @"94302" forKey: @"zip"];
    AssertEqualObjects([nuAddress stringForKey: @"zip"], @"94302");
    AssertNil([address stringForKey: @"zip"]);
    
    // Save:
    CBLDocument* savedDoc = [self saveDocument: doc];
    AssertEqualObjects([savedDoc toDictionary], (@{@"address": @{@"street": @"1 Second street",
                                                                 @"city": @"Palo Alto",
                                                                 @"state": @"CA",
                                                                 @"zip": @"94302"}}));
}


- (void) testSetNSArray {
    NSArray* array = @[@"a", @"b", @"c"];
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setValue: array forKey: @"members"];
    
    CBLMutableArray* members = [doc arrayForKey: @"members"];
    AssertNotNil(members);
    AssertEqual(members, [doc valueForKey: @"members"]);
    
    AssertEqual(members.count, 3u);
    AssertEqualObjects([members valueAtIndex: 0], @"a");
    AssertEqualObjects([members valueAtIndex: 1], @"b");
    AssertEqualObjects([members valueAtIndex: 2], @"c");
    AssertEqualObjects([members toArray], (@[@"a", @"b", @"c"]));
    
    // Update with a new array:
    NSArray* nuArray = @[@"d", @"e", @"f"];
    [doc setValue: nuArray forKey: @"members"];
    
    // Check whether the old members array is still accessible:
    AssertEqual(members.count, 3u);
    AssertEqualObjects([members valueAtIndex: 0], @"a");
    AssertEqualObjects([members valueAtIndex: 1], @"b");
    AssertEqualObjects([members valueAtIndex: 2], @"c");
    AssertEqualObjects([members toArray], (@[@"a", @"b", @"c"]));
    
    // The old members array should be detached:
    CBLMutableArray* nuMembers = [doc arrayForKey: @"members"];
    Assert(members != nuMembers);
    
    // Update nuMembers:
    [nuMembers addValue: @"g"];
    AssertEqual(nuMembers.count, 4u);
    AssertEqualObjects([nuMembers valueAtIndex: 3], @"g");
    AssertEqual(members.count, 3u);
    
    // Save:
    CBLDocument* savedDoc = [self saveDocument: doc];
    AssertEqualObjects([savedDoc toDictionary], (@{@"members": @[@"d", @"e", @"f", @"g"]}));
}


- (void) testUpdateNestedDictionary {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    CBLMutableDictionary* addresses = [[CBLMutableDictionary alloc] init];
    [doc setValue: addresses forKey: @"addresses"];
    
    CBLMutableDictionary* shipping = [[CBLMutableDictionary alloc] init];
    [shipping setValue: @"1 Main street" forKey: @"street"];
    [shipping setValue: @"Mountain View" forKey: @"city"];
    [shipping setValue: @"CA" forKey: @"state"];
    [addresses setValue: shipping forKey: @"shipping"];
    
    // Update:
    CBLDocument* savedDoc = [self saveDocument: doc];
    doc = [savedDoc toMutable];
    
    shipping = [[doc dictionaryForKey: @"addresses"] dictionaryForKey: @"shipping"];
    [shipping setValue: @"94042" forKey: @"zip"];
    savedDoc = [self saveDocument: doc];
    
    NSDictionary* result = @{@"addresses":
                                 @{@"shipping":
                                       @{@"street": @"1 Main street",
                                         @"city": @"Mountain View",
                                         @"state": @"CA",
                                         @"zip": @"94042"}}};
    AssertEqualObjects([savedDoc toDictionary], result);
}


- (void) testUpdateDictionaryInArray {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    CBLMutableArray* addresses = [[CBLMutableArray alloc] init];
    [doc setValue: addresses forKey: @"addresses"];
    
    CBLMutableDictionary* address1 = [[CBLMutableDictionary alloc] init];
    [address1 setValue: @"1 Main street" forKey: @"street"];
    [address1 setValue: @"Mountain View" forKey: @"city"];
    [address1 setValue: @"CA" forKey: @"state"];
    [addresses addValue: address1];
    
    CBLMutableDictionary* address2 = [[CBLMutableDictionary alloc] init];
    [address2 setValue: @"1 Second street" forKey: @"street"];
    [address2 setValue: @"Palo Alto" forKey: @"city"];
    [address2 setValue: @"CA" forKey: @"state"];
    [addresses addValue: address2];
    
    CBLDocument* savedDoc = [self saveDocument: doc];
    doc = [savedDoc toMutable];
    
    address1 = [[doc arrayForKey: @"addresses"] dictionaryAtIndex: 0];
    [address1 setValue: @"2 Main street" forKey: @"street"];
    [address1 setValue: @"94042" forKey: @"zip"];
    
    address2 = [[doc arrayForKey: @"addresses"] dictionaryAtIndex: 1];
    [address2 setValue: @"2 Second street" forKey: @"street"];
    [address2 setValue: @"94302" forKey: @"zip"];
    
    savedDoc = [self saveDocument: doc];
    
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
    AssertEqualObjects([savedDoc toDictionary], result);
}


- (void) testUpdateNestedArray {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    CBLMutableArray* groups = [[CBLMutableArray alloc] init];
    [doc setValue: groups forKey: @"groups"];
    
    CBLMutableArray* group1 = [[CBLMutableArray alloc] init];
    [group1 addValue: @"a"];
    [group1 addValue: @"b"];
    [group1 addValue: @"c"];
    [groups addValue: group1];
    
    CBLMutableArray* group2 = [[CBLMutableArray alloc] init];
    [group2 addValue: @(1)];
    [group2 addValue: @(2)];
    [group2 addValue: @(3)];
    [groups addValue: group2];
    
    CBLDocument* savedDoc = [self saveDocument: doc];
    doc = [savedDoc toMutable];
    
    group1 = [[doc arrayForKey: @"groups"] arrayAtIndex: 0];
    [group1 setValue: @"d" atIndex: 0];
    [group1 setValue: @"e" atIndex: 1];
    [group1 setValue: @"f" atIndex: 2];
    
    group2 = [[doc arrayForKey: @"groups"] arrayAtIndex: 1];
    [group2 setValue: @(4) atIndex: 0];
    [group2 setValue: @(5) atIndex: 1];
    [group2 setValue: @(6) atIndex: 2];
    
    savedDoc = [self saveDocument: doc];
    
    NSDictionary* result = @{@"groups": @[@[@"d", @"e", @"f"], @[@(4), @(5), @(6)]]};
    AssertEqualObjects([savedDoc toDictionary], result);
}


- (void) testUpdateArrayInDictionary {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    
    CBLMutableDictionary* group1 = [[CBLMutableDictionary alloc] init];
    CBLMutableArray* member1 = [[CBLMutableArray alloc] init];
    [member1 addValue: @"a"];
    [member1 addValue: @"b"];
    [member1 addValue: @"c"];
    [group1 setValue: member1 forKey: @"member"];
    [doc setValue: group1 forKey: @"group1"];
    
    CBLMutableDictionary* group2 = [[CBLMutableDictionary alloc] init];
    CBLMutableArray* member2 = [[CBLMutableArray alloc] init];
    [member2 addValue: @(1)];
    [member2 addValue: @(2)];
    [member2 addValue: @(3)];
    [group2 setValue: member2 forKey: @"member"];
    [doc setValue: group2 forKey: @"group2"];
    
    CBLDocument* savedDoc = [self saveDocument: doc];
    doc = [savedDoc toMutable];
    
    member1 = [[doc dictionaryForKey: @"group1"] arrayForKey: @"member"];
    [member1 setValue: @"d" atIndex: 0];
    [member1 setValue: @"e" atIndex: 1];
    [member1 setValue: @"f" atIndex: 2];
    
    member2 = [[doc dictionaryForKey: @"group2"] arrayForKey: @"member"];
    [member2 setValue: @(4) atIndex: 0];
    [member2 setValue: @(5) atIndex: 1];
    [member2 setValue: @(6) atIndex: 2];
    
    savedDoc = [self saveDocument: doc];
    
    NSDictionary* result = @{@"group1": @{@"member": @[@"d", @"e", @"f"]},
                             @"group2": @{@"member": @[@(4), @(5), @(6)]}};
    AssertEqualObjects([savedDoc toDictionary], result);
}


- (void) testSetDictionaryToMultipleKeys {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    
    CBLMutableDictionary* address = [[CBLMutableDictionary alloc] init];
    [address setValue: @"1 Main street" forKey: @"street"];
    [address setValue: @"Mountain View" forKey: @"city"];
    [address setValue: @"CA" forKey: @"state"];
    [doc setValue: address forKey: @"shipping"];
    [doc setValue: address forKey: @"billing"];
    
    AssertEqual([doc valueForKey: @"shipping"], address);
    AssertEqual([doc valueForKey: @"billing"], address);
    
    // Update address: both shipping and billing should get the update.
    [address setValue: @"94042" forKey: @"zip"];
    AssertEqualObjects([[doc dictionaryForKey: @"shipping"] stringForKey: @"zip"], @"94042");
    AssertEqualObjects([[doc dictionaryForKey: @"billing"] stringForKey: @"zip"], @"94042");
    
    CBLDocument* savedDoc = [self saveDocument: doc];
    doc = [savedDoc toMutable];
    
    CBLMutableDictionary* shipping = [doc dictionaryForKey: @"shipping"];
    CBLMutableDictionary* billing = [doc dictionaryForKey: @"billing"];
    
    // After save: both shipping and billing address are now independent to each other
    Assert(shipping != address);
    Assert(billing != address);
    Assert(shipping != billing);
    
    [shipping setValue: @"2 Main street" forKey: @"street"];
    [billing setValue: @"3 Main street" forKey: @"street"];
    
    // Save update:
    savedDoc = [self saveDocument: doc];
    
    AssertEqualObjects([[savedDoc dictionaryForKey: @"shipping"] stringForKey: @"street"], @"2 Main street");
    AssertEqualObjects([[savedDoc dictionaryForKey: @"billing"] stringForKey: @"street"], @"3 Main street");
}


- (void) testSetArrayToMultipleKeys {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    
    CBLMutableArray* phones = [[CBLMutableArray alloc] init];
    [phones addValue: @"650-000-0001"];
    [phones addValue: @"650-000-0002"];
    
    [doc setValue: phones forKey: @"mobile"];
    [doc setValue: phones forKey: @"home"];
    
    AssertEqual([doc valueForKey:@"mobile"], phones);
    AssertEqual([doc valueForKey:@"home"], phones);
    
    // Update phones: both mobile and home should get the update
    [phones addValue: @"650-000-0003"];
    AssertEqualObjects([[doc arrayForKey: @"mobile"] toArray],
                       (@[@"650-000-0001", @"650-000-0002", @"650-000-0003"]));
    AssertEqualObjects([[doc arrayForKey: @"home"] toArray],
                       (@[@"650-000-0001", @"650-000-0002", @"650-000-0003"]));
    
    CBLDocument* savedDoc = [self saveDocument: doc];
    doc = [savedDoc toMutable];
    
    // After save: both mobile and home are not independent to each other
    CBLMutableArray* mobile = [doc arrayForKey: @"mobile"];
    CBLMutableArray* home = [doc arrayForKey: @"home"];
    Assert(mobile != phones);
    Assert(home != phones);
    Assert(mobile != home);
    
    // Update mobile and home:
    [mobile addValue: @"650-000-1234"];
    [home addValue: @"650-000-5678"];
    
    // Save update:
    savedDoc = [self saveDocument: doc];
    
    AssertEqualObjects([[savedDoc arrayForKey: @"mobile"] toArray],
                       (@[@"650-000-0001", @"650-000-0002", @"650-000-0003", @"650-000-1234"]));
    AssertEqualObjects([[savedDoc arrayForKey: @"home"] toArray],
                       (@[@"650-000-0001", @"650-000-0002", @"650-000-0003", @"650-000-5678"]));
}


- (void) failingTestdata {
    CBLMutableDocument* doc1 = [self createDocument: @"doc1"];
    [self populateData: doc1];
    // TODO: Should blob be serialized into JSON dictionary?
}


- (void) testCount {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [self populateData: doc];
    
    AssertEqual(doc.count, 12u);
    AssertEqual(doc.count, [doc toDictionary].count);
    
    CBLDocument* savedDoc = [self saveDocument: doc];
    
    AssertEqual(savedDoc.count, 12u);
    AssertEqual([savedDoc toDictionary].count, doc.count);
}


- (void) testContainsKey {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setData: @{ @"type": @"profile",
                           @"name": @"Jason",
                           @"age": @"30",
                           @"address": @{
                                   @"street": @"1 milky way.",
                                   }
                           }];
    
    Assert([doc containsValueForKey: @"type"]);
    Assert([doc containsValueForKey: @"name"]);
    Assert([doc containsValueForKey: @"age"]);
    Assert([doc containsValueForKey: @"address"]);
    AssertFalse([doc containsValueForKey: @"weight"]);
}


- (void) testRemoveKeys {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setData: @{ @"type": @"profile",
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
    doc = [[self saveDocument: doc] toMutable];
    
    [doc removeValueForKey: @"name"];
    [doc removeValueForKey: @"weight"];
    [doc removeValueForKey: @"age"];
    [doc removeValueForKey: @"active"];
    [[doc dictionaryForKey: @"address"] removeValueForKey: @"city"];
    
    AssertNil([doc stringForKey: @"name"]);
    AssertEqual([doc floatForKey: @"weight"], 0.0);
    AssertEqual([doc doubleForKey: @"weight"], 0.0);
    AssertEqual([doc integerForKey: @"age"], 0);
    AssertEqual([doc booleanForKey: @"active"], NO);
    
    AssertNil([doc valueForKey: @"name"]);
    AssertNil([doc valueForKey: @"weight"]);
    AssertNil([doc valueForKey: @"age"]);
    AssertNil([doc valueForKey: @"active"]);
    AssertNil([[doc dictionaryForKey: @"address"] valueForKey: @"city"]);
    
    AssertFalse([doc containsValueForKey: @"name"]);
    AssertFalse([doc containsValueForKey: @"weight"]);
    AssertFalse([doc containsValueForKey: @"age"]);
    AssertFalse([doc containsValueForKey: @"active"]);
    AssertFalse([[doc dictionaryForKey: @"address"] containsValueForKey: @"city"]);
    
    CBLMutableDictionary* address = [doc dictionaryForKey: @"address"];
    AssertEqualObjects([doc toDictionary], (@{ @"type": @"profile",
                                               @"address": @{
                                                       @"street": @"1 milky way.",
                                                       @"zip" : @12345
                                                       }
                                               }));
    AssertEqualObjects([address toDictionary], (@{ @"street": @"1 milky way.", @"zip" : @12345 }));
    
    // Remove the rest:
    [doc removeValueForKey: @"type"];
    [doc removeValueForKey: @"address"];
    AssertNil([doc valueForKey: @"type"]);
    AssertNil([doc valueForKey: @"address"]);
    AssertFalse([doc containsValueForKey: @"type"]);
    AssertFalse([doc containsValueForKey: @"address"]);
    AssertEqualObjects([doc toDictionary], @{});
}


- (void) failingTestDeleteNewDocument {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setValue: @"Scott Tiger" forKey: @"name"];
    AssertFalse(doc.isDeleted);
    
    NSError* error;
    AssertFalse([_db deleteDocument: doc error: &error]);
    AssertEqual(error.code, 404);
}


- (void) testDeleteDocument {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setValue: @"Scott Tiger" forKey: @"name"];
    AssertFalse(doc.isDeleted);
    
    // Save:
    CBLDocument* savedDoc = [self saveDocument: doc];
    
    // Delete:
    NSError* error;
    Assert([_db deleteDocument: savedDoc error: &error]);
    AssertNil(error);
    AssertNil([_db documentWithID: doc.id]);
}


- (void) testDictionaryAfterDeleteDocument {
    NSDictionary* dict = @{@"address": @{
                                   @"street": @"1 Main street",
                                   @"city": @"Mountain View",
                                   @"state": @"CA"}
                           };
    CBLMutableDocument* doc = [self createDocument: @"doc1" data: dict];
    CBLDocument* savedDoc = [self saveDocument: doc];
    
    CBLDictionary* address = [savedDoc dictionaryForKey: @"address"];
    AssertEqualObjects([address valueForKey: @"street"], @"1 Main street");
    AssertEqualObjects([address valueForKey: @"city"], @"Mountain View");
    AssertEqualObjects([address valueForKey: @"state"], @"CA");
    
    NSError* error;
    Assert([_db deleteDocument: savedDoc error: &error]);
    AssertNil(error);
    
    // The dictionary still has data:
    AssertEqualObjects([address valueForKey: @"street"], @"1 Main street");
    AssertEqualObjects([address valueForKey: @"city"], @"Mountain View");
    AssertEqualObjects([address valueForKey: @"state"], @"CA");
}


- (void) testArrayAfterDeleteDocument {
    NSDictionary* dict = @{@"members": @[@"a", @"b", @"c"]};
    
    CBLMutableDocument* doc = [self createDocument: @"doc1" data: dict];
    CBLDocument* savedDoc = [self saveDocument: doc];
    
    CBLArray* members = [savedDoc arrayForKey: @"members"];
    AssertEqual(members.count, 3u);
    AssertEqualObjects([members valueAtIndex: 0], @"a");
    AssertEqualObjects([members valueAtIndex: 1], @"b");
    AssertEqualObjects([members valueAtIndex: 2], @"c");
    
    NSError* error;
    Assert([_db deleteDocument: savedDoc error: &error]);
    AssertNil(error);
    
    // The array still has data:
    AssertEqual(members.count, 3u);
    AssertEqualObjects([members valueAtIndex: 0], @"a");
    AssertEqualObjects([members valueAtIndex: 1], @"b");
    AssertEqualObjects([members valueAtIndex: 2], @"c");
}


- (void) testPurgeDocument {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setValue: @"profile" forKey: @"type"];
    [doc setValue: @"Scott" forKey: @"name"];
    AssertFalse(doc.isDeleted);
 
    // Purge before save:
    NSError* error;
    AssertFalse([_db purgeDocument: doc error: &error]);
    
    // Save:
    CBLDocument* savedDoc = [self saveDocument: doc];
    
    // Purge:
    Assert([_db purgeDocument: savedDoc error: &error], @"Purging error: %@", error);
}


- (void) testReopenDB {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setValue: @"str" forKey: @"string"];
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Error saving: %@", error);

    [self reopenDB];

    CBLDocument* savedDoc = [self.db documentWithID: @"doc1"];
    AssertEqualObjects([savedDoc stringForKey: @"string"], @"str");
    AssertEqualObjects([savedDoc toDictionary], @{@"string": @"str"});
}


- (void)testBlob {
    NSData* content = [kDocumentTestBlob dataUsingEncoding:NSUTF8StringEncoding];
    NSError* error;
    CBLBlob *data = [[CBLBlob alloc] initWithContentType:@"text/plain" data:content];
    Assert(data, @"Failed to create blob: %@", error);
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setValue: data forKey: @"data"];
    [doc setValue: @"Jim" forKey: @"name"];
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    
    CBLDocument* doc1 = [[self.db copy] documentWithID: @"doc1"];
    AssertEqualObjects([doc1 valueForKey: @"name"], @"Jim");
    Assert([[doc1 valueForKey: @"data"] isKindOfClass:[CBLBlob class]]);
    data = [doc1 valueForKey: @"data"];
    AssertEqual(data.length, 8ull);
    AssertEqualObjects(data.content, content);
    NSInputStream *contentStream = data.contentStream;
    [contentStream open];
    uint8_t buffer[10];
    NSInteger bytesRead = [contentStream read:buffer maxLength:10];
    [contentStream close];
    AssertEqual(bytesRead, 8);
}


- (void)testEmptyBlob {
    NSData* content = [@"" dataUsingEncoding:NSUTF8StringEncoding];
    NSError* error;
    CBLBlob *data = [[CBLBlob alloc] initWithContentType:@"text/plain" data:content];
    Assert(data, @"Failed to create blob: %@", error);
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setValue: data forKey: @"data"];
    
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    CBLDocument* doc1 = [[self.db copy] documentWithID: @"doc1"];
    Assert([[doc1 valueForKey: @"data"] isKindOfClass:[CBLBlob class]]);
    data = [doc1 valueForKey: @"data"];
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
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setValue: data forKey: @"data"];
    
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    CBLDocument* doc1 = [[self.db copy] documentWithID: @"doc1"];
    Assert([[doc1 valueForKey: @"data"] isKindOfClass:[CBLBlob class]]);
    data = [doc1 valueForKey: @"data"];
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
    NSData* content = [kDocumentTestBlob dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error;
    
    CBLBlob* data = [[CBLBlob alloc] initWithContentType:@"text/plain" data:content];
    Assert(data, @"Failed to create blob: %@", error);
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setValue: data forKey: @"data"];
    
    data = [doc valueForKey: @"data"];
    for(int i = 0; i < 5; i++) {
        AssertEqualObjects(data.content, content);
        NSInputStream *contentStream = data.contentStream;
        [contentStream open];
        uint8_t buffer[10];
        NSInteger bytesRead = [contentStream read:buffer maxLength:10];
        [contentStream close];
        AssertEqual(bytesRead, 8);
    }
   
    CBLDocument* savedDoc = [self saveDocument: doc];
    
    Assert([[savedDoc valueForKey: @"data"] isKindOfClass:[CBLBlob class]]);
    data = [savedDoc valueForKey: @"data"];
    for(int i = 0; i < 5; i++) {
        AssertEqualObjects(data.content, content);
        NSInputStream *contentStream = data.contentStream;
        [contentStream open];
        uint8_t buffer[10];
        NSInteger bytesRead = [contentStream read:buffer maxLength:10];
        [contentStream close];
        AssertEqual(bytesRead, 8);
    }
}


- (void)testReadExistingBlob {
    NSData* content = [kDocumentTestBlob dataUsingEncoding:NSUTF8StringEncoding];
    NSError* error;
    CBLBlob *data = [[CBLBlob alloc] initWithContentType:@"text/plain" data:content];
    Assert(data, @"Failed to create blob: %@", error);
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setValue: data forKey: @"data"];
    [doc setValue: @"Jim" forKey: @"name"];
    
    CBLDocument* savedDoc = [self saveDocument: doc];
    Assert([[savedDoc valueForKey: @"data"] isKindOfClass:[CBLBlob class]]);
    data = [savedDoc valueForKey: @"data"];
    AssertEqualObjects(data.content, content);
    
    [self reopenDB];
    
    doc = [[_db documentWithID: @"doc1"] toMutable];
    [doc setValue: @"bar" forKey: @"foo"];
    savedDoc = [self saveDocument: doc];
    Assert([[savedDoc valueForKey: @"data"] isKindOfClass:[CBLBlob class]]);
    data = [savedDoc valueForKey: @"data"];
    AssertEqualObjects(data.content, content);
}


- (void) testEnumeratingKeys {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    for (NSInteger i = 0; i < 20; i++) {
        [doc setValue: @(i) forKey: [NSString stringWithFormat:@"key%ld", (long)i]];
    }
    NSDictionary* content = [doc toDictionary];
    
    __block NSMutableDictionary* result = [NSMutableDictionary dictionary];
    __block NSUInteger count = 0;
    for (NSString* key in doc) {
        result[key] = [doc valueForKey: key];
        count++;
    }
    AssertEqualObjects(result, content);
    AssertEqual(count, content.count);
    
    // Update:
    
    [doc removeValueForKey: @"key2"];
    [doc setValue: @(20) forKey: @"key20"];
    [doc setValue: @(21) forKey: @"key21"];
    content = [doc toDictionary];
    
    [self saveDocument: doc eval: ^(CBLDocument *d) {
        result = [NSMutableDictionary dictionary];
        count = 0;
        for (NSString* key in d) {
            result[key] = [d valueForKey: key];
            count++;
        }
        AssertEqualObjects(result, content);
        AssertEqual(count, content.count);
    }];
}


- (void) testToMutable {
    NSData* content = [kDocumentTestBlob dataUsingEncoding:NSUTF8StringEncoding];
    CBLBlob *data = [[CBLBlob alloc] initWithContentType:@"text/plain" data:content];
    
    CBLMutableDocument* mDoc1 = [self createDocument: @"doc1"];
    [mDoc1 setValue: data forKey: @"data"];
    [mDoc1 setValue: @"Jim" forKey: @"name"];
    [mDoc1 setInteger: 10 forKey: @"score"];
    
    CBLMutableDocument* mDoc2 = [mDoc1 toMutable];
    Assert(mDoc1 != mDoc2);
    AssertEqualObjects([mDoc2 blobForKey: @"data"].content, [mDoc1 blobForKey: @"data"].content);
    AssertEqualObjects([mDoc2 stringForKey: @"name"], [mDoc1 stringForKey: @"name"]);
    AssertEqual([mDoc2 integerForKey: @"score"], [mDoc1 integerForKey: @"score"]);
    
    CBLDocument* doc1 = [self saveDocument: mDoc1];
    CBLMutableDocument* mDoc3 = [doc1 toMutable];
    AssertEqualObjects([doc1 blobForKey: @"data"].content, [mDoc3 blobForKey: @"data"].content);
    AssertEqualObjects([doc1 stringForKey: @"name"], [mDoc3 stringForKey: @"name"]);
    AssertEqual([doc1 integerForKey: @"score"], [mDoc3 integerForKey: @"score"]);
}


- (void) testEquality {
    NSData* data1 = [@"data1" dataUsingEncoding: NSUTF8StringEncoding];
    NSData* data2 = [@"data2" dataUsingEncoding: NSUTF8StringEncoding];
    
    CBLMutableDocument* doc1a = [self createDocument: @"doc1"];
    [doc1a setInteger: 42 forKey: @"answer"];
    [doc1a setValue: @[@"1", @"2", @"3"] forKey: @"options"];
    [doc1a setBlob: [[CBLBlob alloc] initWithContentType: @"text/plain" data: data1] forKey: @"attachment"];
    
    CBLMutableDocument* doc1b = [self createDocument: @"doc1"];
    [doc1b setInteger: 42 forKey: @"answer"];
    [doc1b setValue: @[@"1", @"2", @"3"] forKey: @"options"];
    [doc1b setBlob: [[CBLBlob alloc] initWithContentType: @"text/plain" data: data1] forKey: @"attachment"];
    
    CBLMutableDocument* doc1c = [self createDocument: @"doc1"];
    [doc1c setInteger: 41 forKey: @"answer1"];
    [doc1c setValue: @[@"1", @"2"] forKey: @"options"];
    [doc1c setBlob: [[CBLBlob alloc] initWithContentType: @"text/plain" data: data2] forKey: @"attachment"];
    [doc1c setString: @"This is a comment" forKey: @"comment"];
    
    Assert([doc1a isEqual: doc1a]);
    Assert([doc1a isEqual: doc1b]);
    Assert(![doc1a isEqual: doc1c]);
    
    Assert([doc1b isEqual: doc1a]);
    Assert([doc1b isEqual: doc1b]);
    Assert(![doc1b isEqual: doc1c]);
    
    Assert(![doc1c isEqual: doc1a]);
    Assert(![doc1c isEqual: doc1b]);
    Assert([doc1c isEqual: doc1c]);
    
    CBLDocument* savedDoc = [self saveDocument: doc1c];
    Assert([savedDoc isEqual: savedDoc]);
    Assert([savedDoc isEqual: doc1c]);
    
    CBLMutableDocument* mDoc = [savedDoc toMutable];
    Assert([mDoc isEqual: savedDoc]);
    [mDoc setInteger: 50 forKey: @"answer"];
    Assert(![mDoc isEqual: savedDoc]);
}


- (void) testEqualityDifferentDocID {
    CBLMutableDocument* doc1 = [self createDocument: @"doc1"];
    [doc1 setInteger: 42 forKey: @"answer"];
    [self saveDocument: doc1];
    CBLDocument* sdoc1 = [_db documentWithID: @"doc1"];
    Assert([sdoc1 isEqual: doc1]);
    
    CBLMutableDocument* doc2 = [self createDocument: @"doc2"];
    [doc2 setInteger: 42 forKey: @"answer"];
    [self saveDocument: doc2];
    CBLDocument* sdoc2 = [_db documentWithID: @"doc2"];
    Assert([sdoc2 isEqual: doc2]);
    
    Assert([doc1 isEqual: doc1]);
    Assert(![doc1 isEqual: doc2]);
    
    Assert(![doc2 isEqual: doc1]);
    Assert([doc2 isEqual: doc2]);
    
    Assert([sdoc1 isEqual: sdoc1]);
    Assert(![sdoc1 isEqual: sdoc2]);
    
    Assert(![sdoc2 isEqual: sdoc1]);
    Assert([sdoc2 isEqual: sdoc2]);
}


- (void) testEqualityDifferentDB {
    CBLMutableDocument* doc1a = [self createDocument: @"doc1"];
    [doc1a setInteger: 42 forKey: @"answer"];
    
    CBLDatabase* otherDB = [self openDBNamed: @"other" error: nil];
    CBLMutableDocument* doc1b = [self createDocument: @"doc1"];
    [doc1b setInteger: 42 forKey: @"answer"];
    
    Assert([doc1a isEqual: doc1b]);
    
    CBLDocument* sdoc1a = [_db saveDocument: doc1a error: nil];
    CBLDocument* sdoc1b = [otherDB saveDocument: doc1b error: nil];
    
    Assert([sdoc1a isEqual: doc1a]);
    Assert([sdoc1b isEqual: doc1b]);
    
    Assert(![doc1a isEqual: doc1b]);
    Assert(![sdoc1a isEqual: sdoc1b]);
    
    sdoc1a = [_db documentWithID: @"doc1"];
    sdoc1b = [otherDB documentWithID: @"doc1"];
    Assert(![sdoc1a isEqual: sdoc1b]);
    [otherDB close: nil];
    
    CBLDatabase* sameDB = [_db copy];
    CBLDocument* anotherDoc1a = [sameDB documentWithID: @"doc1"];
    Assert([sdoc1a isEqual: anotherDoc1a]);
    [sameDB close: nil];
}


@end
