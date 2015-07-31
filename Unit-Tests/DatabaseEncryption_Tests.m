//
//  DatabaseEncryption_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/16/15.
//
//

#import "CBLTestCase.h"
#import "CBL_SQLiteStorage.h"


@interface DatabaseEncryption_Tests : CBLTestCaseWithDB
@end


@implementation DatabaseEncryption_Tests


- (void) tearDown {
    CBLEnableMockEncryption = NO;
    [super tearDown];
}


- (void) test01_EncryptionFailsGracefully {
    Assert([dbmgr registerEncryptionKey: @"123456" forDatabaseNamed: @"seekrit"]);
    [self allowWarningsIn:^{
        NSError* error;
        CBLDatabase* seekrit = [dbmgr databaseNamed: @"seekrit" error: &error];
        if (seekrit == nil)
            AssertEq(error.code, 501 /*Not Implemented*/);
    }];
}


- (void) test02_UnEncryptedDB {
    CBLEnableMockEncryption = YES;

    // Create unencrypted DB:
    NSError* error;
    __block CBLDatabase* seekrit = [dbmgr databaseNamed: @"seekrit" error: &error];
    Assert(seekrit, @"Failed to create encrypted db: %@", error);
    [self createDocumentWithProperties: @{@"answer": @42} inDatabase: seekrit];
    Assert([seekrit close: NULL]);

    // Try to reopen with password (fails):
    [self allowWarningsIn:^{
        [dbmgr registerEncryptionKey: @"wrong" forDatabaseNamed: @"seekrit"];
        NSError* error;
        seekrit = [dbmgr databaseNamed: @"seekrit" error: &error];
        AssertNil(seekrit, @"Shouldn't have been able to reopen encrypted db with wrong password");
        AssertEq(error.code, 401);
    }];

    // Reopen with no password:
    [dbmgr registerEncryptionKey: nil forDatabaseNamed: @"seekrit"];
    seekrit = [dbmgr databaseNamed: @"seekrit" error: &error];
    Assert(seekrit, @"Failed to reopen encrypted db: %@", error);
    AssertEq(seekrit.documentCount, 1u);
}


- (void) test03_EncryptedDB {
    CBLEnableMockEncryption = YES;

    // Create encrypted DB:
    NSError* error;
    [dbmgr registerEncryptionKey: @"letmein" forDatabaseNamed: @"seekrit"];
    __block CBLDatabase* seekrit = [dbmgr databaseNamed: @"seekrit" error: &error];
    Assert(seekrit, @"Failed to create encrypted db: %@", error);
    [self createDocumentWithProperties: @{@"answer": @42} inDatabase: seekrit];
    Assert([seekrit close: NULL]);

    // Try to reopen without the password (fails):
    [self allowWarningsIn:^{
        [dbmgr registerEncryptionKey: nil forDatabaseNamed: @"seekrit"];
        NSError* error;
        seekrit = [dbmgr databaseNamed: @"seekrit" error: &error];
        AssertNil(seekrit, @"Shouldn't have been able to reopen encrypted db w/o password");
        AssertEq(error.code, 401);

        // Try to reopen with wrong password (fails):
        [dbmgr registerEncryptionKey: @"wrong" forDatabaseNamed: @"seekrit"];
        seekrit = [dbmgr databaseNamed: @"seekrit" error: &error];
        AssertNil(seekrit, @"Shouldn't have been able to reopen encrypted db with wrong password");
        AssertEq(error.code, 401);
    }];

    // Reopen with correct password:
    [dbmgr registerEncryptionKey: @"letmein" forDatabaseNamed: @"seekrit"];
    seekrit = [dbmgr databaseNamed: @"seekrit" error: &error];
    Assert(seekrit, @"Failed to reopen encrypted db: %@", error);
    AssertEq(seekrit.documentCount, 1u);
}


- (void) test04_DeleteEncryptedDB {
    CBLEnableMockEncryption = YES;

    // Create encrypted DB:
    __block NSError* error;
    [dbmgr registerEncryptionKey: @"letmein" forDatabaseNamed: @"seekrit"];
    __block CBLDatabase* seekrit = [dbmgr databaseNamed: @"seekrit" error: &error];
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
    [self allowWarningsIn:^{
        seekrit = [dbmgr databaseNamed: @"seekrit" error: &error];
    }];
    AssertNil(seekrit, @"Password opened unencrypted db!");
    AssertEq(error.code, 401);
}


- (void) test05_CompactEncryptedDB {
    CBLEnableMockEncryption = YES;

    // Create encrypted DB:
    __block NSError* error;
    [dbmgr registerEncryptionKey: @"letmein" forDatabaseNamed: @"seekrit"];
    __block CBLDatabase* seekrit = [dbmgr databaseNamed: @"seekrit" error: &error];
    Assert(seekrit, @"Failed to create encrypted db: %@", error);

    // Create a doc and then update it:
    CBLDocument* doc = [self createDocumentWithProperties: @{@"answer": @42} inDatabase: seekrit];
    [doc update: ^BOOL(CBLUnsavedRevision *rev) {
        rev[@"foo" ] = @84;
        return YES;
    } error: NULL];

    // Compact:
    Assert([seekrit compact: &error], @"Compaction failed: %@", error);

    // Add a document:
    [doc update:^BOOL(CBLUnsavedRevision *rev) {
        rev[@"foo"] = @85;
        return YES;
    } error: NULL];

    // Close and re-open:
    Assert([seekrit close: &error], @"Close failed: %@", error);
    [dbmgr registerEncryptionKey: @"letmein" forDatabaseNamed: @"seekrit"];
    seekrit = [dbmgr databaseNamed: @"seekrit" error: &error];
    Assert(seekrit, @"Failed to reopen encrypted db: %@", error);
    AssertEq(seekrit.documentCount, 1u);
}


- (void) test06_Keychain {
#if !TARGET_OS_IPHONE
    CBLEnableMockEncryption = YES;

    // Create encrypted DB:
    NSError* error;
    Assert([dbmgr encryptDatabaseNamed: @"seekrit"], @"encryptDatabaseNamed failed");
    __block CBLDatabase* seekrit = [dbmgr databaseNamed: @"seekrit" error: &error];
    Assert(seekrit, @"Failed to create encrypted db: %@", error);
    [self createDocumentWithProperties: @{@"answer": @42} inDatabase: seekrit];
    Assert([seekrit close: NULL]);

    // Try to reopen without the password (fails):
    [self allowWarningsIn:^{
        [dbmgr registerEncryptionKey: nil forDatabaseNamed: @"seekrit"];
        NSError* error;
        seekrit = [dbmgr databaseNamed: @"seekrit" error: &error];
        AssertNil(seekrit, @"Shouldn't have been able to reopen encrypted db w/o password");
        AssertEq(error.code, 401);

        // Try to reopen with wrong password (fails):
        [dbmgr registerEncryptionKey: @"wrong" forDatabaseNamed: @"seekrit"];
        seekrit = [dbmgr databaseNamed: @"seekrit" error: &error];
        AssertNil(seekrit, @"Shouldn't have been able to reopen encrypted db with wrong password");
        AssertEq(error.code, 401);
    }];

    // Reopen with correct password:
    Assert([dbmgr encryptDatabaseNamed: @"seekrit"], @"encryptDatabaseNamed failed");
    seekrit = [dbmgr databaseNamed: @"seekrit" error: &error];
    Assert(seekrit, @"Failed to reopen encrypted db: %@", error);
    AssertEq(seekrit.documentCount, 1u);
#endif
}


@end
