//
//  main.m
//  PerfTest
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

#import <CouchbaseLite/CouchbaseLite.h>
#import "DocPerfTest.h"
#import "TunesPerfTest.h"

#define kDatabaseName @"perfdb"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSString* resourceDir = [@(argv[0]) stringByDeletingLastPathComponent];
        [PerfTest setResourceDirectory: resourceDir];
        NSLog(@"Reading resources from %@", resourceDir);

        CBLDatabaseConfiguration* config = [CBLDatabaseConfiguration new];
        config.directory = [NSTemporaryDirectory() stringByAppendingPathComponent: @"CouchbaseLite"];

        NSLog(@"Starting test...");
        [DocPerfTest runWithConfig: config];
        [TunesPerfTest runWithConfig: config];
    }
    return 0;
}
