//
//  SubdocumentTest.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/17/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLInternal.h"
#import "CBLJSON.h"

@interface SubdocumentTest : CBLTestCase

@end

@implementation SubdocumentTest


- (void) testNewSubdoc {
    CBLDocument* doc = [self.db documentWithID: @"profile1"];
    AssertNil([doc subdocumentForKey: @"address"]);
    AssertNil(doc[@"address"]);
    
    CBLSubdocument* address = [[CBLSubdocument alloc] init];
    AssertNil(address.document);
    AssertNil(address.properties);
    AssertFalse(address.exists);
    
    address[@"street"] = @"1 Space Ave.";
    AssertEqualObjects(address[@"street"], @"1 Space Ave.");
    AssertEqualObjects(address.properties, (@{@"street": @"1 Space Ave."}));
    
    doc[@"address"] = address;
    AssertEqualObjects([doc subdocumentForKey: @"address"], address);
    AssertEqualObjects(doc[@"address"], address);
    AssertEqualObjects(address.document, doc);
    
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);
    Assert(address.exists);
    AssertEqualObjects(address[@"street"], @"1 Space Ave.");
    AssertEqualObjects(address.properties, (@{@"street": @"1 Space Ave."}));
    AssertEqualObjects(doc.properties, (@{@"address": address}));
    
    doc = [[self.db copy] documentWithID: @"profile1"];
    address = [doc subdocumentForKey: @"address"];
    Assert(address.exists);
    AssertEqualObjects(address[@"street"], @"1 Space Ave.");
    AssertEqualObjects(address.properties, (@{@"street": @"1 Space Ave."}));
    AssertEqualObjects(doc.properties, (@{@"address": address}));
}


- (void) testGetSubdoc {
    CBLDocument* doc = [self.db documentWithID: @"profile1"];
    CBLSubdocument* address = [doc subdocumentForKey: @"address"];
    AssertNil(address);
    
    doc.properties = @{@"address": @{@"street": @"1 Space Ave."}};
    
    address = [doc subdocumentForKey: @"address"];
    Assert(address);
    AssertEqualObjects(address.document, doc);
    AssertEqualObjects(address.properties, (@{@"street": @"1 Space Ave."}));
    AssertEqualObjects(address[@"street"], @"1 Space Ave.");
    
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);

    doc = [[self.db copy] documentWithID: @"profile1"];
    address = [doc subdocumentForKey: @"address"];
    Assert(address);
    AssertEqualObjects(address.document, doc);
    Assert(address.exists);
    AssertEqualObjects(address[@"street"], @"1 Space Ave.");
    AssertEqualObjects(address.properties, (@{@"street": @"1 Space Ave."}));
}


- (void) testPropertyAccessors {
    CBLSubdocument* subdoc = [CBLSubdocument subdocument];
    
    // Setter:
    // Premitives:
    [subdoc setBoolean: YES forKey: @"bool"];
    [subdoc setDouble: 1.1 forKey: @"double"];
    [subdoc setFloat: 1.2f forKey: @"float"];
    [subdoc setInteger: 2 forKey: @"integer"];
    
    // Objects:
    [subdoc setObject: @"str" forKey: @"string"];
    [subdoc setObject: @(YES) forKey: @"boolObj"];
    [subdoc setObject: @(1) forKey: @"number"];
    [subdoc setObject: @[@"string", @(1), @(YES), @{@"foo": @"bar"}] forKey: @"array"];
    
    // Date:
    NSDate* date = [NSDate date];
    [subdoc setObject: date forKey: @"date"];
    
    // Getter:
    // Primitives:
    AssertEqual([subdoc booleanForKey: @"bool"], YES);
    AssertEqual([subdoc doubleForKey: @"double"], 1.1);
    AssertEqual([subdoc floatForKey: @"float"], @(1.2).floatValue);
    AssertEqual([subdoc integerForKey: @"integer"], 2);
    
    // Objects:
    AssertEqualObjects([subdoc stringForKey: @"string"], @"str");
    AssertEqualObjects([subdoc objectForKey: @"boolObj"], @(YES));
    AssertEqualObjects([subdoc objectForKey: @"number"], @(1));
    AssertEqualObjects([subdoc objectForKey: @"array"],
                       (@[@"string", @(1), @(YES), @{@"foo": @"bar"}]));
    
    // Date:
    AssertEqualObjects([CBLJSON JSONObjectWithDate: [subdoc dateForKey: @"date"]],
                       [CBLJSON JSONObjectWithDate: date]);
}


