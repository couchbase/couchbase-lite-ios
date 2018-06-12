//
//  CBLTestCase.m
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

#import "CBLTestCase.h"
#include "c4.h"

#define kDatabaseName @"testdb"

#ifdef COUCHBASE_ENTERPRISE
#define kLogFileName @"CouchbaseLiteTests_EE.c4log"
#define kDatabaseDirName @"CouchbaseLite_EE"
#else
#define kLogFileName @"CouchbaseLiteTests.c4log"
#define kDatabaseDirName @"CouchbaseLite"
#endif


@implementation CBLTestCase
{
    int _c4ObjectCount;
}

@synthesize db=_db;


+ (void) initialize {
    if (self == [CBLTestCase class]) {
        NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent: kLogFileName];
        C4Error error;
        NSAssert(c4log_writeToBinaryFile(kC4LogVerbose, c4str(path.UTF8String), &error), @"Couldn't initialize logging");
        NSLog(@"Writing log to %@", path);
    }
}


- (void) setUp {
    [super setUp];
    
    Assert([self deleteDBNamed: kDatabaseName error: nil]);
    
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
            Assert([_db close: &error], @"Failed to close db: %@", error);
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
    return [NSTemporaryDirectory() stringByAppendingPathComponent: kDatabaseDirName];
}


- (CBLDatabase*) openDBNamed: (NSString*)name error: (NSError**)error {
    CBLDatabaseConfiguration* config = [[CBLDatabaseConfiguration alloc] init];
    config.directory = self.directory;
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
    Assert([_db close: &error], @"Close error: %@", error);
    _db = nil;
    [self openDB];
}


- (void) cleanDB {
    NSError *error;
    Assert([_db delete: &error], @"Delete error: %@", error);
    [self reopenDB];
}


- (BOOL) deleteDBNamed: (NSString*)name error: (NSError**)error {
    return [CBLDatabase deleteDatabase: name inDirectory:self.directory error: error];
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


- (void) saveDocument: (CBLMutableDocument*)document {
    NSError* error;
    Assert([_db saveDocument: document error: &error], @"Saving error: %@", error);
    
    CBLDocument* savedDoc = [_db documentWithID: document.id];
    AssertNotNil(savedDoc);
    AssertEqualObjects(savedDoc.id, document.id);
    AssertEqualObjects([savedDoc toDictionary], [document toDictionary]);
}


- (void) saveDocument: (CBLMutableDocument*)document eval: (void(^)(CBLDocument*))block {
    NSError* error;
    block(document);
    Assert([_db saveDocument: document error: &error], @"Saving error: %@", error);
    block(document);
    block([_db documentWithID: document.id]);
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


- (NSString*) randomStringWithLength: (NSUInteger)length {
    static NSString *chars = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXZY0123456789";
    NSMutableString *s = [NSMutableString stringWithCapacity: length];
    for (NSUInteger i = 0; i < length; i++) {
        [s appendFormat:@"%C",
            [chars characterAtIndex: (arc4random() % [chars length])]];
    }
    return s;
}


- (void) loadJSONResource: (NSString*)resourceName {
    @autoreleasepool {
        NSString* contents = [self stringFromResource: resourceName ofType: @"json"];
        return [self loadJSONString: contents named: resourceName];
    }
}

- (void) loadJSONString: (NSString*)contents named: (NSString*)resourceName {
    @autoreleasepool {
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
                Assert([_db saveDocument: doc error: &error], @"Couldn't save document: %@", error);
            }];
        }];
        Assert(ok, @"loadJSONString failed: %@", batchError);
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
                  domain, (long)code, error);
    }
}


- (void) expectException: (NSString*)name in: (void (^) (void))block {
    ++gC4ExpectExceptions;
    XCTAssertThrowsSpecificNamed(block(), NSException, name);
    --gC4ExpectExceptions;
}

- (void) mayHaveException: (NSString*)name in: (void (^) (void))block {
    @try {
        ++gC4ExpectExceptions;
        block();
    }
    @catch (NSException* e) {
        AssertEqualObjects(e.name, name);
    }
    @finally {
        --gC4ExpectExceptions;
    }
}
@end
