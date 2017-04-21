//
//  SubdocumentTest.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 2/13/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"

@interface SubdocumentTest : CBLTestCase

@end

@implementation SubdocumentTest


- (void) testCreateSubdocument {
    CBLSubdocument* address = [[CBLSubdocument alloc] init];
    AssertEqual(address.count, 0u);
    AssertEqualObjects([address toDictionary], @{});
    
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc1 setObject: address forKey: @"address"];
    AssertEqual([doc1 subdocumentForKey: @"address"], address);
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Saving error: %@", error);
    doc1 = [_db documentWithID: @"doc1"];
    AssertEqualObjects([[doc1 subdocumentForKey: @"address"] toDictionary], @{});
}


- (void) testCreateSubdocumentWithDict {
    NSDictionary* dict = @{@"street": @"1 Main street",
                           @"city": @"Mountain View",
                           @"state": @"CA"};
    CBLSubdocument* address = [[CBLSubdocument alloc] initWithDictionary: dict];
    AssertEqualObjects([address objectForKey: @"street"], @"1 Main street");
    AssertEqualObjects([address objectForKey: @"city"], @"Mountain View");
    AssertEqualObjects([address objectForKey: @"state"], @"CA");
    AssertEqualObjects([address toDictionary], dict);
    
    CBLDocument* doc1 = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc1 setObject: address forKey: @"address"];
    AssertEqual([doc1 subdocumentForKey: @"address"], address);
    
    NSError* error;
    Assert([_db saveDocument: doc1 error: &error], @"Saving error: %@", error);
    doc1 = [_db documentWithID: @"doc1"];
    AssertEqualObjects([[doc1 subdocumentForKey: @"address"] toDictionary], dict);
}


- (void) testGetValueFromNewEmptySubdoc {
    CBLSubdocument* subdoc = [[CBLSubdocument alloc] init];
    
    AssertEqual([subdoc integerForKey: @"key"], 0);
    AssertEqual([subdoc floatForKey: @"key"], 0.0f);
    AssertEqual([subdoc doubleForKey: @"key"], 0.0);
    AssertEqual([subdoc booleanForKey: @"key"], NO);
    AssertNil([subdoc blobForKey: @"key"]);
    AssertNil([subdoc dateForKey: @"key"]);
    AssertNil([subdoc numberForKey: @"key"]);
    AssertNil([subdoc objectForKey: @"key"]);
    AssertNil([subdoc stringForKey: @"key"]);
    AssertNil([subdoc subdocumentForKey: @"key"]);
    AssertNil([subdoc arrayForKey: @"key"]);
    AssertEqualObjects([subdoc toDictionary], @{});
    
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc setObject: subdoc forKey: @"subdoc"];
    
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    subdoc = [doc subdocumentForKey: @"subdoc"];
    AssertEqual([subdoc integerForKey: @"key"], 0);
    AssertEqual([subdoc floatForKey: @"key"], 0.0f);
    AssertEqual([subdoc doubleForKey: @"key"], 0.0);
    AssertEqual([subdoc booleanForKey: @"key"], NO);
    AssertNil([subdoc blobForKey: @"key"]);
    AssertNil([subdoc dateForKey: @"key"]);
    AssertNil([subdoc numberForKey: @"key"]);
    AssertNil([subdoc objectForKey: @"key"]);
    AssertNil([subdoc stringForKey: @"key"]);
    AssertNil([subdoc subdocumentForKey: @"key"]);
    AssertNil([subdoc arrayForKey: @"key"]);
    AssertEqualObjects([subdoc toDictionary], @{});
}


- (void) testSetNestedSubdocuments {
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    
    CBLSubdocument *level1 = [[CBLSubdocument alloc] init];
    [level1 setObject: @"n1" forKey: @"name"];
    [doc setObject: level1 forKey: @"level1"];
    
    CBLSubdocument *level2 = [CBLSubdocument subdocument];
    [level2 setObject: @"n2" forKey: @"name"];
    [level1 setObject: level2 forKey: @"level2"];
    
    CBLSubdocument *level3 = [CBLSubdocument subdocument];
    [level3 setObject: @"n3" forKey: @"name"];
    [level2 setObject: level3 forKey: @"level3"];
    
    AssertEqualObjects([doc subdocumentForKey: @"level1"], level1);
    AssertEqualObjects([level1 subdocumentForKey: @"level2"], level2);
    AssertEqualObjects([level2 subdocumentForKey: @"level3"], level3);
    NSDictionary* dict = @{@"level1": @{@"name": @"n1",
                                        @"level2": @{@"name": @"n2",
                                                     @"level3": @{@"name": @"n3"}}}};
    AssertEqualObjects([doc toDictionary], dict);
    
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    Assert([doc subdocumentForKey: @"level1"] != level1);
    level1 = [doc subdocumentForKey: @"level1"];
    level2 = [level1 subdocumentForKey: @"level2"];
    level3 = [level2 subdocumentForKey: @"level3"];
    
    AssertEqualObjects([level1 subdocumentForKey: @"level2"], level2);
    AssertEqualObjects([level2 subdocumentForKey: @"level3"], level3);
    AssertEqualObjects([doc toDictionary], dict);
}


