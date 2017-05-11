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
{
    int _c4ObjectCount;
}

@synthesize db=_db;


+ (void) initialize {
    if (self == [CBLTestCase class]) {
        NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent: @"CouchbaseLiteTests.c4log"];
        C4Error error;
        NSAssert(c4log_writeToBinaryFile(c4str(path.UTF8String), &error), @"Couldn't initialize logging");
        NSLog(@"Writing log to %@", path);
    }
}


- (void) setUp {
    [super setUp];

    _c4ObjectCount = c4_getObjectCount();
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
        @autoreleasepool {
            NSError* error;
            Assert([_db close: &error]);
            _db = nil;
        }
    }

    // Wait a little while for objects to be cleaned up:
    for (int i = 0; i < 20; i++) {
        if (c4_getObjectCount() == _c4ObjectCount)
            break;
        else
            [NSThread sleepForTimeInterval: 0.1];
    }
    AssertEqual(c4_getObjectCount(), _c4ObjectCount);
    [super tearDown];
}


+ (NSString*) directory {
    return [NSTemporaryDirectory() stringByAppendingPathComponent: @"CouchbaseLite"];
}


- (CBLDatabase*) openDBNamed: (NSString*)name error: (NSError**)error {
    CBLDatabaseOptions* options = [CBLDatabaseOptions defaultOptions];
    options.directory = [[self class] directory];
    return [[CBLDatabase alloc] initWithName: name options: options error: error];
}


- (void) openDB {
    Assert(!_db);
    NSError* error;
    _db = [self openDBNamed: kDatabaseName error: &error];
    AssertNil(error);
    AssertNotNil(_db);
}


- (void) reopenDB {
    NSError *error;
    Assert([_db close: &error]);
    _db = nil;
    [self openDB];
}


- (CBLDocument*) createDocument: (NSString*)documentID {
    return [[CBLDocument alloc] initWithID: documentID];
}


- (CBLDocument*) createDocument:(NSString *)documentID dictionary:(NSDictionary *)dictionary {
    return [[CBLDocument alloc] initWithID: documentID dictionary: dictionary];
}


- (CBLDocument*) saveDocument: (CBLDocument*)document {
    NSError* error;
    Assert([_db saveDocument: document error: &error], @"Saving error: %@", error);
    return [_db documentWithID: document.documentID];
}


- (CBLDocument*) saveDocument: (CBLDocument*)doc eval: (void(^)(CBLDocument*))block {
    block(doc);
    doc = [self saveDocument: doc];
    block(doc);
    return doc;
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