- (void) testUnsupportedDataType {
    CBLSubdocument* subdoc = [CBLSubdocument subdocument];
    XCTAssertThrows([subdoc setObject: [[NSMapTable alloc] init] forKey: @"table"]);
    XCTAssertThrows([subdoc setObject: @[[NSDate date]] forKey: @"dates"]);
    XCTAssertThrows([subdoc setObject: @[[CBLSubdocument subdocument]] forKey: @"subdocs"]);
}


- (void) testNestedSubdocs {
    CBLDocument* doc = [self.db documentWithID: @"doc1"];
    AssertNil(doc.properties);
    
    doc[@"level1"] = [CBLSubdocument subdocument];
    doc[@"level1"][@"name"] = @"n1";
    
    doc[@"level1"][@"level2"] = [CBLSubdocument subdocument];
    doc[@"level1"][@"level2"][@"name"] = @"n2";
    
    doc[@"level1"][@"level2"][@"level3"] = [CBLSubdocument subdocument];
    doc[@"level1"][@"level2"][@"level3"][@"name"] = @"n3";
    
    CBLSubdocument *level1 = doc[@"level1"];
    CBLSubdocument *level2 = doc[@"level1"][@"level2"];
    CBLSubdocument *level3 = doc[@"level1"][@"level2"][@"level3"];
    
    AssertFalse(level1.exists);
    AssertFalse(level2.exists);
    AssertFalse(level3.exists);
    
    AssertEqualObjects(doc.properties, (@{@"level1": level1}));
    AssertEqualObjects(level1.properties, (@{@"name": @"n1", @"level2": level2}));
    AssertEqualObjects(level2.properties, (@{@"name": @"n2", @"level3": level3}));
    AssertEqualObjects(level3.properties, (@{@"name": @"n3"}));
    
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);
    Assert(level1.exists);
    Assert(level2.exists);
    Assert(level3.exists);
}


- (void) testGetSetDictionary {
    CBLDocument* doc = [self.db documentWithID: @"profile1"];
    AssertNil(doc.properties);
    AssertNil(doc[@"address"]);
    doc[@"address"] = @{@"street": @"1 Space Ave."};
    
    CBLSubdocument* address = doc[@"address"];
    AssertEqualObjects(address.properties, @{@"street": @"1 Space Ave."});
    
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);
    Assert(address.exists);
    AssertEqualObjects(address, doc[@"address"]);
    AssertEqualObjects(address.properties, @{@"street": @"1 Space Ave."});
}


- (void) testNullify {
    CBLDocument* doc = [self.db documentWithID: @"profile1"];
    
    CBLSubdocument* address = [CBLSubdocument subdocument];
    address[@"street"] = @"1 Space Ave.";
    AssertEqualObjects(address[@"street"], @"1 Space Ave.");
    AssertEqualObjects(address.properties, (@{@"street": @"1 Space Ave."}));
    
    doc[@"address"] = address;
    AssertEqualObjects(doc[@"address"], address);
    AssertEqualObjects(address.document, doc);
    
    doc[@"address"] = nil;
    AssertNil(address.document);
    AssertNil(address.properties);
    AssertEqualObjects(doc.properties, @{});
    
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);
}



- (void) testReplaceNonDict {
    CBLDocument* doc = [self.db documentWithID: @"profile1"];
    
    CBLSubdocument* address = [CBLSubdocument subdocument];
    address[@"street"] = @"1 Space Ave.";
    AssertEqualObjects(address[@"street"], @"1 Space Ave.");
    AssertEqualObjects(address.properties, (@{@"street": @"1 Space Ave."}));
    
    doc[@"address"] = address;
    AssertEqualObjects(doc[@"address"], address);
    AssertEqualObjects(address.document, doc);
    
    doc[@"address"] = @"123 Galaxy Dr.";
    AssertNil(address.document);
    AssertNil(address.properties);
    AssertEqualObjects(doc.properties, @{@"address": @"123 Galaxy Dr."});
    AssertEqualObjects(doc[@"address"], @"123 Galaxy Dr.");
    
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);
}


- (void) testDeleteDocument {
    CBLDocument* doc = [self.db documentWithID: @"profile1"];
    
    CBLSubdocument* address = [CBLSubdocument subdocument];
    address[@"street"] = @"1 Space Ave.";
    doc[@"address"] = address;
    AssertEqualObjects(address.document, doc);
    
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);
    
    Assert(address.exists);
    AssertEqualObjects(address.document, doc);
    AssertEqualObjects(address.properties, @{@"street": @"1 Space Ave."});
    
    Assert([doc deleteDocument: &error], @"Deleting error: %@", error);
    Assert(doc.exists);
    AssertNil(doc.properties);
    AssertNil(address.properties);
    AssertNil(address.document);
    AssertFalse(address.exists);
}


@end
