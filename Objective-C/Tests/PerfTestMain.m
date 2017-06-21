//
//  main.m
//  PerfTest
//
//  Created by Jens Alfke on 1/30/17.
//  Copyright © 2017 Couchbase. All rights reserved.
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
