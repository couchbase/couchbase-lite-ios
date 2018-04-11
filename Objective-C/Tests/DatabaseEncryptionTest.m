//
//  DatabaseEncryptionTest.m
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
#import "CBLDatabase+Internal.h"

@interface DatabaseEncryptionTest : CBLTestCase

@end

@implementation DatabaseEncryptionTest {
    CBLDatabase* _seekrit;
}


- (void) tearDown {
    [_seekrit close: nil];
    [super tearDown];
}

- (CBLDatabase*) openSeekritWithPassword: (nullable NSString*)password error: (NSError**)error {
    CBLDatabaseConfiguration* config = [[CBLDatabaseConfiguration alloc] init];
    if (password)
        config.encryptionKey = [[CBLEncryptionKey alloc] initWithPassword: password];
    config.directory = self.directory;
    return [[CBLDatabase alloc] initWithName: @"seekrit" config: config error: error];
}


- (void) testUnEncryptedDatabase {
    NSError* error;
    _seekrit = [self openSeekritWithPassword: nil error: &error];
    Assert(_seekrit, @"Failed to create unencrypted db: %@", error);
    
    CBLMutableDocument* doc = [self createDocument: nil data: @{@"answer": @(42)}];
    Assert([_seekrit saveDocument: doc error: &error], @"Error when save a document: %@", error);
    [_seekrit close: nil];
    _seekrit = nil;
    
    static const int expectedError = CBLErrorUnreadableDatabase;
    
    // Try to reopen with password (fails):
    [self expectError: CBLErrorDomain code: expectedError in: ^BOOL(NSError **err) {
        return [self openSeekritWithPassword: @"wrong" error: err] != nil;
    }];
    
    // Reopen with no password:
    _seekrit = [self openSeekritWithPassword: nil error: &error];
    Assert(_seekrit, @"Failed to reopen encrypted db: %@", error);
    AssertEqual(_seekrit.count, 1u);
}


- (void) testEncryptedDatabase {
    // Create encrypted database:
    NSError* error;
    _seekrit = [self openSeekritWithPassword: @"letmein" error: &error];
    Assert(_seekrit, @"Failed to reopen encrypted db: %@", error);
    
    CBLMutableDocument* doc = [self createDocument: nil data: @{@"answer": @(42)}];
    Assert([_seekrit saveDocument: doc error: &error], @"Error when save a document: %@", error);
    [_seekrit close: nil];
    _seekrit = nil;
    
    // Reopen without password (fails):
    [self expectError: CBLErrorDomain code: CBLErrorUnreadableDatabase in: ^BOOL(NSError ** err) {
        return [self openSeekritWithPassword: nil error: err] != nil;
    }];
    
    // Reopen with wrong password (fails):
    [self expectError: CBLErrorDomain code: CBLErrorUnreadableDatabase in: ^BOOL(NSError ** err) {
        return [self openSeekritWithPassword: @"wrong" error: err] != nil;
    }];
    
    // Reopen with correct password:
    _seekrit = [self openSeekritWithPassword: @"letmein" error: &error];
    Assert(_seekrit, @"Failed to reopen encrypted db: %@", error);
}


- (void) testDeleteEncryptedDatabase {
    // Create encrypted database:
    NSError* error;
    _seekrit = [self openSeekritWithPassword: @"letmein" error: &error];
    Assert(_seekrit, @"Failed to reopen encrypted db: %@", error);
    
    // Delete database:
    Assert([_seekrit delete: &error], @"Couldn't delete database: %@", error);
    
    // Re-create database:
    _seekrit = [self openSeekritWithPassword: nil error: &error];
    Assert(_seekrit, @"Failed to create formally encrypted db: %@", error);
    AssertEqual(_seekrit.count, 0u);
    Assert([_seekrit close: nil]);
    _seekrit = nil;
    
    // Make sure it doesn't need a password now:
    _seekrit = [self openSeekritWithPassword: nil error: &error];
    Assert(_seekrit, @"Failed to create formally encrypted db: %@", error);
    AssertEqual(_seekrit.count, 0u);
    Assert([_seekrit close: nil]);
    _seekrit = nil;
    
    // Make sure old password doesn't work:
    [self expectError: CBLErrorDomain code: CBLErrorUnreadableDatabase in: ^BOOL(NSError ** err) {
        return [self openSeekritWithPassword: @"letmein" error: err] != nil;
    }];
}


- (void) testCompactEncryptedDatabase {
    // Create encrypted database:
    NSError* error;
    _seekrit = [self openSeekritWithPassword: @"letmein" error: &error];
    Assert(_seekrit, @"Failed to reopen encrypted db: %@", error);
    
    // Create a doc and then update it:
    CBLMutableDocument* doc = [self createDocument: nil data: @{@"answer": @(42)}];
    Assert([_seekrit saveDocument: doc error: &error], @"Saving Error: %@", error);
    
    [doc setValue: @(84) forKey: @"answer"];
    Assert([_seekrit saveDocument: doc error: &error], @"Saving Error: %@", error);
    
    // Compact:
    Assert([_seekrit compact: &error], @"Compaction failed: %@", error);
    
    // Update the document again:
    [doc setValue: @(85) forKey: @"answer"];
    Assert([_seekrit saveDocument: doc error: &error], @"Error when save a document: %@", error);
    
    // Close and re-open:
    Assert([_seekrit close: &error], @"Close failed: %@", error);
    _seekrit = [self openSeekritWithPassword: @"letmein" error: &error];
    Assert(_seekrit, @"Failed to reopen encrypted db: %@", error);
    AssertEqual(_seekrit.count, 1u);
}


