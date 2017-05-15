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


- (void) populateData: (CBLDocument*)doc {
    [doc setObject: @(YES) forKey: @"true"];
    [doc setObject: @(NO) forKey: @"false"];
    [doc setObject: @"string" forKey: @"string"];
    [doc setObject: @(0) forKey: @"zero"];
    [doc setObject: @(1) forKey: @"one"];
    [doc setObject: @(-1) forKey: @"minus_one"];
    [doc setObject: @(1.1) forKey: @"one_dot_one"];
    [doc setObject: [CBLJSON dateWithJSONObject: kDocumentTestDate] forKey: @"date"];
    [doc setObject: [NSNull null] forKey: @"null"];
    
    // Dictionary:
    CBLDictionary* dict = [[CBLDictionary alloc] init];
    [dict setObject: @"1 Main street" forKey: @"street"];
    [dict setObject: @"Mountain View" forKey: @"city"];
    [dict setObject: @"CA" forKey: @"state"];
    [doc setObject: dict forKey: @"dict"];
    
    // Array:
    CBLArray* array = [[CBLArray alloc] init];
    [array addObject: @"650-123-0001"];
    [array addObject: @"650-123-0002"];
    [doc setObject: array forKey: @"array"];
    
    // Blob:
    NSData* content = [kDocumentTestBlob dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType:@"text/plain" data: content];
    [doc setObject: blob forKey: @"blob"];
}


- (void) testCreateDoc {
    CBLDocument* doc1a = [[CBLDocument alloc] init];
    AssertNotNil(doc1a);
    Assert(doc1a.documentID.length > 0);
    AssertFalse(doc1a.isDeleted);
    AssertEqualObjects([doc1a toDictionary], @{});
    
    CBLDocument* doc1b = [self saveDocument: doc1a];
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
    
    CBLDocument* doc1b = [self saveDocument: doc1a];
    Assert(doc1b != doc1a);
    AssertNotNil(doc1b);
    AssertEqualObjects(doc1b.documentID, doc1a.documentID);
}


- (void) testCreateDocWithEmptyStringID {
    CBLDocument* doc1a = [[CBLDocument alloc] initWithID: @""];
    AssertNotNil(doc1a);
    
    NSError *error;
    AssertFalse([_db saveDocument: doc1a error: &error]);
    AssertEqual(error.code, 38); // Invalid docID
    AssertEqualObjects(error.domain, @"LiteCore");
}


- (void) testCreateDocWithNilID {
    CBLDocument* doc1a = [[CBLDocument alloc] initWithID: nil];
    AssertNotNil(doc1a);
    Assert(doc1a.documentID.length > 0);
    AssertFalse(doc1a.isDeleted);
    AssertEqualObjects([doc1a toDictionary], @{});
    
    CBLDocument* doc1b = [self saveDocument: doc1a];;
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
    
    CBLDocument* doc1b = [self saveDocument: doc1a];
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
    
    CBLDocument* doc1b = [self saveDocument: doc1a];;
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
    
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setDictionary: dict];
    AssertEqualObjects([doc toDictionary], dict);
    
    doc = [self saveDocument: doc];
    AssertEqualObjects([doc toDictionary], dict);
    
    NSDictionary* nuDict = @{@"name": @"Danial Tiger",
                             @"age": @(32),
                             @"address": @{
                                     @"street": @"2 Main street.",
                                     @"city": @"Palo Alto",
                                     @"state": @"CA"},
                             @"phones": @[@"650-234-0001", @"650-234-0002"]
                             };
    [doc setDictionary: nuDict];
    AssertEqualObjects([doc toDictionary], nuDict);
    
    doc = [self saveDocument: doc];
    AssertEqualObjects([doc toDictionary], nuDict);
}


- (void) testGetValueFromNewEmptyDoc {
    CBLDocument* doc = [self createDocument: @"doc1"];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqual([d integerForKey: @"key"], 0);
        AssertEqual([d floatForKey: @"key"], 0.0f);
        AssertEqual([d doubleForKey: @"key"], 0.0);
        AssertEqual([d booleanForKey: @"key"], NO);
        AssertNil([d blobForKey: @"key"]);
        AssertNil([d dateForKey: @"key"]);
        AssertNil([d numberForKey: @"key"]);
        AssertNil([d objectForKey: @"key"]);
        AssertNil([d stringForKey: @"key"]);
        AssertNil([d dictionaryForKey: @"key"]);
        AssertNil([d arrayForKey: @"key"]);
        AssertEqualObjects([d toDictionary], @{});
    }];
}


- (void) testGetValueFromExistingEmptyDoc {
    CBLDocument* doc = [self createDocument: @"doc1"];
    doc = [self saveDocument: doc];
    
    AssertEqual([doc integerForKey: @"key"], 0);
    AssertEqual([doc floatForKey: @"key"], 0.0f);
    AssertEqual([doc doubleForKey: @"key"], 0.0);
    AssertEqual([doc booleanForKey: @"key"], NO);
    AssertNil([doc blobForKey: @"key"]);
    AssertNil([doc dateForKey: @"key"]);
    AssertNil([doc numberForKey: @"key"]);
    AssertNil([doc objectForKey: @"key"]);
    AssertNil([doc stringForKey: @"key"]);
    AssertNil([doc dictionaryForKey: @"key"]);
    AssertNil([doc arrayForKey: @"key"]);
    AssertEqualObjects([doc toDictionary], @{});
}


