//
//  DocumentTest.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/11/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"

#import "CBLBlob.h"
#import "CBLInternal.h"
#import "CBLJSON.h"
#import "CBLDocument+Internal.h"

#include "c4.h"
#include "c4Document+Fleece.h"
#include "Fleece.h"
#include "Fleece+CoreFoundation.h"


@interface TheirsWins : NSObject <CBLConflictResolver>
@end

@implementation TheirsWins

- (CBLReadOnlyDocument*) resolve: (CBLConflict *)conflict {
    return conflict.target;
}

@end


@interface MergeThenTheirsWins : NSObject <CBLConflictResolver>
@end

@implementation MergeThenTheirsWins

- (CBLReadOnlyDocument*) resolve: (CBLConflict *)conflict {
    CBLDocument* resolved = [[CBLDocument alloc] init];
    for (NSString* key in [conflict.commonAncestor allKeys]) {
        [resolved setObject: [conflict.commonAncestor objectForKey: key] forKey: key];
    }
    
    NSMutableSet *changed = [NSMutableSet new];
    for (NSString* key in [conflict.target allKeys]) {
        [resolved setObject: [conflict.target objectForKey: key] forKey: key];
        [changed addObject: key];
    }
    
    for (NSString* key in [conflict.source allKeys]) {
        if(![changed containsObject: key]) {
            [resolved setObject: [conflict.source objectForKey: key] forKey: key];
        }
    }
    return resolved;
}

@end


@interface GiveUp : NSObject <CBLConflictResolver>
@end

@implementation GiveUp

- (CBLReadOnlyDocument*) resolve: (CBLConflict *)conflict {
    return nil;
}

@end


@interface DoNotResolve : NSObject <CBLConflictResolver>
@end

@implementation DoNotResolve

- (CBLReadOnlyDocument*) resolve: (CBLConflict*)conflict {
    NSAssert(NO, @"Resolver should not have been called!");
    return nil;
}

@end


@interface DocumentTest : CBLTestCase

@end


@implementation DocumentTest
{
    CBLDocument* doc;
}


- (void) setUp {
    [super setUp];
    // Make sure resolver isn't being called at inappropriate times by defaulting to one that
    // will raise an exception:
    self.db.conflictResolver = [DoNotResolve new];
    
    doc = [[CBLDocument alloc] initWithID: @"doc1"];
}


- (void) tearDown {
    [super tearDown];
}


- (void) reopenDB {
    [super reopenDB];
    
    self.db.conflictResolver = [DoNotResolve new];
    
    doc = [self.db documentWithID: @"doc1"];
    if (!doc) {
        doc = [[CBLDocument alloc] initWithID: @"doc1"];
    }
}


- (BOOL)saveProperties: (NSDictionary*)props toDocWithID: (NSString*)docID error: (NSError**)error {
    // Save to database:
    BOOL ok = [self.db inBatch: error do: ^{
        C4Slice docIDSlice = c4str([docID cStringUsingEncoding: NSASCIIStringEncoding]);
        C4Document* tricky = c4doc_get(self.db.c4db, docIDSlice, true, NULL);
        
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
    }];
    
    Assert(ok);
    return YES;
}

- (void) testNewDoc {
    CBLDocument* newDoc = [[CBLDocument alloc] init];
    AssertNotNil(newDoc);
    AssertNotNil(newDoc.documentID);
    Assert(newDoc.documentID.length > 0);
    AssertFalse(newDoc.exists);
    AssertFalse(newDoc.isDeleted);
    
    AssertEqualObjects([newDoc toDictionary], @{});
    AssertFalse([newDoc booleanForKey: @"prop"]);
    AssertEqual([newDoc integerForKey: @"prop"], 0);
    AssertEqual([newDoc floatForKey: @"prop"], 0.0);
    AssertEqual([newDoc doubleForKey: @"prop"], 0.0);
    AssertNil([newDoc dateForKey: @"prop"]);
    AssertNil([newDoc stringForKey: @"prop"]);
    AssertNil([newDoc objectForKey: @"prop"]);
    AssertNil([newDoc blobForKey: @"prop"]);
    
    NSError* error;
    Assert([_db saveDocument: newDoc error: &error], @"Error saving: %@", error);
}


