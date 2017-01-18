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

@interface DocumentTest : CBLTestCase

@end


@implementation DocumentTest


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

- (void)testBlob {
    CBLDocument* doc = [self.db documentWithID: @"doc1"];
    NSData* content = [@"12345" dataUsingEncoding:NSUTF8StringEncoding];
    NSError* error;
    CBLBlob *data = [[CBLBlob alloc] initWithContentType:@"text/plain" data:content error:&error];
    Assert(data, @"Failed to create blob: %@", error);
    doc[@"data"] = data;
    Assert([doc save: &error], @"Saving error: %@", error);
    
    CBLDocument* doc1 = [[self.db copy] documentWithID: @"doc1"];
    Assert([doc1[@"data"] isKindOfClass:[CBLBlob class]]);
    data = doc1[@"data"];
    AssertEqual(data.length, 5);
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
    AssertEqual(data.length, 0);
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
    AssertEqual(data.length, 0);
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

- (void)testInvalidBlobs {
    NSError *error;
    CBLBlob* data = [self createBlob:nil withData:nil error:&error];
    AssertNil(data);
    
    data = [self createBlob:@"application/foo" withData:nil error:&error];
    AssertNil(data);
    
    NSData *content = [@"12345" dataUsingEncoding:NSUTF8StringEncoding];
    data = [self createBlob:nil withData:content error:&error];
    AssertNil(data);
    
    data = [self createBlob:nil withStream:nil error:&error];
    AssertNil(data);
    
    NSInputStream* contentStream = [[NSInputStream alloc] initWithData:content];
    data = [self createBlob:nil withStream:contentStream error:&error];
    AssertNil(data);
    
    data = [self createBlob:@"application/foo" withStream:nil error:&error];
    AssertNil(data);
}

@end