- (void) testSaveThenGetFromAnotherDB {
    CBLDocument* doc1a = [self createDocument: @"doc1"];
    [doc1a setObject: @"Scott Tiger" forKey: @"name"];
    
    [self saveDocument: doc1a];
    
    CBLDatabase* anotherDb = [_db copy];
    CBLDocument* doc1b = [anotherDb documentWithID: doc1a.documentID];
    Assert(doc1b != doc1a);
    AssertEqualObjects(doc1b.documentID, doc1a.documentID);
    AssertEqualObjects([doc1b toDictionary], [doc1a toDictionary]);
    
    [anotherDb close: nil];
}


- (void) testNoCacheNoLive {
    CBLDocument* doc1a = [self createDocument: @"doc1"];
    [doc1a setObject: @"Scott Tiger" forKey: @"name"];
    
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
    [doc1b setObject:@"Daniel Tiger" forKey: @"name"];
    [self saveDocument: doc1b];
    
    XCTAssertNotEqualObjects([doc1b toDictionary], [doc1a toDictionary]);
    XCTAssertNotEqualObjects([doc1b toDictionary], [doc1c toDictionary]);
    XCTAssertNotEqualObjects([doc1b toDictionary], [doc1d toDictionary]);
    
    [anotherDb close: nil];
}


- (void) testSetString {
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: @"" forKey: @"string1"];
    [doc setObject: @"string" forKey: @"string2"];
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects([d objectForKey: @"string1"], @"");
        AssertEqualObjects([d objectForKey: @"string2"], @"string");
    }];
    
    // Update:
    
    [doc setObject: @"string" forKey: @"string1"];
    [doc setObject: @"" forKey: @"string2"];
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects([d objectForKey: @"string1"], @"string");
        AssertEqualObjects([d objectForKey: @"string2"], @"");
    }];
}


- (void) testGetString {
    CBLDocument* doc = [self createDocument: @"doc1"];
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
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: @(1) forKey: @"number1"];
    [doc setObject: @(0) forKey: @"number2"];
    [doc setObject: @(-1) forKey: @"number3"];
    [doc setObject: @(1.1) forKey: @"number4"];
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects([d objectForKey: @"number1"], @(1));
        AssertEqualObjects([d objectForKey: @"number2"], @(0));
        AssertEqualObjects([d objectForKey: @"number3"], @(-1));
        AssertEqualObjects([d objectForKey: @"number4"], @(1.1));
    }];
    
    // Update:
    
    [doc setObject: @(0) forKey: @"number1"];
    [doc setObject: @(1) forKey: @"number2"];
    [doc setObject: @(1.1) forKey: @"number3"];
    [doc setObject: @(-1) forKey: @"number4"];
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects([d objectForKey: @"number1"], @(0));
        AssertEqualObjects([d objectForKey: @"number2"], @(1));
        AssertEqualObjects([d objectForKey: @"number3"], @(1.1));
        AssertEqualObjects([d objectForKey: @"number4"], @(-1));
    }];
}


- (void) testGetNumber {
    CBLDocument* doc = [self createDocument: @"doc1"];
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
    CBLDocument* doc = [self createDocument: @"doc1"];
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
    CBLDocument* doc = [self createDocument: @"doc1"];
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
    CBLDocument* doc = [self createDocument: @"doc1"];
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
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: @(NSIntegerMin) forKey: @"min_int"];
    [doc setObject: @(NSIntegerMax) forKey: @"max_int"];
    [doc setObject: @(FLT_MIN) forKey: @"min_float"];
    [doc setObject: @(FLT_MAX) forKey: @"max_float"];
    [doc setObject: @(DBL_MIN) forKey: @"min_double"];
    [doc setObject: @(DBL_MAX) forKey: @"max_double"];
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects([d numberForKey: @"min_int"], @(NSIntegerMin));
        AssertEqualObjects([d numberForKey: @"max_int"], @(NSIntegerMax));
        AssertEqualObjects([d objectForKey: @"min_int"], @(NSIntegerMin));
        AssertEqualObjects([d objectForKey: @"max_int"], @(NSIntegerMax));
        AssertEqual([d integerForKey: @"min_int"], NSIntegerMin);
        AssertEqual([d integerForKey: @"max_int"], NSIntegerMax);
        
        AssertEqualObjects([d numberForKey: @"min_float"], @(FLT_MIN));
        AssertEqualObjects([d numberForKey: @"max_float"], @(FLT_MAX));
        AssertEqualObjects([d objectForKey: @"min_float"], @(FLT_MIN));
        AssertEqualObjects([d objectForKey: @"max_float"], @(FLT_MAX));
        AssertEqual([d floatForKey: @"min_float"], FLT_MIN);
        AssertEqual([d floatForKey: @"max_float"], FLT_MAX);
        
        AssertEqualObjects([d numberForKey: @"min_double"], @(DBL_MIN));
        AssertEqualObjects([d numberForKey: @"max_double"], @(DBL_MAX));
        AssertEqualObjects([d objectForKey: @"min_double"], @(DBL_MIN));
        AssertEqualObjects([d objectForKey: @"max_double"], @(DBL_MAX));
        AssertEqual([d doubleForKey: @"min_double"], DBL_MIN);
        AssertEqual([d doubleForKey: @"max_double"], DBL_MAX);
    }];
}


