//
//  SubdocumentTest.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 2/13/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLInternal.h"
#import "CBLJSON.h"

@interface SubdocumentTest : CBLTestCase

@end

@implementation SubdocumentTest
{
    CBLDocument* doc;
}


- (void) setUp {
    [super setUp];

    doc = [self.db documentWithID: @"doc1"];
}


- (void) tearDown {
    // Avoid "Closing database with 1 unsaved docs" warning:
    [doc revert];
    
    [super tearDown];
}


- (void) testNewSubdoc {
    AssertNil([doc subdocumentForKey: @"address"]);
    AssertNil(doc[@"address"]);
    
    CBLSubdocument* address = [[CBLSubdocument alloc] init];
    AssertNil(address.document);
    AssertNil(address.parent);
    AssertNil(address.properties);
    AssertFalse(address.exists);
    
    address[@"street"] = @"1 Space Ave.";
    AssertEqualObjects(address[@"street"], @"1 Space Ave.");
    AssertEqualObjects(address.properties, (@{@"street": @"1 Space Ave."}));
    
    doc[@"address"] = address;
    AssertEqualObjects([doc subdocumentForKey: @"address"], address);
    AssertEqualObjects(doc[@"address"], address);
    AssertEqualObjects(address.document, doc);
    AssertEqualObjects(address.parent, doc);
    
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);
    Assert(address.exists);
    AssertEqualObjects(address[@"street"], @"1 Space Ave.");
    AssertEqualObjects(address.properties, (@{@"street": @"1 Space Ave."}));
    AssertEqualObjects(address.document, doc);
    AssertEqualObjects(address.parent, doc);
    AssertEqualObjects(doc.properties, (@{@"address": address}));
    
    [self reopenDB];
    
    doc = [self.db documentWithID: @"doc1"];
    address = [doc subdocumentForKey: @"address"];
    Assert(address.exists);
    AssertEqualObjects(address[@"street"], @"1 Space Ave.");
    AssertEqualObjects(address.properties, (@{@"street": @"1 Space Ave."}));
    AssertEqualObjects(address.document, doc);
    AssertEqualObjects(address.parent, doc);
    AssertEqualObjects(doc.properties, (@{@"address": address}));
}


- (void) testGetSubdoc {
    CBLSubdocument* address = [doc subdocumentForKey: @"address"];
    AssertNil(address);
    
    doc.properties = @{@"address": @{@"street": @"1 Space Ave."}};
    
    address = [doc subdocumentForKey: @"address"];
    Assert(address);
    AssertEqualObjects(address.document, doc);
    AssertEqualObjects(address.parent, doc);
    AssertEqualObjects(address.properties, (@{@"street": @"1 Space Ave."}));
    AssertEqualObjects(address[@"street"], @"1 Space Ave.");
    
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);
    
    [self reopenDB];
    
    doc = [self.db documentWithID: @"doc1"];
    address = [doc subdocumentForKey: @"address"];
    Assert(address);
    AssertEqualObjects(address.document, doc);
    AssertEqualObjects(address.parent, doc);
    Assert(address.exists);
    AssertEqualObjects(address[@"street"], @"1 Space Ave.");
    AssertEqualObjects(address.properties, (@{@"street": @"1 Space Ave."}));
}


- (void) testNestedSubdocs {
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


- (void) testSetProperties {
    doc.properties = @{ @"name": @"Jason",
                        @"address": @{
                                @"street": @"1 Star Way.",
                                @"phones": @{@"mobile": @"650-123-4567"}
                                },
                        @"references": @[@{@"name": @"Scott"}, @{@"name": @"Sam"}]
                        };
    
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);
    
    AssertEqualObjects(doc[@"name"], @"Jason");
    
    CBLSubdocument* address = doc[@"address"];
    AssertEqualObjects(address.document, doc);
    AssertEqualObjects(address.parent, doc);
    Assert([address exists]);
    AssertEqualObjects(address[@"street"], @"1 Star Way.");
    
    CBLSubdocument* phones = address[@"phones"];
    AssertEqualObjects(phones.document, doc);
    AssertEqualObjects(phones.parent, address);
    Assert([phones exists]);
    AssertEqualObjects(phones[@"mobile"], @"650-123-4567");
    
    NSArray* references = doc[@"references"];
    AssertEqual([references count], 2u);
    
    CBLSubdocument* r1 = references[0];
    AssertEqualObjects(r1.document, doc);
    AssertEqualObjects(r1.parent, doc);
    Assert([r1 exists]);
    AssertEqualObjects(r1[@"name"], @"Scott");
    
    CBLSubdocument* r2 = references[1];
    AssertEqualObjects(r2.document, doc);
    AssertEqualObjects(r2.parent, doc);
    Assert([r2 exists]);
    AssertEqualObjects(r2[@"name"], @"Sam");
}