- (void) testNewDocWithId {
    CBLDocument* newDoc = [[CBLDocument alloc] initWithID: @"doc-a"];
    AssertNotNil(newDoc);
    AssertEqual(newDoc.documentID, @"doc-a");
    AssertFalse(newDoc.isDeleted);
    
    AssertEqualObjects([newDoc toDictionary], @{});
    AssertFalse([newDoc booleanForKey: @"prop"]);
    AssertEqual([newDoc integerForKey: @"prop"], 0);
    AssertEqual([newDoc floatForKey: @"prop"], 0.0);
    AssertEqual([newDoc doubleForKey: @"prop"], 0.0);
    AssertNil([newDoc dateForKey: @"prop"]);
    AssertNil([newDoc stringForKey: @"prop"]);
    AssertNil([newDoc objectForKey: @"prop"]);
    AssertNil([newDoc blobForKey: @"prop"]);
    
    NSError* error;
    Assert([_db saveDocument: newDoc error: &error], @"Error saving: %@", error);
}


// Verify that round trip NSString -> NSDate -> NSString conversion doesn't alter the string (#1611)
- (void) testJSONDateRoundTrip {
    NSString* dateStr1 = @"2017-02-05T18:14:06.347Z";
    NSDate* date1 = [CBLJSON dateWithJSONObject: dateStr1];
    NSString* dateStr2 = [CBLJSON JSONObjectWithDate: date1];
    NSDate* date2 = [CBLJSON dateWithJSONObject: dateStr2];
    XCTAssertEqualWithAccuracy(date2.timeIntervalSinceReferenceDate,
                               date1.timeIntervalSinceReferenceDate, 0.0001);
    AssertEqualObjects(dateStr2, dateStr1);
}


