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

@synthesize db=_db, conflictResolver=_conflictResolver;


+ (void) initialize {
    if (self == [CBLTestCase class]) {
        NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent: @"CouchbaseLiteTests.c4log"];
        C4Error error;
        NSAssert(c4log_writeToBinaryFile(kC4LogVerbose, c4str(path.UTF8String), &error), @"Couldn't initialize logging");
        NSLog(@"Writing log to %@", path);
    }
}


- (void) setUp {
    [super setUp];

    _c4ObjectCount = c4_getObjectCount();
    NSString* dir = self.directory;
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
    int leaks;
    for (int i = 0; i < 20; i++) {
        leaks = c4_getObjectCount() - _c4ObjectCount;
        if (leaks == 0)
            break;
        else
            [NSThread sleepForTimeInterval: 0.1];
    }
    if (leaks) {
        fprintf(stderr, "**** LITECORE OBJECTS STILL NOT FREED: ****\n");
        c4_dumpInstances();
        XCTFail("%d LiteCore objects have not been freed (see above)", leaks);
    }
    [super tearDown];
}


- (NSString*) directory {
    return [NSTemporaryDirectory() stringByAppendingPathComponent: @"CouchbaseLite"];
}


- (CBLDatabase*) openDBNamed: (NSString*)name error: (NSError**)error {
    id config = [[CBLDatabaseConfiguration alloc] initWithBlock:
                   ^(CBLDatabaseConfigurationBuilder *builder)
    {
        builder.directory = self.directory;
        if (self.conflictResolver)
            builder.conflictResolver = self.conflictResolver;
    }];
    
    return [[CBLDatabase alloc] initWithName: name config: config error: error];
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


- (CBLMutableDocument*) createDocument {
    return [[CBLMutableDocument alloc] init];
}


- (CBLMutableDocument*) createDocument: (NSString*)documentID {
    return [[CBLMutableDocument alloc] initWithID: documentID];
}


- (CBLMutableDocument*) createDocument:(NSString *)documentID data:(NSDictionary *)data {
    return [[CBLMutableDocument alloc] initWithID: documentID data: data];
}


- (CBLDocument*) saveDocument: (CBLMutableDocument*)document {
    NSError* error;
    CBLDocument* newDoc = [_db saveDocument: document error: &error];
    Assert(newDoc != nil, @"Saving error: %@", error);
    return newDoc;
}


- (CBLDocument*) saveDocument: (CBLMutableDocument*)doc eval: (void(^)(CBLDocument*))block {
    block(doc);
    CBLDocument* newDoc = [self saveDocument: doc];
    block(newDoc);
    return newDoc;
}


- (NSData*) dataFromResource: (NSString*)resourceName ofType: (NSString*)type {
    NSString* res = [@"Support" stringByAppendingPathComponent: resourceName];
    NSString* path = [[NSBundle bundleForClass: [self class]] pathForResource: res
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
        BOOL ok = [self.db inBatch: &batchError usingBlock: ^{
            [contents enumerateLinesUsingBlock: ^(NSString *line, BOOL *stop) {
                NSString* docID = [NSString stringWithFormat: @"doc-%03llu", ++n];
                NSData* json = [line dataUsingEncoding: NSUTF8StringEncoding];
                CBLMutableDocument* doc = [[CBLMutableDocument alloc] initWithID: docID];
                NSError* error;
                NSDictionary* dict = [NSJSONSerialization JSONObjectWithData: (NSData*)json
                                                                     options: 0 error: &error];
                Assert(dict, @"Couldn't parse line %llu of %@.json: %@", n, resourceName, error);
                [doc setData: dict];
                BOOL saved = [_db saveDocument: doc error: &error] != nil;
                Assert(saved, @"Couldn't save document: %@", error);
            }];
        }];
        Assert(ok, @"loadJSONResource failed: %@", batchError);
    }
}


// helper method to check error
- (void) expectError: (NSErrorDomain)domain code: (NSInteger)code in: (BOOL (^)(NSError**))block {
    ++gC4ExpectExceptions;
    NSError* error;
    BOOL succeeded = block(&error);
    --gC4ExpectExceptions;

    if (succeeded) {
        XCTFail("Block expected to fail but didn't");
    } else {
        XCTAssert([domain isEqualToString: error.domain] && code == error.code,
                  "Block expected to return error (%@ %ld), but instead returned %@",
                  domain, code, error);
    }
}


- (void) expectException: (NSString*)name in: (void (^) (void))block {
    ++gC4ExpectExceptions;
    XCTAssertThrowsSpecificNamed(block(), NSException, name);
    --gC4ExpectExceptions;
}

@end
