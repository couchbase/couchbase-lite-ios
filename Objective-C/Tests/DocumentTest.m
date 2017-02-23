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
{
    CBLDocument* doc;
}


- (void) setUp {
    [super setUp];
    // Make sure resolver isn't being called at inappropriate times by defaulting to one that
    // will raise an exception:
    self.db.conflictResolver = [DoNotResolve new];
    doc = [self.db documentWithID: @"doc1"];
}


- (void) tearDown {
    // Avoid "Closing database with 1 unsaved docs" warning:
    [doc revert];

    [super tearDown];
}


- (void) reopenDB {
    [super reopenDB];
    
    self.db.conflictResolver = [DoNotResolve new];
    doc = [self.db documentWithID: @"doc1"];
}


- (BOOL)saveProperties:(NSDictionary *)props toDocWithID:(NSString *)docID error:(NSError **)error {
    // Save to database:
    BOOL ok = [self.db inBatch:error do: ^{
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
    }];
    
    Assert(ok);
    return YES;
}

- (void) testNewDoc {
    NSError* error;
    
    doc = [self.db document];
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
    Assert([doc save: &error], @"Error saving: %@", error);
    
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
    AssertEqualObjects([doc objectForKey: @"array"], (@[@"1", @"2"]));
    AssertEqualObjects(((CBLSubdocument*)[doc objectForKey: @"dict"]).properties, @{@"foo": @"bar"});
    
    // String:
    AssertEqualObjects([doc stringForKey: @"string"], @"str");
    
    // Subdocuments:
    subdoc = [doc subdocumentForKey: @"subdoc"];
    AssertNotNil(subdoc);
    AssertEqualObjects(subdoc, [doc objectForKey: @"subdoc"]);
    AssertEqualObjects([subdoc objectForKey: @"firstname"], @"scottie");
    AssertEqualObjects([subdoc objectForKey: @"lastname"], @"zebra");
    
    // NSNull:
    AssertEqualObjects([doc objectForKey: @"null"], [NSNull null]);
    AssertEqualObjects([doc objectForKey: @"nullarray"], (@[[NSNull null], [NSNull null]]));
    
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
    AssertEqualObjects([doc objectForKey: @"array"], (@[@"1", @"2"]));
    AssertEqualObjects(((CBLSubdocument*)[doc objectForKey: @"dict"]).properties, @{@"foo": @"bar"});
    
    // String:
    AssertEqualObjects([doc stringForKey: @"string"], @"str");
    
    // Subdocuments:
    subdoc = [doc subdocumentForKey: @"subdoc"];
    AssertNotNil(subdoc);
    AssertEqualObjects(subdoc, [doc objectForKey: @"subdoc"]);
    AssertEqualObjects([subdoc objectForKey: @"firstname"], @"scottie");
    AssertEqualObjects([subdoc objectForKey: @"lastname"], @"zebra");
    
    // NSNull:
    AssertEqualObjects([doc objectForKey: @"null"], [NSNull null]);
    AssertEqualObjects([doc objectForKey: @"nullarray"], (@[[NSNull null], [NSNull null]]));
    
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


- (void) testProperties {
    doc[@"type"] = @"demo";
    doc[@"weight"] = @12.5;
    doc[@"tags"] = @[@"useless", @"temporary"];
    
    AssertEqualObjects(doc[@"type"], @"demo");
    AssertEqual([doc doubleForKey: @"weight"], 12.5);
    AssertEqualObjects(doc.properties,
        (@{@"type": @"demo", @"weight": @12.5, @"tags": @[@"useless", @"temporary"]}));
}


- (void) testRemoveKeys {
    doc.properties = @{ @"type": @"profile",
                        @"name": @"Jason",
                        @"weight": @130.5,
                        @"active": @YES,
                        @"age": @30,
                        @"address": @{
                                @"street": @"1 milky way.",
                                @"city": @"galaxy city",
                                @"zip" : @12345
                                }
                        };
    NSError* error;
    Assert([doc save: &error], @"Error saving: %@", error);
    
    doc[@"name"] = nil;
    doc[@"weight"] = nil;
    doc[@"age"] = nil;
    doc[@"active"] = nil;
    doc[@"address"][@"city"] = nil;
    
    AssertNil([doc stringForKey: @"name"]);
    AssertEqual([doc floatForKey: @"weight"], 0.0);
    AssertEqual([doc doubleForKey: @"weight"], 0.0);
    AssertEqual([doc integerForKey: @"age"], 0);
    AssertEqual([doc booleanForKey: @"active"], NO);
    
    AssertNil(doc[@"name"]);
    AssertNil(doc[@"weight"]);
    AssertNil(doc[@"age"]);
    AssertNil(doc[@"active"]);
    AssertNil(doc[@"address"][@"city"]);
    
    CBLSubdocument* address = doc[@"address"];
    AssertEqualObjects(doc.properties, (@{ @"type": @"profile",
                                           @"address": address }));
    AssertEqualObjects(address.properties, (@{ @"street": @"1 milky way.",
                                               @"zip" : @12345 }));
    
    // Remove the rest:
    doc[@"type"] = nil;
    doc[@"address"] = nil;
    AssertNil(doc[@"type"]);
    AssertNil(doc[@"address"]);
    AssertEqualObjects(doc.properties, @{});
}


- (void) testContainsKey {
    doc.properties = @{ @"type": @"profile",
                        @"name": @"Jason",
                        @"age": @"30",
                        @"address": @{
                                @"street": @"1 milky way.",
                                }
                        };
    
    Assert([doc containsObjectForKey: @"type"]);
    Assert([doc containsObjectForKey: @"name"]);
    Assert([doc containsObjectForKey: @"address"]);
    AssertFalse([doc containsObjectForKey: @"weight"]);
    
    NSError* error;
    Assert([doc save: &error], @"Error saving: %@", error);
    
    [self reopenDB];
    
    doc[@"modified"] = @(YES);
    
    // Access a subdocument to load the subdocument into cache:
    AssertNotNil(doc[@"address"]);
    
    Assert([doc containsObjectForKey: @"type"]);
    Assert([doc containsObjectForKey: @"name"]);
    Assert([doc containsObjectForKey: @"age"]);
    Assert([doc containsObjectForKey: @"address"]);
    Assert([doc containsObjectForKey: @"modified"]);
    AssertFalse([doc containsObjectForKey: @"weight"]);
}


- (void) testDelete {
    doc[@"type"] = @"profile";
    doc[@"name"] = @"Scott";
    AssertFalse(doc.exists);
    AssertFalse(doc.isDeleted);
    
    // Delete before save:
    AssertFalse([doc deleteDocument: nil]);
    AssertEqualObjects(doc[@"type"], @"profile");
    AssertEqualObjects(doc[@"name"], @"Scott");
    
    // Save:
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);
    Assert(doc.exists);
    AssertFalse(doc.isDeleted);
    
    // Delete:
    Assert([doc deleteDocument: &error], @"Deleting error: %@", error);
    Assert(doc.exists);
    Assert(doc.isDeleted);
    AssertNil(doc.properties);
}