- (void) testPropertyAccessors {
    // Premitives:
    [doc setBoolean: YES forKey: @"yes"];
    [doc setBoolean: NO forKey: @"no"];
    [doc setDouble: 1.1 forKey: @"double"];
    [doc setFloat: 1.2f forKey: @"float"];
    [doc setInteger: 2 forKey: @"integer"];
    [doc setInteger: 0 forKey: @"zero"];
    
    // Objects:
    [doc setObject: @"str" forKey: @"string"];
    [doc setObject: @(YES) forKey: @"boolObj"];
    [doc setObject: @(1) forKey: @"number"];
    
    [doc setObject: @{@"foo": @"bar"} forKey: @"dict"];
    [doc setObject: @[@"1", @"2"] forKey: @"array"];
    
    // Subdocuments:
    CBLSubdocument* subdoc = [CBLSubdocument subdocument];
    [subdoc setObject: @"scottie" forKey: @"firstname"];
    [subdoc setObject: @"zebra" forKey: @"lastname"];
    [doc setObject: subdoc forKey: @"subdoc"];
    
    // NSNull:
    [doc setObject: [NSNull null] forKey: @"null"];
    [doc setObject: @[[NSNull null], [NSNull null]] forKey: @"nullarray"];
    
    // Date:
    NSDate* date = [NSDate date];
    [doc setObject: date forKey: @"date"];
    
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Error saving: %@", error);
    
    // Primitives:
    AssertEqual([doc booleanForKey: @"yes"], YES);
    AssertEqual([doc booleanForKey: @"no"], NO);
    AssertEqual([doc doubleForKey: @"double"], 1.1);
    AssertEqual([doc floatForKey: @"float"], @(1.2).floatValue);
    AssertEqual([doc integerForKey: @"integer"], 2);
    AssertEqual([doc integerForKey: @"zero"], 0);
    
    // Objects:
    AssertEqualObjects([doc objectForKey: @"string"], @"str");
    AssertEqualObjects([doc objectForKey: @"boolObj"], @(YES));
    AssertEqualObjects([doc objectForKey: @"number"], @(1));
    AssertEqualObjects([((CBLArray*)[doc objectForKey: @"array"]) toArray], (@[@"1", @"2"]));
    AssertEqualObjects([((CBLSubdocument*)[doc objectForKey: @"dict"]) toDictionary], @{@"foo": @"bar"});
    
    // String:
    AssertEqualObjects([doc stringForKey: @"string"], @"str");
    
    // Subdocuments:
    subdoc = [doc subdocumentForKey: @"subdoc"];
    AssertNotNil(subdoc);
    AssertEqualObjects(subdoc, [doc objectForKey: @"subdoc"]);
    AssertEqualObjects([subdoc objectForKey: @"firstname"], @"scottie");
    AssertEqualObjects([subdoc objectForKey: @"lastname"], @"zebra");
    
    // NSNull:
    AssertNil([doc objectForKey: @"null"]);
    AssertEqualObjects([((CBLArray*)[doc objectForKey: @"nullarray"]) toArray], (@[[NSNull null], [NSNull null]]));
    
    // Date:
    AssertEqualObjects([CBLJSON JSONObjectWithDate: [doc dateForKey: @"date"]],
                       [CBLJSON JSONObjectWithDate: date]);
    
    // Boolean:
    Assert([doc booleanForKey:@"double"]);
    Assert([doc booleanForKey:@"float"]);
    Assert([doc booleanForKey:@"integer"]);
    Assert([doc booleanForKey:@"string"]);
    Assert([doc booleanForKey:@"array"]);
    Assert([doc booleanForKey:@"dict"]);
    AssertFalse([doc booleanForKey:@"zero"]);
    AssertFalse([doc booleanForKey:@"null"]);
    
    ////// Reopen the database and get the document again:

    [self reopenDB];
    
    // Primitives:
    AssertEqual([doc booleanForKey: @"yes"], YES);
    AssertEqual([doc booleanForKey: @"no"], NO);
    AssertEqual([doc doubleForKey: @"double"], 1.1);
    AssertEqual([doc floatForKey: @"float"], @(1.2).floatValue);
    AssertEqual([doc integerForKey: @"integer"], 2);
    AssertEqual([doc integerForKey: @"zero"], 0);
    
    // Objects:
    AssertEqualObjects([doc objectForKey: @"string"], @"str");
    AssertEqualObjects([doc objectForKey: @"boolObj"], @(YES));
    AssertEqualObjects([doc objectForKey: @"number"], @(1));
    AssertEqualObjects([((CBLArray*)[doc objectForKey: @"array"]) toArray], (@[@"1", @"2"]));
    AssertEqualObjects([((CBLSubdocument*)[doc objectForKey: @"dict"]) toDictionary], @{@"foo": @"bar"});
    
    // String:
    AssertEqualObjects([doc stringForKey: @"string"], @"str");
    
    // Subdocuments:
    subdoc = [doc subdocumentForKey: @"subdoc"];
    AssertNotNil(subdoc);
    AssertEqualObjects(subdoc, [doc objectForKey: @"subdoc"]);
    AssertEqualObjects([subdoc objectForKey: @"firstname"], @"scottie");
    AssertEqualObjects([subdoc objectForKey: @"lastname"], @"zebra");
    
    // NSNull:
    AssertNil([doc objectForKey: @"null"]);
    AssertEqualObjects([((CBLArray*)[doc objectForKey: @"nullarray"]) toArray], (@[[NSNull null], [NSNull null]]));
    
    // Date:
    AssertEqualObjects([CBLJSON JSONObjectWithDate: [doc dateForKey: @"date"]],
                       [CBLJSON JSONObjectWithDate: date]);
    
    // Boolean:
    Assert([doc booleanForKey:@"double"]);
    Assert([doc booleanForKey:@"float"]);
    Assert([doc booleanForKey:@"integer"]);
    Assert([doc booleanForKey:@"string"]);
    Assert([doc booleanForKey:@"array"]);
    Assert([doc booleanForKey:@"dict"]);
    AssertFalse([doc booleanForKey:@"zero"]);
    AssertFalse([doc booleanForKey:@"null"]);
}