- (void) failingTestSetGetFloatNumbers {
    // TODO: Fleece asInt() does round up
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: @(1.00) forKey: @"number1"];
    [doc setObject: @(1.49) forKey: @"number2"];
    [doc setObject: @(1.50) forKey: @"number3"];
    [doc setObject: @(1.51) forKey: @"number4"];
    [doc setObject: @(1.99) forKey: @"number5"];
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects([d objectForKey: @"number1"], @(1.00));
        AssertEqualObjects([d numberForKey: @"number1"], @(1.00));
        AssertEqual([d integerForKey: @"number1"], 1);
        AssertEqual([d floatForKey: @"number1"], 1.00f);
        AssertEqual([d doubleForKey: @"number1"], 1.00);
        
        AssertEqualObjects([d objectForKey: @"number2"], @(1.49));
        AssertEqualObjects([d numberForKey: @"number2"], @(1.49));
        AssertEqual([d integerForKey: @"number2"], 1);
        AssertEqual([d floatForKey: @"number2"], 1.49f);
        AssertEqual([d doubleForKey: @"number2"], 1.49);
        
        AssertEqualObjects([d objectForKey: @"number3"], @(1.50));
        AssertEqualObjects([d numberForKey: @"number3"], @(1.50));
        AssertEqual([d integerForKey: @"number3"], 1);
        AssertEqual([d floatForKey: @"number3"], 1.50f);
        AssertEqual([d doubleForKey: @"number3"], 1.50);
        
        AssertEqualObjects([d objectForKey: @"number4"], @(1.51));
        AssertEqualObjects([d numberForKey: @"number4"], @(1.51));
        AssertEqual([d integerForKey: @"number4"], 1);
        AssertEqual([d floatForKey: @"number4"], 1.51f);
        AssertEqual([d doubleForKey: @"number4"], 1.51);
        
        AssertEqualObjects([d objectForKey: @"number5"], @(1.99));
        AssertEqualObjects([d numberForKey: @"number5"], @(1.99));
        AssertEqual([d integerForKey: @"number5"], 1);
        AssertEqual([d floatForKey: @"number5"], 1.99f);
        AssertEqual([d doubleForKey: @"number5"], 1.99);
    }];
}


- (void) testSetBoolean {
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: @(YES) forKey: @"boolean1"];
    [doc setObject: @(NO) forKey: @"boolean2"];
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects([d objectForKey: @"boolean1"], @(1));
        AssertEqualObjects([d objectForKey: @"boolean2"], @(0));
        AssertEqual([d booleanForKey: @"boolean1"], YES);
        AssertEqual([d booleanForKey: @"boolean2"], NO);
    }];
    
    // Update:
    
    [doc setObject: @(NO) forKey: @"boolean1"];
    [doc setObject: @(YES) forKey: @"boolean2"];
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects([d objectForKey: @"boolean1"], @(0));
        AssertEqualObjects([d objectForKey: @"boolean2"], @(1));
        AssertEqual([d booleanForKey: @"boolean1"], NO);
        AssertEqual([d booleanForKey: @"boolean2"], YES);
    }];
}


- (void) testGetBoolean {
    CBLDocument* doc = [self createDocument: @"doc1"];
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
    CBLDocument* doc = [self createDocument: @"doc1"];
    NSDate* date = [NSDate date];
    NSString* dateStr = [CBLJSON JSONObjectWithDate: date];
    Assert(dateStr.length > 0);
    [doc setObject: date forKey: @"date"];
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects([d objectForKey: @"date"], dateStr);
        AssertEqualObjects([d stringForKey: @"date"], dateStr);
        AssertEqualObjects([CBLJSON JSONObjectWithDate: [d dateForKey: @"date"]], dateStr);
    }];
    
    // Update:
    
    NSDate* nuDate = [NSDate dateWithTimeInterval: 60.0 sinceDate: date];
    NSString* nuDateStr = [CBLJSON JSONObjectWithDate: nuDate];
    [doc setObject: nuDate forKey: @"date"];
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects([d objectForKey: @"date"], nuDateStr);
        AssertEqualObjects([d stringForKey: @"date"], nuDateStr);
        AssertEqualObjects([CBLJSON JSONObjectWithDate: [d dateForKey: @"date"]], nuDateStr);
    }];
}


- (void) testGetDate {
    CBLDocument* doc = [self createDocument: @"doc1"];
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
    CBLDocument* doc = [self createDocument: @"doc1"];
    NSData* content = [kDocumentTestBlob dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType: @"text/plain" data: content];
    [doc setObject: blob forKey: @"blob"];
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects(((CBLBlob*)[d objectForKey: @"blob"]).properties, blob.properties);
        AssertEqualObjects([d blobForKey: @"blob"].properties, blob.properties);
        AssertEqualObjects([d blobForKey: @"blob"].content, content);
    }];
    
    // Update:
    
    NSData* nuContent = [@"1234567890" dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlob* nuBlob = [[CBLBlob alloc] initWithContentType: @"text/plain" data: nuContent];
    [doc setObject: nuBlob forKey: @"blob"];
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects(((CBLBlob*)[d objectForKey: @"blob"]).properties, nuBlob.properties);
        AssertEqualObjects([d blobForKey: @"blob"].properties, nuBlob.properties);
        AssertEqualObjects([d blobForKey: @"blob"].content, nuContent);
    }];
}


