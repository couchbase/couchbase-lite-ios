//
//  SubdocumentTest.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/17/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLInternal.h"

@interface SubdocumentTest : CBLTestCase

@end

@implementation SubdocumentTest


- (void) testNewSubdoc {
    CBLDocument* doc1 = [self.db documentWithID: @"doc1"];
    CBLSubdocument* subdoc = [[CBLSubdocument alloc] init];
    AssertNil(subdoc.properties);
    AssertFalse(subdoc.exists);
    AssertNil(subdoc[@"type"]);
    subdoc[@"type"] = @"profile";
    subdoc[@"name"] = @"Scott";
    AssertEqualObjects(subdoc[@"type"], @"profile");
    AssertEqualObjects(subdoc[@"name"], @"Scott");
    AssertEqualObjects(subdoc.properties, (@{@"type": @"profile", @"name": @"Scott"}));
    doc1[@"subdoc"] = subdoc;
    
    NSError* error;
    Assert([doc1 save: &error], @"Saving error: %@", error);
    Assert([doc1 exists]);
    AssertFalse(doc1.isDeleted);
    Assert(subdoc.exists);
    AssertEqualObjects(subdoc[@"type"], @"profile");
    AssertEqualObjects(subdoc[@"name"], @"Scott");
    AssertEqualObjects(subdoc.properties, (@{@"type": @"profile", @"name": @"Scott"}));
    
    doc1 = [[self.db copy] documentWithID: @"doc1"];
    subdoc = [doc1 subdocumentForKey: @"subdoc"];
    Assert(subdoc.exists);
    AssertEqualObjects(subdoc[@"type"], @"profile");
    AssertEqualObjects(subdoc[@"name"], @"Scott");
    AssertEqualObjects(subdoc.properties, (@{@"type": @"profile", @"name": @"Scott"}));
}


- (void) testGetSubdoc {
    CBLDocument* doc1 = [self.db documentWithID: @"doc1"];
    CBLSubdocument* subdoc = [doc1 subdocumentForKey: @"subdoc"];
    AssertNil(subdoc.properties);
    AssertFalse(subdoc.exists);
    AssertNil(subdoc[@"type"]);
    subdoc[@"type"] = @"profile";
    subdoc[@"name"] = @"Scott";
    AssertEqualObjects(subdoc[@"type"], @"profile");
    AssertEqualObjects(subdoc[@"name"], @"Scott");
    AssertEqualObjects(subdoc.properties, (@{@"type": @"profile", @"name": @"Scott"}));
    
    NSError* error;
    Assert([doc1 save: &error], @"Saving error: %@", error);
    Assert([doc1 exists]);
    AssertFalse(doc1.isDeleted);
    Assert(subdoc.exists);
    AssertEqualObjects(subdoc[@"type"], @"profile");
    AssertEqualObjects(subdoc[@"name"], @"Scott");
    AssertEqualObjects(subdoc.properties, (@{@"type": @"profile", @"name": @"Scott"}));
    
    doc1 = [[self.db copy] documentWithID: @"doc1"];
    subdoc = [doc1 subdocumentForKey: @"subdoc"];
    Assert(subdoc.exists);
    AssertEqualObjects(subdoc[@"type"], @"profile");
    AssertEqualObjects(subdoc[@"name"], @"Scott");
    AssertEqualObjects(subdoc.properties, (@{@"type": @"profile", @"name": @"Scott"}));
}


- (void) testNestedSubdoc {
    CBLDocument* doc1 = [self.db documentWithID: @"doc1"];
    AssertNil(doc1.properties);
    
    CBLSubdocument* level1 = [doc1 subdocumentForKey: @"l1"];
    AssertNil(level1.properties);
    AssertFalse(level1.exists);
    level1[@"name"] = @"n1";
    
    CBLSubdocument* level2 = [level1 subdocumentForKey: @"l2"];
    AssertNil(level2.properties);
    AssertFalse(level2.exists);
    level2[@"name"] = @"n2";
    
    CBLSubdocument* level3 = [level2 subdocumentForKey: @"l3"];
    AssertNil(level3.properties);
    AssertFalse(level3.exists);
    level3[@"name"] = @"n3";
    
    AssertEqualObjects(doc1.properties, (@{@"l1": level1}));
    AssertEqualObjects(level1.properties, (@{@"name": @"n1", @"l2": level2}));
    AssertEqualObjects(level2.properties, (@{@"name": @"n2", @"l3": level3}));
    AssertEqualObjects(level3.properties, (@{@"name": @"n3"}));
    AssertEqualObjects(doc1.encodeAsJSON, (@{@"l1": @{@"name": @"n1",
                                                      @"l2": @{@"name": @"n2",
                                                               @"l3": @{@"name": @"n3"}}}}));
    
    NSError* error;
    Assert([doc1 save: &error], @"Saving error: %@", error);
    Assert([doc1 exists]);
    Assert(level1.exists);
    Assert(level2.exists);
    Assert(level3.exists);
    
    doc1 = [[self.db copy] documentWithID: @"doc1"];
    level1 = doc1[@"l1"];
    level2 = level1[@"l2"];
    level3 = level2[@"l3"];
    Assert(level1.exists);
    Assert(level2.exists);
    Assert(level3.exists);
    AssertEqualObjects(doc1.properties, (@{@"l1": level1}));
    AssertEqualObjects(level1.properties, (@{@"name": @"n1", @"l2": level2}));
    AssertEqualObjects(level2.properties, (@{@"name": @"n2", @"l3": level3}));
    AssertEqualObjects(level3.properties, (@{@"name": @"n3"}));
    AssertEqualObjects(doc1.encodeAsJSON, (@{@"l1": @{@"name": @"n1",
                                                      @"l2": @{@"name": @"n2",
                                                               @"l3": @{@"name": @"n3"}}}}));
}