- (void) testRemoveKeys {
    [doc setDictionary: @{ @"type": @"profile",
                           @"name": @"Jason",
                           @"weight": @130.5,
                           @"active": @YES,
                           @"age": @30,
                           @"address": @{
                                   @"street": @"1 milky way.",
                                   @"city": @"galaxy city",
                                   @"zip" : @12345
                                   }
                           }];
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Error saving: %@", error);
    
    [doc setObject: nil forKey: @"name"];
    [doc setObject: nil forKey: @"weight"];
    [doc setObject: nil forKey: @"age"];
    [doc setObject: nil forKey: @"active"];;
    [[doc subdocumentForKey: @"address"] setObject: nil forKey: @"city"];
    
    AssertNil([doc stringForKey: @"name"]);
    AssertEqual([doc floatForKey: @"weight"], 0.0);
    AssertEqual([doc doubleForKey: @"weight"], 0.0);
    AssertEqual([doc integerForKey: @"age"], 0);
    AssertEqual([doc booleanForKey: @"active"], NO);
    
    AssertNil([doc objectForKey: @"name"]);
    AssertNil([doc objectForKey: @"weight"]);
    AssertNil([doc objectForKey: @"age"]);
    AssertNil([doc objectForKey: @"active"]);
    AssertNil([[doc subdocumentForKey: @"address"] objectForKey: @"city"]);
    
    CBLSubdocument* address = [doc subdocumentForKey: @"address"];
    AssertEqualObjects([doc toDictionary], (@{ @"type": @"profile",
                                               @"address": @{
                                                       @"street": @"1 milky way.",
                                                       @"zip" : @12345
                                                       }
                                               }));
    AssertEqualObjects([address toDictionary], (@{ @"street": @"1 milky way.", @"zip" : @12345 }));
    
    // Remove the rest:
    [doc setObject: nil forKey: @"type"];
    [doc setObject: nil forKey: @"address"];
    AssertNil([doc objectForKey: @"type"]);
    AssertNil([doc objectForKey: @"address"]);
    AssertEqualObjects([doc toDictionary], @{});
}


- (void) testContainsKey {
    [doc setDictionary: @{ @"type": @"profile",
                           @"name": @"Jason",
                           @"age": @"30",
                           @"address": @{
                                   @"street": @"1 milky way.",
                                   }
                           }];
    
    Assert([doc containsObjectForKey: @"type"]);
    Assert([doc containsObjectForKey: @"name"]);
    Assert([doc containsObjectForKey: @"address"]);
    AssertFalse([doc containsObjectForKey: @"weight"]);
}


- (void) testDelete {
    [doc setObject: @"profile" forKey: @"type"];
    [doc setObject: @"Scott" forKey: @"name"];
    AssertFalse(doc.isDeleted);
    
    // Delete before save:
    NSError* error;
    AssertFalse([_db deleteDocument: doc error: &error]);
    AssertEqualObjects([doc objectForKey: @"type"], @"profile");
    AssertEqualObjects([doc objectForKey: @"name"], @"Scott");
    
    // Save:
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    AssertFalse(doc.isDeleted);
    
    // Delete:
    Assert([_db deleteDocument: doc error: &error], @"Deleting error: %@", error);
    Assert(doc.isDeleted);
    AssertEqualObjects([doc toDictionary], @{});
}


- (void) testPurge {
    [doc setObject: @"profile" forKey: @"type"];
    [doc setObject: @"Scott" forKey: @"name"];
    AssertFalse(doc.exists);
    AssertFalse(doc.isDeleted);
    
    // Purge before save:
    NSError* error;
    AssertFalse([_db purgeDocument: doc error: &error]);
    AssertEqualObjects([doc objectForKey: @"type"], @"profile");
    AssertEqualObjects([doc objectForKey: @"name"], @"Scott");
    
    // Save:
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    AssertFalse(doc.isDeleted);
    
    // Purge:
    Assert([_db purgeDocument: doc error: &error], @"Purging error: %@", error);
    AssertFalse(doc.isDeleted);
}