- (void) testGetBlob {
    CBLDocument* doc = [self createDocument: @"doc1"];
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
    CBLDocument* doc = [self createDocument: @"doc1"];
    CBLDictionary* dict = [[CBLDictionary alloc] init];
    [dict setObject: @"1 Main street" forKey: @"street"];
    [doc setObject: dict forKey: @"dict"];
    
    AssertEqual([doc objectForKey: @"dict"], dict);
    doc = [self saveDocument: doc];
    
    Assert([doc objectForKey: @"dict"] != dict);
    AssertEqual([doc objectForKey: @"dict"], [doc dictionaryForKey: @"dict"]);
    AssertEqualObjects([[doc dictionaryForKey: @"dict"] toDictionary], [dict toDictionary]);
    
    // Update:
    
    dict = [doc dictionaryForKey: @"dict"];
    [dict setObject: @"Mountain View" forKey: @"city"];
    
    AssertEqual([doc objectForKey: @"dict"], [doc dictionaryForKey: @"dict"]);
    NSDictionary* nsdict = @{@"street": @"1 Main street", @"city": @"Mountain View"};
    AssertEqualObjects([[doc dictionaryForKey: @"dict"] toDictionary], nsdict);
    
    doc = [self saveDocument: doc];
    
    Assert([doc objectForKey: @"dict"] != dict);
    AssertEqual([doc objectForKey: @"dict"], [doc dictionaryForKey: @"dict"]);
    AssertEqualObjects([[doc dictionaryForKey: @"dict"] toDictionary], nsdict);
}


- (void) testGetDictionary {
    CBLDocument* doc = [self createDocument: @"doc1"];
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
    CBLDocument* doc = [self createDocument: @"doc1"];
    CBLArray* array = [[CBLArray alloc] init];
    [array addObject: @"item1"];
    [array addObject: @"item2"];
    [array addObject: @"item3"];
    [doc setObject: array forKey: @"array"];
    
    AssertEqual([doc objectForKey: @"array"], array);
    AssertEqual([doc arrayForKey: @"array"], array);
    AssertEqualObjects([[doc arrayForKey: @"array"] toArray], (@[@"item1", @"item2", @"item3"]));
    
    doc = [self saveDocument: doc];
    
    Assert([doc objectForKey: @"array"] != array);
    AssertEqual([doc objectForKey: @"array"], [doc arrayForKey: @"array"]);
    AssertEqualObjects([[doc arrayForKey: @"array"] toArray], (@[@"item1", @"item2", @"item3"]));
    
    // Update:
    array = [doc arrayForKey: @"array"];
    [array addObject: @"item4"];
    [array addObject: @"item5"];
    
    doc = [self saveDocument: doc];
    
    Assert([doc objectForKey: @"array"] != array);
    AssertEqual([doc objectForKey: @"array"], [doc arrayForKey: @"array"]);
    AssertEqualObjects([[doc arrayForKey: @"array"] toArray],
                       (@[@"item1", @"item2", @"item3", @"item4", @"item5"]));
}


- (void) testGetArray {
    CBLDocument* doc = [self createDocument: @"doc1"];
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
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: [NSNull null] forKey: @"null"];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqual([d objectForKey: @"null"], [NSNull null]);
        AssertEqual(d.count, 1u);
    }];
}


- (void) testSetNSDictionary {
    NSDictionary* dict = @{@"street": @"1 Main street",
                           @"city": @"Mountain View",
                           @"state": @"CA"};
    
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: dict forKey: @"address"];
    
    CBLDictionary* address = [doc dictionaryForKey: @"address"];
    AssertNotNil(address);
    AssertEqual(address, [doc objectForKey: @"address"]);
    AssertEqualObjects([address stringForKey: @"street"], @"1 Main street");
    AssertEqualObjects([address stringForKey: @"city"], @"Mountain View");
    AssertEqualObjects([address stringForKey: @"state"], @"CA");
    AssertEqualObjects([address toDictionary], dict);
    
    // Update with a new dictionary:
    NSDictionary* nuDict = @{@"street": @"1 Second street",
                             @"city": @"Palo Alto",
                             @"state": @"CA"};
    [doc setObject: nuDict forKey: @"address"];
    
    // Check whether the old address dictionary is still accessible:
    Assert(address != [doc dictionaryForKey: @"address"]);
    AssertEqualObjects([address stringForKey: @"street"], @"1 Main street");
    AssertEqualObjects([address stringForKey: @"city"], @"Mountain View");
    AssertEqualObjects([address stringForKey: @"state"], @"CA");
    AssertEqualObjects([address toDictionary], dict);
    
    // The old address dictionary should be detached:
    CBLDictionary* nuAddress = [doc dictionaryForKey: @"address"];
    Assert(address != nuAddress);
    
    // Update nuAddress:
    [nuAddress setObject: @"94302" forKey: @"zip"];
    AssertEqualObjects([nuAddress stringForKey: @"zip"], @"94302");
    AssertNil([address stringForKey: @"zip"]);
    
    // Save:
    doc = [self saveDocument: doc];
    
    AssertEqualObjects([doc toDictionary], (@{@"address": @{@"street": @"1 Second street",
                                                             @"city": @"Palo Alto",
                                                             @"state": @"CA",
                                                             @"zip": @"94302"}}));
}