- (void) testCopySubdocument {
    doc.properties = @{ @"name": @"Jason",
                        @"address": @{
                                @"street": @"1 Star Way.",
                                @"phones": @{@"mobile": @"650-123-4567"}
                                }
                        };
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);
    
    CBLSubdocument* address = doc[@"address"];
    AssertEqualObjects(address.document, doc);
    AssertEqualObjects(address.parent, doc);
    
    CBLSubdocument* phones = address[@"phones"];
    AssertEqualObjects(phones.document, doc);
    AssertEqualObjects(phones.parent, address);
    
    CBLSubdocument* address2 = [address copy];
    AssertFalse(address2 == address);
    AssertNil(address2.document);
    AssertNil(address2.parent);
    AssertEqualObjects(address2[@"street"], address[@"street"]);
    
    CBLSubdocument* phones2 = address2[@"phones"];
    AssertFalse(phones2 == phones);
    AssertNil(phones2.document);
    AssertEqualObjects(phones2.parent, address2);
    AssertEqualObjects(phones2[@"mobile"], phones[@"mobile"]);
}


- (void) testSetSubdocumentFromAnotherKey {
    doc.properties = @{ @"name": @"Jason",
                        @"address": @{
                                @"street": @"1 Star Way.",
                                @"phones": @{@"mobile": @"650-123-4567"}
                                }
                        };
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);
    
    CBLSubdocument* address = doc[@"address"];
    AssertEqualObjects(address.document, doc);
    AssertEqualObjects(address.parent, doc);
    
    CBLSubdocument* phones = address[@"phones"];
    AssertEqualObjects(phones.document, doc);
    AssertEqualObjects(phones.parent, address);
    
    doc[@"address2"] = address;
    CBLSubdocument* address2 = doc[@"address2"];
    AssertFalse(address2 == address);
    AssertEqualObjects(address2.document, doc);
    AssertEqualObjects(address2.parent, doc);
    AssertEqualObjects(address2[@"street"], address[@"street"]);
    
    CBLSubdocument* phones2 = address2[@"phones"];
    AssertFalse(phones2 == phones);
    AssertEqualObjects(phones2.document, doc);
    AssertEqualObjects(phones2.parent, address2);
    AssertEqualObjects(phones2[@"mobile"], phones[@"mobile"]);
}


- (void) testSubdocumentArray {
    NSArray* dicts = @[@{@"name": @"1"}, @{@"name": @"2"}, @{@"name": @"3"}, @{@"name": @"4"}];
    doc.properties = @{@"subdocs": dicts};
    
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);
    
    NSArray* subdocs = doc[@"subdocs"];
    AssertEqual([subdocs count], 4u);
    
    CBLSubdocument* s1 = subdocs[0];
    CBLSubdocument* s2 = subdocs[1];
    CBLSubdocument* s3 = subdocs[2];
    CBLSubdocument* s4 = subdocs[3];
    
    AssertEqualObjects(s1[@"name"], @"1");
    AssertEqualObjects(s2[@"name"], @"2");
    AssertEqualObjects(s3[@"name"], @"3");
    AssertEqualObjects(s4[@"name"], @"4");
    
    // Make Changes:
    
    CBLSubdocument* s5 = [CBLSubdocument subdocument];
    s5[@"name"] = @"5";
    
    NSArray* nuSubdocs1 = @[s5, @"dummy", s2, @{@"name": @"6"}, s1];
    doc[@"subdocs"] = nuSubdocs1;
    
    NSArray* nuSubdocs2 = doc[@"subdocs"];
    AssertEqual([nuSubdocs2 count], 5u);
    AssertEqualObjects(nuSubdocs2[0], s5);
    AssertEqualObjects(nuSubdocs2[1], @"dummy");
    AssertEqualObjects(nuSubdocs2[2], s2);
    AssertEqualObjects(nuSubdocs2[3], s4);
    AssertEqualObjects(nuSubdocs2[4], s1);
    
    AssertEqualObjects(s1[@"name"], @"1");
    AssertEqualObjects(s2[@"name"], @"2");
    AssertNil(s3[@"name"]); // Invalidated
    AssertNil(s3.document);
    AssertEqualObjects(s4[@"name"], @"6");
    AssertEqualObjects(s5[@"name"], @"5");
}


- (void) testNilSubdocument {
    doc.properties = @{ @"name": @"Jason",
                        @"address": @{
                                @"street": @"1 Star Way.",
                                @"phones": @{@"mobile": @"650-123-4567"}
                                },
                        @"references": @[@{@"name": @"Scott"}, @{@"name": @"Sam"}]
                        };
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);
    
    CBLSubdocument* address = doc[@"address"];
    CBLSubdocument* phones = address[@"phones"];
    AssertNotNil(address);
    AssertNotNil(phones);
    
    NSArray* references = doc[@"references"];
    AssertEqual([references count], 2u);
    CBLSubdocument* r1 = references[0];
    CBLSubdocument* r2 = references[1];
    AssertNotNil(r1);
    AssertNotNil(r2);
    
    doc[@"address"] = nil;
    AssertNil(address.document);
    AssertNil(address.parent);
    AssertFalse([address exists]);
    AssertNil(address.properties);
    AssertNil(address[@"street"]);
    AssertNil(address[@"phones"]);
    
    AssertNil(phones.document);
    AssertNil(phones.parent);
    AssertFalse([phones exists]);
    AssertNil(phones.properties);
    AssertNil(phones[@"mobile"]);
    
    doc[@"references"] = nil;
    
    AssertNil(r1.document);
    AssertNil(r1.parent);
    AssertFalse([r1 exists]);
    AssertNil(r1.properties);
    AssertNil(r1[@"name"]);
    
    AssertNil(r2.document);
    AssertNil(r2.parent);
    AssertFalse([r2 exists]);
    AssertNil(r2.properties);
    AssertNil(r2[@"name"]);
    
    doc[@"name"] = nil;
    AssertEqualObjects(doc.properties, @{});
}