- (void) testReopenDB {
    [doc setObject: @"str" forKey: @"string"];
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Error saving: %@", error);

    [self reopenDB];

    doc = [self.db documentWithID: @"doc1"];
    AssertEqualObjects([doc stringForKey: @"string"], @"str");
    AssertEqualObjects([doc toDictionary], @{@"string": @"str"});
}


- (CBLDocument*) setupConflict {
    // Setup a default database conflict resolver
    [doc setObject: @"profile" forKey: @"type"];
    [doc setObject: @"Scott" forKey: @"name"];
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    
    // Force a conflict
    NSMutableDictionary *properties = [[doc toDictionary] mutableCopy];
    properties[@"name"] = @"Scotty";
    BOOL ok = [self saveProperties: properties toDocWithID: [doc documentID] error: &error];
    Assert(ok);
    
    // Change document in memory, so save will trigger a conflict
    [doc setObject: @"Scott Pilgrim" forKey: @"name"];
    
    return doc;
}


- (void)testConflict {
    NSError* error;
    self.db.conflictResolver = [TheirsWins new];
    doc = [self setupConflict];
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    AssertEqualObjects([doc objectForKey: @"name"], @"Scotty");
    
    // Get a new document with its own conflict resolver
    doc = [[CBLDocument alloc] initWithID: @"doc2"];
    
    self.db.conflictResolver = [MergeThenTheirsWins new];
    [doc setObject: @"profile" forKey: @"type"];
    [doc setObject: @"Scott" forKey: @"name"];
    
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    
    // Force a conflict again
    NSMutableDictionary* properties = [[doc toDictionary] mutableCopy];
    properties[@"type"] = @"bio";
    properties[@"gender"] = @"male";
    BOOL ok = [self saveProperties: properties toDocWithID: [doc documentID] error: &error];
    Assert(ok);
    
    // Save and make sure that the correct conflict resolver won
    [doc setObject:@"biography" forKey: @"type"];
    [doc setObject: @(31) forKey: @"age"];
    
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    
    AssertEqual([doc integerForKey: @"age"], 31);
    AssertEqualObjects([doc stringForKey: @"type"], @"bio");
    AssertEqualObjects([doc stringForKey: @"gender"], @"male");
    AssertEqualObjects([doc stringForKey: @"name"], @"Scott");
}


- (void)testConflictResolverGivesUp {
    self.db.conflictResolver = [GiveUp new];
    doc = [self setupConflict];
    NSError* error;
    AssertFalse([_db saveDocument: doc error: &error], @"Save should have failed!");
    AssertEqualObjects(error.domain, @"LiteCore");      //TODO: Should have CBL error domain/code
    AssertEqual(error.code, kC4ErrorConflict);
}


- (void)testDeletionConflict {
    self.db.conflictResolver = [DoNotResolve new];
    doc = [self setupConflict];
    NSError* error;
    Assert([doc deleteDocument: &error], @"Deletion error: %@", error);
    Assert(doc.exists);
    AssertFalse(doc.isDeleted);
    AssertEqualObjects([doc stringForKey: @"name"], @"Scotty");
}


- (void)testConflictMineIsDeeper {
    self.db.conflictResolver = nil;
    doc = [self setupConflict];
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    AssertEqualObjects([doc stringForKey: @"name"], @"Scott Pilgrim");
}


- (void)testConflictTheirsIsDeeper {
    self.db.conflictResolver = nil;
    doc = [self setupConflict];

    // Add another revision to the conflict, so it'll have a higher generation:
    NSMutableDictionary *properties = [[doc toDictionary] mutableCopy];
    properties[@"name"] = @"Scott of the Sahara";
    NSError* error;
    [self saveProperties:properties toDocWithID:[doc documentID] error:&error];

    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    AssertEqualObjects([doc stringForKey: @"name"], @"Scott of the Sahara");
}