- (void) testSetNSArray {
    NSArray* array = @[@"a", @"b", @"c"];
    
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: array forKey: @"members"];
    
    CBLArray* members = [doc arrayForKey: @"members"];
    AssertNotNil(members);
    AssertEqual(members, [doc objectForKey: @"members"]);
    
    AssertEqual(members.count, 3u);
    AssertEqualObjects([members objectAtIndex: 0], @"a");
    AssertEqualObjects([members objectAtIndex: 1], @"b");
    AssertEqualObjects([members objectAtIndex: 2], @"c");
    AssertEqualObjects([members toArray], (@[@"a", @"b", @"c"]));
    
    // Update with a new array:
    NSArray* nuArray = @[@"d", @"e", @"f"];
    [doc setObject: nuArray forKey: @"members"];
    
    // Check whether the old members array is still accessible:
    AssertEqual(members.count, 3u);
    AssertEqualObjects([members objectAtIndex: 0], @"a");
    AssertEqualObjects([members objectAtIndex: 1], @"b");
    AssertEqualObjects([members objectAtIndex: 2], @"c");
    AssertEqualObjects([members toArray], (@[@"a", @"b", @"c"]));
    
    // The old members array should be detached:
    CBLArray* nuMembers = [doc arrayForKey: @"members"];
    Assert(members != nuMembers);
    
    // Update nuMembers:
    [nuMembers addObject: @"g"];
    AssertEqual(nuMembers.count, 4u);
    AssertEqualObjects([nuMembers objectAtIndex: 3], @"g");
    AssertEqual(members.count, 3u);
    
    // Save:
    doc = [self saveDocument: doc];
    
    AssertEqualObjects([doc toDictionary], (@{@"members": @[@"d", @"e", @"f", @"g"]}));
}


- (void) testUpdateNestedDictionary {
    CBLDocument* doc = [self createDocument: @"doc1"];
    CBLDictionary* addresses = [[CBLDictionary alloc] init];
    [doc setObject: addresses forKey: @"addresses"];
    
    CBLDictionary* shipping = [[CBLDictionary alloc] init];
    [shipping setObject: @"1 Main street" forKey: @"street"];
    [shipping setObject: @"Mountain View" forKey: @"city"];
    [shipping setObject: @"CA" forKey: @"state"];
    [addresses setObject: shipping forKey: @"shipping"];
    
    doc = [self saveDocument: doc];
    
    shipping = [[doc dictionaryForKey: @"addresses"] dictionaryForKey: @"shipping"];
    [shipping setObject: @"94042" forKey: @"zip"];
    
    doc = [self saveDocument: doc];
    
    NSDictionary* result = @{@"addresses":
                                 @{@"shipping":
                                       @{@"street": @"1 Main street",
                                         @"city": @"Mountain View",
                                         @"state": @"CA",
                                         @"zip": @"94042"}}};
    AssertEqualObjects([doc toDictionary], result);
}


- (void) testUpdateDictionaryInArray {
    CBLDocument* doc = [self createDocument: @"doc1"];
    CBLArray* addresses = [[CBLArray alloc] init];
    [doc setObject: addresses forKey: @"addresses"];
    
    CBLDictionary* address1 = [[CBLDictionary alloc] init];
    [address1 setObject: @"1 Main street" forKey: @"street"];
    [address1 setObject: @"Mountain View" forKey: @"city"];
    [address1 setObject: @"CA" forKey: @"state"];
    [addresses addObject: address1];
    
    CBLDictionary* address2 = [[CBLDictionary alloc] init];
    [address2 setObject: @"1 Second street" forKey: @"street"];
    [address2 setObject: @"Palo Alto" forKey: @"city"];
    [address2 setObject: @"CA" forKey: @"state"];
    [addresses addObject: address2];
    
    doc = [self saveDocument: doc];
    
    address1 = [[doc arrayForKey: @"addresses"] dictionaryAtIndex: 0];
    [address1 setObject: @"2 Main street" forKey: @"street"];
    [address1 setObject: @"94042" forKey: @"zip"];
    
    address2 = [[doc arrayForKey: @"addresses"] dictionaryAtIndex: 1];
    [address2 setObject: @"2 Second street" forKey: @"street"];
    [address2 setObject: @"94302" forKey: @"zip"];
    
    doc = [self saveDocument: doc];
    
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
    AssertEqualObjects([doc toDictionary], result);
}


