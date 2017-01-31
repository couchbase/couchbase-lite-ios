//
//  PerfTest.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/30/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "PerfTest.h"
#import <CouchbaseLite/CouchbaseLite.h>
#import "Benchmark.hh"
#import <string>

// Define this to limit the number of docs imported into the database.
//#define kMaxDocsToImport 1000


@implementation PerfTest
{
    CBLDatabaseOptions* _dbOptions;
    NSString* _dbName;
}

@synthesize db=_db;

static NSString* sResourceDir;


+ (void) setResourceDirectory: (NSString*)resourceDir {
    sResourceDir = resourceDir;
}


- (instancetype) initWithDatabaseOptions: (CBLDatabaseOptions*)dbOptions
{
    self = [super init];
    if (self) {
        _dbOptions = dbOptions;
        _dbName = @"perfdb";

        if (_dbOptions)
            Assert([CBLDatabase deleteDatabase: _dbName inDirectory: _dbOptions.directory
                                         error: nil]);
}
    return self;
}

- (instancetype) initWithDatabase: (CBLDatabase*)db
{
    CBLDatabaseOptions* options = nil; // db.options;   //TODO: Use this when property is added
    self = [self initWithDatabaseOptions: options];
    if (self) {
        _db = db;
        //_dbName = db.name;    //TODO: Use this when property is added
    }
    return self;
}


- (NSData*) dataFromResource: (NSString*)resourceName ofType: (NSString*)type {
    NSString* path = [[sResourceDir stringByAppendingPathComponent: resourceName]
                                                      stringByAppendingPathExtension: type];
    NSData* contents = [NSData dataWithContentsOfFile: path
                                              options: 0
                                                error: NULL];
    Assert(contents);
    return contents;
}


- (void) openDB {
    Assert(_dbName);
    Assert(!_db);
    NSError* error;
    _db = [[CBLDatabase alloc] initWithName: _dbName options: _dbOptions error: &error];
    Assert(_db, @"Couldn't open db: %@", error);
}


- (void) eraseDB {
    if (_db) {
        NSError *error;
        Assert([_db close: &error]);
        _db = nil;
    }
    Assert([CBLDatabase deleteDatabase: _dbName inDirectory: _dbOptions.directory error: nil]);
    [self openDB];
}


- (void) setUp { }
- (void) test {AssertAbstractMethod();}
- (void) tearDown { }

- (void) run {
    NSLog(@"====== %@ ======", [self class]);
    [self setUp];
    [self test];
    [self tearDown];
}

+ (void) runWithOptions: (CBLDatabaseOptions*)options {
    [[[self alloc] initWithDatabaseOptions: options] run];
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