- (void) testPurge {
    doc[@"type"] = @"profile";
    doc[@"name"] = @"Scott";
    AssertFalse(doc.exists);
    AssertFalse(doc.isDeleted);
    
    // Purge before save:
    AssertFalse([doc purge: nil]);
    AssertEqualObjects(doc[@"type"], @"profile");
    AssertEqualObjects(doc[@"name"], @"Scott");
    
    // Save:
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);
    Assert(doc.exists);
    AssertFalse(doc.isDeleted);
    
    // Purge:
    Assert([doc purge: &error], @"Purging error: %@", error);
    AssertFalse(doc.exists);
    AssertFalse(doc.isDeleted);
}


- (void) testRevert {
    doc[@"type"] = @"profile";
    doc[@"name"] = @"Scott";
    CBLSubdocument* address = [CBLSubdocument subdocument];
    address[@"street"] = @"1 Star Way.";
    doc[@"address"] = address;
    
    // Revert before save:
    [doc revert];
    AssertNil(doc[@"type"]);
    AssertNil(doc[@"name"]);
    AssertNil(doc[@"address"]);
    AssertNil(address.parent);
    AssertNil(address.document);
    AssertNil(address.properties);
    
    // Save:
    doc[@"type"] = @"profile";
    doc[@"name"] = @"Scott";
    address = [CBLSubdocument subdocument];
    address[@"street"] = @"1 Star Way.";
    doc[@"address"] = address;
    
    CBLSubdocument* phones = [CBLSubdocument subdocument];
    phones[@"mobile"] = @"650-123-4567";
    doc[@"phones"] = phones;
    
    CBLSubdocument* r1 = [CBLSubdocument subdocument];
    r1[@"name"] = @"Jason";
    CBLSubdocument* r2 = [CBLSubdocument subdocument];
    r2[@"name"] = @"John";
    doc[@"references"] = @[r1, r2];
    
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);
    AssertEqualObjects(doc[@"type"], @"profile");
    AssertEqualObjects(doc[@"name"], @"Scott");
    AssertEqualObjects(doc[@"address"][@"street"], @"1 Star Way.");
    AssertEqualObjects(doc[@"phones"][@"mobile"], @"650-123-4567");
    AssertEqualObjects(doc[@"references"][0][@"name"], @"Jason");
    AssertEqualObjects(doc[@"references"][1][@"name"], @"John");
    
    // Make some changes:
    doc[@"type"] = @"user";
    doc[@"name"] = nil;
    AssertNil(doc[@"name"]);
    doc[@"address"][@"street"] = @"1 Space Dr.";
    doc[@"address"][@"zip"] = @"88888";
    doc[@"phones"] = nil;
    
    CBLSubdocument* r3 = [CBLSubdocument subdocument];
    r3[@"name"] = @"Jack";
    doc[@"references"] = @[r3, r2, r1];
    
    AssertEqualObjects(doc[@"type"], @"user");
    AssertNil(doc[@"name"]);
    AssertEqualObjects(doc[@"address"][@"street"], @"1 Space Dr.");
    AssertEqualObjects(doc[@"address"][@"zip"], @"88888");
    AssertNil(doc[@"phones"]);
    AssertEqualObjects(doc[@"references"][0][@"name"], @"Jack");
    AssertEqualObjects(doc[@"references"][1][@"name"], @"John");
    AssertEqualObjects(doc[@"references"][2][@"name"], @"Jason");
    
    // Revert:
    [doc revert];
    AssertEqualObjects(doc[@"type"], @"profile");
    AssertEqualObjects(doc[@"name"], @"Scott");
    AssertEqualObjects(doc[@"address"][@"street"], @"1 Star Way.");
    AssertNil(doc[@"address"][@"zip"]);
    AssertEqualObjects(doc[@"phones"][@"mobile"], @"650-123-4567");
    AssertEqualObjects(doc[@"references"][0][@"name"], @"Jason");
    AssertEqualObjects(doc[@"references"][1][@"name"], @"John");
}