- (void) testUpdateNestedArray {
    CBLDocument* doc = [self createDocument: @"doc1"];
    CBLArray* groups = [[CBLArray alloc] init];
    [doc setObject: groups forKey: @"groups"];
    
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
    
    doc = [self saveDocument: doc];
    
    group1 = [[doc arrayForKey: @"groups"] arrayAtIndex: 0];
    [group1 setObject: @"d" atIndex: 0];
    [group1 setObject: @"e" atIndex: 1];
    [group1 setObject: @"f" atIndex: 2];
    
    group2 = [[doc arrayForKey: @"groups"] arrayAtIndex: 1];
    [group2 setObject: @(4) atIndex: 0];
    [group2 setObject: @(5) atIndex: 1];
    [group2 setObject: @(6) atIndex: 2];
    
    doc = [self saveDocument: doc];
    
    NSDictionary* result = @{@"groups": @[@[@"d", @"e", @"f"], @[@(4), @(5), @(6)]]};
    AssertEqualObjects([doc toDictionary], result);
}


- (void) testUpdateArrayInDictionary {
    CBLDocument* doc = [self createDocument: @"doc1"];
    
    CBLDictionary* group1 = [[CBLDictionary alloc] init];
    CBLArray* member1 = [[CBLArray alloc] init];
    [member1 addObject: @"a"];
    [member1 addObject: @"b"];
    [member1 addObject: @"c"];
    [group1 setObject: member1 forKey: @"member"];
    [doc setObject: group1 forKey: @"group1"];
    
    CBLDictionary* group2 = [[CBLDictionary alloc] init];
    CBLArray* member2 = [[CBLArray alloc] init];
    [member2 addObject: @(1)];
    [member2 addObject: @(2)];
    [member2 addObject: @(3)];
    [group2 setObject: member2 forKey: @"member"];
    [doc setObject: group2 forKey: @"group2"];
    
    doc = [self saveDocument: doc];
    
    member1 = [[doc dictionaryForKey: @"group1"] arrayForKey: @"member"];
    [member1 setObject: @"d" atIndex: 0];
    [member1 setObject: @"e" atIndex: 1];
    [member1 setObject: @"f" atIndex: 2];
    
    member2 = [[doc dictionaryForKey: @"group2"] arrayForKey: @"member"];
    [member2 setObject: @(4) atIndex: 0];
    [member2 setObject: @(5) atIndex: 1];
    [member2 setObject: @(6) atIndex: 2];
    
    doc = [self saveDocument: doc];
    
    NSDictionary* result = @{@"group1": @{@"member": @[@"d", @"e", @"f"]},
                             @"group2": @{@"member": @[@(4), @(5), @(6)]}};
    AssertEqualObjects([doc toDictionary], result);
}


- (void) testSetDictionaryToMultipleKeys {
    CBLDocument* doc = [self createDocument: @"doc1"];
    
    CBLDictionary* address = [[CBLDictionary alloc] init];
    [address setObject: @"1 Main street" forKey: @"street"];
    [address setObject: @"Mountain View" forKey: @"city"];
    [address setObject: @"CA" forKey: @"state"];
    [doc setObject: address forKey: @"shipping"];
    [doc setObject: address forKey: @"billing"];
    
    AssertEqual([doc objectForKey: @"shipping"], address);
    AssertEqual([doc objectForKey: @"billing"], address);
    
    // Update address: both shipping and billing should get the update.
    [address setObject: @"94042" forKey: @"zip"];
    AssertEqualObjects([[doc dictionaryForKey: @"shipping"] stringForKey: @"zip"], @"94042");
    AssertEqualObjects([[doc dictionaryForKey: @"billing"] stringForKey: @"zip"], @"94042");
    
    doc = [self saveDocument: doc];
    
    CBLDictionary* shipping = [doc dictionaryForKey: @"shipping"];
    CBLDictionary* billing = [doc dictionaryForKey: @"billing"];
    
    // After save: both shipping and billing address are now independent to each other
    Assert(shipping != address);
    Assert(billing != address);
    Assert(shipping != billing);
    
    [shipping setObject: @"2 Main street" forKey: @"street"];
    [billing setObject: @"3 Main street" forKey: @"street"];
    
    // Save update:
    doc = [self saveDocument: doc];
    
    AssertEqualObjects([[doc dictionaryForKey: @"shipping"] stringForKey: @"street"], @"2 Main street");
    AssertEqualObjects([[doc dictionaryForKey: @"billing"] stringForKey: @"street"], @"3 Main street");
}