- (void) testSubdocumentArray {
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    NSArray* dicts = @[@{@"name": @"1"}, @{@"name": @"2"}, @{@"name": @"3"}, @{@"name": @"4"}];
    [doc setDictionary: @{@"subdocs": dicts}];
    
    CBLArray* subdocs = [doc arrayForKey: @"subdocs"];
    AssertEqual(subdocs.count, 4u);
    
    CBLSubdocument* s1 = [subdocs subdocumentAtIndex: 0];
    CBLSubdocument* s2 = [subdocs subdocumentAtIndex: 1];
    CBLSubdocument* s3 = [subdocs subdocumentAtIndex: 2];
    CBLSubdocument* s4 = [subdocs subdocumentAtIndex: 3];
    
    AssertEqualObjects([s1 stringForKey: @"name"], @"1");
    AssertEqualObjects([s2 stringForKey: @"name"], @"2");
    AssertEqualObjects([s3 stringForKey: @"name"], @"3");
    AssertEqualObjects([s4 stringForKey: @"name"], @"4");
    
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    subdocs = [doc arrayForKey: @"subdocs"];
    AssertEqual(subdocs.count, 4u);
    
    s1 = [subdocs subdocumentAtIndex: 0];
    s2 = [subdocs subdocumentAtIndex: 1];
    s3 = [subdocs subdocumentAtIndex: 2];
    s4 = [subdocs subdocumentAtIndex: 3];
    
    AssertEqualObjects([s1 stringForKey: @"name"], @"1");
    AssertEqualObjects([s2 stringForKey: @"name"], @"2");
    AssertEqualObjects([s3 stringForKey: @"name"], @"3");
    AssertEqualObjects([s4 stringForKey: @"name"], @"4");
}


- (void) testReplaceSubdocument {
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    CBLSubdocument *profile1 = [[CBLSubdocument alloc] init];
    [profile1 setObject: @"Scott Tiger" forKey: @"name"];
    [doc setObject: profile1 forKey: @"profile"];
    AssertEqualObjects([doc subdocumentForKey: @"profile"], profile1);
    
    CBLSubdocument *profile2 = [[CBLSubdocument alloc] init];
    [profile2 setObject: @"Daniel Tiger" forKey: @"name"];
    [doc setObject: profile2 forKey: @"profile"];
    AssertEqualObjects([doc subdocumentForKey: @"profile"], profile2);
    
    // Profile1 should be now detached:
    [profile1 setObject: @(20) forKey: @"age"];
    AssertEqualObjects([profile1 objectForKey: @"name"], @"Scott Tiger");
    AssertEqualObjects([profile1 objectForKey: @"age"], @(20));
    
    // Check profile2:
    AssertEqualObjects([profile2 objectForKey: @"name"], @"Daniel Tiger");
    AssertNil([profile2 objectForKey: @"age"]);
    
    // Save:
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    Assert([doc subdocumentForKey: @"profile"] != profile2);
    profile2 = [doc subdocumentForKey: @"profile"];
    AssertEqualObjects([profile2 objectForKey: @"name"], @"Daniel Tiger");
}


- (void) testReplaceSubdocumentDifferentType {
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    CBLSubdocument *profile1 = [[CBLSubdocument alloc] init];
    [profile1 setObject: @"Scott Tiger" forKey: @"name"];
    [doc setObject: profile1 forKey: @"profile"];
    AssertEqualObjects([doc subdocumentForKey: @"profile"], profile1);
    
    // Set string value to profile:
    [doc setObject: @"Daniel Tiger" forKey: @"profile"];
    AssertEqualObjects([doc objectForKey: @"profile"], @"Daniel Tiger");
    
    // Profile1 should be now detached:
    [profile1 setObject: @(20) forKey: @"age"];
    AssertEqualObjects([profile1 objectForKey: @"name"], @"Scott Tiger");
    AssertEqualObjects([profile1 objectForKey: @"age"], @(20));

    // Check whether the profile value has no change:
    AssertEqualObjects([doc objectForKey: @"profile"], @"Daniel Tiger");
    
    // Save:
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    AssertEqualObjects([doc objectForKey: @"profile"], @"Daniel Tiger");
}


@end