- (void) testReopenDB {
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
    doc = [self setupConflict];
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
    doc = [self setupConflict];
    NSError* error;
    AssertFalse([doc save: &error], @"Save should have failed!");
    AssertEqualObjects(error.domain, @"LiteCore");      //TODO: Should have CBL error domain/code
    AssertEqual(error.code, kC4ErrorConflict);
    Assert(doc.hasChanges);
}


- (void)testDeletionConflict {
    self.db.conflictResolver = [DoNotResolve new];
    doc = [self setupConflict];
    NSError* error;
    Assert([doc deleteDocument: &error], @"Deletion error: %@", error);
    Assert(doc.exists);
    AssertFalse(doc.isDeleted);
    AssertEqualObjects(doc[@"name"], @"Scotty");
}


- (void)testConflictMineIsDeeper {
    self.db.conflictResolver = nil;
    doc = [self setupConflict];
    NSError* error;
    Assert([doc save: &error], @"Saving error: %@", error);
    AssertEqualObjects(doc[@"name"], @"Scott Pilgrim");
}


- (void)testConflictTheirsIsDeeper {
    self.db.conflictResolver = nil;
    doc = [self setupConflict];

    // Add another revision to the conflict, so it'll have a higher generation:
    NSMutableDictionary *properties = [doc.properties mutableCopy];
    properties[@"name"] = @"Scott of the Sahara";
    NSError* error;
    [self saveProperties:properties toDocWithID:[doc documentID] error:&error];

    Assert([doc save: &error], @"Saving error: %@", error);
    AssertEqualObjects(doc[@"name"], @"Scott of the Sahara");
}


- (void)testBlob {
    NSData* content = [@"12345" dataUsingEncoding:NSUTF8StringEncoding];
    NSError* error;
    CBLBlob *data = [[CBLBlob alloc] initWithContentType:@"text/plain" data:content];
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
    NSData* content = [@"" dataUsingEncoding:NSUTF8StringEncoding];
    NSError* error;
    CBLBlob *data = [[CBLBlob alloc] initWithContentType:@"text/plain" data:content];
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
    NSData* content = [@"" dataUsingEncoding:NSUTF8StringEncoding];
    NSInputStream *contentStream = [[NSInputStream alloc] initWithData:content];
    NSError* error;
    CBLBlob *data = [[CBLBlob alloc] initWithContentType:@"text/plain" contentStream:contentStream];
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
    NSData* content = [@"12345" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error;
    
    CBLBlob* data = [[CBLBlob alloc] initWithContentType:@"text/plain" data:content];
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


- (void)testReadExistingBlob {
    NSData* content = [@"12345" dataUsingEncoding:NSUTF8StringEncoding];
    NSError* error;
    CBLBlob *data = [[CBLBlob alloc] initWithContentType:@"text/plain" data:content];
    Assert(data, @"Failed to create blob: %@", error);
    doc[@"data"] = data;
    doc[@"name"] = @"Jim";
    Assert([doc save: &error], @"Saving error: %@", error);

    [self reopenDB];

    Assert([doc[@"data"] isKindOfClass:[CBLBlob class]]);
    data = doc[@"data"];
    AssertEqualObjects(data.content, content);
    
    [self reopenDB];

    doc[@"foo"] = @"bar";
    Assert([doc save: &error], @"Saving error: %@", error);
    Assert([doc[@"data"] isKindOfClass:[CBLBlob class]]);
    data = doc[@"data"];
    AssertEqualObjects(data.content, content);
}


@end