- (void) testSetArrayToMultipleKeys {
    CBLDocument* doc = [self createDocument: @"doc1"];
    
    CBLArray* phones = [[CBLArray alloc] init];
    [phones addObject: @"650-000-0001"];
    [phones addObject: @"650-000-0002"];
    
    [doc setObject: phones forKey: @"mobile"];
    [doc setObject: phones forKey: @"home"];
    
    AssertEqual([doc objectForKey:@"mobile"], phones);
    AssertEqual([doc objectForKey:@"home"], phones);
    
    // Update phones: both mobile and home should get the update
    [phones addObject: @"650-000-0003"];
    AssertEqualObjects([[doc arrayForKey: @"mobile"] toArray],
                       (@[@"650-000-0001", @"650-000-0002", @"650-000-0003"]));
    AssertEqualObjects([[doc arrayForKey: @"home"] toArray],
                       (@[@"650-000-0001", @"650-000-0002", @"650-000-0003"]));
    
    doc = [self saveDocument: doc];
    
    // After save: both mobile and home are not independent to each other
    CBLArray* mobile = [doc arrayForKey: @"mobile"];
    CBLArray* home = [doc arrayForKey: @"home"];
    Assert(mobile != phones);
    Assert(home != phones);
    Assert(mobile != home);
    
    // Update mobile and home:
    [mobile addObject: @"650-000-1234"];
    [home addObject: @"650-000-5678"];
    
    // Save update:
    doc = [self saveDocument: doc];
    
    AssertEqualObjects([[doc arrayForKey: @"mobile"] toArray],
                       (@[@"650-000-0001", @"650-000-0002", @"650-000-0003", @"650-000-1234"]));
    AssertEqualObjects([[doc arrayForKey: @"home"] toArray],
                       (@[@"650-000-0001", @"650-000-0002", @"650-000-0003", @"650-000-5678"]));
}


- (void) failingTestToDictionary {
    CBLDocument* doc1 = [self createDocument: @"doc1"];
    [self populateData: doc1];
    // TODO: Should blob be serialized into JSON dictionary?
}


- (void) testCount {
    CBLDocument* doc = [self createDocument: @"doc1"];
    [self populateData: doc];
    
    AssertEqual(doc.count, 12u);
    AssertEqual(doc.count, [doc toDictionary].count);
    
    doc = [self saveDocument: doc];
    
    AssertEqual(doc.count, 12u);
    AssertEqual([doc toDictionary].count, doc.count);
}


- (void) testRemoveKeys {
    CBLDocument* doc = [self createDocument: @"doc1"];
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
    [self saveDocument: doc];
    
    [doc setObject: nil forKey: @"name"];
    [doc setObject: nil forKey: @"weight"];
    [doc setObject: nil forKey: @"age"];
    [doc setObject: nil forKey: @"active"];;
    [[doc dictionaryForKey: @"address"] setObject: nil forKey: @"city"];
    
    AssertNil([doc stringForKey: @"name"]);
    AssertEqual([doc floatForKey: @"weight"], 0.0);
    AssertEqual([doc doubleForKey: @"weight"], 0.0);
    AssertEqual([doc integerForKey: @"age"], 0);
    AssertEqual([doc booleanForKey: @"active"], NO);
    
    AssertNil([doc objectForKey: @"name"]);
    AssertNil([doc objectForKey: @"weight"]);
    AssertNil([doc objectForKey: @"age"]);
    AssertNil([doc objectForKey: @"active"]);
    AssertNil([[doc dictionaryForKey: @"address"] objectForKey: @"city"]);
    
    CBLDictionary* address = [doc dictionaryForKey: @"address"];
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
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setDictionary: @{ @"type": @"profile",
                           @"name": @"Jason",
                           @"age": @"30",
                           @"address": @{
                                   @"street": @"1 milky way.",
                                   }
                           }];
    
    Assert([doc containsObjectForKey: @"type"]);
    Assert([doc containsObjectForKey: @"name"]);
    Assert([doc containsObjectForKey: @"age"]);
    Assert([doc containsObjectForKey: @"address"]);
    AssertFalse([doc containsObjectForKey: @"weight"]);
}


- (void) failingTestDeleteNewDocument {
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: @"Scott Tiger" forKey: @"name"];
    AssertFalse(doc.isDeleted);
    
    NSError* error;
    AssertFalse([_db deleteDocument: doc error: &error]);
    AssertEqual(error.code, 404);
    AssertFalse(doc.isDeleted);
    AssertEqualObjects([doc objectForKey: @"name"], @"Scott Tiger");
    
}


- (void) testDeleteDocument {
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: @"Scott Tiger" forKey: @"name"];
    AssertFalse(doc.isDeleted);
    
    // Save:
    [self saveDocument: doc];
    
    // Delete:
    NSError* error;
    Assert([_db deleteDocument: doc error: &error]);
    AssertNil(error);
    AssertNil([doc objectForKey: @"name"]);
    AssertEqualObjects([doc toDictionary], @{});
    Assert(doc.isDeleted);
}


- (void) testDictionaryAfterDeleteDocument {
    NSDictionary* dict = @{@"address": @{
                                   @"street": @"1 Main street",
                                   @"city": @"Mountain View",
                                   @"state": @"CA"}
                           };
    CBLDocument* doc = [self createDocument: @"doc1" dictionary: dict];
    [self saveDocument: doc];
    
    CBLDictionary* address = [doc dictionaryForKey: @"address"];
    AssertEqualObjects([address objectForKey: @"street"], @"1 Main street");
    AssertEqualObjects([address objectForKey: @"city"], @"Mountain View");
    AssertEqualObjects([address objectForKey: @"state"], @"CA");
    
    NSError* error;
    Assert([_db deleteDocument: doc error: &error]);
    AssertNil(error);
    AssertNil([doc dictionaryForKey: @"address"]);
    AssertEqualObjects([doc toDictionary], @{});
    
    // The dictionary still has data but is detached:
    AssertEqualObjects([address objectForKey: @"street"], @"1 Main street");
    AssertEqualObjects([address objectForKey: @"city"], @"Mountain View");
    AssertEqualObjects([address objectForKey: @"state"], @"CA");
    
    // Make changes to the dictionary shouldn't affect the document.
    [address setObject: @"94042" forKey: @"zip"];
    AssertNil([doc dictionaryForKey: @"address"]);
    AssertEqualObjects([doc toDictionary], @{});
}


