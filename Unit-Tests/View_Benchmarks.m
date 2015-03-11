//
//  View_Benchmarks.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/11/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLView+Internal.h"


@interface View_Benchmarks : CBLTestCaseWithDB
@end


@implementation View_Benchmarks

- (void) benchmarkIndexingWithDocTypeOptimization: (BOOL)optimize {
    [db inTransaction:^BOOL{
        for (NSUInteger i = 0; i < 5000; i++) {
            NSString* type = (i % 10 == 0) ? @"INTP" : @"ESFJ";
            NSMutableDictionary* props = [@{@"type": type, @"i": @(i)} mutableCopy];
            for (NSUInteger j = 0; j < 20; j++) {
                NSString* key = $sprintf(@"%lx", random());
                id value = @(random());
                props[key] = value;
            }
            [self createDocumentWithProperties: props];
        }
        return YES;
    }];

    [self reopenTestDB];

    CBLView* intpView = [db viewNamed: @"INTP"];
    [intpView setMapBlock: MAPBLOCK({
        if ([doc[@"type"] isEqualToString: @"INTP"])
            emit(doc[@"i"], nil);
    }) version: @"1"];
    
    if (optimize)
        intpView.documentType = @"INTP";

    [self measureBlock:^{
        [intpView deleteIndex];
        [intpView updateIndex];
    }];
}

- (void)testDocType_SQLite {
    if (self.isSQLiteDB)
        [self benchmarkIndexingWithDocTypeOptimization: NO];
}

- (void)testDocType_SQLite_Optimized {
    if (self.isSQLiteDB)
        [self benchmarkIndexingWithDocTypeOptimization: YES];
}

- (void) testDocType_ForestDB {
    if (!self.isSQLiteDB)
        [self benchmarkIndexingWithDocTypeOptimization: NO];
}

- (void) testDocType_ForestDB_Optimized {
    if (!self.isSQLiteDB)
        [self benchmarkIndexingWithDocTypeOptimization: YES];
}

@end
