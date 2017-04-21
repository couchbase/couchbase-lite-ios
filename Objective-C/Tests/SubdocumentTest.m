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
#import "CBLDocument+Internal.h"

@interface SubdocumentTest : CBLTestCase

@end

@implementation SubdocumentTest
{
    CBLDocument* doc;
}


- (void) setUp {
    [super setUp];

    doc = [[CBLDocument alloc] initWithID: @"doc1"];
}


- (void) tearDown {
    [super tearDown];
}


- (void) reopenDB {
    [super reopenDB];
    
    doc = [self.db documentWithID: @"doc1"];
    if (!doc)
        doc = [[CBLDocument alloc] initWithID: @"doc1"];
}


- (void) testNewSubdocument {
    CBLSubdocument* address = [CBLSubdocument subdocument];
    [address setObject: @"1 Space Ave." forKey: @"street"];
    AssertEqualObjects([address stringForKey: @"street"], @"1 Space Ave.");
    
    [doc setObject: address forKey: @"address"];
    AssertEqualObjects([doc subdocumentForKey: @"address"], address);
    
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    
    [self reopenDB];
    
    address = [doc subdocumentForKey: @"address"];
    AssertEqualObjects([address stringForKey: @"street"], @"1 Space Ave.");
}


- (void) testGetSubdocument {
    [doc setDictionary: @{@"address": @{@"street": @"1 Space Ave."}}];
    
    CBLSubdocument* address = [doc subdocumentForKey: @"address"];
    Assert(address);
    AssertEqualObjects([doc subdocumentForKey: @"address"], address);
    AssertEqualObjects([address stringForKey: @"street"], @"1 Space Ave.");
    
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    
    [self reopenDB];
    
    address = [doc subdocumentForKey: @"address"];
    Assert(address);
    AssertEqualObjects([doc subdocumentForKey: @"address"], address);
    AssertEqualObjects([address stringForKey: @"street"], @"1 Space Ave.");
}


- (void) testNestedSubdocuments {
    CBLSubdocument *level1 = [CBLSubdocument subdocument];
    [level1 setObject: @"n1" forKey: @"name"];
    [doc setObject: level1 forKey: @"level1"];
    
    CBLSubdocument *level2 = [CBLSubdocument subdocument];
    [level2 setObject: @"n2" forKey: @"name"];
    [level1 setObject: level2 forKey: @"level2"];
    
    CBLSubdocument *level3 = [CBLSubdocument subdocument];
    [level3 setObject: @"n3" forKey: @"name"];
    [level2 setObject: level3 forKey: @"level3"];
    
    AssertEqualObjects([doc subdocumentForKey: @"level1"], level1);
    AssertEqualObjects([[doc subdocumentForKey: @"level1"]
                                subdocumentForKey: @"level2"], level2);
    AssertEqualObjects([[[doc subdocumentForKey: @"level1"]
                                subdocumentForKey: @"level2"]
                                    subdocumentForKey: @"level3"], level3);
}


- (void) testSetDocumentDictionary {
    [doc setDictionary: @{ @"name": @"Jason",
                           @"address": @{
                                   @"street": @"1 Star Way.",
                                   @"phones": @{@"mobile": @"650-123-4567"}
                                   },
                           @"references": @[@{@"name": @"Scott"}, @{@"name": @"Sam"}]
                           }];
    
    CBLSubdocument* address = [doc subdocumentForKey: @"address"];
    AssertEqualObjects([address stringForKey: @"street"], @"1 Star Way.");
    
    CBLSubdocument* phones = [address subdocumentForKey: @"phones"];
    AssertEqualObjects([phones stringForKey: @"mobile"], @"650-123-4567");
    
    CBLArray* references = [doc arrayForKey: @"references"];
    AssertEqual(references.count, 2u);
    
    CBLSubdocument* r1 = [references objectAtIndex: 0];
    AssertEqualObjects([r1 stringForKey: @"name"], @"Scott");
    
    CBLSubdocument* r2 = [references objectAtIndex: 1];
    AssertEqualObjects([r2 stringForKey: @"name"], @"Sam");
}


- (void) testSetSubdocumentToAnotherKey {
    [doc setDictionary: @{ @"name": @"Jason",
                           @"address": @{
                                   @"street": @"1 Star Way.",
                                   @"phones": @{@"mobile": @"650-123-4567"}
                                   }
                           }];
    
    CBLSubdocument* address = [doc subdocumentForKey: @"address"];
    [doc setObject: address forKey: @"address2"];
    CBLSubdocument* address2 = [doc objectForKey: @"address2"];
    Assert(address == address2);
}


