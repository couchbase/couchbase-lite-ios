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

@synthesize db=_db;


- (void) setUp {
    [super setUp];
    [CBLDatabase deleteDatabase: kDatabaseName inDirectory: [[self class] directory] error: nil];
    [self openDB];
}


- (void) tearDown {
    if (_db) {
        NSError* error;
        Assert([_db close: &error]);
        _db = nil;
    }
    [super tearDown];
}


+ (NSString*) directory {
    return [NSTemporaryDirectory() stringByAppendingPathComponent: @"CouchbaseLite"];
}


- (void) openDB {
    Assert(!_db);
    NSError* error;
    CBLDatabaseOptions* options = [CBLDatabaseOptions defaultOptions];
    options.directory = [[self class] directory];
    _db = [[CBLDatabase alloc] initWithName: kDatabaseName options: options error: &error];
    AssertNotNil(_db, @"Couldn't open db: %@", error);
}


- (void) reopenDB {
    NSError *error;
    Assert([_db close: &error]);
    _db = nil;
    [self openDB];
}


- (void) loadJSONResource: (NSString*)resourceName {
    @autoreleasepool {
        NSString* path = [[NSBundle bundleForClass: [self class]] pathForResource: resourceName
                                                                           ofType: @"json"];
        Assert(path, @"Missing test file names_100.json");
        NSString* contents = (NSString*)[NSString stringWithContentsOfFile: path encoding: NSUTF8StringEncoding error: NULL];
        Assert(contents);
        __block uint64_t n = 0;
        NSError *batchError;
        BOOL ok = [self.db inBatch: &batchError do: ^BOOL{
            [contents enumerateLinesUsingBlock: ^(NSString *line, BOOL *stop) {
                NSString* docID = [NSString stringWithFormat: @"doc-%03llu", ++n];
                NSData* json = [line dataUsingEncoding: NSUTF8StringEncoding];
                CBLDocument* doc = [self.db documentWithID: docID];
                NSError* error;
                NSDictionary* properties = [NSJSONSerialization JSONObjectWithData: (NSData*)json
                                                                           options: 0
                                                                             error: &error];
                Assert(properties, @"Couldn't parse line %llu of %@.json: %@", n, path, error);
                doc.properties = properties;
                bool saved = [doc save: &error];
                Assert(saved, @"Couldn't save document: %@", error);
            }];
            return true;
        }];
        Assert(ok, @"loadJSONResource failed: %@", batchError);
    }
}


@end
