//
//  JSViewCompiler_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/4/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//
//

#import "CBLTestCase.h"
#import "CBLJSViewCompiler.h"
#import "CBL_Revision.h"
#import "CBLReduceFuncs.h"


@interface JSViewCompiler_Tests : CBLTestCase
@end


@implementation JSViewCompiler_Tests


- (void) test_JSMapFunction {
    CBLJSViewCompiler* c = [[CBLJSViewCompiler alloc] init];
    CBLMapBlock mapBlock = [c compileMapFunction: @"function(doc){emit(doc.key, doc);}"
                                       language: @"javascript"];
    Assert(mapBlock);

    NSDictionary* doc = @{@"_id": @"doc1", @"_rev": @"1-xyzzy", @"key": @"value"};

    NSMutableArray* emitted = [NSMutableArray array];
    CBLMapEmitBlock emit = ^(id key, id value) {
        Log(@"Emitted: %@ -> %@", key, value);
        [emitted addObject: key];
        [emitted addObject: value];
    };
    mapBlock(doc, emit);

    AssertEqual(emitted, (@[@"value", doc]));
}


- (void) test_JSReduceFunction {
    CBLJSViewCompiler* c = [[CBLJSViewCompiler alloc] init];
    CBLReduceBlock reduceBlock = [c compileReduceFunction: @"function(k,v,r){return [k,v,r];}"
                                                language: @"javascript"];
    Assert(reduceBlock);

    NSArray* keys = @[@"master", @"schlage", @"medeco"];
    NSArray* values = @[@1, @2, @3];
    id result = reduceBlock(keys, values, false);

    AssertEqual(result, (@[keys, values, @NO]));
}


- (void) test_JSBuiltInReduceFunctions {
    CBLJSViewCompiler* c = [[CBLJSViewCompiler alloc] init];
    CBLReduceBlock reduceBlock = [c compileReduceFunction: @"_count"
                                                 language: @"javascript"];
    Assert(reduceBlock);
    AssertEq(reduceBlock, CBLGetReduceFunc(@"count"));

    reduceBlock = [c compileReduceFunction: @"_stats" language: @"javascript"];
    Assert(reduceBlock);
    AssertEq(reduceBlock, CBLGetReduceFunc(@"stats"));
    NSArray* keys = @[@"master", @"schlage", @"medeco"];
    NSArray* values = @[@19, @-75, @3.1416];
    id result = reduceBlock(keys, values, false);
    AssertEqual(result, (@{@"count": @(3), @"sum": @(-52.8584), @"sumsqr": @(5995.86965056),
                           @"max": @(19), @"min": @(-75)}));

    reduceBlock = [c compileReduceFunction: @"_frob"
                                  language: @"javascript"];
    AssertNil(reduceBlock);
}


- (void) test_JSFilterFunction {
    CBLJSFilterCompiler* c = [[CBLJSFilterCompiler alloc] init];
    CBLFilterBlock filterBlock = [c compileFilterFunction: @"function(doc,req){return doc.ok;}"
                                                 language: @"javascript"];
    Assert(filterBlock);

    // I'm using a CBL_Revision as a sort of mock CBLRevision, simply because it's easier to
    // instantiate one. The only method that will be called on it is -properties.
    CBL_Revision* rev = [[CBL_Revision alloc] initWithProperties: @{@"_id": @"doc1",
                                                                    @"_rev": @"1-aa",
                                                                    @"foo": @666}];
    Assert(!filterBlock((CBLSavedRevision*)rev,nil));
    rev = [[CBL_Revision alloc] initWithProperties: @{@"_id": @"doc1",
                                                      @"_rev": @"1-aa",
                                                      @"ok": $false}];
    Assert(!filterBlock((CBLSavedRevision*)rev,nil));
    rev = [[CBL_Revision alloc] initWithProperties: @{@"_id": @"doc1",
                                                      @"_rev": @"1-aa",
                                                      @"ok": $true}];
    Assert(filterBlock((CBLSavedRevision*)rev,nil));
    rev = [[CBL_Revision alloc] initWithProperties: @{@"_id": @"doc1",
                                                      @"_rev": @"1-aa",
                                                      @"ok": @"mais oui"}];
    Assert(filterBlock((CBLSavedRevision*)rev,nil));
}


- (void) test_JSFilterFunctionWithParams {
    CBLJSFilterCompiler* c = [[CBLJSFilterCompiler alloc] init];
    CBLFilterBlock filterBlock = [c compileFilterFunction: @"function(doc,req){return doc.name == req.name;}"
                                                 language: @"javascript"];
    Assert(filterBlock);

    NSDictionary* params = @{@"name": @"jens"};
    // I'm using a CBL_Revision as a sort of mock CBLRevision, simply because it's easier to
    // instantiate one. The only method that will be called on it is -properties.
    CBL_Revision* rev = [[CBL_Revision alloc] initWithProperties: @{@"_id": @"doc1",
                                                                    @"_rev": @"1-aa",
                                                                    @"foo": @666}];
    Assert(!filterBlock((CBLSavedRevision*)rev, params));
    rev = [[CBL_Revision alloc] initWithProperties: @{@"_id": @"doc1",
                                                      @"_rev": @"1-aa",
                                                      @"name": @"bob"}];
    Assert(!filterBlock((CBLSavedRevision*)rev, params));
    rev = [[CBL_Revision alloc] initWithProperties: @{@"_id": @"doc1",
                                                      @"_rev": @"1-aa",
                                                      @"name": @"jens"}];
    Assert(filterBlock((CBLSavedRevision*)rev, params));
}


- (void) test_JSLogFunction {
    // This case will test that calling log() function doesn't cause any errors running the JS map
    // map function.
    CBLJSViewCompiler* c = [[CBLJSViewCompiler alloc] init];
    CBLMapBlock mapBlock = [c compileMapFunction: @"function(doc){log('Log Message'); emit(doc.key, doc);}"
                                        language: @"javascript"];
    Assert(mapBlock);

    NSDictionary* doc = @{@"_id": @"doc1", @"_rev": @"1-xyzzy", @"key": @"value"};
    NSMutableArray* emitted = [NSMutableArray array];
    CBLMapEmitBlock emit = ^(id key, id value) {
        [emitted addObject: value];
    };
    mapBlock(doc, emit);
    AssertEqual(emitted, (@[doc]));
}


@end