- (void) testSubdocumentArray {
    NSArray* dicts = @[@{@"name": @"1"}, @{@"name": @"2"}, @{@"name": @"3"}, @{@"name": @"4"}];
    [doc setDictionary: @{@"subdocs": dicts}];
    
    CBLArray* subdocs = [doc arrayForKey: @"subdocs"];
    AssertEqual([subdocs count], 4u);
    
    CBLSubdocument* s1 = [subdocs subdocumentAtIndex: 0];
    CBLSubdocument* s2 = [subdocs subdocumentAtIndex: 1];
    CBLSubdocument* s3 = [subdocs subdocumentAtIndex: 2];
    CBLSubdocument* s4 = [subdocs subdocumentAtIndex: 3];
    
    AssertEqualObjects([s1 stringForKey: @"name"], @"1");
    AssertEqualObjects([s2 stringForKey: @"name"], @"2");
    AssertEqualObjects([s3 stringForKey: @"name"], @"3");
    AssertEqualObjects([s4 stringForKey: @"name"], @"4");
}


- (void) testSetSubdocumentPropertiesNil {
    [doc setDictionary: @{ @"name": @"Jason",
                           @"address": @{
                                   @"street": @"1 Star Way.",
                                   @"phones": @{@"mobile": @"650-123-4567"}
                                   },
                           @"references": @[@{@"name": @"Scott"}, @{@"name": @"Sam"}]
                           }];
    
    CBLSubdocument* address = [doc subdocumentForKey: @"address"];
    CBLSubdocument* phones = [address subdocumentForKey: @"phones"];
    AssertNotNil(address);
    AssertNotNil(phones);
    
    CBLArray* references = [doc arrayForKey: @"references"];
    AssertEqual(references.count, 2u);
    CBLSubdocument* r1 = [references subdocumentAtIndex: 0];
    CBLSubdocument* r2 = [references subdocumentAtIndex: 1];
    AssertNotNil(r1);
    AssertNotNil(r2);
    
    [doc setObject: nil forKey: @"address"];
    [doc setObject: nil forKey: @"references"];
    
    // Check address:
    AssertEqualObjects([address stringForKey: @"street"], @"1 Star Way.");
    AssertEqualObjects([address subdocumentForKey: @"phones"], phones);
    
    // Check phones:
    AssertEqualObjects([phones stringForKey: @"mobile"], @"650-123-4567");
    
    // Check references"
    AssertEqual(references.count, 2u);
    AssertEqualObjects([references subdocumentAtIndex: 0], r1);
    AssertEqualObjects([references subdocumentAtIndex: 1], r2);
    
    AssertEqualObjects([r1 stringForKey: @"name"], @"Scott");
    AssertEqualObjects([r2 stringForKey: @"name"], @"Sam");
    
    Assert([doc subdocumentForKey: @"address"] != address);
    Assert([doc arrayForKey: @"references"] != references);
}


- (void) testDeleteDocument {
    [doc setDictionary: @{ @"name": @"Jason",
                           @"address": @{
                                   @"street": @"1 Star Way.",
                                   @"phones": @{@"mobile": @"650-123-4567"}
                                   },
                           @"references": @[@{@"name": @"Scott"}, @{@"name": @"Sam"}]
                           }];
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    
    CBLSubdocument* address = [doc subdocumentForKey: @"address"];
    CBLSubdocument* phones = [address subdocumentForKey: @"phones"];
    AssertNotNil(address);
    AssertNotNil(phones);
    
    CBLArray* references = [doc arrayForKey: @"references"];
    AssertEqual(references.count, 2u);
    CBLSubdocument* r1 = [references subdocumentAtIndex: 0];
    CBLSubdocument* r2 = [references subdocumentAtIndex: 1];
    AssertNotNil(r1);
    AssertNotNil(r2);
    
    
    Assert([doc deleteDocument: &error], @"Deleting error: %@", error);
    
    // Check address:
    AssertEqualObjects([address stringForKey: @"street"], @"1 Star Way.");
    AssertEqualObjects([address subdocumentForKey: @"phones"], phones);
    
    // Check phones:
    AssertEqualObjects([phones stringForKey: @"mobile"], @"650-123-4567");
    
    // Check references"
    AssertEqual(references.count, 2u);
    AssertEqualObjects([references subdocumentAtIndex: 0], r1);
    AssertEqualObjects([references subdocumentAtIndex: 1], r2);
    
    AssertEqualObjects([r1 stringForKey: @"name"], @"Scott");
    AssertEqualObjects([r2 stringForKey: @"name"], @"Sam");
}

@end