- (void) testArrayAfterDeleteDocument {
    NSDictionary* dict = @{@"members": @[@"a", @"b", @"c"]};
    
    CBLDocument* doc = [self createDocument: @"doc1" dictionary: dict];
    [self saveDocument: doc];
    
    CBLArray* members = [doc arrayForKey: @"members"];
    AssertEqual(members.count, 3u);
    AssertEqualObjects([members objectAtIndex: 0], @"a");
    AssertEqualObjects([members objectAtIndex: 1], @"b");
    AssertEqualObjects([members objectAtIndex: 2], @"c");
    
    NSError* error;
    Assert([_db deleteDocument: doc error: &error]);
    AssertNil(error);
    AssertNil([doc arrayForKey: @"members"]);
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
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: @"profile" forKey: @"type"];
    [doc setObject: @"Scott" forKey: @"name"];
    AssertFalse(doc.isDeleted);
 
    // Purge before save:
    NSError* error;
    AssertFalse([_db purgeDocument: doc error: &error]);
    AssertEqualObjects([doc objectForKey: @"type"], @"profile");
    AssertEqualObjects([doc objectForKey: @"name"], @"Scott");
    
    // Save:
    [self saveDocument: doc];
    AssertFalse(doc.isDeleted);
    
    // Purge:
    Assert([_db purgeDocument: doc error: &error], @"Purging error: %@", error);
    AssertFalse(doc.isDeleted);
}


- (void) testReopenDB {
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: @"str" forKey: @"string"];
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Error saving: %@", error);

    [self reopenDB];

    doc = [self.db documentWithID: @"doc1"];
    AssertEqualObjects([doc stringForKey: @"string"], @"str");
    AssertEqualObjects([doc toDictionary], @{@"string": @"str"});
}


- (void)testBlob {
    NSData* content = [kDocumentTestBlob dataUsingEncoding:NSUTF8StringEncoding];
    NSError* error;
    CBLBlob *data = [[CBLBlob alloc] initWithContentType:@"text/plain" data:content];
    Assert(data, @"Failed to create blob: %@", error);
    
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: data forKey: @"data"];
    [doc setObject: @"Jim" forKey: @"name"];
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    
    CBLDocument* doc1 = [[self.db copy] documentWithID: @"doc1"];
    AssertEqualObjects([doc objectForKey: @"name"], @"Jim");
    Assert([[doc1 objectForKey: @"data"] isKindOfClass:[CBLBlob class]]);
    data = [doc1 objectForKey: @"data"];
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
    
    CBLDocument* doc = [self createDocument: @"doc1"];
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
    
    CBLDocument* doc = [self createDocument: @"doc1"];
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
    NSData* content = [kDocumentTestBlob dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error;
    
    CBLBlob* data = [[CBLBlob alloc] initWithContentType:@"text/plain" data:content];
    Assert(data, @"Failed to create blob: %@", error);
    
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: data forKey: @"data"];
    
    data = [doc objectForKey: @"data"];
    for(int i = 0; i < 5; i++) {
        AssertEqualObjects(data.content, content);
        NSInputStream *contentStream = data.contentStream;
        [contentStream open];
        uint8_t buffer[10];
        NSInteger bytesRead = [contentStream read:buffer maxLength:10];
        [contentStream close];
        AssertEqual(bytesRead, 8);
    }
   
    doc = [self saveDocument: doc];
    
    Assert([[doc objectForKey: @"data"] isKindOfClass:[CBLBlob class]]);
    data = [doc objectForKey: @"data"];
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
    
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: data forKey: @"data"];
    [doc setObject: @"Jim" forKey: @"name"];
    
    doc = [self saveDocument: doc];
    
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


- (void) testEnumeratingKeys {
    CBLDocument* doc = [self createDocument: @"doc1"];
    for (NSInteger i = 0; i < 20; i++) {
        [doc setObject: @(i) forKey: [NSString stringWithFormat:@"key%ld", (long)i]];
    }
    NSDictionary* content = [doc toDictionary];
    
    __block NSMutableDictionary* result = [NSMutableDictionary dictionary];
    __block NSUInteger count = 0;
    for (NSString* key in doc) {
        result[key] = [doc objectForKey: key];
        count++;
    }
    AssertEqualObjects(result, content);
    AssertEqual(count, content.count);
    
    // Update:
    
    [doc setObject: nil forKey: @"key2"];
    [doc setObject: @(20) forKey: @"key20"];
    [doc setObject: @(21) forKey: @"key21"];
    content = [doc toDictionary];
    
    [self saveDocument: doc eval:^(CBLDocument *d) {
        result = [NSMutableDictionary dictionary];
        count = 0;
        for (NSString* key in d) {
            result[key] = [d objectForKey: key];
            count++;
        }
        AssertEqualObjects(result, content);
        AssertEqual(count, content.count);
    }];
}


@end
