//
//  QueryEnumerator_Tests.m
//  CouchbaseLite
//
//  Created by Mark Glasgow on 19/01/2017.
//  Copyright © 2017 Couchbase, Inc. All rights reserved.
//

#import "CBLTestCase.h"

@interface QueryEnumerator_Tests : CBLTestCaseWithDB
@end

@implementation QueryEnumerator_Tests

- (void) test1_CurrentRowIndex {
    CBLView* view = [db viewNamed: @"vu"];
    Assert(view);
    [view setMapBlock: MAPBLOCK({
        emit(doc[@"sequence"], nil);
    }) version: @"1"];
    Assert(view.mapBlock != nil);
    
    // add 20 documents
    [self createDocuments: 20];
    AssertEq(view.totalRows, 20u);
    
    // create enumerator
    CBLQuery* query = [view createQuery];
    CBLQueryEnumerator* rows = [query run: NULL];
    
    // check current index without reading any rows
    AssertEq(rows.currentRowIndex, -1);
    
    // read first row and check current index progression.
    // for iterator enumerators (such as ForestDB)
    // this ensures that we are iterator mode
    // rather than buffering all rows into an array
    Assert([rows nextRow] != nil);
    
    AssertEq(rows.currentRowIndex, 0);
    
    // read rest of the rows
    for (NSUInteger i = 1; i < 20u; i++) {
        [rows nextRow];
        AssertEq(rows.currentRowIndex, (NSInteger)i);
    }
    
    // confirm we have finished reading
    AssertNil([rows nextRow]);
    AssertEq(rows.currentRowIndex, 19);
}

@end
