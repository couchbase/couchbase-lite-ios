//
//  DocPerfTest.m
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
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
    __block CBLMutableDocument* doc = [CBLMutableDocument documentWithID: @"doc"];
    Assert(doc, @"Couldn't create doc");
    NSError *error;
    BOOL ok = [self.db inBatch: &error usingBlock: ^{
        for (unsigned i = 0; i < numRevisions; ++i) {
            @autoreleasepool {
                [doc setValue: @(i) forKey: @"count"];
                NSError *error2;
                doc = [[self.db saveDocument: doc error: &error2] mutableCopy];
                Assert(doc, @"Save failed: %@", error2);
            }
        }
    }];
    Assert(ok);
}


@end
