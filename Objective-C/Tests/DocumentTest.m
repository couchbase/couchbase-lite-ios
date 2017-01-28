//
//  DocumentTest.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/11/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLJSON.h"
#import "CBLBlob.h"
#import "CBLInternal.h"
#include "c4.h"
#include "Fleece.h"
#include "c4Document+Fleece.h"
#include "Fleece+CoreFoundation.h"


@interface TheirsWins : NSObject <CBLConflictResolver>
@end

@implementation TheirsWins

- (NSDictionary *)resolveMine:(NSDictionary *)mine
                   withTheirs:(NSDictionary *)theirs
                      andBase:(NSDictionary *)base
{
    return theirs;
}

@end


@interface MergeThenTheirsWins : NSObject <CBLConflictResolver>
@end

@implementation MergeThenTheirsWins

- (NSDictionary *)resolveMine:(NSDictionary *)mine
                   withTheirs:(NSDictionary *)theirs
                      andBase:(NSDictionary *)base
{
    NSMutableDictionary *resolved = [NSMutableDictionary new];
    for (NSString *key in base) {
        resolved[key] = base[key];
    }
    
    NSMutableSet *changed = [NSMutableSet new];
    for (NSString *key in theirs) {
        resolved[key] = theirs[key];
        [changed addObject:key];
    }
    
    for (NSString *key in mine) {
        if(![changed containsObject:key]) {
            resolved[key] = mine[key];
        }
    }
    
    return resolved;
}

@end


@interface GiveUp : NSObject <CBLConflictResolver>
@end

@implementation GiveUp

- (NSDictionary *)resolveMine:(NSDictionary *)mine
                   withTheirs:(NSDictionary *)theirs
                      andBase:(NSDictionary *)base
{
    return nil;
}

@end


@interface DoNotResolve : NSObject <CBLConflictResolver>
@end

@implementation DoNotResolve

- (NSDictionary *)resolveMine:(NSDictionary *)mine
                   withTheirs:(NSDictionary *)theirs
                      andBase:(NSDictionary *)base
{
    NSAssert(NO, @"Resolver should not have been called!");
    return nil;
}

@end


@interface DocumentTest : CBLTestCase

@end


@implementation DocumentTest

- (void) setUp {
    [super setUp];
    // Make sure resolver isn't being called at inappropriate times by defaulting to one that
    // will raise an exception:
    self.db.conflictResolver = [DoNotResolve new];
}


- (BOOL)saveProperties:(NSDictionary *)props toDocWithID:(NSString *)docID error:(NSError **)error {
    // Save to database:
    BOOL ok = [self.db inBatch:error do:^BOOL{
        C4Slice docIDSlice = c4str([docID cStringUsingEncoding:NSASCIIStringEncoding]);
        C4Document *tricky = c4doc_get(self.db.c4db, docIDSlice, true, NULL);
        
        C4DocPutRequest put = {
            .docID = tricky->docID,
            .history = &tricky->revID,
            .historyCount = 1,
            .save = true,
        };
        
        NSMutableDictionary* properties = [props mutableCopy];
        FLEncoder enc = c4db_createFleeceEncoder(self.db.c4db);
        FLEncoder_WriteNSObject(enc, properties);
        FLError flErr;
        FLSliceResult body = FLEncoder_Finish(enc, &flErr);
        FLEncoder_Free(enc);
        Assert(body.buf);
        put.body = (C4Slice){body.buf, body.size};
        
        C4Error err;
        C4Document* newDoc = c4doc_put(self.db.c4db, &put, NULL, &err);
        c4slice_free(put.body);
        Assert(newDoc);
        
        return YES;
    }];
    
    Assert(ok);
    return YES;
}

- (void) testNewDoc {
    NSError* error;
    
    CBLDocument* doc = [self.db document];
    AssertNotNil(doc);
    AssertNotNil(doc.documentID);
    Assert(doc.documentID.length > 0);
    AssertEqual(doc.database, self.db);
    AssertFalse(doc.exists);
    AssertFalse(doc.isDeleted);
    AssertNil(doc.properties);
    AssertEqual(doc[@"prop"], nil);
    AssertFalse([doc booleanForKey: @"prop"]);
    AssertEqual([doc integerForKey: @"prop"], 0);
    AssertEqual([doc floatForKey: @"prop"], 0.0);
    AssertEqual([doc doubleForKey: @"prop"], 0.0);
    AssertNil([doc dateForKey: @"prop"]);
    AssertNil([doc stringForKey: @"prop"]);
    
    Assert([doc save: &error], @"Error saving: %@", error);
    Assert(doc.exists);
    AssertFalse(doc.isDeleted);
    AssertNil(doc.properties);
}