- (void)testBlob {
    NSData* content = [@"12345" dataUsingEncoding:NSUTF8StringEncoding];
    NSError* error;
    CBLBlob *data = [[CBLBlob alloc] initWithContentType:@"text/plain" data:content];
    Assert(data, @"Failed to create blob: %@", error);
    [doc setObject: data forKey: @"data"];
    [doc setObject: @"Jim" forKey: @"name"];
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    
    CBLDocument* doc1 = [[self.db copy] documentWithID: @"doc1"];
    AssertEqualObjects([doc objectForKey: @"name"], @"Jim");
    Assert([[doc1 objectForKey: @"data"] isKindOfClass:[CBLBlob class]]);
    data = [doc1 objectForKey: @"data"];
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
    NSData* content = [@"" dataUsingEncoding:NSUTF8StringEncoding];
    NSError* error;
    CBLBlob *data = [[CBLBlob alloc] initWithContentType:@"text/plain" data:content];
    Assert(data, @"Failed to create blob: %@", error);
    [doc setObject: data forKey: @"data"];
    
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    CBLDocument* doc1 = [[self.db copy] documentWithID: @"doc1"];
    Assert([[doc1 objectForKey: @"data"] isKindOfClass:[CBLBlob class]]);
    data = [doc1 objectForKey: @"data"];
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
    NSData* content = [@"" dataUsingEncoding:NSUTF8StringEncoding];
    NSInputStream *contentStream = [[NSInputStream alloc] initWithData:content];
    NSError* error;
    CBLBlob *data = [[CBLBlob alloc] initWithContentType:@"text/plain" contentStream:contentStream];
    Assert(data, @"Failed to create blob: %@", error);
    [doc setObject: data forKey: @"data"];
    
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    CBLDocument* doc1 = [[self.db copy] documentWithID: @"doc1"];
    Assert([[doc1 objectForKey: @"data"] isKindOfClass:[CBLBlob class]]);
    data = [doc1 objectForKey: @"data"];
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
    NSData* content = [@"12345" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error;
    
    CBLBlob* data = [[CBLBlob alloc] initWithContentType:@"text/plain" data:content];
    Assert(data, @"Failed to create blob: %@", error);
    [doc setObject: data forKey: @"data"];
    
    data = [doc objectForKey: @"data"];
    for(int i = 0; i < 5; i++) {
        AssertEqualObjects(data.content, content);
        NSInputStream *contentStream = data.contentStream;
        [contentStream open];
        uint8_t buffer[10];
        NSInteger bytesRead = [contentStream read:buffer maxLength:10];
        [contentStream close];
        AssertEqual(bytesRead, 5);
    }
   
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    CBLDocument* doc1 = [[self.db copy] documentWithID: @"doc1"];
    Assert([[doc1 objectForKey: @"data"] isKindOfClass:[CBLBlob class]]);
    data = [doc1 objectForKey: @"data"];
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


- (void)testReadExistingBlob {
    NSData* content = [@"12345" dataUsingEncoding:NSUTF8StringEncoding];
    NSError* error;
    CBLBlob *data = [[CBLBlob alloc] initWithContentType:@"text/plain" data:content];
    Assert(data, @"Failed to create blob: %@", error);
    [doc setObject: data forKey: @"data"];
    [doc setObject: @"Jim" forKey: @"name"];
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);

    [self reopenDB];

    Assert([[doc objectForKey: @"data"] isKindOfClass:[CBLBlob class]]);
    data = [doc objectForKey: @"data"];
    AssertEqualObjects(data.content, content);
    
    [self reopenDB];

    [doc setObject: @"bar" forKey: @"foo"];
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    Assert([[doc objectForKey: @"data"] isKindOfClass:[CBLBlob class]]);
    data = [doc objectForKey: @"data"];
    AssertEqualObjects(data.content, content);
}


@end