- (void) testEncryptedBlobs {
    [self _testEncryptedBlobsWithPassword: @"letmein"];
}


- (void) _testEncryptedBlobsWithPassword: (nullable NSString*)password {
    // Create database with the password:
    NSError* error;
    _seekrit = [self openSeekritWithPassword: password error: &error];
    Assert(_seekrit, @"Couldn't open db: %@", error);
    
    // Save a doc with a blob:
    CBLMutableDocument* doc = [self createDocument: @"att"];
    NSData* body = [@"This is a blob!" dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType: @"text/plain" data: body];
    [doc setValue: blob forKey: @"blob"];
    Assert([_seekrit saveDocument: doc error: &error], @"Error when save a document: %@", error);
    
    // Read content from the raw blob file:
    blob = [doc blobForKey: @"blob"];
    Assert(blob.digest);
    
    NSString* fileName = [blob.digest substringFromIndex: 5];
    fileName = [fileName stringByReplacingOccurrencesOfString: @"/" withString: @"_"];
    NSString* path = [NSString stringWithFormat: @"%@Attachments/%@.blob", _seekrit.path, fileName];
    NSData* raw = [NSData dataWithContentsOfFile: path];
    Assert(raw != nil);
    if (password)
        Assert(![raw isEqualToData: body], @"Oops, attachment was not encrypted");
    else
        Assert([raw isEqualToData: body], @"Oops, attachment was encrypted");
    
    // Check blob content:
    CBLDocument* savedDoc = [_seekrit documentWithID: @"att"];
    blob = [savedDoc blobForKey: @"blob"];
    Assert(blob.digest);
    NSString* content = [[NSString alloc] initWithData: blob.content encoding: NSUTF8StringEncoding];
    AssertEqualObjects(content, @"This is a blob!");
}


- (void) testMultipleDatabases {
    // Create encryped database:
    NSError* error;
    _seekrit = [self openSeekritWithPassword: @"seekrit" error: &error];
    
    // Get another instance of the database:
    CBLDatabase* seekrit2 = [self openSeekritWithPassword: @"seekrit" error: &error];
    Assert(seekrit2);
    Assert([seekrit2 close: nil]);
    
    // Try rekey:
    CBLEncryptionKey* newKey = [[CBLEncryptionKey alloc] initWithPassword: @"foobar"];
    Assert([_seekrit setEncryptionKey:newKey error: &error], @"Cannot rekey: %@", error);
}


- (void) testAddKey     { [self rekeyUsingOldPassword: nil newPassword: @"letmein"]; }
- (void) testReKey      { [self rekeyUsingOldPassword: @"letmein" newPassword: @"letmeout"]; }
- (void) testRemoveKey  { [self rekeyUsingOldPassword: @"letmein" newPassword: nil]; }


- (void) rekeyUsingOldPassword: (nullable NSString*)oldPass newPassword: (nullable NSString*)newPass {
    // First run the encryped blobs test to populate the database:
    [self _testEncryptedBlobsWithPassword: oldPass];
    
    // Create some documents:
    NSError* error;
    [_seekrit inBatch: &error usingBlock: ^{
        for (unsigned i=0; i<100; i++) {
            CBLMutableDocument* doc = [self createDocument: nil data: @{@"seq": @(i)}];
            [_seekrit saveDocument: doc error: nil];
        }
    }];
    
    // Rekey:
    CBLEncryptionKey* newKey = newPass ? [[CBLEncryptionKey alloc] initWithPassword: newPass] : nil;
    Assert([_seekrit setEncryptionKey: newKey error: &error],
           @"Error changing encryption key: %@", error);
    
    // Close & reopen seekrit:
    Assert([_seekrit close: &error], @"Couldn't close seekrit: %@", error);
    _seekrit = nil;
    
    // Reopen the database with the new key:
    CBLDatabase* seekrit2 = [self openSeekritWithPassword: newPass error: &error];
    Assert(seekrit2, @"Couldn't reopen seekrit: %@", error);
    _seekrit = seekrit2;
    
    // Check the document and its attachment:
    CBLDocument* doc = [_seekrit documentWithID: @"att"];
    CBLBlob* blob = [doc blobForKey: @"blob"];
    Assert(blob.content);
    NSString* content = [[NSString alloc] initWithData: blob.content encoding: NSUTF8StringEncoding];
    AssertEqualObjects(content, @"This is a blob!");
    
    // Query documents:
    CBLQueryExpression* SEQ = [CBLQueryExpression property: @"seq"];
    CBLQuery* query = [CBLQueryBuilder select: @[[CBLQuerySelectResult expression: SEQ]]
                                         from: [CBLQueryDataSource database: _seekrit]
                                        where: [SEQ notNullOrMissing]
                                      orderBy: @[[CBLQueryOrdering expression: SEQ]]];
    CBLQueryResultSet* rs = [query execute: &error];
    Assert(rs, @"Error when running the query: %@", error);
    AssertEqual(rs.allObjects.count, 100u);
    
    NSInteger i = 0;
    for (CBLQueryResult *r in rs) {
        AssertEqual([r integerAtIndex: 0], i++);
    }
}


@end
