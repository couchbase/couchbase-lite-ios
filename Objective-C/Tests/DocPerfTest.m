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
    CBLDocument* doc = self.db[@"doc"];
    NSError *error;
    BOOL ok = [self.db inBatch: &error do: ^{
        for (unsigned i = 0; i < numRevisions; ++i) {
            [doc setInteger: i forKey: @"count"];
            NSAssert([doc save: NULL], @"Save failed");
        }
    }];
    Assert(ok);
}


@end
