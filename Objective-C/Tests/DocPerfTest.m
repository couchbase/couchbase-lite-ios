//
//  DocPerfTest.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/31/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "DocPerfTest.h"


@implementation DocPerfTest


- (void) test {
    const unsigned revs = 10000;
    NSLog(@"--- Creating %u revisions ---", revs);
    [self measureAtScale: revs unit: @"revision" block:^{
        [self addRevisions: revs];
    }];
}


- (void) addRevisions: (unsigned)numRevisions {
    CBLMutableDocument* doc = [CBLMutableDocument documentWithID: @"doc"];
    Assert(doc, @"Couldn't create doc");
    NSError *error;
    BOOL ok = [self.db inBatch: &error usingBlock: ^{
        for (unsigned i = 0; i < numRevisions; ++i) {
            @autoreleasepool {
                [doc setValue: @(i) forKey: @"count"];
                NSError *error2;
                Assert([self.db saveDocument: doc error: &error2], @"Save failed: %@", error2);
            }
        }
    }];
    Assert(ok);
}


@end