- (void) testNewDocWithId {
    NSError* error;
    
    CBLDocument* doc = [self.db documentWithID: @"doc1"];
    AssertEqual(doc, self.db[@"doc1"]);
    AssertNotNil(doc);
    AssertEqual(doc.documentID, @"doc1");
    AssertEqual(doc.database, self.db);
    AssertFalse(doc.exists);
    AssertFalse(doc.isDeleted);
    AssertNil(doc.properties);
    AssertEqual(doc[@"prop"], nil);
    AssertFalse([doc booleanForKey: @"prop"]);
    AssertEqual([doc integerForKey: @"prop"], 0);
    AssertEqual([doc floatForKey: @"prop"], 0.0);
    AssertEqual([doc doubleForKey: @"prop"], 0.0);
    AssertNil([doc dateForKey: @"prop"]);
    AssertNil([doc stringForKey: @"prop"]);
    
    Assert([doc save: &error], @"Error saving: %@", error);
    Assert(doc.exists);
    AssertFalse(doc.isDeleted);
    AssertNil(doc.properties);
    AssertEqual(doc, self.db[@"doc1"]);
}


- (void) testPropertyAccessors {
    CBLDocument* doc = [self.db documentWithID: @"doc1"];
    
    // Premitives:
    [doc setBoolean: YES forKey: @"bool"];
    [doc setDouble: 1.1 forKey: @"double"];
    [doc setFloat: 1.2f forKey: @"float"];
    [doc setInteger: 2 forKey: @"integer"];
    
    // Objects:
    [doc setObject: @"str" forKey: @"string"];
    [doc setObject: @(YES) forKey: @"boolObj"];
    [doc setObject: @(1) forKey: @"number"];
    [doc setObject: @{@"foo": @"bar"} forKey: @"dict"];
    [doc setObject: @[@"1", @"2"] forKey: @"array"];
    
    // Date:
    NSDate* date = [NSDate date];
    [doc setObject: date forKey: @"date"];
    
    NSError* error;
    Assert([doc save: &error], @"Error saving: %@", error);
    
    // Primitives:
    AssertEqual([doc booleanForKey: @"bool"], YES);
    AssertEqual([doc doubleForKey: @"double"], 1.1);
    AssertEqual([doc floatForKey: @"float"], @(1.2).floatValue);
    AssertEqual([doc integerForKey: @"integer"], 2);
    
    // Objects:
    AssertEqualObjects([doc stringForKey: @"string"], @"str");
    AssertEqualObjects([doc objectForKey: @"boolObj"], @(YES));
    AssertEqualObjects([doc objectForKey: @"number"], @(1));
    AssertEqualObjects([doc objectForKey: @"dict"], @{@"foo": @"bar"});
    AssertEqualObjects([doc objectForKey: @"array"], (@[@"1", @"2"]));
    
    // Date:
    // TODO: Why is comparing two date objects not equal?
    AssertEqualObjects([CBLJSON JSONObjectWithDate: [doc dateForKey: @"date"]],
                       [CBLJSON JSONObjectWithDate: date]);
    
    ////// Get the doc from a different database and check again:
    
    CBLDocument* doc1 = [[self.db copy] documentWithID: @"doc1"];
    
    AssertEqual([doc1 booleanForKey: @"bool"], YES);
    AssertEqual([doc1 doubleForKey: @"double"], 1.1);
    AssertEqual([doc1 floatForKey: @"float"], @(1.2).floatValue);
    AssertEqual([doc1 integerForKey: @"integer"], 2);
    
    // Objects:
    AssertEqualObjects([doc1 stringForKey: @"string"], @"str");
    AssertEqualObjects([doc1 objectForKey: @"boolObj"], @(YES));
    AssertEqualObjects([doc1 objectForKey: @"number"], @(1));
    AssertEqualObjects([doc1 objectForKey: @"dict"], @{@"foo": @"bar"});
    AssertEqualObjects([doc1 objectForKey: @"array"], (@[@"1", @"2"]));
    
    // Date:
    // TODO: Why is comparing two date objects not equal?
    AssertEqualObjects([CBLJSON JSONObjectWithDate: [doc1 dateForKey: @"date"]],
                       [CBLJSON JSONObjectWithDate: date]);
}