- (void) testNilProperties {
    doc.properties = @{ @"name": @"Jason",
                        @"address": @{
                                @"street": @"1 Star Way.",
                                @"phones": @{@"mobile": @"650-123-4567"}
                                },
                        @"references": @[@{@"name": @"Scott"}, @{@"name": @"Sam"}]
                        };
    
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);
    
    AssertNotNil(doc[@"name"]);
    
    CBLSubdocument* address = doc[@"address"];
    CBLSubdocument* phones = address[@"phones"];
    AssertNotNil(address);
    AssertNotNil(phones);
    
    NSArray* references = doc[@"references"];
    AssertEqual([references count], 2u);
    CBLSubdocument* r1 = references[0];
    CBLSubdocument* r2 = references[1];
    AssertNotNil(r1);
    AssertNotNil(r2);
    
    doc.properties = nil;
    
    AssertNil(doc.properties);
    AssertNil(doc[@"name"]);
    AssertNil(doc[@"addresses"]);
    AssertNil(doc[@"references"]);
    
    AssertNil(address.document);
    AssertNil(address.parent);
    AssertFalse([address exists]);
    AssertNil(address.properties);
    AssertNil(address[@"street"]);
    AssertNil(address[@"phones"]);
    
    AssertNil(phones.document);
    AssertNil(phones.parent);
    AssertFalse([phones exists]);
    AssertNil(phones.properties);
    AssertNil(phones[@"mobile"]);
    
    AssertNil(r1.document);
    AssertNil(r1.parent);
    AssertFalse([r1 exists]);
    AssertNil(r1.properties);
    AssertNil(r1[@"name"]);
    
    AssertNil(r2.document);
    AssertNil(r2.parent);
    AssertFalse([r2 exists]);
    AssertNil(r2.properties);
    AssertNil(r2[@"name"]);
}


- (void) testReplaceWithNonDict {
    CBLSubdocument* address = [CBLSubdocument subdocument];
    address[@"street"] = @"1 Star Way.";
    AssertEqualObjects(address[@"street"], @"1 Star Way.");
    AssertEqualObjects(address.properties, (@{@"street": @"1 Star Way."}));
    
    doc[@"address"] = address;
    AssertEqualObjects(doc[@"address"], address);
    AssertEqualObjects(address.document, doc);
    
    doc[@"address"] = @"123 Space Dr.";
    AssertNil(address.document);
    AssertNil(address.properties);
    AssertEqualObjects(doc.properties, @{@"address": @"123 Space Dr."});
    AssertEqualObjects(doc[@"address"], @"123 Space Dr.");
    
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);
}


- (void) testDeleteDocument {
    doc.properties = @{ @"name": @"Jason",
                        @"address": @{
                                @"street": @"1 Star Way.",
                                @"phones": @{@"mobile": @"650-123-4567"}
                                },
                        @"references": @[@{@"name": @"Scott"}, @{@"name": @"Sam"}]
                        };
    
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);
    
    AssertNotNil(doc[@"name"]);
    
    CBLSubdocument* address = doc[@"address"];
    CBLSubdocument* phones = address[@"phones"];
    AssertNotNil(address);
    AssertNotNil(phones);
    
    NSArray* references = doc[@"references"];
    AssertEqual([references count], 2u);
    CBLSubdocument* r1 = references[0];
    CBLSubdocument* r2 = references[1];
    AssertNotNil(r1);
    AssertNotNil(r2);

    Assert([doc deleteDocument: &error], @"Deleting error: %@", error);
    Assert(doc.exists);
    AssertNil(doc.properties);
    AssertNil(doc[@"name"]);
    AssertNil(doc[@"addresses"]);
    AssertNil(doc[@"references"]);
    
    AssertNil(address.document);
    AssertNil(address.parent);
    AssertFalse([address exists]);
    AssertNil(address.properties);
    AssertNil(address[@"street"]);
    AssertNil(address[@"phones"]);
    
    AssertNil(phones.document);
    AssertNil(phones.parent);
    AssertFalse([phones exists]);
    AssertNil(phones.properties);
    AssertNil(phones[@"mobile"]);
    
    AssertNil(r1.document);
    AssertNil(r1.parent);
    AssertFalse([r1 exists]);
    AssertNil(r1.properties);
    AssertNil(r1[@"name"]);
    
    AssertNil(r2.document);
    AssertNil(r2.parent);
    AssertFalse([r2 exists]);
    AssertNil(r2.properties);
    AssertNil(r2[@"name"]);
}


@end
