//
//  FragmentTest.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"

@interface CBLFragmentTest : CBLTestCase

@end

@implementation CBLFragmentTest


- (void)testGetFragmentValues {
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc setDictionary: @{ @"name": @"Jason",
                           @"address": @{
                                   @"street": @"1 Star Way.",
                                   @"phones": @{@"mobile": @"650-123-4567"}
                                   },
                           @"references": @[@{@"name": @"Scott"}, @{@"name": @"Sam"}]
                           }];
    
    AssertEqualObjects(doc[@"name"].string, @"Jason");
    AssertEqualObjects(doc[@"address"][@"street"].string, @"1 Star Way.");
    AssertEqualObjects(doc[@"address"][@"phones"][@"mobile"].string, @"650-123-4567");
    AssertEqualObjects(doc[@"references"][0][@"name"].string, @"Scott");
    AssertEqualObjects(doc[@"references"][1][@"name"].string, @"Sam");
    
    AssertNil(doc[@"references"][2][@"name"].value);
    AssertNil(doc[@"dummy"][@"dummy"][@"dummy"].value);
    AssertNil(doc[@"dummy"][@"dummy"][0][@"dummy"].value);
}


- (void)testSetFragmentValues {
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    doc[@"name"].value = @"Jason";
    
    doc[@"address"].value = [[CBLSubdocument alloc] init];
    doc[@"address"][@"street"].value = @"1 Star Way.";
    doc[@"address"][@"phones"].value = [[CBLSubdocument alloc] init];
    doc[@"address"][@"phones"][@"mobile"].value = @"650-123-4567";
    
    AssertEqualObjects(doc[@"name"].string, @"Jason");
    AssertEqualObjects(doc[@"address"][@"street"].string, @"1 Star Way.");
    AssertEqualObjects(doc[@"address"][@"phones"][@"mobile"].string, @"650-123-4567");
}


@end
