//
//  TDJSViewCompiler_Test.m
//  TouchDB
//
//  Created by Jens Alfke on 1/4/13.
//
//

#import "TDJSViewCompiler.h"
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


TestCase(TDJSViewCompiler) {
    RequireTestCase(JSMapFunction);
    RequireTestCase(JSReduceFunction);
}
