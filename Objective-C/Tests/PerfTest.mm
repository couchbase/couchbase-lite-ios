//
//  PerfTest.m
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

#import "PerfTest.h"
#import <CouchbaseLite/CouchbaseLite.h>
#import "Benchmark.hh"
#import <string>


@implementation PerfTest
{
    CBLDatabaseConfiguration* _dbConfig;
    NSString* _dbName;
    CBLDatabase* _db;
}


static NSString* sResourceDir;


+ (void) setResourceDirectory: (NSString*)resourceDir {
    sResourceDir = resourceDir;
}


+ (CBLDatabaseConfiguration*) defaultConfig {
    CBLDatabaseConfiguration* config = [[CBLDatabaseConfiguration alloc] init];
    config.directory = [NSTemporaryDirectory() stringByAppendingPathComponent: @"CouchbaseLite"];
    return config;
}


+ (void) runWithConfig: (CBLDatabaseConfiguration*)config {
    [[[self alloc] initWithDatabaseConfig: config] run];
}


- (instancetype) initWithDatabaseConfig: (CBLDatabaseConfiguration*)dbConfig {
    self = [super init];
    if (self) {
        _dbConfig = dbConfig ?: [[self class] defaultConfig];
        _dbName = @"perfdb";

        if (_dbConfig)
            Assert([CBLDatabase deleteDatabase: _dbName
                                   inDirectory: _dbConfig.directory
                                         error: nil]);
    }
    return self;
}


- (instancetype) init {
    return [self initWithDatabaseConfig: nil];
}


// unused, currently
- (instancetype) initWithDatabase: (CBLDatabase*)db {
    self = [self initWithDatabaseConfig: db.config];
    if (self) {
        _db = db;
        _dbName = db.name;
    }
    return self;
}


- (void) dealloc {
    NSError *error;
    if (_db && ![_db close: &error])
        NSLog(@"WARNING: Error closing database: %@", error);
}


- (NSData*) dataFromResource: (NSString*)resourceName ofType: (NSString*)type {
    NSString *dir = sResourceDir ?: [[NSBundle bundleForClass: [self class]] resourcePath];
    NSString* path = [[dir stringByAppendingPathComponent: resourceName]
                                                          stringByAppendingPathExtension: type];
    NSData* contents = [NSData dataWithContentsOfFile: path options: 0 error: NULL];
    Assert(contents, @"Couldn't load resource file %@", path);
    return contents;
}


- (void) openDB {
    Assert(_dbName);
    Assert(!_db);
    NSError* error;
    _db = [[CBLDatabase alloc] initWithName: _dbName config: _dbConfig error: &error];
    Assert(_db, @"Couldn't open db: %@", error);
}


- (void) reopenDB {
    [_db close: NULL];
    _db = nil;
    [self openDB];
}


- (void) eraseDB {
    if (_db) {
        NSError *error;
        Assert([_db close: &error]);
        _db = nil;
    }
    Assert([CBLDatabase deleteDatabase: _dbName inDirectory: _dbConfig.directory error: nil]);
    [self openDB];
}


- (CBLDatabase*) db {
    if (!_db)
        [self openDB];
    return _db;
}


- (void) setUp {
    // Subclasses can override this.
}


- (void) test {
    AssertAbstractMethod(); // Subclasses MUST override this
}


- (void) tearDown {
    // Subclasses can override this but must call 'super' last.
    [_db close: NULL];
    _db = nil;
}


- (void) run {
    NSLog(@"====== %@ ======", [self class]);
    [self setUp];
    [self test];
    [self tearDown];
}


- (void) measureAtScale: (NSUInteger)count unit: (NSString*)unit block: (void (^)())block {
    Benchmark b;
    static const int reps = 10;
    for (int i = 0; i < reps; i++) {
        [self eraseDB];
        b.start();
        block();
        double t = b.stop();
        fprintf(stderr, "%.03g  ", t);
    }
    fprintf(stderr,"\n");
    b.printReport();
    if (count > 1) {
        b.printReport(1.0/count, unit.UTF8String);
    }
}

@end