- (void) testSubdocArray {
    CBLDocument* doc1 = [self.db documentWithID: @"doc1"];
    AssertNil(doc1.properties);
    
    CBLSubdocument* sub1 = [[CBLSubdocument alloc] init];
    CBLSubdocument* sub2 = [[CBLSubdocument alloc] init];
    sub2[@"name"] = @"sub2";
    CBLSubdocument* sub3 = [[CBLSubdocument alloc] init];
    sub3[@"name"] = @"sub3";
    
    doc1[@"subs"] = @[sub1, sub2, sub3];
    AssertFalse(sub1.exists);
    AssertFalse(sub2.exists);
    AssertFalse(sub3.exists);
    AssertEqualObjects(doc1[@"subs"], (@[sub1, sub2, sub3]));
    
    NSError* error;
    Assert([doc1 save: &error], @"Saving error: %@", error);
    Assert([doc1 exists]);
    Assert(sub1.exists);
    Assert(sub2.exists);
    Assert(sub3.exists);
    
    doc1 = [[self.db copy] documentWithID: @"doc1"];
    NSArray* subs = doc1[@"subs"];
    AssertEqual(subs.count, 3);
    AssertEqualObjects(((CBLSubdocument*)subs[0]).properties, @{});
    AssertEqualObjects(((CBLSubdocument*)subs[1]).properties, @{@"name": @"sub2"});
    AssertEqualObjects(((CBLSubdocument*)subs[2]).properties, @{@"name": @"sub3"});
    Assert(((CBLSubdocument*)subs[0]).exists);
    Assert(((CBLSubdocument*)subs[1]).exists);
    Assert(((CBLSubdocument*)subs[2]).exists);
}


- (void) testSetNil {
    CBLDocument* doc1 = [self.db documentWithID: @"doc1"];
    AssertNil(doc1.properties);
    
    CBLSubdocument* subdoc1 = [doc1 subdocumentForKey: @"subdoc1"];
    AssertNil(subdoc1.properties);
    AssertFalse(subdoc1.exists);
    AssertNil(subdoc1[@"type"]);
    subdoc1[@"type"] = @"profile";
    AssertEqualObjects(subdoc1[@"type"], @"profile");
    AssertEqualObjects(subdoc1.properties, (@{@"type": @"profile"}));
    
    doc1[@"subdoc1"] = nil;
    AssertNil(doc1[@"subdoc1"]);
    AssertFalse(subdoc1.exists);
    
    NSError* error;
    Assert([doc1 save: &error], @"Saving error: %@", error);
    AssertFalse(subdoc1.exists);
    
    CBLSubdocument* subdoc1a = [doc1 subdocumentForKey: @"subdoc1"];
    AssertFalse(subdoc1a.exists);
    AssertNil(subdoc1a.properties);
    AssertNil(subdoc1a[@"type"]);
    AssertEqualObjects(subdoc1a, doc1[@"subdoc1"]);
    
    subdoc1a[@"type"] = @"profile";
    Assert([doc1 save: &error], @"Saving error: %@", error);
    Assert(subdoc1a.exists);
}


- (void) testGetSetDictionary {
    CBLDocument* doc1 = [self.db documentWithID: @"doc1"];
    AssertNil(doc1.properties);
    AssertNil(doc1[@"subdoc1"]);
    doc1[@"subdoc1"] = @{@"type": @"profile"};
    
    CBLSubdocument* subdoc1 = doc1[@"subdoc1"];
    AssertEqualObjects(subdoc1.properties, @{@"type": @"profile"});
    
    NSError* error;
    Assert([doc1 save: &error], @"Saving error: %@", error);
    Assert(subdoc1.exists);
    AssertEqualObjects(subdoc1, doc1[@"subdoc1"]);
    AssertEqualObjects(subdoc1.properties, @{@"type": @"profile"});
}


- (void) testReplaceWithNewType {
    CBLDocument* doc1 = [self.db documentWithID: @"doc1"];
    CBLSubdocument* subdoc1 = [doc1 subdocumentForKey: @"subdoc1"];
    subdoc1[@"type"] = @"profile";
    AssertEqualObjects(subdoc1[@"type"], @"profile");
    AssertEqualObjects(subdoc1.properties, @{@"type": @"profile"});
    
    doc1[@"subdoc1"] = @"profile";
    AssertNil(subdoc1.properties);
    AssertEqualObjects(doc1[@"subdoc1"], @"profile");
}


- (void) testDeleteDocument {
    CBLDocument* doc1 = [self.db documentWithID: @"doc1"];
    CBLSubdocument* subdoc1 = [doc1 subdocumentForKey: @"subdoc1"];
    subdoc1[@"type"] = @"profile";
    
    NSError* error;
    Assert([doc1 save: &error], @"Saving error: %@", error);
    Assert(subdoc1.exists);
    AssertEqualObjects(subdoc1.properties, @{@"type": @"profile"});
    
    Assert([doc1 deleteDocument: &error], @"Deleting error: %@", error);
    Assert(doc1.exists);
    AssertNil(doc1.properties);
    AssertFalse(subdoc1.exists);
    AssertNil(subdoc1.properties);
}


@end
