//
//  CBLTestCase.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"


#define kDatabaseName @"testdb"


@implementation CBLTestCase


- (void) setUp {
    [super setUp];
    
    NSString* dir = [NSTemporaryDirectory() stringByAppendingPathComponent: @"CouchbaseLite"];
    [CBLDatabase deleteDatabase: kDatabaseName inDirectory: dir error: nil];
    
    NSError* error;
    CBLDatabaseOptions* options = [CBLDatabaseOptions defaultOptions];
    options.directory = dir;
    _db = [[CBLDatabase alloc] initWithName: kDatabaseName options: options error: &error];
    AssertNotNil(_db, @"Couldn't open db: %@", error);
}


- (void) tearDown {
    if (_db) {
        NSError* error;
        Assert([_db close: &error]);
        _db = nil;
    }
    [super tearDown];
}


@end