- (void) testProperties {
    CBLDocument* doc = self.db[@"doc1"];
    doc[@"type"] = @"demo";
    doc[@"weight"] = @12.5;
    doc[@"tags"] = @[@"useless", @"temporary"];
    
    AssertEqualObjects(doc[@"type"], @"demo");
    AssertEqual([doc doubleForKey: @"weight"], 12.5);
    AssertEqualObjects(doc.properties,
        (@{@"type": @"demo", @"weight": @12.5, @"tags": @[@"useless", @"temporary"]}));
}


- (void) testDelete {
    CBLDocument* doc = [self.db documentWithID: @"doc1"];
    doc[@"type"] = @"profile";
    doc[@"name"] = @"Scott";
    AssertFalse([doc exists]);
    AssertFalse(doc.isDeleted);
    
    // Delete before save:
    AssertFalse([doc deleteDocument: nil]);
    AssertEqualObjects(doc[@"type"], @"profile");
    AssertEqualObjects(doc[@"name"], @"Scott");
    
    // Save:
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);
    Assert([doc exists]);
    AssertFalse(doc.isDeleted);
    
    // Delete:
    Assert([doc deleteDocument: &error], @"Deleting error: %@", error);
    Assert([doc exists]);
    Assert(doc.isDeleted);
    AssertNil(doc.properties);
}


- (void) testPurge {
    CBLDocument* doc = [self.db documentWithID: @"doc1"];
    doc[@"type"] = @"profile";
    doc[@"name"] = @"Scott";
    AssertFalse([doc exists]);
    AssertFalse(doc.isDeleted);
    
    // Purge before save:
    AssertFalse([doc purge: nil]);
    AssertEqualObjects(doc[@"type"], @"profile");
    AssertEqualObjects(doc[@"name"], @"Scott");
    
    // Save:
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);
    Assert([doc exists]);
    AssertFalse(doc.isDeleted);
    
    // Purge:
    Assert([doc purge: &error], @"Purging error: %@", error);
    AssertFalse([doc exists]);
    AssertFalse(doc.isDeleted);
}


- (void) testRevert {
    CBLDocument* doc = [self.db documentWithID: @"doc1"];
    doc[@"type"] = @"profile";
    doc[@"name"] = @"Scott";
    
    // Revert before save:
    [doc revert];
    AssertNil(doc[@"type"]);
    AssertNil(doc[@"name"]);
    
    // Save:
    doc[@"type"] = @"profile";
    doc[@"name"] = @"Scott";
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);
    AssertEqualObjects(doc[@"type"], @"profile");
    AssertEqualObjects(doc[@"name"], @"Scott");
    
    // Make some changes:
    doc[@"type"] = @"user";
    doc[@"name"] = @"Scottie";
    
    // Revert:
    [doc revert];
    AssertEqualObjects(doc[@"type"], @"profile");
    AssertEqualObjects(doc[@"name"], @"Scott");
}


- (void) testReopenDB {
    CBLDocument* doc = [self.db documentWithID: @"doc1"];
    [doc setObject: @"str" forKey: @"string"];
    AssertEqualObjects(doc.properties, @{@"string": @"str"});
    NSError* error;
    Assert([doc save: &error], @"Error saving: %@", error);

    [self reopenDB];

    doc = [self.db documentWithID: @"doc1"];
    AssertEqualObjects(doc.properties, @{@"string": @"str"});
    AssertEqualObjects(doc[@"string"], @"str");
}


