//
//  DatabaseEncryption_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/16/15.
//
//

#import "CBLTestCase.h"
#import "CBL_SQLiteStorage.h"
#import "CBL_Attachment.h"
#import "CBL_BlobStore.h"


@interface CBL_BlobStore ()
- (NSString*) rawPathForKey: (CBLBlobKey)key;
@end



@interface DatabaseEncryption_Tests : CBLTestCaseWithDB
@end


@implementation DatabaseEncryption_Tests


- (void) tearDown {
    CBLEnableMockEncryption = NO;
    [super tearDown];
}


- (void) test_EncryptionFailsGracefully {
    Assert([dbmgr registerEncryptionKey: @"123456" forDatabaseNamed: @"seekrit"]);
    NSError* error;
    CBLDatabase* seekrit = [dbmgr databaseNamed: @"seekrit" error: &error];
    if (seekrit == nil)
        AssertEq(error.code, 501 /*Not Implemented*/);
}


- (void) test_UnEncryptedDB {
    CBLEnableMockEncryption = YES;

    // Create unencrypted DB:
    NSError* error;
    CBLDatabase* seekrit = [dbmgr databaseNamed: @"seekrit" error: &error];
    Assert(seekrit, @"Failed to create encrypted db: %@", error);
    [self createDocumentWithProperties: @{@"answer": @42} inDatabase: seekrit];
    Assert([seekrit close: NULL]);

    // Try to reopen with password (fails):
    [dbmgr registerEncryptionKey: @"wrong" forDatabaseNamed: @"seekrit"];
    seekrit = [dbmgr databaseNamed: @"seekrit" error: &error];
    AssertNil(seekrit, @"Shouldn't have been able to reopen encrypted db with wrong password");
    AssertEq(error.code, (self.isSQLiteDB ? 401 : 501));

    // Reopen with no password:
    [dbmgr registerEncryptionKey: nil forDatabaseNamed: @"seekrit"];
    seekrit = [dbmgr databaseNamed: @"seekrit" error: &error];
    Assert(seekrit, @"Failed to reopen encrypted db: %@", error);
    AssertEq(seekrit.documentCount, 1u);
}


- (void) test_EncryptedDB {
    if (!self.isSQLiteDB)
        return;
    CBLEnableMockEncryption = YES;

    // Create encrypted DB:
    NSError* error;
    [dbmgr registerEncryptionKey: @"letmein" forDatabaseNamed: @"seekrit"];
    CBLDatabase* seekrit = [dbmgr databaseNamed: @"seekrit" error: &error];
    Assert(seekrit, @"Failed to create encrypted db: %@", error);
    [self createDocumentWithProperties: @{@"answer": @42} inDatabase: seekrit];
    Assert([seekrit close: NULL]);

    // Try to reopen without the password (fails):
    [dbmgr registerEncryptionKey: nil forDatabaseNamed: @"seekrit"];
    seekrit = [dbmgr databaseNamed: @"seekrit" error: &error];
    AssertNil(seekrit, @"Shouldn't have been able to reopen encrypted db w/o password");
    AssertEq(error.code, 401);

    // Try to reopen with wrong password (fails):
    [dbmgr registerEncryptionKey: @"wrong" forDatabaseNamed: @"seekrit"];
    seekrit = [dbmgr databaseNamed: @"seekrit" error: &error];
    AssertNil(seekrit, @"Shouldn't have been able to reopen encrypted db with wrong password");
    AssertEq(error.code, 401);

    // Reopen with correct password:
    [dbmgr registerEncryptionKey: @"letmein" forDatabaseNamed: @"seekrit"];
    seekrit = [dbmgr databaseNamed: @"seekrit" error: &error];
    Assert(seekrit, @"Failed to reopen encrypted db: %@", error);
    AssertEq(seekrit.documentCount, 1u);
}




- (void) test_DeleteEncryptedDB {
    if (!self.isSQLiteDB)
        return;
    CBLEnableMockEncryption = YES;

    // Create encrypted DB:
    NSError* error;
    [dbmgr registerEncryptionKey: @"letmein" forDatabaseNamed: @"seekrit"];
    CBLDatabase* seekrit = [dbmgr databaseNamed: @"seekrit" error: &error];
    Assert(seekrit, @"Failed to create encrypted db: %@", error);
    [self createDocumentWithProperties: @{@"answer": @42} inDatabase: seekrit];

    // Delete db; this also unregisters its password:
    Assert([seekrit deleteDatabase: NULL], @"Couldn't delete database");

    // Re-create database:
    seekrit = [dbmgr databaseNamed: @"seekrit" error: &error];
    Assert(seekrit, @"Failed to re-create formerly encrypted db: %@", error);
    AssertEq(seekrit.documentCount, 0u);
    Assert([seekrit close: NULL]);

    // Make sure it doesn't need a password now:
    [dbmgr registerEncryptionKey: nil forDatabaseNamed: @"seekrit"];
    seekrit = [dbmgr databaseNamed: @"seekrit" error: &error];
    AssertEq(seekrit.documentCount, 0u);
    Assert([seekrit close: NULL]);

    // Make sure old password doesn't work:
    [dbmgr registerEncryptionKey: @"letmein" forDatabaseNamed: @"seekrit"];
    seekrit = [dbmgr databaseNamed: @"seekrit" error: &error];
    AssertNil(seekrit, @"Password opened unencrypted db!");
    AssertEq(error.code, 401);
}


- (void) test07_EncryptedAttachments {
    if (!self.isSQLiteDB)
        return;
    CBLEnableMockEncryption = YES;
    [dbmgr registerEncryptionKey: @"letmein" forDatabaseNamed: @"seekrit"];
    CBLDatabase* seekrit = [dbmgr databaseNamed: @"seekrit" error: NULL];
    Assert(seekrit);

    // Save a doc with an attachment:
    CBLDocument* doc = [seekrit documentWithID: @"att"];
    NSData* body = [@"This is a test attachment!" dataUsingEncoding: NSUTF8StringEncoding];
    CBLUnsavedRevision *rev = [doc newRevision];
    [rev setAttachmentNamed: @"att.txt" withContentType: @"text/plain; charset=utf-8" content:body];
    NSError* error;
    CBLSavedRevision* savedRev = [rev save: &error];
    Assert(savedRev, @"Saving doc failed: %@", error);

    // Read the raw attachment file and make sure it's not cleartext:
    NSString* digest = savedRev[@"_attachments"][@"att.txt"][@"digest"];
    Assert(digest);
    CBLBlobKey attKey;
    Assert([CBL_Attachment digest: digest toBlobKey: &attKey]);
    NSString* path = [seekrit.attachmentStore rawPathForKey: attKey];
    NSData* raw = [NSData dataWithContentsOfFile: path];
    Assert(raw != nil);
    Assert(![raw isEqual: body], @"Oops, attachment was not encrypted");
}


@end
