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
    CBLDocument* doc = [self.db document];
    AssertNotNil(doc);
    AssertNotNil(doc.documentID);
    Assert(doc.documentID.length > 0);
    AssertEqual(doc.database, self.db);
    AssertFalse(doc.exists);
    AssertFalse(doc.isDeleted);
    AssertNil(doc.properties);
    
    CBLDocument* doc1 = [self.db documentWithID: @"doc1"];
    AssertNotNil(doc1);
    AssertEqualObjects(doc1.documentID, @"doc1");
    AssertEqual(doc1.database, self.db);
    AssertFalse(doc1.exists);
    AssertFalse(doc1.isDeleted);
    AssertEqual(doc1, [self.db documentWithID: @"doc1"]);
    AssertEqual(doc1, self.db[@"doc1"]);
    AssertNil(doc1.properties);
}


- (void) testDocumentExists {
    AssertFalse([self.db documentExists: @"doc1"]);
    
    NSError* error;
    CBLDocument* doc1 = [self.db documentWithID: @"doc1"];
    Assert([doc1 save: &error], @"Error saving: %@", error);
    Assert([self.db documentExists: @"doc1"]);
    AssertNil(doc1.properties);
}


- (void) testInBatchSuccess {
    NSError* error;
    BOOL success = [self.db inBatch: &error do: ^{
        for (int i = 0; i < 10; i++) {
            NSString* docId = [NSString stringWithFormat:@"doc%d", i];
            CBLDocument* doc = [self.db documentWithID: docId];
            [doc save: nil];
        }
    }];
    Assert(success, @"Error in batch: %@", error);
    for (int i = 0; i < 10; i++) {
        NSString* docId = [NSString stringWithFormat:@"doc%d", i];
        Assert([self.db documentExists: docId]);
    }
}


#if TARGET_OS_IPHONE
#if !TARGET_IPHONE_SIMULATOR
- (void) testFileProtection {
    NSError* error;
    NSString* dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     @"CouchbaseLite-test-file-protection"];
    [[NSFileManager defaultManager] removeItemAtPath:dir error: nil];
    
    // Check default file protection, NSFileProtectionCompleteUnlessOpen:
    CBLDatabaseOptions* options = [CBLDatabaseOptions defaultOptions];
    options.directory = dir;
    CBLDatabase* db = [[CBLDatabase alloc] initWithName: @"db" options: options error: &error];
    
    // Add a document with a blob:
    CBLDocument* doc = [db document];
    doc[@"foo"] = @"bar";
    NSString* str = @"This is a blob.";
    NSData* data = [str dataUsingEncoding: NSUTF8StringEncoding];
    doc[@"blob"] = [[CBLBlob alloc] initWithContentType :@"text/plain" data :data error: &error];
    [doc save: &error];
    
    [self verifyFileProtection: NSFileProtectionCompleteUnlessOpen forDir: dir];
    Assert([db close: &error], @"Couldn't close db: %@", error);
    
    // Change file protection to NSFileProtectionNone:
    options.fileProtection = NSDataWritingFileProtectionNone;
    db = [[CBLDatabase alloc] initWithName: @"db" options: options error: &error];
    [self verifyFileProtection: NSFileProtectionNone forDir: dir];
    
    // Clean up:
    Assert([db close: &error], @"Couldn't close db: %@", error);
    Assert([[NSFileManager defaultManager]
            removeItemAtPath:dir error: &error], @"Cannot delete directory: %@", error);
}


- (void) verifyFileProtection: (NSFileProtectionType)protection forDir: (NSString*)dir {
    NSFileManager* fmgr = [NSFileManager defaultManager];
    NSArray* paths = [[fmgr subpathsAtPath: dir] arrayByAddingObject: @"."];
    for (NSString* path in paths) {
        NSString* absPath = [dir stringByAppendingPathComponent: path];
        id p = [[fmgr attributesOfItemAtPath: absPath error: nil] objectForKey: NSFileProtectionKey];
        // Not checking -shm file as it will have NSFileProtectionNone by default regardless of its
        // parent directory projection level. However, the -shm file contains non-sensitive info.
        if (![path hasSuffix:@"-shm"])
            AssertEqual(p, protection);
    }
}
#endif
#endif


@end