- (CBLDocument*) setupConflict {
    // Setup a default database conflict resolver
    CBLDocument* doc = [self.db documentWithID: @"doc1"];
    doc[@"type"] = @"profile";
    doc[@"name"] = @"Scott";
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);
    
    // Force a conflict
    NSMutableDictionary *properties = [doc.properties mutableCopy];
    properties[@"name"] = @"Scotty";
    BOOL ok = [self saveProperties:properties toDocWithID:[doc documentID] error:&error];
    Assert(ok);
    
    // Change document in memory, so save will trigger a conflict
    doc[@"name"] = @"Scott Pilgrim";
    return doc;
}

- (void)testConflict {
    self.db.conflictResolver = [TheirsWins new];
    CBLDocument* doc = [self setupConflict];
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);
    AssertEqualObjects(doc[@"name"], @"Scotty");
    
    // Get a new document with its own conflict resolver
    doc = [self.db documentWithID: @"doc2"];
    doc.conflictResolver = [MergeThenTheirsWins new];
    doc[@"type"] = @"profile";
    doc[@"name"] = @"Scott";
    Assert([doc save: &error], @"Saving error: %@", error);
    
    // Force a conflict again
    NSMutableDictionary* properties = [doc.properties mutableCopy];
    properties[@"type"] = @"bio";
    properties[@"gender"] = @"male";
    BOOL ok = [self saveProperties:properties toDocWithID:[doc documentID] error:&error];
    Assert(ok);
    
    // Save and make sure that the correct conflict resolver won
    doc[@"type"] = @"biography";
    doc[@"age"] = @(31);
    Assert([doc save: &error], @"Saving error: %@", error);
    AssertEqual([doc[@"age"] intValue], 31);
    AssertEqualObjects(doc[@"type"], @"bio");
    AssertEqualObjects(doc[@"gender"], @"male");
    AssertEqualObjects(doc[@"name"], @"Scott");
}

- (void)testConflictResolverGivesUp {
    self.db.conflictResolver = [GiveUp new];
    CBLDocument* doc = [self setupConflict];
    NSError* error;
    AssertFalse([doc save: &error], @"Save should have failed!");
    AssertEqualObjects(error.domain, @"LiteCore");      //TODO: Should have CBL error domain/code
    AssertEqual(error.code, kC4ErrorConflict);
    Assert(doc.hasChanges);
}

- (void)testDeletionConflict {
    self.db.conflictResolver = [DoNotResolve new];
    CBLDocument* doc = [self setupConflict];
    NSError* error;
    Assert([doc deleteDocument: &error], @"Deletion error: %@", error);
    Assert(doc.exists);
    AssertFalse(doc.isDeleted);
    AssertEqualObjects(doc[@"name"], @"Scotty");
}

- (void)testConflictMineIsDeeper {
    self.db.conflictResolver = nil;
    CBLDocument* doc = [self setupConflict];
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);
    AssertEqualObjects(doc[@"name"], @"Scott Pilgrim");
}

- (void)testConflictTheirsIsDeeper {
    self.db.conflictResolver = nil;
    CBLDocument* doc = [self setupConflict];

    // Add another revision to the conflict, so it'll have a higher generation:
    NSMutableDictionary *properties = [doc.properties mutableCopy];
    properties[@"name"] = @"Scott of the Sahara";
    NSError* error;
    [self saveProperties:properties toDocWithID:[doc documentID] error:&error];

    Assert([doc save: &error], @"Saving error: %@", error);
    AssertEqualObjects(doc[@"name"], @"Scott of the Sahara");
}

- (void)testBlob {
    CBLDocument* doc = [self.db documentWithID: @"doc1"];
    NSData* content = [@"12345" dataUsingEncoding:NSUTF8StringEncoding];
    NSError* error;
    CBLBlob *data = [[CBLBlob alloc] initWithContentType:@"text/plain" data:content error:&error];
    Assert(data, @"Failed to create blob: %@", error);
    doc[@"data"] = data;
    doc[@"name"] = @"Jim";
    Assert([doc save: &error], @"Saving error: %@", error);
    
    CBLDocument* doc1 = [[self.db copy] documentWithID: @"doc1"];
    AssertEqualObjects(doc[@"name"], @"Jim");
    Assert([doc1[@"data"] isKindOfClass:[CBLBlob class]]);
    data = doc1[@"data"];
    AssertEqual(data.length, 5ull);
    AssertEqualObjects(data.content, content);
    NSInputStream *contentStream = data.contentStream;
    [contentStream open];
    uint8_t buffer[10];
    NSInteger bytesRead = [contentStream read:buffer maxLength:10];
    [contentStream close];
    AssertEqual(bytesRead, 5);
}

