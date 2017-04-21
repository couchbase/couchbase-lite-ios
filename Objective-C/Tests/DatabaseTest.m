//
//  DatabaseTest.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLInternal.h"


@interface DatabaseTest : CBLTestCase

@end

@implementation DatabaseTest


- (void) testCreate {
    NSError* error;
    NSString* dir = [NSTemporaryDirectory() stringByAppendingPathComponent: @"CouchbaseLite"];
    [CBLDatabase deleteDatabase: @"db" inDirectory: dir error: nil];
    
    CBLDatabaseOptions* options = [CBLDatabaseOptions defaultOptions];
    options.directory = dir;
    CBLDatabase* db = [[CBLDatabase alloc] initWithName: @"db" options: options error: &error];
    AssertNotNil(db, @"Couldn't open db: %@", error);
    Assert([db.path.lastPathComponent hasSuffix: @".cblite2"]);
    AssertEqualObjects(db.name, @"db");

    Assert([db close: &error], @"Couldn't close db: %@", error);
    AssertNil(db.path);
    Assert([CBLDatabase deleteDatabase: @"db" inDirectory: dir error: &error],
           @"Couldn't delete closed database: %@", error);
}


- (void) testDelete {
    Assert(self.db.path);
    Assert([[NSFileManager defaultManager] fileExistsAtPath: self.db.path]);
    
    NSError* error;
    NSString* path = self.db.path;
    Assert([self.db deleteDatabase: &error], @"Couldn't delete db: %@", error);
    AssertNil(self.db.path);
    AssertFalse([[NSFileManager defaultManager] fileExistsAtPath: path]);
}


- (void) testCreateDocument {
    CBLDocument* doc = [[CBLDocument alloc] init];
    AssertNotNil(doc);
    AssertNotNil(doc.documentID);
    Assert(doc.documentID.length > 0);
    AssertFalse(doc.isDeleted);
    AssertEqualObjects(doc.toDictionary, @{});
    
    CBLDocument* docA = [[CBLDocument alloc] initWithID: @"doc-a"];
    AssertNotNil(docA);
    AssertEqualObjects(docA.documentID, @"doc-a");
    AssertFalse(docA.isDeleted);
    AssertEqualObjects(docA.toDictionary, @{});
}


- (void) testDocumentExists {
    AssertFalse([self.db documentExists: @"doc-a"]);
    
    NSError* error;
    CBLDocument* docA = [[CBLDocument alloc] initWithID: @"doc-a"];
    Assert([_db saveDocument: docA error: &error], @"Error saving: %@", error);
    Assert([self.db documentExists: @"doc-a"]);
}


- (void) testInBatchSuccess {
    NSError* error;
    BOOL success = [self.db inBatch: &error do: ^{
        for (int i = 0; i < 10; i++) {
            NSString* docId = [NSString stringWithFormat:@"doc%d", i];
            CBLDocument* doc = [[CBLDocument alloc] initWithID: docId];
            [_db saveDocument: doc error: nil];
        }
    }];
    Assert(success, @"Error in batch: %@", error);
    for (int i = 0; i < 10; i++) {
        NSString* docId = [NSString stringWithFormat:@"doc%d", i];
        Assert([self.db documentExists: docId]);
    }
}


@end
