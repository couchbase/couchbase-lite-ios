//
//  CBLJSViewCompiler_Test.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/4/13.
//
//

#import "CBLJSViewCompiler.h"
#import "CBL_Revision.h"
#import "Test.h"


TestCase(JSMapFunction) {
    CBLJSViewCompiler* c = [[CBLJSViewCompiler alloc] init];
    CBLMapBlock mapBlock = [c compileMapFunction: @"function(doc){emit(doc.key, doc);}"
                                       language: @"javascript"];
    CAssert(mapBlock);

    NSDictionary* doc = @{@"_id": @"doc1", @"_rev": @"1-xyzzy", @"key": @"value"};

    NSMutableArray* emitted = [NSMutableArray array];
    CBLMapEmitBlock emit = ^(id key, id value) {
        Log(@"Emitted: %@ -> %@", key, value);
        [emitted addObject: key];
        [emitted addObject: value];
    };
    mapBlock(doc, emit);

    CAssertEqual(emitted, (@[@"value", doc]));
}


TestCase(JSReduceFunction) {
    CBLJSViewCompiler* c = [[CBLJSViewCompiler alloc] init];
    CBLReduceBlock reduceBlock = [c compileReduceFunction: @"function(k,v,r){return [k,v,r];}"
                                                language: @"javascript"];
    CAssert(reduceBlock);

    NSArray* keys = @[@"master", @"schlage", @"medeco"];
    NSArray* values = @[@1, @2, @3];
    id result = reduceBlock(keys, values, false);

    CAssertEqual(result, (@[keys, values, @NO]));
}


TestCase(JSFilterFunction) {
    CBLJSFilterCompiler* c = [[CBLJSFilterCompiler alloc] init];
    CBL_FilterBlock filterBlock = [c compileFilterFunction: @"function(doc,req){return doc.ok;}"
                                                 language: @"javascript"];
    CAssert(filterBlock);

    CBL_Revision* rev = [[CBL_Revision alloc] initWithProperties: @{@"foo": @666}];
    CAssert(!filterBlock(rev,nil));
    rev = [[CBL_Revision alloc] initWithProperties: @{@"ok": $false}];
    CAssert(!filterBlock(rev,nil));
    rev = [[CBL_Revision alloc] initWithProperties: @{@"ok": $true}];
    CAssert(filterBlock(rev,nil));
    rev = [[CBL_Revision alloc] initWithProperties: @{@"ok": @"mais oui"}];
    CAssert(filterBlock(rev,nil));
}


TestCase(JSFilterFunctionWithParams) {
    CBLJSFilterCompiler* c = [[CBLJSFilterCompiler alloc] init];
    CBL_FilterBlock filterBlock = [c compileFilterFunction: @"function(doc,req){return doc.name == req.name;}"
                                                 language: @"javascript"];
    CAssert(filterBlock);

    NSDictionary* params = @{@"name": @"jens"};
    CBL_Revision* rev = [[CBL_Revision alloc] initWithProperties: @{@"foo": @666}];
    CAssert(!filterBlock(rev, params));
    rev = [[CBL_Revision alloc] initWithProperties: @{@"name": @"bob"}];
    CAssert(!filterBlock(rev, params));
    rev = [[CBL_Revision alloc] initWithProperties: @{@"name": @"jens"}];
    CAssert(filterBlock(rev, params));
}


TestCase(CBLJSCompiler) {
    RequireTestCase(JSMapFunction);
    RequireTestCase(JSReduceFunction);
    RequireTestCase(JSFilterFunction);
}
