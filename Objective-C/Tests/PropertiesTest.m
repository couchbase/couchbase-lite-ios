
//
//  PropertiesTest.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/24/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLJSON.h"

@interface PropertiesTest : CBLTestCase

@end

@implementation PropertiesTest


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
    
    // NSNull:
    [doc setObject: [NSNull null] forKey: @"null"];
    [doc setObject: @[[NSNull null], [NSNull null]] forKey: @"nullarray"];
    
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
    
    // NSNull:
    AssertEqualObjects([doc objectForKey: @"null"], [NSNull null]);
    AssertEqualObjects([doc objectForKey: @"nullarray"], (@[[NSNull null], [NSNull null]]));
    
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


- (void) testGetProperties {
    CBLDocument* doc = self.db[@"doc1"];
    doc[@"type"] = @"demo";
    doc[@"weight"] = @12.5;
    doc[@"tags"] = @[@"useless", @"temporary"];
    
    AssertEqualObjects(doc[@"type"], @"demo");
    AssertEqual([doc doubleForKey: @"weight"], 12.5);
    AssertEqualObjects(doc.properties,
                       (@{@"type": @"demo", @"weight": @12.5, @"tags": @[@"useless", @"temporary"]}));
}


- (void) testGetSetProperties {
    CBLDocument* doc = self.db[@"doc1"];
    doc.properties =
        @{ @"type": @"profile",
           @"name": @"Jason",
           @"weight": @130.5,
           @"active": @YES,
           @"address": @{
                   @"street": @"1 milky way.",
                   @"city": @"galaxy city",
                   @"zip" : @12345
           }
        };
    
    AssertEqualObjects(doc[@"type"], @"profile");
    AssertEqualObjects(doc[@"name"], @"Jason");
    AssertEqual([doc doubleForKey: @"weight"], 130.5);
    
    CBLSubdocument* address = doc[@"address"];
    AssertNotNil(address);
    AssertEqualObjects(address[@"street"], @"1 milky way.");
    AssertEqualObjects(address[@"city"], @"galaxy city");
    AssertEqual([address integerForKey: @"zip"], 12345);
    
    AssertEqualObjects(doc.properties, (
        @{ @"type": @"profile",
           @"name": @"Jason",
           @"weight": @130.5,
           @"active": @YES,
           @"address": address
           }));
}


- (void) testRemoveKeys {
    CBLDocument* doc = self.db[@"doc1"];
    doc.properties =
        @{ @"type": @"profile",
           @"name": @"Jason",
           @"weight": @130.5,
           @"active": @YES,
           @"address": @{
                   @"street": @"1 milky way.",
                   @"city": @"galaxy city",
                   @"zip" : @12345
                   }
           };
    
    AssertEqual([doc doubleForKey: @"weight"], 130.5);
    AssertEqualObjects(doc[@"address"][@"city"], @"galaxy city");
    
    doc[@"weight"] = nil;
    doc[@"address"][@"city"] = nil;
    
    AssertEqual([doc doubleForKey: @"weight"], 0.0);
    AssertNil(doc[@"weight"]);
    AssertNil(doc[@"address"][@"city"]);
    
    CBLSubdocument* address = doc[@"address"];
    AssertEqualObjects(doc.properties, (
        @{ @"type": @"profile",
           @"name": @"Jason",
           @"active": @YES,
           @"address": address
           }));
    AssertEqualObjects(address.properties, (
        @{ @"street": @"1 milky way.",
           @"zip" : @12345
           }));
}


- (void) testContainsKey {
    CBLDocument* doc = self.db[@"doc1"];
    doc.properties =
        @{ @"type": @"profile",
           @"name": @"Jason",
           @"address": @{
                   @"street": @"1 milky way.",
                   }
           };
    Assert([doc containsObjectForKey: @"type"]);
    Assert([doc containsObjectForKey: @"name"]);
    Assert([doc containsObjectForKey: @"address"]);
    AssertFalse([doc containsObjectForKey: @"weight"]);
    Assert([doc[@"address"] containsObjectForKey: @"street"]);
    AssertFalse([doc[@"address"] containsObjectForKey: @"city"]);
}


@end
