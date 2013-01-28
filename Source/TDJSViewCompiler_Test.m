//
//  TDJSViewCompiler_Test.m
//  TouchDB
//
//  Created by Jens Alfke on 1/4/13.
//
//

#import "TDJSViewCompiler.h"
#import "TD_Revision.h"
#import "Test.h"


TestCase(JSMapFunction) {
    TDJSViewCompiler* c = [[TDJSViewCompiler alloc] init];
    TDMapBlock mapBlock = [c compileMapFunction: @"function(doc){emit(doc.key, doc);}"
                                       language: @"javascript"];
    CAssert(mapBlock);

    NSDictionary* doc = @{@"_id": @"doc1", @"_rev": @"1-xyzzy", @"key": @"value"};

    NSMutableArray* emitted = [NSMutableArray array];
    TDMapEmitBlock emit = ^(id key, id value) {
        Log(@"Emitted: %@ -> %@", key, value);
        [emitted addObject: key];
        [emitted addObject: value];
    };
    mapBlock(doc, emit);

    CAssertEqual(emitted, (@[@"value", doc]));
}


TestCase(JSReduceFunction) {
    TDJSViewCompiler* c = [[TDJSViewCompiler alloc] init];
    TDReduceBlock reduceBlock = [c compileReduceFunction: @"function(k,v,r){return [k,v,r];}"
                                                language: @"javascript"];
    CAssert(reduceBlock);

    NSArray* keys = @[@"master", @"schlage", @"medeco"];
    NSArray* values = @[@1, @2, @3];
    id result = reduceBlock(keys, values, false);

    CAssertEqual(result, (@[keys, values, @NO]));
}


TestCase(JSFilterFunction) {
    TDJSFilterCompiler* c = [[TDJSFilterCompiler alloc] init];
    TD_FilterBlock filterBlock = [c compileFilterFunction: @"function(doc,req){return doc.ok;}"
                                                 language: @"javascript"];
    CAssert(filterBlock);

    TD_Revision* rev = [[TD_Revision alloc] initWithProperties: @{@"foo": @666}];
    CAssert(!filterBlock(rev,nil));
    rev = [[TD_Revision alloc] initWithProperties: @{@"ok": $false}];
    CAssert(!filterBlock(rev,nil));
    rev = [[TD_Revision alloc] initWithProperties: @{@"ok": $true}];
    CAssert(filterBlock(rev,nil));
    rev = [[TD_Revision alloc] initWithProperties: @{@"ok": @"mais oui"}];
    CAssert(filterBlock(rev,nil));
}


TestCase(JSFilterFunctionWithParams) {
    TDJSFilterCompiler* c = [[TDJSFilterCompiler alloc] init];
    TD_FilterBlock filterBlock = [c compileFilterFunction: @"function(doc,req){return doc.name == req.name;}"
                                                 language: @"javascript"];
    CAssert(filterBlock);

    NSDictionary* params = @{@"name": @"jens"};
    TD_Revision* rev = [[TD_Revision alloc] initWithProperties: @{@"foo": @666}];
    CAssert(!filterBlock(rev, params));
    rev = [[TD_Revision alloc] initWithProperties: @{@"name": @"bob"}];
    CAssert(!filterBlock(rev, params));
    rev = [[TD_Revision alloc] initWithProperties: @{@"name": @"jens"}];
    CAssert(filterBlock(rev, params));
}


TestCase(TDJSCompiler) {
    RequireTestCase(JSMapFunction);
    RequireTestCase(JSReduceFunction);
    RequireTestCase(JSFilterFunction);
}