- (void)testEmptyBlob {
    CBLDocument* doc = [self.db documentWithID: @"doc1"];
    NSData* content = [@"" dataUsingEncoding:NSUTF8StringEncoding];
    NSError* error;
    CBLBlob *data = [[CBLBlob alloc] initWithContentType:@"text/plain" data:content error:&error];
    Assert(data, @"Failed to create blob: %@", error);
    doc[@"data"] = data;
    
    Assert([doc save: &error], @"Saving error: %@", error);
    CBLDocument* doc1 = [[self.db copy] documentWithID: @"doc1"];
    Assert([doc1[@"data"] isKindOfClass:[CBLBlob class]]);
    data = doc1[@"data"];
    AssertEqual(data.length, 0ull);
    AssertEqualObjects(data.content, content);
    NSInputStream *contentStream = data.contentStream;
    [contentStream open];
    uint8_t buffer[10];
    NSInteger bytesRead = [contentStream read:buffer maxLength:10];
    [contentStream close];
    AssertEqual(bytesRead, 0);
}

- (void)testBlobWithStream {
    CBLDocument* doc = [self.db documentWithID: @"doc1"];
    NSData* content = [@"" dataUsingEncoding:NSUTF8StringEncoding];
    NSInputStream *contentStream = [[NSInputStream alloc] initWithData:content];
    NSError* error;
    CBLBlob *data = [[CBLBlob alloc] initWithContentType:@"text/plain" contentStream:contentStream error:&error];
    Assert(data, @"Failed to create blob: %@", error);
    doc[@"data"] = data;
    
    
    Assert([doc save: &error], @"Saving error: %@", error);
    CBLDocument* doc1 = [[self.db copy] documentWithID: @"doc1"];
    Assert([doc1[@"data"] isKindOfClass:[CBLBlob class]]);
    data = doc1[@"data"];
    AssertEqual(data.length, 0ull);
    AssertEqualObjects(data.content, content);
    contentStream = data.contentStream;
    [contentStream open];
    uint8_t buffer[10];
    NSInteger bytesRead = [contentStream read:buffer maxLength:10];
    [contentStream close];
    AssertEqual(bytesRead, 0);
}

- (void)testMultipleBlobRead {
    CBLDocument* doc = [self.db documentWithID: @"doc1"];
    NSData* content = [@"12345" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error;
    
    CBLBlob* data = [[CBLBlob alloc] initWithContentType:@"text/plain" data:content error:&error];
    Assert(data, @"Failed to create blob: %@", error);
    doc[@"data"] = data;
    
    data = doc[@"data"];
    for(int i = 0; i < 5; i++) {
        AssertEqualObjects(data.content, content);
        NSInputStream *contentStream = data.contentStream;
        [contentStream open];
        uint8_t buffer[10];
        NSInteger bytesRead = [contentStream read:buffer maxLength:10];
        [contentStream close];
        AssertEqual(bytesRead, 5);
    }
   
    Assert([doc save: &error], @"Saving error: %@", error);
    CBLDocument* doc1 = [[self.db copy] documentWithID: @"doc1"];
    Assert([doc1[@"data"] isKindOfClass:[CBLBlob class]]);
    data = doc1[@"data"];
    for(int i = 0; i < 5; i++) {
        AssertEqualObjects(data.content, content);
        NSInputStream *contentStream = data.contentStream;
        [contentStream open];
        uint8_t buffer[10];
        NSInteger bytesRead = [contentStream read:buffer maxLength:10];
        [contentStream close];
        AssertEqual(bytesRead, 5);
    }
}

- (CBLBlob *)createBlob:(NSString *)contentType withData:(NSData *)data error:(NSError **)outError {
    return [[CBLBlob alloc] initWithContentType:contentType data:data error:outError];
}

- (CBLBlob *)createBlob:(NSString *)contentType withStream:(NSInputStream *)stream error:(NSError **)outError {
    return [[CBLBlob alloc] initWithContentType:contentType contentStream:stream error:outError];
}

@end
