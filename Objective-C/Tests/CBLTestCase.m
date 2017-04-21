//
//  CBLTestCase.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#include "c4.h"

#define kDatabaseName @"testdb"


@implementation CBLTestCase

@synthesize db=_db;


- (void) setUp {
    [super setUp];
    
    NSString* dir = [[self class] directory];
    if ([[NSFileManager defaultManager] fileExistsAtPath: dir]) {
        NSError* error;
        Assert([[NSFileManager defaultManager] removeItemAtPath: dir error: &error],
               @"Error deleting CouchbaseLite folder: %@", error);
    }
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


- (CBLDatabase*) openDBNamed: (NSString*)name {
    NSError* error;
    CBLDatabaseOptions* options = [CBLDatabaseOptions defaultOptions];
    options.directory = [[self class] directory];
    CBLDatabase* theDB = [[CBLDatabase alloc] initWithName: name options: options error: &error];
    AssertNotNil(theDB, @"Couldn't open db: %@", error);
    return theDB;
}


- (void) openDB {
    Assert(!_db);
    _db = [self openDBNamed: kDatabaseName];
}


- (void) reopenDB {
    NSError *error;
    Assert([_db close: &error]);
    _db = nil;
    [self openDB];
}


- (NSData*) dataFromResource: (NSString*)resourceName ofType: (NSString*)type {
    NSString* path = [[NSBundle bundleForClass: [self class]] pathForResource: resourceName
                                                                       ofType: type];
    Assert(path, @"Missing test file %@.%@", resourceName, type);
    NSData* contents = [NSData dataWithContentsOfFile: path
                                              options: 0
                                                error: NULL];
    Assert(contents);
    return contents;
}


- (NSString*) stringFromResource: (NSString*)resourceName ofType: (NSString*)type {
    NSData* contents = [self dataFromResource: resourceName ofType: type];
    NSString* str = [[NSString alloc] initWithData: contents
                                          encoding: NSUTF8StringEncoding];
    Assert(str);
    return str;
}


- (void) loadJSONResource: (NSString*)resourceName {
    @autoreleasepool {
        NSString* contents = [self stringFromResource: resourceName ofType: @"json"];
        __block uint64_t n = 0;
        NSError *batchError;
        BOOL ok = [self.db inBatch: &batchError do: ^{
            [contents enumerateLinesUsingBlock: ^(NSString *line, BOOL *stop) {
                NSString* docID = [NSString stringWithFormat: @"doc-%03llu", ++n];
                NSData* json = [line dataUsingEncoding: NSUTF8StringEncoding];
                CBLDocument* doc = [[CBLDocument alloc] initWithID: docID];
                NSError* error;
                NSDictionary* dict = [NSJSONSerialization JSONObjectWithData: (NSData*)json
                                                                     options: 0 error: &error];
                Assert(dict, @"Couldn't parse line %llu of %@.json: %@", n, resourceName, error);
                [doc setDictionary: dict];
                BOOL saved = [_db saveDocument: doc error: &error];
                Assert(saved, @"Couldn't save document: %@", error);
            }];
        }];
        Assert(ok, @"loadJSONResource failed: %@", batchError);
    }
}


@end
