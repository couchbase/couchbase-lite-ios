//
//  CBL_SQLiteStorage.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/14/15.
//  Copyright (c) 2011-2015 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBL_SQLiteStorage.h"
#import "CBL_SQLiteViewStorage.h"
#import "CBLManager+Internal.h"
#import "CBL_Shared.h"
#import "CBLCollateJSON.h"
#import "CBL_Attachment.h"
#import "CBLMisc.h"
#import "CBJSONEncoder.h"
#import "CBLSymmetricKey.h"
#import "CBLInternal.h"
#import "CouchbaseLitePrivate.h"
#import "ExceptionUtils.h"
#import "MYAction.h"

#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "sqlite3_unicodesn_tokenizer.h"


#define kDBFilename @"db.sqlite3"

#define kSQLiteMMapSize (50*1024*1024)

#define kDocIDCacheSize 1000

#define kSQLiteBusyTimeout 5.0 // seconds

#define kTransactionMaxRetries 10
#define kTransactionRetryDelay 0.050

#define kLocalCheckpointDocId @"CBL_LocalCheckpoint"

#ifdef MOCK_ENCRYPTION
BOOL CBLEnableMockEncryption = NO;
#else
#define CBLEnableMockEncryption NO
#endif

static unsigned sSQLiteVersion;

static void CBLComputeFTSRank(sqlite3_context *pCtx, int nVal, sqlite3_value **apVal);


@implementation CBL_SQLiteStorage
{
    NSString* _directory;
    BOOL _readOnly;
    NSCache* _docIDs;
    CBLSymmetricKey* _encryptionKey;
}

@synthesize delegate=_delegate, autoCompact=_autoCompact,
            maxRevTreeDepth=_maxRevTreeDepth, fmdb=_fmdb;


+ (void) firstTimeSetup {
    // Test the version of the actual SQLite implementation at runtime. Necessary because
    // the app might be linked with a custom version of SQLite (like SQLCipher) instead of the
    // system library, so the actual version/features may differ from what was declared in
    // sqlite3.h at compile time.
    Log(@"Couchbase Lite using SQLite version %s (%s)",
        sqlite3_libversion(), sqlite3_sourceid());
#if 0
    for (int i=0; true; i++) {
        const char* opt = sqlite3_compileoption_get(i);
        if (!opt)
            break;
        Log(@"SQLite option '%s'", opt);
    }
#endif
    sSQLiteVersion = sqlite3_libversion_number();
    Assert(sSQLiteVersion >= 3007000,
           @"SQLite library is too old (%s); needs to be at least 3.7", sqlite3_libversion());

    // Enable memory-mapped I/O if available
#ifndef SQLITE_CONFIG_MMAP_SIZE
#define SQLITE_CONFIG_MMAP_SIZE    22  /* sqlite3_int64, sqlite3_int64 */
#endif
    int err = sqlite3_config(SQLITE_CONFIG_MMAP_SIZE, (SInt64)kSQLiteMMapSize, (SInt64)-1);
    if (err != SQLITE_OK)
        Log(@"FYI, couldn't enable SQLite mmap: error %d", err);
}


#pragma mark - OPEN/CLOSE:


+ (BOOL) databaseExistsIn: (NSString*)directory {
    NSString* dbPath = [directory stringByAppendingPathComponent: kDBFilename];
    return [[NSFileManager defaultManager] fileExistsAtPath: dbPath isDirectory: NULL];
}


- (void) setEncryptionKey:(CBLSymmetricKey *)key {
    _encryptionKey = key;
}


/** Opens storage. Files will be created in the directory, which must already exist. */
- (BOOL) openInDirectory: (NSString*)directory
                readOnly: (BOOL)readOnly
                 manager: (CBLManager*)manager
                   error: (NSError**)error
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [[self class] firstTimeSetup];
    });

    _directory = [directory copy];
    _readOnly = readOnly;
    NSString* path = [_directory stringByAppendingPathComponent: kDBFilename];
    _fmdb = [[CBL_FMDatabase alloc] initWithPath: path];
    _fmdb.dispatchQueue = manager.dispatchQueue;
    _fmdb.databaseLock = [manager.shared lockForDatabaseNamed: path];
#if DEBUG
    _fmdb.logsErrors = YES;
#else
    _fmdb.logsErrors = WillLogTo(Database);
#endif
    _fmdb.traceExecution = WillLogVerbose(Database);

    _docIDs = [[NSCache alloc] init];
    _docIDs.countLimit = kDocIDCacheSize;

    return [self open: error];
}


- (BOOL) runStatements: (NSString*)statements error: (NSError**)outError {
    for (NSString* quotedStatement in [statements componentsSeparatedByString: @";"]) {
        NSString* statement = [quotedStatement stringByReplacingOccurrencesOfString: @"|"
                                                                         withString: @";"];
        if (sSQLiteVersion < 3008000) {
            // No partial index support before SQLite 3.8
            if ([statement rangeOfString: @"CREATE INDEX "].length > 0) {
                NSRange where = [statement rangeOfString: @"WHERE"];
                if (where.length > 0)
                    statement = [statement substringToIndex: where.location];
            }
        }
        if (statement.length && ![_fmdb executeUpdate: statement]) {
            if (outError) *outError = self.fmdbError;
            return NO;
        }
    }
    return YES;
}

- (BOOL) initialize: (NSString*)statements error: (NSError**)outError {
    if ([self runStatements: statements error: outError])
        return YES;
    Warn(@"CBLDatabase: Could not initialize schema of %@ -- May be an old/incompatible format. "
          "SQLite error: %@", _directory, _fmdb.lastErrorMessage);
    [_fmdb close];
    return NO;
}


- (int) schemaVersion {
    return [_fmdb intForQuery: @"PRAGMA user_version"];
}


- (BOOL) openFMDB: (NSError**)outError {
    // Without the -ObjC linker flag, object files containing only category methods, not any
    // class's main implementation, will be dead-stripped. This breaks several pieces of CBL.
    Assert([CBL_FMDatabase instancesRespondToSelector: @selector(intForQuery:)],
           @"Critical Couchbase Lite code has been stripped from the app binary! "
            "Please make sure to build using the -ObjC linker flag!");

    int flags = 0;
    if (_readOnly)
        flags |= SQLITE_OPEN_READONLY;
    else
        flags |= SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE;

    LogTo(Database, @"Open %@ (flags=%X%@)",
          _fmdb.databasePath, flags, (_encryptionKey ? @", encryption key given" : nil));
    if (![_fmdb openWithFlags: flags]) {
        if (outError) *outError = self.fmdbError;
        return NO;
    }

    if (![self decryptWithKey: _encryptionKey error: outError])
        return NO;

    // Register CouchDB-compatible JSON collation functions:
    sqlite3* dbHandle = _fmdb.sqliteHandle;
    sqlite3_create_collation(dbHandle, "JSON", SQLITE_UTF8,
                             kCBLCollateJSON_Unicode, CBLCollateJSON);
    sqlite3_create_collation(dbHandle, "JSON_RAW", SQLITE_UTF8,
                             kCBLCollateJSON_Raw, CBLCollateJSON);
    sqlite3_create_collation(dbHandle, "JSON_ASCII", SQLITE_UTF8,
                             kCBLCollateJSON_ASCII, CBLCollateJSON);
    sqlite3_create_collation(dbHandle, "REVID", SQLITE_UTF8,
                             NULL, CBLCollateRevIDs);
    register_unicodesn_tokenizer(dbHandle);
    sqlite3_create_function(dbHandle, "ftsrank", 1, SQLITE_ANY, NULL,
                            CBLComputeFTSRank, NULL, NULL);

    // Stuff we need to initialize every time the database opens:
    if (![self initialize: @"PRAGMA foreign_keys = ON;" error: outError])
        return NO;
    return YES;
}


// Give SQLCipher the encryption key, if provided:
- (BOOL) decryptWithKey: (CBLSymmetricKey*)encryptionKey error: (NSError**)outError {
    BOOL hasRealEncryption = sqlite3_compileoption_used("SQLITE_HAS_CODEC") != 0;
#ifdef MOCK_ENCRYPTION
    if (!hasRealEncryption && CBLEnableMockEncryption)
        return [self mockDecryptWithKey: encryptionKey error: outError];
#endif

    if (encryptionKey) {
        if (!hasRealEncryption) {
            Warn(@"CBL_SQLiteStorage: encryption not available (app not built with SQLCipher)");
            return CBLStatusToOutNSError(kCBLStatusNotImplemented,  outError);
        } else {
            // http://sqlcipher.net/sqlcipher-api/#key
            if (![_fmdb executeUpdate: $sprintf(@"PRAGMA key = \"x'%@'\"",encryptionKey.hexData)]) {
                Warn(@"CBL_SQLiteStorage: 'pragma key' failed (SQLite error %d)",
                     self.lastDbStatus);
                if (outError) *outError = self.fmdbError;
                return NO;
            }
        }
    }

    // Verify that encryption key is correct (or db is unencrypted, if no key given):
    if ([_fmdb intForQuery:@"SELECT count(*) FROM sqlite_master"] == 0) {
        int err = _fmdb.lastErrorCode;
        if (err) {
            Warn(@"CBL_SQLiteStorage: database is unreadable (err %d)", err);
            if (outError) {
                if (err == SQLITE_NOTADB)
                    CBLStatusToOutNSError(kCBLStatusUnauthorized, outError);
                else
                    *outError = self.fmdbError;
            }
            return NO;
        }
    }
    return YES;
}


#ifdef MOCK_ENCRYPTION
- (BOOL) mockDecryptWithKey: (CBLSymmetricKey*)encryptionKey error: (NSError**)outError {
    NSData* givenKeyData = encryptionKey ? encryptionKey.keyData : [NSData data];
    NSString* keyPath = [_directory stringByAppendingPathComponent: @"mock_key"];
    NSData* actualKeyData = [NSData dataWithContentsOfFile: keyPath];
    if (!actualKeyData) {
        // Save key (which may be empty) the first time:
        [givenKeyData writeToFile: keyPath atomically: YES];
    } else {
        // After that, compare the keys:
        if (![actualKeyData isEqual: givenKeyData])
            return CBLStatusToOutNSError(kCBLStatusUnauthorized, outError);
    }
    return YES;
}
#endif


- (BOOL) checkUpdate: (BOOL)updateResult error: (NSError**)outError {
    if (!updateResult && outError)
        *outError = self.fmdbError;
    return updateResult;
}


- (MYAction*) actionToChangeEncryptionKey: (CBLSymmetricKey*)newKey {
    BOOL hasRealEncryption = sqlite3_compileoption_used("SQLITE_HAS_CODEC") != 0;
    if (!hasRealEncryption) {
#ifdef MOCK_ENCRYPTION
        if (!CBLEnableMockEncryption)
#endif
            return nil;
    }

    MYAction* action = [MYAction new];

    __block BOOL dbWasClosed = NO;
    NSString* tempPath;
#ifdef MOCK_ENCRYPTION
    if (!hasRealEncryption) {
        NSData* givenKeyData = newKey ? newKey.keyData : [NSData data];
        NSString* oldKeyPath = [_directory stringByAppendingPathComponent: @"mock_key"];
        NSString* newKeyPath = [_directory stringByAppendingPathComponent: @"mock_new_key"];
        [givenKeyData writeToFile: newKeyPath atomically: YES];
        [action addAction: [MYAction moveFile: newKeyPath toPath: oldKeyPath]];
    } else
#endif
    {
        // Make a path for a temporary database file:
        tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent: CBLCreateUUID()];
        [action addPerform: nil backOut: ^BOOL(NSError **outError) {
            return [[NSFileManager defaultManager] removeItemAtPath: tempPath error: outError];
        } cleanUp: nil];

        // Create & attach a temporary database encrypted with the new key:
        [action addPerform:^BOOL(NSError **outError) {
            NSString* sql;
            if (newKey)
                sql = $sprintf(@"ATTACH DATABASE ? AS rekeyed_db KEY \"x'%@'\"", newKey.hexData);
            else
                sql = @"ATTACH DATABASE ? AS rekeyed_db KEY ''";
            return [self checkUpdate: [_fmdb executeUpdate: sql, tempPath] error: outError];
        } backOutOrCleanUp:^BOOL(NSError **outError) {
            return dbWasClosed ||
                        [self checkUpdate: [_fmdb executeUpdate: @"DETACH DATABASE rekeyed_db"]
                                    error: outError];
        }];

        // Export the current database's contents to the new one:
        // <https://www.zetetic.net/sqlcipher/sqlcipher-api/#sqlcipher_export>
        [action addPerform:^BOOL(NSError **outError) {
            NSString* vers = $sprintf(@"PRAGMA rekeyed_db.user_version = %d", self.schemaVersion);
            return [self checkUpdate: [_fmdb executeUpdate:@"SELECT sqlcipher_export('rekeyed_db')"]
                               error: outError]
                && [self checkUpdate: [_fmdb executeUpdate: vers]
                               error: outError];
        } backOut: NULL cleanUp: NULL];
    }

    // Close the database (and re-open it on cleanup):
    [action addPerform: ^BOOL(NSError **outError) {
        [_fmdb close];
        dbWasClosed = YES;
        return YES;
    } backOut: ^BOOL(NSError **outError) {
        return [self open: outError];
    } cleanUp: ^BOOL(NSError **outError) {
        [self setEncryptionKey: newKey];
        return [self open: outError];
    }];

    // Overwrite the old db file with the new one:
    if (hasRealEncryption) {
        [action addAction: [MYAction moveFile: tempPath toPath: _fmdb.databasePath]];
    }

    return action;
}


- (BOOL) open: (NSError**)outError {
    LogTo(Database, @"Opening %@", self);
    if (![self openFMDB: outError])
        return NO;
    
    // Check the user_version number we last stored in the database:
    __unused int dbVersion = self.schemaVersion;
    
    // Incompatible version changes increment the hundreds' place:
    if (dbVersion >= 200) {
        Warn(@"CBLDatabase: Database version (%d) is newer than I know how to work with", dbVersion);
        [_fmdb close];
        if (outError) *outError = [NSError errorWithDomain: @"CouchbaseLite" code: 1 userInfo: nil]; //FIX: Real code
        return NO;
    }

    BOOL isNew = (dbVersion == 0);
    if (isNew && ![self initialize: @"PRAGMA journal_mode=WAL; BEGIN TRANSACTION" error: outError])
        return NO;

    if (dbVersion < 17) {
        // First-time initialization:
        // (Note: Declaring revs.sequence as AUTOINCREMENT means the values will always be
        // monotonically increasing, never reused. See <http://www.sqlite.org/autoinc.html>)
        if (!isNew) {
            Warn(@"CBLDatabase: Database version (%d) is older than I know how to work with", dbVersion);
            [_fmdb close];
            if (outError) *outError = [NSError errorWithDomain: @"CouchbaseLite" code: 1 userInfo: nil]; //FIX: Real code
            return NO;
        }
        NSString *schema = @"\
            CREATE TABLE docs (\
                doc_id INTEGER PRIMARY KEY,\
                docid TEXT UNIQUE NOT NULL);\
            CREATE INDEX docs_docid ON docs(docid);\
            \
            CREATE TABLE revs (\
                sequence INTEGER PRIMARY KEY AUTOINCREMENT,\
                doc_id INTEGER NOT NULL REFERENCES docs(doc_id) ON DELETE CASCADE,\
                revid TEXT NOT NULL COLLATE REVID,\
                parent INTEGER REFERENCES revs(sequence) ON DELETE SET NULL,\
                current BOOLEAN,\
                deleted BOOLEAN DEFAULT 0,\
                json BLOB,\
                no_attachments BOOLEAN,\
                UNIQUE (doc_id, revid));\
            CREATE INDEX revs_parent ON revs(parent);\
            CREATE INDEX revs_by_docid_revid ON revs(doc_id, revid desc, current, deleted);\
            CREATE INDEX revs_current ON revs(doc_id, current desc, deleted, revid desc);\
            \
            CREATE TABLE localdocs (\
                docid TEXT UNIQUE NOT NULL,\
                revid TEXT NOT NULL COLLATE REVID,\
                json BLOB);\
            CREATE INDEX localdocs_by_docid ON localdocs(docid);\
            \
            CREATE TABLE views (\
                view_id INTEGER PRIMARY KEY,\
                name TEXT UNIQUE NOT NULL,\
                version TEXT,\
                lastsequence INTEGER DEFAULT 0,\
                total_docs INTEGER DEFAULT -1);\
            CREATE INDEX views_by_name ON views(name);\
            \
            CREATE TABLE info (\
                key TEXT PRIMARY KEY,\
                value TEXT);\
            \
            PRAGMA user_version = 17";             // at the end, update user_version
        //OPT: Would be nice to use partial indexes but that requires SQLite 3.8 and makes the
        // db file only readable by SQLite 3.8+, i.e. the file would not be portable to iOS 8
        // which only has SQLite 3.7 :(
        // On the revs_parent index we could add "WHERE parent not null".

        if (![self initialize: schema error: outError])
            return NO;
        dbVersion = 17;
    }

    if (dbVersion < 18) {
        NSString *schema = @"\
            ALTER TABLE revs ADD COLUMN doc_type TEXT;\
            PRAGMA user_version = 18";             // at the end, update user_version
        if (![self initialize: schema error: outError])
            return NO;
        dbVersion = 18;
    }

    if (dbVersion < 101) {
        NSString *schema = @"\
        PRAGMA user_version = 101";
        if (![self initialize: schema error: outError])
            return NO;
        dbVersion = 101;
    }

    if (isNew && ![self initialize: @"END TRANSACTION" error: outError])
        return NO;

    if (isNew)
        [self setInfo: @"true" forKey: @"pruned"];  // See -compact: for explanation

    if (!isNew)
        [self optimizeSQLIndexes];          // runs ANALYZE query

#if DEBUG
    _fmdb.crashOnErrors = YES;
#endif

    _fmdb.shouldCacheStatements = YES;      // Saves the time to recompile SQL statements
    return YES;
}


- (void) close {
    [_fmdb close]; // this returns BOOL, but its implementation never returns NO
    _fmdb = nil;
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}


#pragma mark - ERRORS:


- (CBLStatus) lastDbStatus {
    switch (_fmdb.lastErrorCode) {
        case SQLITE_OK:
        case SQLITE_ROW:
        case SQLITE_DONE:
            return kCBLStatusOK;
        case SQLITE_READONLY:
        case SQLITE_PERM:
            return kCBLStatusForbidden;
        case SQLITE_BUSY:
        case SQLITE_LOCKED:
            return kCBLStatusDBBusy;
        case SQLITE_CORRUPT:
            return kCBLStatusCorruptError;
        case SQLITE_NOTADB:
            return kCBLStatusUnauthorized; // DB is probably encrypted (SQLCipher)
        default:
            LogTo(Database, @"Other _fmdb.lastErrorCode %d", _fmdb.lastErrorCode);
            return kCBLStatusDBError;
    }
}

- (CBLStatus) lastDbError {
    CBLStatus status = self.lastDbStatus;
    return (status == kCBLStatusOK) ? kCBLStatusDBError : status;
}


- (NSError*) fmdbError {
    NSDictionary* info = $dict({NSLocalizedDescriptionKey, _fmdb.lastErrorMessage});
    return [NSError errorWithDomain: @"SQLite" code: _fmdb.lastErrorCode userInfo: info];
}


#pragma mark - ACCESSORS:


- (NSUInteger) documentCount {
    NSUInteger result = NSNotFound;
    CBL_FMResultSet* r = [_fmdb executeQuery: @"SELECT COUNT(DISTINCT doc_id) FROM revs "
                                               "WHERE current=1 AND deleted=0"];
    if ([r next]) {
        result = [r intForColumnIndex: 0];
    }
    [r close];
    return result;
}


- (SequenceNumber) lastSequence {
    // See http://www.sqlite.org/fileformat2.html#seqtab
    return [_fmdb longLongForQuery: @"SELECT seq FROM sqlite_sequence WHERE name='revs'"];
}


- (BOOL) inTransaction {
    return _fmdb.transactionLevel > 0;
}


- (BOOL) beginTransaction {
    if (![_fmdb beginTransaction]) {
        Warn(@"Failed to create SQLite transaction!");
        return NO;
    }
    LogTo(Database, @"Begin transaction (level %d)...", _fmdb.transactionLevel);
    return YES;
}

- (BOOL) endTransaction: (BOOL)commit {
    LogTo(Database, @"%@ transaction (level %d)",
          (commit ? @"Commit" : @"Abort"), _fmdb.transactionLevel);

    BOOL ok = [_fmdb endTransaction: commit];
    if (!ok)
        Warn(@"Failed to end transaction!");

    [_delegate storageExitedTransaction: commit];
    return ok;
}

// Runs the block inside a transaction. If the block returns an error status, or raises an
// exception, the transaction is aborted and any changes rolled back. If this was a nested
// transaction, only its changes are rolled back, not any from the outer transaction.
// (Also supports retrying the block if it fails with a SQLite "BUSY" error, but this shouldn't
// occur anymore now that our hacked FMDB uses a mutex to enforce database locking.)
- (CBLStatus) inTransaction: (CBLStatus(^)())block {
    CBLStatus status;
    int retries = 0;
    do {
        if (![self beginTransaction])
            return self.lastDbError;
        @try {
            status = block();
        } @catch (NSException* x) {
            MYReportException(x, @"CBLDatabase transaction");
            status = kCBLStatusException;
        } @finally {
            [self endTransaction: !CBLStatusIsError(status)];
        }
        if (status == kCBLStatusDBBusy) {
            // retry if locked out:
            if (_fmdb.transactionLevel > 1)
                break;
            if (++retries > kTransactionMaxRetries) {
                Warn(@"%@: Db busy, too many retries, giving up", self);
                break;
            }
            Log(@"%@: Db busy, retrying transaction (#%d)...", self, retries);
            [NSThread sleepForTimeInterval: kTransactionRetryDelay];
        }
    } while (status == kCBLStatusDBBusy);
    return status;
}

// This is like -inTransaction: except that it will not create _nested_ SQLite transactions,
// only the outer one. There turns out to be significant overhead in a nested transaction, so in
// cases where you just need to exclude other threads, and don't need to be able to roll back
// the change you're making, this method is cheaper.
- (CBLStatus) inOuterTransaction: (CBLStatus(^)())block {
    if (!self.inTransaction)
        return [self inTransaction: block];
    // Instead of a nested transaction, just run the block and catch exceptions:
    CBLStatus status;
    @try {
        status = block();
    } @catch (NSException* x) {
        MYReportException(x, @"CBLDatabase transaction");
        status = kCBLStatusException;
    }
    return status;
}


#pragma mark - DOCUMENTS:


- (CBL_MutableRevision*) getDocumentWithID: (NSString*)docID
                                revisionID: (NSString*)revID
                                  withBody: (BOOL)withBody
                                    status: (CBLStatus*)outStatus
{
    SInt64 docNumericID = [self getDocNumericID: docID];
    if (docNumericID <= 0) {
        if (outStatus) *outStatus = kCBLStatusNotFound;
        return nil;
    }

    CBL_MutableRevision* result = nil;
    CBLStatus status;
    NSMutableString* sql = [NSMutableString stringWithString: @"SELECT revid, deleted, sequence"];
    if (withBody)
        [sql appendString: @", json"];
    if (revID)
        [sql appendString: @" FROM revs WHERE revs.doc_id=? AND revid=? AND json notnull LIMIT 1"];
    else
        [sql appendString: @" FROM revs WHERE revs.doc_id=? and current=1 and deleted=0 "
                            "ORDER BY revid DESC LIMIT 1"];
    CBL_FMResultSet *r = [_fmdb executeQuery: sql, @(docNumericID), revID];
    if (!r) {
        status = self.lastDbError;
    } else if (![r next]) {
        status = revID ? kCBLStatusNotFound : kCBLStatusDeleted;
    } else {
        if (!revID)
            revID = [r stringForColumnIndex: 0];
        BOOL deleted = [r boolForColumnIndex: 1];
        result = [[CBL_MutableRevision alloc] initWithDocID: docID revID: revID deleted: deleted];
        result.sequence = [r longLongIntForColumnIndex: 2];
        if (withBody)
            result.asJSON = [r dataNoCopyForColumnIndex: 3];
        status = kCBLStatusOK;
    }
    [r close];
    if (outStatus)
        *outStatus = status;
    return result;
}


- (BOOL) existsDocumentWithID: (NSString*)docID revisionID: (NSString*)revID {
    CBLStatus status;
    return [self getDocumentWithID: docID revisionID: revID withBody: NO status: &status] != nil;
}


// Loads revision given its sequence. Assumes the given docID is valid.
- (CBL_MutableRevision*) getDocumentWithID: (NSString*)docID
                                  sequence: (SequenceNumber)sequence
                                    status: (CBLStatus*)outStatus
{
    CBL_MutableRevision* result = nil;
    CBLStatus status;
    CBL_FMResultSet *r = [_fmdb executeQuery:
                          @"SELECT revid, deleted, json FROM revs WHERE sequence=?",
                          @(sequence)];
    if (!r) {
        status = self.lastDbError;
    } else if (![r next]) {
        status = kCBLStatusNotFound;
    } else {
        NSString* revID = [r stringForColumnIndex: 0];
        BOOL deleted = [r boolForColumnIndex: 1];
        result = [[CBL_MutableRevision alloc] initWithDocID: docID
                                                      revID: revID
                                                    deleted: deleted];
        result.sequence = sequence;
        result.asJSON =[r dataNoCopyForColumnIndex: 2];
        status = kCBLStatusOK;
    }
    [r close];
    if (outStatus)
        *outStatus = status;
    return result;
}


- (CBLStatus) loadRevisionBody: (CBL_MutableRevision*)rev {
    if (rev.body && rev.sequence)
        return kCBLStatusOK;  // no-op
    Assert(rev.docID && rev.revID);
    SInt64 docNumericID = [self getDocNumericID: rev.docID];
    if (docNumericID <= 0)
        return kCBLStatusNotFound;
    CBL_FMResultSet *r = [_fmdb executeQuery: @"SELECT sequence, json FROM revs "
                            "WHERE doc_id=? AND revid=? LIMIT 1",
                            @(docNumericID), rev.revID];
    if (!r)
        return self.lastDbError;
    CBLStatus status = kCBLStatusNotFound;
    if ([r next]) {
        // Found the rev. But the JSON still might be null if the database has been compacted.
        NSData* json = [r dataNoCopyForColumnIndex: 1];
        if (json) {
            status = kCBLStatusOK;
            rev.sequence = [r longLongIntForColumnIndex: 0];
            rev.asJSON = json;
        }
    }
    [r close];
    return status;
}


- (CBL_MutableRevision*) revisionWithDocID: (NSString*)docID
                                     revID: (NSString*)revID
                                   deleted: (BOOL)deleted
                                  sequence: (SequenceNumber)sequence
                                      json: (NSData*)json
{
    CBL_MutableRevision* rev = [[CBL_MutableRevision alloc] initWithDocID: docID revID: revID
                                                                  deleted: deleted];
    rev.sequence = sequence;
    if (json)
        rev.asJSON = json;
    return rev;
}


- (SInt64) getDocNumericID: (NSString*)docID {
    NSNumber* cached = [_docIDs objectForKey: docID];
    if (cached) {
        return cached.longLongValue;
    } else {
        SInt64 result = [_fmdb longLongForQuery: @"SELECT doc_id FROM docs WHERE docid=?", docID];
        if (result <= 0)
            return result;
        [_docIDs setObject: @(result) forKey: docID];
        return result;
    }
}

- (SInt64) _getDocNumericID: (NSString*)docID {
    return [_fmdb longLongForQuery: @"SELECT doc_id FROM docs WHERE docid=?", docID];
}

- (SInt64) _createDocNumericID: (NSString*)docID {
    if (![_fmdb executeUpdate: @"INSERT OR IGNORE INTO docs (docid) VALUES (?)", docID])
        return -1;
    if (_fmdb.changes == 0)
        return 0;
    return _fmdb.lastInsertRowId;
}

// Registers a docID and returns its numeric row ID in the 'docs' table.
// On input, *ioIsNew should be YES if the docID is probably not known, NO if it's probably known.
// On return, *ioIsNew will be YES iff the docID is newly-created (was not known before.)
// Return value is the positive row ID of this doc, or <= 0 on error.
- (SInt64) createOrGetDocNumericID: (NSString*)docID isNew: (BOOL*)ioIsNew {
    NSNumber* cached = [_docIDs objectForKey: docID];
    if (cached) {
        *ioIsNew = NO;
        return cached.longLongValue;
    }

    SInt64 row = *ioIsNew ? [self _createDocNumericID: docID] : [self _getDocNumericID: docID];
    if (row < 0)
        return row;
    if (row == 0) {
        *ioIsNew = !*ioIsNew;
        row = *ioIsNew ? [self _createDocNumericID: docID] : [self _getDocNumericID: docID];
    }

    if (row > 0)
        [_docIDs setObject: @(row) forKey: docID];
    return row;
}


- (SequenceNumber) getSequenceOfDocument: (SInt64)docNumericID
                                revision: (NSString*)revID
                             onlyCurrent: (BOOL)onlyCurrent
{
    NSString* sql = $sprintf(@"SELECT sequence FROM revs WHERE doc_id=? AND revid=? %@ LIMIT 1",
                             (onlyCurrent ? @"AND current=1" : @""));
    return [_fmdb longLongForQuery: sql, @(docNumericID), revID];
}


- (SequenceNumber) getRevisionSequence: (CBL_Revision*)rev {
    SInt64 docNumericID = [self getDocNumericID: rev.docID];
    if (docNumericID <=0 )
        return 0;
    NSString* sql = @"SELECT sequence FROM revs WHERE doc_id=? AND revid=? LIMIT 1";
    return [_fmdb longLongForQuery: sql, @(docNumericID), rev.revID];
}


- (CBL_Revision*) getParentRevision: (CBL_Revision*)rev {
    // First get the parent's sequence:
    SequenceNumber seq = rev.sequenceIfKnown;
    if (seq) {
        seq = [_fmdb longLongForQuery: @"SELECT parent FROM revs WHERE sequence=?",
                                @(seq)];
    } else {
        SInt64 docNumericID = [self getDocNumericID: rev.docID];
        if (!docNumericID)
            return nil;
        seq = [_fmdb longLongForQuery: @"SELECT parent FROM revs WHERE doc_id=? and revid=?",
                                @(docNumericID), rev.revID];
    }
    if (seq == 0)
        return nil;

    // Now get its revID and deletion status:
    CBL_Revision* result = nil;
    CBL_FMResultSet* r = [_fmdb executeQuery: @"SELECT revid, deleted FROM revs WHERE sequence=?",
                               @(seq)];
    if ([r next]) {
        result = [[CBL_Revision alloc] initWithDocID: rev.docID
                                               revID: [r stringForColumnIndex: 0]
                                             deleted: [r boolForColumnIndex: 1]];
        result.sequence = seq;
    }
    [r close];
    return result;
}


/** Returns an array of CBL_Revisions in reverse chronological order,
    starting with the given revision. */
- (NSArray*) getRevisionHistory: (CBL_Revision*)rev
                   backToRevIDs: (NSSet*)ancestorRevIDs
{
    NSString* docID = rev.docID;
    NSString* revID = rev.revID;
    Assert(revID && docID);

    SInt64 docNumericID = [self getDocNumericID: docID];
    if (docNumericID < 0)
        return nil;
    else if (docNumericID == 0)
        return @[];

    CBL_FMResultSet* r = [_fmdb executeQuery: @"SELECT sequence, parent, revid, deleted, json isnull "
                                           "FROM revs WHERE doc_id=? ORDER BY sequence DESC",
                                          @(docNumericID)];
    if (!r)
        return nil;
    SequenceNumber lastSequence = 0;
    NSMutableArray* history = $marray();
    while ([r next]) {
        SequenceNumber sequence = [r longLongIntForColumnIndex: 0];
        BOOL matches;
        if (lastSequence == 0)
            matches = ($equal(revID, [r stringForColumnIndex: 2]));
        else
            matches = (sequence == lastSequence);
        if (matches) {
            NSString* revID = [r stringForColumnIndex: 2];
            BOOL deleted = [r boolForColumnIndex: 3];
            CBL_MutableRevision* rev = [[CBL_MutableRevision alloc] initWithDocID: docID
                                                                            revID: revID
                                                                          deleted: deleted];
            rev.sequence = sequence;
            rev.missing = [r boolForColumnIndex: 4];
            [history addObject: rev];
            lastSequence = [r longLongIntForColumnIndex: 1];
            if (lastSequence == 0)
                break;
            if ([ancestorRevIDs containsObject: revID])
                break;
        }
    }
    [r close];
    return history;
}


/** Returns the revision history as a _revisions dictionary, as returned by the REST API's ?revs=true option. If 'ancestorRevIDs' is present, the revision history will only go back as far as any of the revision ID strings in that array. */
- (NSDictionary*) getRevisionHistoryDict: (CBL_Revision*)rev
                       startingFromAnyOf: (NSArray*)ancestorRevIDs
{
    NSString* docID = rev.docID;
    NSString* revID = rev.revID;
    Assert(revID && docID);

    SInt64 docNumericID = [self getDocNumericID: docID];
    if (docNumericID < 0)
        return nil;

    NSMutableArray* history = $marray();

    if (docNumericID > 0) {
        CBL_FMResultSet* r = [_fmdb executeQuery: @"SELECT sequence, parent, revid, deleted, json isnull "
                              "FROM revs WHERE doc_id=? ORDER BY sequence DESC",
                              @(docNumericID)];
        if (!r)
            return nil;
        SequenceNumber lastSequence = 0;
        while ([r next]) {
            SequenceNumber sequence = [r longLongIntForColumnIndex: 0];
            BOOL matches;
            if (lastSequence == 0)
                matches = ($equal(revID, [r stringForColumnIndex: 2]));
            else
                matches = (sequence == lastSequence);
            if (matches) {
                NSString* revID = [r stringForColumnIndex: 2];
                BOOL deleted = [r boolForColumnIndex: 3];
                CBL_MutableRevision* rev = [[CBL_MutableRevision alloc] initWithDocID: docID
                                                                                revID: revID
                                                                              deleted: deleted];
                rev.sequence = sequence;
                rev.missing = [r boolForColumnIndex: 4];
                [history addObject: rev];
                lastSequence = [r longLongIntForColumnIndex: 1];
                if (lastSequence == 0)
                    break;
                if ([ancestorRevIDs containsObject: revID])
                    break;
            }
        }
        [r close];
    }

    // Try to extract descending numeric prefixes:
    NSMutableArray* suffixes = $marray();
    id start = nil;
    int lastRevNo = -1;
    for (CBL_Revision* rev in history) {
        int revNo;
        NSString* suffix;
        if ([CBL_Revision parseRevID: rev.revID intoGeneration: &revNo andSuffix: &suffix]) {
            if (!start)
                start = @(revNo);
            else if (revNo != lastRevNo - 1) {
                start = nil;
                break;
            }
            lastRevNo = revNo;
            [suffixes addObject: suffix];
        } else {
            start = nil;
            break;
        }
    }

    NSArray* revIDs = start ? suffixes : [history my_map: ^(id rev) {return [rev revID];}];
    return $dict({@"ids", revIDs}, {@"start", start});
}


/** Returns all the known revisions (or all current/conflicting revisions) of a document. */
- (CBL_RevisionList*) getAllRevisionsOfDocumentID: (NSString*)docID
                                      onlyCurrent: (BOOL)onlyCurrent
{
    SInt64 docNumericID = [self getDocNumericID: docID];
    if (docNumericID < 0)
        return nil;
    else if (docNumericID == 0)
        return [[CBL_RevisionList alloc] init];  // no such document
    else
        return [self getAllRevisionsOfDocumentID: docID
                                       numericID: docNumericID
                                     onlyCurrent: onlyCurrent];
}


- (CBL_RevisionList*) getAllRevisionsOfDocumentID: (NSString*)docID
                                        numericID: (SInt64)docNumericID
                                      onlyCurrent: (BOOL)onlyCurrent
{
    NSString* sql;
    if (onlyCurrent)
        sql = @"SELECT sequence, revid, deleted FROM revs "
               "WHERE doc_id=? AND current ORDER BY sequence DESC";
    else
        sql = @"SELECT sequence, revid, deleted FROM revs "
               "WHERE doc_id=? ORDER BY sequence DESC";
    CBL_FMResultSet* r = [_fmdb executeQuery: sql, @(docNumericID)];
    if (!r)
        return nil;
    CBL_RevisionList* revs = [[CBL_RevisionList alloc] init];
    while ([r next]) {
        CBL_Revision* rev = [[CBL_Revision alloc] initWithDocID: docID
                                              revID: [r stringForColumnIndex: 1]
                                            deleted: [r boolForColumnIndex: 2]];
        rev.sequence = [r longLongIntForColumnIndex: 0];
        [revs addRev: rev];
    }
    [r close];
    return revs;
}


/** Returns IDs of local revisions of the same document, that have a lower generation number.
    Does not return revisions whose bodies have been compacted away, or deletion markers.
    If 'onlyAttachments' is true, only revisions with attachments will be returned. */
- (NSArray*) getPossibleAncestorRevisionIDs: (CBL_Revision*)rev
                                      limit: (unsigned)limit
                            onlyAttachments: (BOOL)onlyAttachments;
{
    int generation = rev.generation;
    if (generation <= 1)
        return nil;
    SInt64 docNumericID = [self getDocNumericID: rev.docID];
    if (docNumericID <= 0)
        return nil;
    int sqlLimit = limit > 0 ? (int)limit : -1;     // SQL uses -1, not 0, to denote 'no limit'
    CBL_FMResultSet* r = [_fmdb executeQuery:
                      @"SELECT revid, sequence FROM revs WHERE doc_id=? and revid < ?"
                       " and deleted=0 and json not null"
                       " ORDER BY sequence DESC LIMIT ?",
                      @(docNumericID), $sprintf(@"%d-", generation), @(sqlLimit)];
    if (!r)
        return nil;
    NSMutableArray* revIDs = $marray();
    while ([r next]) {
        if (onlyAttachments && ![self sequenceHasAttachments: [r longLongIntForColumnIndex: 1]])
            continue;
        [revIDs addObject: [r stringForColumnIndex: 0]];
    }
    [r close];
    return revIDs;
}


- (BOOL) sequenceHasAttachments: (SequenceNumber)sequence {
    return [_fmdb boolForQuery: @"SELECT no_attachments=0 FROM revs WHERE sequence=?", @(sequence)];
}


/** Returns the most recent member of revIDs that appears in rev's ancestry. */
- (NSString*) findCommonAncestorOf: (CBL_Revision*)rev withRevIDs: (NSArray*)revIDs {
    if (revIDs.count == 0)
        return nil;
    SInt64 docNumericID = [self getDocNumericID: rev.docID];
    if (docNumericID <= 0)
        return nil;
    NSString* sql = $sprintf(@"SELECT revid FROM revs "
                              "WHERE doc_id=? and revid in (%@) and revid <= ? "
                              "ORDER BY revid DESC LIMIT 1", 
                              CBLJoinSQLQuotedStrings(revIDs));
    _fmdb.shouldCacheStatements = NO;
    NSString* ancestor = [_fmdb stringForQuery: sql, @(docNumericID), rev.revID];
    _fmdb.shouldCacheStatements = YES;
    return ancestor;
}


NSString* CBLJoinSQLQuotedStrings(NSArray* strings) {
    if (strings.count == 0)
        return @"";
    NSMutableString* result = [NSMutableString stringWithString: @"'"];
    BOOL first = YES;
    for (NSString* str in strings) {
        if (first)
            first = NO;
        else
            [result appendString: @"','"];
        NSRange range = NSMakeRange(result.length, str.length);
        [result appendString: str];
        [result replaceOccurrencesOfString: @"'" withString: @"''"
                                   options: NSLiteralSearch range: range];
    }
    [result appendString: @"'"];
    return result;
}


- (CBL_RevisionList*) changesSinceSequence: (SequenceNumber)lastSequence
                                   options: (const CBLChangesOptions*)options
                                    filter: (CBL_RevisionFilter)filter
                                    status: (CBLStatus*)outStatus
{
    // http://wiki.apache.org/couchdb/HTTP_database_API#Changes
    if (!options) options = &kDefaultCBLChangesOptions;
    BOOL includeDocs = options->includeDocs || (filter != NULL);

    NSString* sql = $sprintf(@"SELECT sequence, revs.doc_id, docid, revid, deleted %@ FROM revs, docs "
                             "WHERE sequence > ? AND current=1 "
                             "AND revs.doc_id = docs.doc_id "
                             "ORDER BY revs.doc_id, deleted, revid DESC",
                             (includeDocs ? @", json" : @""));
    CBL_FMResultSet* r = [_fmdb executeQuery: sql, @(lastSequence)];
    if (!r)
        return nil;
    CBL_RevisionList* changes = [[CBL_RevisionList alloc] init];
    int64_t lastDocID = 0;
    while ([r next]) {
        @autoreleasepool {
            if (!options->includeConflicts) {
                // Only count the first rev for a given doc (the rest will be losing conflicts):
                int64_t docNumericID = [r longLongIntForColumnIndex: 1];
                if (docNumericID == lastDocID)
                    continue;
                lastDocID = docNumericID;
            }

            NSString* docID = [r stringForColumnIndex: 2];
            NSString* revID = [r stringForColumnIndex: 3];
            BOOL deleted = [r boolForColumnIndex: 4];
            CBL_MutableRevision* rev = [[CBL_MutableRevision alloc] initWithDocID: docID
                                                                            revID: revID
                                                                          deleted: deleted];
            rev.sequence = [r longLongIntForColumnIndex: 0];
            if (includeDocs)
                rev.asJSON = [r dataNoCopyForColumnIndex: 5];
            if (!filter || filter(rev))
                [changes addRev: rev];
        }
    }
    [r close];
    
    if (options->sortBySequence) {
        [changes sortBySequenceAscending: !options->descending];
        [changes limit: options->limit];
    }
    return changes;
}


- (BOOL) findMissingRevisions: (CBL_RevisionList*)revs
                       status: (CBLStatus*)outStatus
{
    if (revs.count == 0)
        return YES;
    NSString* sql = $sprintf(@"SELECT docid, revid FROM revs, docs "
                              "WHERE revid in (%@) AND docid IN (%@) "
                              "AND revs.doc_id == docs.doc_id",
                             CBLJoinSQLQuotedStrings(revs.allRevIDs),
                             CBLJoinSQLQuotedStrings(revs.allDocIDs));
    _fmdb.shouldCacheStatements = NO;
    CBL_FMResultSet* r = [_fmdb executeQuery: sql];
    _fmdb.shouldCacheStatements = YES;
    if (!r) {
        *outStatus = self.lastDbStatus;
        return NO;
    }
    while ([r next]) {
        @autoreleasepool {
            CBL_Revision* rev = [revs revWithDocID: [r stringForColumnIndex: 0]
                                           revID: [r stringForColumnIndex: 1]];
            if (rev)
                [revs removeRev: rev];
        }
    }
    [r close];
    return YES;
}


- (CBLQueryEnumerator*) getAllDocs: (CBLQueryOptions*)options
                            status: (CBLStatus*)outStatus
{
    SequenceNumber lastSeq = self.lastSequence;
    BOOL includeDocs = (options->includeDocs || options.filter);
    BOOL includeDeletedDocs = (options->allDocsMode == kCBLIncludeDeleted);
    CBLQueryRowFilter filter = options.filter;
    
    // Generate the SELECT statement, based on the options:
    BOOL cacheQuery = YES;
    NSMutableString* sql = [@"SELECT revs.doc_id, docid, revid, sequence" mutableCopy];
    if (includeDocs)
        [sql appendString: @", json, no_attachments"];
    if (includeDeletedDocs)
        [sql appendString: @", deleted"];
    [sql appendString: @" FROM revs, docs WHERE"];
    if (options.keys) {
        [sql appendFormat: @" revs.doc_id IN (SELECT doc_id FROM docs WHERE docid IN (%@)) AND", CBLJoinSQLQuotedStrings(options.keys)];
        cacheQuery = NO; // we've put hardcoded key strings in the query
    }
    [sql appendString: @" docs.doc_id = revs.doc_id AND current=1"];
    if (!includeDeletedDocs)
        [sql appendString: @" AND deleted=0"];

    NSMutableArray* args = $marray();
    id minKey = options.minKey, maxKey = options.maxKey;
    BOOL inclusiveMin = options->inclusiveStart, inclusiveMax = options->inclusiveEnd;
    if (options->descending) {
        inclusiveMin = options->inclusiveEnd;
        inclusiveMax = options->inclusiveStart;
    }
    if (minKey) {
        Assert([minKey isKindOfClass: [NSString class]]);
        [sql appendString: (inclusiveMin ? @" AND docid >= ?" :  @" AND docid > ?")];
        [args addObject: minKey];
    }
    if (maxKey) {
        Assert([maxKey isKindOfClass: [NSString class]]);
        [sql appendString: (inclusiveMax ? @" AND docid <= ?" :  @" AND docid < ?")];
        [args addObject: maxKey];
    }
    
    [sql appendFormat: @" ORDER BY docid %@, %@ revid DESC LIMIT ? OFFSET ?",
                       (options->descending ? @"DESC" : @"ASC"),
                       (includeDeletedDocs ? @"deleted ASC," : @"")];
    [args addObject: @(options->limit)];
    [args addObject: @(options->skip)];

    // Now run the database query:
    if (!cacheQuery)
        _fmdb.shouldCacheStatements = NO;
    CBL_FMResultSet* r = [_fmdb executeQuery: sql withArgumentsInArray: args];
    if (!cacheQuery)
        _fmdb.shouldCacheStatements = YES;
    if (!r) {
        *outStatus = self.lastDbError;
        return nil;
    }
    
    NSMutableArray* rows = $marray();
    NSMutableDictionary* docs = options.keys ? $mdict() : nil;

    BOOL keepGoing = [r next]; // Go to first result row
    while (keepGoing) {
        @autoreleasepool {
            // Get row values now, before the code below advances 'r':
            int64_t docNumericID = [r longLongIntForColumnIndex: 0];
            NSString* docID = [r stringForColumnIndex: 1];
            NSString* revID = [r stringForColumnIndex: 2];
            SequenceNumber sequence = [r longLongIntForColumnIndex: 3];
            BOOL deleted = includeDeletedDocs && [r boolForColumn: @"deleted"];

            CBL_Revision* docRevision = nil;
            if (includeDocs) {
                // Fill in the document contents:
                docRevision = [self revisionWithDocID: docID
                                                revID: revID
                                              deleted: deleted
                                             sequence: sequence
                                                 json: [r dataForColumnIndex: 4]];
                Assert(docRevision);
            }
            
            // Iterate over following rows with the same doc_id -- these are conflicts.
            // Skip them, but collect their revIDs if the 'conflicts' option is set:
            NSMutableArray* conflicts = nil;
            while ((keepGoing = [r next]) && [r longLongIntForColumnIndex: 0] == docNumericID) {
                if (options->allDocsMode >= kCBLShowConflicts) {
                    if (!conflicts)
                        conflicts = $marray(revID);
                    [conflicts addObject: [r stringForColumnIndex: 2]];
                }
            }
            if (options->allDocsMode == kCBLOnlyConflicts && !conflicts)
                continue;

            NSDictionary* value = $dict({@"rev", revID},
                                        {@"deleted", (deleted ?$true : nil)},
                                        {@"_conflicts", conflicts});  // (not found in CouchDB)
            CBLQueryRow* row = [[CBLQueryRow alloc] initWithDocID: docID
                                                         sequence: sequence
                                                              key: docID
                                                            value: value
                                                      docRevision: docRevision];
            if (options.keys)
                docs[docID] = row;
            else if (!filter || [self row: row passesFilter: filter])
                [rows addObject: row];
        }
    }
    [r close];

    // If given doc IDs, sort the output into that order, and add entries for missing docs:
    if (options.keys) {
        for (NSString* docID in options.keys) {
            CBLQueryRow* row = docs[docID];
            if (!row) {
                // create entry for missing or deleted doc:
                NSDictionary* value = nil;
                SInt64 docNumericID = [self getDocNumericID: docID];
                if (docNumericID > 0) {
                    BOOL deleted;
                    CBLStatus status;
                    NSString* revID = [self winningRevIDOfDocNumericID: docNumericID
                                                             isDeleted: &deleted
                                                            isConflict: NULL
                                                                status: &status];
                    AssertEq(status, kCBLStatusOK);
                    if (revID)
                        value = $dict({@"rev", revID}, {@"deleted", $true});
                }
                row = [[CBLQueryRow alloc] initWithDocID: (value ?docID :nil)
                                                   sequence: 0
                                                        key: docID
                                                      value: value
                                                docRevision: nil];
            }
            if (!filter || [self row: row passesFilter: filter])
                [rows addObject: row];
        }
    }

    //OPT: Return objects from enum as they're found, without collecting them in an array first
    return [[CBLQueryEnumerator alloc] initWithSequenceNumber: lastSeq rows: rows];
}


- (BOOL) row: (CBLQueryRow*)row passesFilter: (CBLQueryRowFilter)filter {
    [row moveToDatabase: _delegate view: nil];      //FIX: Technically _delgate is not CBLDatabase
    if (!filter(row))
        return NO;
    [row _clearDatabase];
    return YES;
}


- (NSMutableDictionary*) documentPropertiesFromJSON: (NSData*)json
                                              docID: (NSString*)docID
                                              revID: (NSString*)revID
                                            deleted: (BOOL)deleted
                                           sequence: (SequenceNumber)sequence
{
    CBL_MutableRevision* rev = [[CBL_MutableRevision alloc] initWithDocID: docID revID: revID
                                                                  deleted: deleted];
    rev.sequence = sequence;
    rev.missing = (json == nil);
    NSMutableDictionary* docProperties;
    if (json.length == 0 || (json.length==2 && memcmp(json.bytes, "{}", 2)==0))
        docProperties = $mdict();      // optimization, and workaround for issue #44
    else {
        docProperties = [CBLJSON JSONObjectWithData: json
                                            options: CBLJSONReadingMutableContainers
                                              error: NULL];
        if (!docProperties) {
            Warn(@"Unparseable JSON for doc=%@, rev=%@: %@", docID, revID, [json my_UTF8ToString]);
            docProperties = $mdict();
        }
    }
    docProperties[@"_id"] = docID;
    docProperties[@"_rev"] = revID;
    if (deleted)
        docProperties[@"_deleted"] = $true;
    return docProperties;
}


/** Returns the rev ID of the 'winning' revision of this document, and whether it's deleted. */
- (NSString*) winningRevIDOfDocNumericID: (SInt64)docNumericID
                               isDeleted: (BOOL*)outIsDeleted
                              isConflict: (BOOL*)outIsConflict // optional
                                  status: (CBLStatus*)outStatus
{
    Assert(docNumericID > 0);
    CBL_FMResultSet* r = [_fmdb executeQuery: @"SELECT revid, deleted FROM revs"
                                               " WHERE doc_id=? and current=1"
                                               " ORDER BY deleted asc, revid desc LIMIT ?",
                          @(docNumericID), @(outIsConflict ? 2 : 1)];
    if (!r) {
        *outStatus = self.lastDbError;
        return nil;
    }
    NSString* revID = nil;
    if ([r next]) {
        revID = [r stringForColumnIndex: 0];
        *outIsDeleted = [r boolForColumnIndex: 1];
        // The document is in conflict if there are two+ result rows that are not deletions.
        if (outIsConflict)
            *outIsConflict = !*outIsDeleted && [r next] && ![r boolForColumnIndex: 1];
    } else {
        *outIsDeleted = NO;
        if (outIsConflict)
            *outIsConflict = NO;
    }
    [r close];
    *outStatus = kCBLStatusOK;
    return revID;
}


#pragma mark - LOCAL DOCS / DB INFO:


- (CBL_MutableRevision*) getLocalDocumentWithID: (NSString*)docID
                                     revisionID: (NSString*)revID
{
    CBL_MutableRevision* result = nil;
    CBL_FMResultSet *r = [_fmdb executeQuery: @"SELECT revid, json FROM localdocs WHERE docid=?",docID];
    if ([r next]) {
        NSString* gotRevID = [r stringForColumnIndex: 0];
        if (revID && !$equal(revID, gotRevID))
            return nil;
        NSData* json = [r dataNoCopyForColumnIndex: 1];
        NSMutableDictionary* properties;
        if (json.length==0 || (json.length==2 && memcmp(json.bytes, "{}", 2)==0))
            properties = $mdict();      // workaround for issue #44
        else {
            properties = [CBLJSON JSONObjectWithData: json
                                            options:CBLJSONReadingMutableContainers
                                              error: NULL];
            if (!properties)
                return nil;
        }
        properties[@"_id"] = docID;
        properties[@"_rev"] = gotRevID;
        result = [[CBL_MutableRevision alloc] initWithDocID: docID revID: gotRevID deleted:NO];
        result.properties = properties;
    }
    [r close];
    return result;
}


- (CBL_Revision*) putLocalRevision: (CBL_Revision*)revision
                    prevRevisionID: (NSString*)prevRevID
                          obeyMVCC: (BOOL)obeyMVCC
                            status: (CBLStatus*)outStatus
{
    NSString* docID = revision.docID;
    if (![docID hasPrefix: @"_local/"]) {
        *outStatus = kCBLStatusBadID;
        return nil;
    }
    if (!obeyMVCC) {
        return [self putLocalRevisionNoMVCC: revision status: outStatus];
    } else if (!revision.deleted) {
        // PUT:
        NSData* json = [self encodeDocumentJSON: revision];
        if (!json) {
            *outStatus = kCBLStatusBadJSON;
            return nil;
        }
        
        NSString* newRevID;
        if (prevRevID) {
            unsigned generation = [CBL_Revision generationFromRevID: prevRevID];
            if (generation == 0) {
                *outStatus = kCBLStatusBadID;
                return nil;
            }
            newRevID = $sprintf(@"%d-local", ++generation);
            if (![_fmdb executeUpdate: @"UPDATE localdocs SET revid=?, json=? "
                                        "WHERE docid=? AND revid=?", 
                                       newRevID, json, docID, prevRevID]) {
                *outStatus = self.lastDbError;
                return nil;
            }
        } else {
            newRevID = @"1-local";
            // The docid column is unique so the insert will be a no-op if there is already
            // a doc with this ID.
            if (![_fmdb executeUpdate: @"INSERT OR IGNORE INTO localdocs (docid, revid, json) "
                                        "VALUES (?, ?, ?)",
                                   docID, newRevID, json]) {
                *outStatus = self.lastDbError;
                return nil;
            }
        }
        if (_fmdb.changes == 0) {
            *outStatus = kCBLStatusConflict;
            return nil;
        }
        *outStatus = kCBLStatusCreated;
        return [revision mutableCopyWithDocID: docID revID: newRevID];
        
    } else {
        // DELETE:
        *outStatus = [self deleteLocalDocumentWithID: docID revisionID: prevRevID];
        return *outStatus < 300 ? revision : nil;
    }
}


- (CBL_Revision*) putLocalRevisionNoMVCC: (CBL_Revision*)revision
                                  status: (CBLStatus*)outStatus
{
    __block CBL_Revision* result = nil;
    *outStatus = [self inTransaction: ^CBLStatus {
        CBL_Revision* prevRev = [self getLocalDocumentWithID: revision.docID revisionID: nil];
        result = [self putLocalRevision: revision
                         prevRevisionID: prevRev.revID
                               obeyMVCC: YES
                                 status: outStatus];
        return *outStatus;
    }];
    return result;
}


- (CBLStatus) deleteLocalDocumentWithID: (NSString*)docID
                             revisionID: (NSString*)revID
{
    if (!revID) {
        // Didn't specify a revision to delete: kCBLStatusNotFound or a kCBLStatusConflict, depending
        return [self getLocalDocumentWithID: docID revisionID: nil] ? kCBLStatusConflict : kCBLStatusNotFound;
    }
    if (![_fmdb executeUpdate: @"DELETE FROM localdocs WHERE docid=? AND revid=?", docID, revID])
        return self.lastDbError;
    if (_fmdb.changes == 0)
        return [self getLocalDocumentWithID: docID revisionID: nil] ? kCBLStatusConflict : kCBLStatusNotFound;
    return kCBLStatusOK;
}


- (NSString*) infoForKey: (NSString*)key {
    return [_fmdb stringForQuery: @"SELECT value FROM info WHERE key=?", key];
}

- (CBLStatus) setInfo: (id)info forKey: (NSString*)key {
    if ([_fmdb executeUpdate: @"INSERT OR REPLACE INTO info (key, value) VALUES (?, ?)", key, info])
        return kCBLStatusOK;
    else
        return self.lastDbError;
}


#pragma mark - INSERTION:

- (CBL_Revision*) addDocID: (NSString*)inDocID
                 prevRevID: (NSString*)inPrevRevID
                properties: (NSMutableDictionary*)properties
                  deleting: (BOOL)deleting
             allowConflict: (BOOL)allowConflict
           validationBlock: (CBL_StorageValidationBlock)validationBlock
                    status: (CBLStatus*)outStatus
                     error: (NSError**)outError
{
    if (outError)
        *outError = nil;

    __block NSData* json = nil;
    if (properties) {
        json = [CBL_Revision asCanonicalJSON: properties error: NULL];
        if (!json) {
            *outStatus = kCBLStatusBadJSON;
            CBLStatusToOutNSError(*outStatus, outError);
            return nil;
        }
    } else {
        json = [NSData dataWithBytes: "{}" length: 2];
    }

    __block CBL_MutableRevision* newRev = nil;
    __block NSString* winningRevID = nil;
    __block BOOL inConflict = NO;

    *outStatus = [self inOuterTransaction: ^CBLStatus {
        // Remember, this block may be called multiple times if I have to retry the transaction.
        newRev = nil;
        winningRevID = nil;
        inConflict = NO;
        NSString* prevRevID = inPrevRevID;
        NSString* docID = inDocID;

        //// PART I: In which are performed lookups and validations prior to the insert...

        // Get the doc's numeric ID (doc_id) and its current winning revision:
        BOOL isNewDoc = (prevRevID == nil);
        SInt64 docNumericID;
        if (docID) {
            docNumericID = [self createOrGetDocNumericID: docID isNew: &isNewDoc];
            if (docNumericID <= 0)
                return self.lastDbError;
        } else {
            docNumericID = 0;
            isNewDoc = YES;
        }
        BOOL oldWinnerWasDeletion = NO;
        BOOL wasConflicted = NO;
        NSString* oldWinningRevID = nil;
        if (!isNewDoc) {
            // Look up which rev is the winner, before this insertion
            //OPT: This rev ID could be cached in the 'docs' row
            CBLStatus status;
            oldWinningRevID = [self winningRevIDOfDocNumericID: docNumericID
                                                     isDeleted: &oldWinnerWasDeletion
                                                    isConflict: &wasConflicted
                                                        status: &status];
            if (CBLStatusIsError(status))
                return status;
        }

        SequenceNumber parentSequence = 0;
        if (prevRevID) {
            // Replacing: make sure given prevRevID is current & find its sequence number:
            if (isNewDoc)
                return kCBLStatusNotFound;
            parentSequence = [self getSequenceOfDocument: docNumericID revision: prevRevID
                                             onlyCurrent: !allowConflict];
            if (parentSequence == 0) {
                // Not found: kCBLStatusNotFound or a kCBLStatusConflict, depending on whether there is any current revision
                if (!allowConflict && [self existsDocumentWithID: docID revisionID: nil])
                    return kCBLStatusConflict;
                else
                    return kCBLStatusNotFound;
            }

        } else {
            // Inserting first revision.
            if (deleting && docID) {
                // Didn't specify a revision to delete: NotFound or a Conflict, depending
                return [self existsDocumentWithID: docID revisionID: nil] ? kCBLStatusConflict
                                                                          : kCBLStatusNotFound;
            }
            
            if (docID) {
                // Inserting first revision, with docID given (PUT):
                // Check whether current winning revision is deleted:
                if (oldWinnerWasDeletion) {
                    prevRevID = oldWinningRevID;
                    parentSequence = [self getSequenceOfDocument: docNumericID
                                                        revision: prevRevID
                                                     onlyCurrent: NO];
                } else if (oldWinningRevID) {
                    // The current winning revision is not deleted, so this is a conflict
                    return kCBLStatusConflict;
                }
            } else {
                // Inserting first revision, with no docID given (POST): generate a unique docID:
                docID = CBLCreateUUID();
                docNumericID = [self createOrGetDocNumericID: docID isNew: &isNewDoc];
                if (docNumericID <= 0)
                    return self.lastDbError;
            }
        }

        // There may be a conflict if (a) the document was already in conflict, or
        // (b) a conflict is created by adding a non-deletion child of a non-winning rev.
        inConflict = wasConflicted || (!deleting && !$equal(prevRevID, oldWinningRevID));

        //// PART II: In which we prepare for insertion...
        
        // Bump the revID and update the JSON:
        NSString* newRevID = [_delegate generateRevIDForJSON: json
                                                     deleted: deleting
                                                   prevRevID: prevRevID];
        if (!newRevID)
            return kCBLStatusBadID;  // invalid previous revID (no numeric prefix)
        Assert(docID);
        newRev = [[CBL_MutableRevision alloc] initWithDocID: docID
                                                      revID: newRevID
                                                    deleted: deleting];
        if (properties) {
            properties[@"_id"] = docID;
            properties[@"_rev"] = newRevID;
            newRev.properties = properties;
        }

        // Validate:
        if (validationBlock) {
            // Fetch the previous revision and validate the new one against it:
            CBL_Revision* prevRev = nil;
            if (prevRevID) {
                prevRev = [[CBL_Revision alloc] initWithDocID: docID
                                                        revID: prevRevID
                                                      deleted: NO];
            }
            CBLStatus status = validationBlock(newRev, prevRev, prevRevID, outError);
            if (CBLStatusIsError(status))
                return status;
        }

        // Don't store a SQL null in the 'json' column -- I reserve it to mean that the revision data
        // is missing due to compaction or replication.
        // Instead, store an empty zero-length blob.
        if (json == nil)
            json = [NSData data];

        //// PART III: In which the actual insertion finally takes place:
        
        SequenceNumber sequence = [self insertRevision: newRev
                                          docNumericID: docNumericID
                                        parentSequence: parentSequence
                                               current: YES
                                        hasAttachments: (properties.cbl_attachments != nil)
                                                  JSON: json
                                               docType: properties[@"type"]];
        if (!sequence) {
            // The insert failed. If it was due to a constraint violation, that means a revision
            // already exists with identical contents and the same parent rev. We can ignore this
            // insert call, then.
            if (_fmdb.lastErrorCode != SQLITE_CONSTRAINT)
                return self.lastDbError;
            LogTo(Database, @"Duplicate rev insertion: %@ / %@", docID, newRevID);
            newRev.body = nil;
            // don't return yet; update the parent's current just to be sure (see #509)
        }
        
        // Make replaced rev non-current:
        if (parentSequence > 0) {
            if (![_fmdb executeUpdate: @"UPDATE revs SET current=0, doc_type=null WHERE sequence=?",
                                       @(parentSequence)]) {
                CBLStatus status = self.lastDbError;
                [_fmdb executeUpdate: @"DELETE FROM revs WHERE sequence=?", @(sequence)];
                return status;
            }
        }

        if (!sequence)
            return kCBLStatusOK;  // duplicate rev; see above

        // Delete the deepest revs in the tree to enforce the maxRevTreeDepth:
        int minGenToKeep = (int)newRev.generation - (int)_maxRevTreeDepth + 1;
        if (minGenToKeep > 1) {
            unsigned pruned = [self pruneDocument: docNumericID generationsBelow: minGenToKeep];
            if (pruned > 0)
                LogVerbose(Database, @"Pruned %lu old revisions of doc '%@'",
                           (unsigned long)pruned, docID);
        }

        // Figure out what the new winning rev ID is:
            winningRevID = [self winnerWithDocID: docNumericID
                                 oldWinner: oldWinningRevID oldDeleted: oldWinnerWasDeletion
                                        newRev: newRev];

        // Success!
        return deleting ? kCBLStatusOK : kCBLStatusCreated;
    }];
    
    if (CBLStatusIsError(*outStatus)) {
        if (outError && !*outError)
            CBLStatusToOutNSError(*outStatus, outError);
        return nil;
    }
    
    //// EPILOGUE: A change notification is sent...
    if (newRev.sequenceIfKnown != 0) {
        [_delegate databaseStorageChanged: [[CBLDatabaseChange alloc] initWithAddedRevision: newRev
                                                                  winningRevisionID: winningRevID
                                                                         inConflict: inConflict
                                                                             source: nil]];
    }
    return newRev;
}


- (CBLStatus) forceInsert: (CBL_Revision*)inRev
          revisionHistory: (NSArray*)history
          validationBlock: (CBL_StorageValidationBlock)validationBlock
                   source: (NSURL*)source
                    error: (NSError**)outError
{
    if (outError)
        *outError = nil;

    CBL_MutableRevision* rev = inRev.mutableCopy;
    rev.sequence = 0;
    NSString* docID = rev.docID;
    
    __block NSString* winningRevID = nil;
    __block BOOL inConflict = NO;
    CBLStatus status = [self inTransaction: ^CBLStatus {
        // First look up the document's row-id and all locally-known revisions of it:
        NSMutableDictionary* localRevs = nil;
        NSString* oldWinningRevID = nil;
        BOOL oldWinnerWasDeletion = NO;
        BOOL isNewDoc = (history.count == 1);
        SInt64 docNumericID = [self createOrGetDocNumericID: docID isNew: &isNewDoc];
        if (docNumericID <= 0)
            return self.lastDbError;
        if (!isNewDoc) {
            CBL_RevisionList* localRevsList = [self getAllRevisionsOfDocumentID: docID
                                                                      numericID: docNumericID
                                                                    onlyCurrent: NO];
            if (!localRevsList)
                return self.lastDbError;
            localRevs = [[NSMutableDictionary alloc] initWithCapacity: localRevsList.count];
            for (CBL_Revision* rev in localRevsList)
                localRevs[rev.revID] = rev;

            // Look up which rev is the winner, before this insertion
            CBLStatus tempStatus;
            oldWinningRevID = [self winningRevIDOfDocNumericID: docNumericID
                                                     isDeleted: &oldWinnerWasDeletion
                                                    isConflict: &inConflict
                                                        status: &tempStatus];
            if (CBLStatusIsError(tempStatus))
                return tempStatus;
        }

        // Validate against the latest common ancestor:
        if (validationBlock) {
            CBL_Revision* oldRev = nil;
            for (NSUInteger i = 1; i<history.count; ++i) {
                oldRev = localRevs[history[i]];
                if (oldRev)
                    break;
            }
            NSString* parentRevID = (history.count > 1) ? history[1] : nil;
            CBLStatus status = validationBlock(rev, oldRev, parentRevID, outError);
            if (CBLStatusIsError(status))
                return status;
        }
        
        // Walk through the remote history in chronological order, matching each revision ID to
        // a local revision. When the list diverges, start creating blank local revisions to fill
        // in the local history:
        SequenceNumber sequence = 0;
        SequenceNumber localParentSequence = 0;
        for (NSInteger i = history.count - 1; i>=0; --i) {
            NSString* revID = history[i];
            CBL_Revision* localRev = localRevs[revID];
            if (localRev) {
                // This revision is known locally. Remember its sequence as the parent of the next one:
                sequence = localRev.sequence;
                Assert(sequence > 0);
                localParentSequence = sequence;

            } else {
                // This revision isn't known, so add it:
                CBL_MutableRevision* newRev;
                NSData* json = nil;
                NSString* docType = nil;
                BOOL current = NO;
                if (i==0) {
                    // Hey, this is the leaf revision we're inserting:
                    newRev = rev;
                    json = [self encodeDocumentJSON: rev];
                    if (!json)
                        return kCBLStatusBadJSON;
                    docType = rev[@"type"];
                    current = YES;
                } else {
                    // It's an intermediate parent, so insert a stub:
                    newRev = [[CBL_MutableRevision alloc] initWithDocID: docID revID: revID
                                                                deleted: NO];
                }

                // Insert it:
                sequence = [self insertRevision: newRev
                                   docNumericID: docNumericID
                                 parentSequence: sequence
                                        current: current 
                                 hasAttachments: (newRev.attachments != nil)
                                           JSON: json
                                        docType: docType];
                if (sequence <= 0)
                    return self.lastDbError;
            }
        }

        if (localParentSequence == sequence)
            return kCBLStatusOK;      // No-op: No new revisions were inserted.

        // Mark the latest local rev as no longer current:
        if (localParentSequence > 0) {
            if (![_fmdb executeUpdate: @"UPDATE revs SET current=0, doc_type=null"
                                        " WHERE sequence=? AND current!=0",
                  @(localParentSequence)])
                return self.lastDbError;
            if (_fmdb.changes == 0)
                inConflict = YES; // local parent wasn't a leaf, ergo we just created a branch
        }

        // Delete the deepest revs in the tree to enforce the maxRevTreeDepth:
        if (inRev.generation > _maxRevTreeDepth) {
            __block unsigned minGen, maxGen;
            minGen = maxGen = rev.generation;
            [localRevs enumerateKeysAndObjectsUsingBlock:^(id key, CBL_Revision* rev, BOOL* stop) {
                unsigned generation = rev.generation;
                minGen = MIN(minGen, generation);
                maxGen = MAX(maxGen, generation);
            }];
            int minGenToKeep = maxGen - _maxRevTreeDepth + 1;
            if ((int)minGen < minGenToKeep) {
                unsigned pruned = [self pruneDocument: docNumericID generationsBelow: minGenToKeep];
                if (pruned > 0)
                    LogVerbose(Database, @"Pruned %u old revisions of doc '%@'", pruned, docID);
            }
        }

        // Figure out what the new winning rev ID is:
        winningRevID = [self winnerWithDocID: docNumericID
                                   oldWinner: oldWinningRevID
                                  oldDeleted: oldWinnerWasDeletion
                                      newRev: rev];

        return kCBLStatusCreated;
    }];

    if (status == kCBLStatusCreated) {
        [_delegate databaseStorageChanged: [[CBLDatabaseChange alloc] initWithAddedRevision: rev
                                                              winningRevisionID: winningRevID
                                                                     inConflict: inConflict
                                                                         source: source]];
    } else if (CBLStatusIsError(status)) {
        if (outError && !*outError)
            CBLStatusToOutNSError(status, outError);
    }

    return status;
}


// Raw row insertion. Returns new sequence, or 0 on error
- (SequenceNumber) insertRevision: (CBL_Revision*)rev
                     docNumericID: (SInt64)docNumericID
                   parentSequence: (SequenceNumber)parentSequence
                          current: (BOOL)current
                   hasAttachments: (BOOL)hasAttachments
                             JSON: (NSData*)json
                          docType: (NSString*)docType
{
    if (![_fmdb executeUpdate: @"INSERT INTO revs (doc_id, revid, parent, current, deleted, "
          "no_attachments, json, doc_type) "
          "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
          @(docNumericID),
          rev.revID,
          (parentSequence ? @(parentSequence) : nil ),
          @(current),
          @(rev.deleted),
          @(!hasAttachments),
          json,
          docType])
        return 0;
    return rev.sequence = _fmdb.lastInsertRowId;
}


/** Returns the JSON to be stored into the 'json' column for a given CBL_Revision.
    This has all the special keys like "_id" stripped out. */
- (NSData*) encodeDocumentJSON: (CBL_Revision*)rev {
    static NSSet* sSpecialKeysToRemove, *sSpecialKeysToLeave;
    if (!sSpecialKeysToRemove) {
        sSpecialKeysToRemove = [[NSSet alloc] initWithObjects: @"_id", @"_rev",
            @"_deleted", @"_revisions", @"_revs_info", @"_conflicts", @"_deleted_conflicts",
            @"_local_seq", nil];
        sSpecialKeysToLeave = [[NSSet alloc] initWithObjects:
            @"_removed", @"_attachments", nil];
    }

    NSDictionary* origProps = rev.properties;
    if (!origProps)
        return nil;
    
    // Don't leave in any "_"-prefixed keys except for the ones in sSpecialKeysToLeave.
    // Keys in sSpecialKeysToRemove (_id, _rev, ...) are left out, any others trigger an error.
    NSMutableDictionary* properties = [[NSMutableDictionary alloc] initWithCapacity: origProps.count];
    for (NSString* key in origProps) {
        if (![key hasPrefix: @"_"]  || [sSpecialKeysToLeave member: key]) {
            properties[key] = origProps[key];
        } else if (![sSpecialKeysToRemove member: key]) {
            Log(@"CBLDatabase: Invalid top-level key '%@' in document to be inserted", key);
            return nil;
        }
    }
    
    // Create canonical JSON -- this is important, because the JSON data returned here will be used
    // to create the new revision ID, and we need to guarantee that equivalent revision bodies
    // result in equal revision IDs.
    NSData* json = [CBJSONEncoder canonicalEncoding: properties error: nil];
    return json;
}


- (NSString*) winnerWithDocID: (SInt64)docNumericID
                    oldWinner: (NSString*)oldWinningRevID
                   oldDeleted: (BOOL)oldWinnerWasDeletion
                       newRev: (CBL_Revision*)newRev
{
    NSString* newRevID = newRev.revID;
    if (!oldWinningRevID)
        return newRevID;
    if (!newRev.deleted) {
        if (oldWinnerWasDeletion || CBLCompareRevIDs(newRevID, oldWinningRevID) > 0)
            return newRevID;   // this is now the winning live revision
    } else if (oldWinnerWasDeletion) {
        if (CBLCompareRevIDs(newRevID, oldWinningRevID) > 0)
            return newRevID;  // doc still deleted, but this beats previous deletion rev
    } else {
        // Doc was alive. How does this deletion affect the winning rev ID?
        BOOL deleted;
        CBLStatus status;
        NSString* winningRevID = [self winningRevIDOfDocNumericID: docNumericID
                                                        isDeleted: &deleted
                                                       isConflict: NULL
                                                           status: &status];
        AssertEq(status, kCBLStatusOK);
        if (!$equal(winningRevID, oldWinningRevID))
            return winningRevID;
    }
    return nil; // no change
}


#pragma mark - HOUSEKEEPING:


- (void) optimizeSQLIndexes {
    SequenceNumber curSequence = self.lastSequence;
    if (curSequence > 0) {
        SequenceNumber lastOptimized = [[self infoForKey: @"last_optimized"] longLongValue];
        if (lastOptimized <= curSequence/10) {
            [self inTransaction:^CBLStatus{
                LogTo(Database, @"%@: Optimizing SQL indexes (curSeq=%lld, last run at %lld)",
                      self, curSequence, lastOptimized);
                [_fmdb executeUpdate: @"ANALYZE"];
                [_fmdb executeUpdate: @"ANALYZE sqlite_master"];
                [_fmdb clearCachedStatements];
                [self setInfo: $sprintf(@"%lld", curSequence) forKey: @"last_optimized"];
                return kCBLStatusOK;
            }];
        }
    }
}


- (BOOL) compact: (NSError**)outError {
    if (![self infoForKey: @"pruned"]) {
        // Bulk pruning is no longer needed, because revisions are pruned incrementally as new
        // ones are added. But databases from before this feature was added (1.3) may have documents
        // that need pruning. So we'll do a one-time bulk prune, then set a flag indicating that
        // it isn't needed anymore.
        NSUInteger nPruned;
        CBLStatus status = [self pruneRevsToMaxDepth: _maxRevTreeDepth numberPruned: &nPruned];
        if (status != kCBLStatusOK)
            return CBLStatusToOutNSError(status, outError);
        [self setInfo: @"true" forKey: @"pruned"];
    }

    // Remove the JSON of non-current revisions, which is most of the space.
    Log(@"CBLDatabase: Deleting JSON of old revisions...");
    if (![_fmdb executeUpdate: @"UPDATE revs SET json=null, doc_type=null, no_attachments=1"
                                " WHERE current=0"])
        return CBLStatusToOutNSError(self.lastDbError, outError);
    Log(@"    ... deleted %d revisions", _fmdb.changes);

    Log(@"Flushing SQLite WAL...");
    if (![_fmdb executeUpdate: @"PRAGMA wal_checkpoint(RESTART)"])
        return CBLStatusToOutNSError(self.lastDbError, outError);

    Log(@"Vacuuming SQLite database...");
    if (![_fmdb executeUpdate: @"VACUUM"])
        return CBLStatusToOutNSError(self.lastDbError, outError);

//    Log(@"Closing and re-opening database...");
//    [_fmdb close];
//    if (![self openFMDB: nil])
//        return CBLStatusToOutNSError(self.lastDbError, outError);

    Log(@"...Finished database compaction.");
    return YES;
}


- (CBLStatus) pruneRevsToMaxDepth: (NSUInteger)maxDepth numberPruned: (NSUInteger*)outPruned {
    // TODO: This implementation is a bit simplistic. It won't do quite the right thing in
    // histories with branches, if one branch stops much earlier than another. The shorter branch
    // will be deleted entirely except for its leaf revision. A more accurate pruning
    // would require an expensive full tree traversal. Hopefully this way is good enough.
    if (maxDepth == 0)
        maxDepth = self.maxRevTreeDepth;

    Log(@"CBLDatabase: Pruning revisions to max depth %ld...", (unsigned long)maxDepth);
    *outPruned = 0;
    // First find which docs need pruning, and by how much:
    NSMutableDictionary* toPrune = $mdict();
    NSString* sql = @"SELECT doc_id, MIN(revid), MAX(revid) FROM revs GROUP BY doc_id";
    CBL_FMResultSet* r = [_fmdb executeQuery: sql];
    while ([r next]) {
        UInt64 docNumericID = [r longLongIntForColumnIndex: 0];
        unsigned minGen = [CBL_Revision generationFromRevID: [r stringForColumnIndex: 1]];
        unsigned maxGen = [CBL_Revision generationFromRevID: [r stringForColumnIndex: 2]];
        if ((maxGen - minGen + 1) > maxDepth)
            toPrune[@(docNumericID)] = @(maxGen - maxDepth);
    }
    [r close];

    if (toPrune.count == 0)
        return kCBLStatusOK;

    // Now prune:
    return [self inTransaction:^CBLStatus{
        for (NSNumber* docNumericID in toPrune) {
            *outPruned += [self pruneDocument: docNumericID.unsignedLongLongValue
                             generationsBelow: [toPrune[docNumericID] intValue] + 1];
        }
        return kCBLStatusOK;
    }];
}


// Returns the number of revisions pruned.
- (unsigned) pruneDocument: (UInt64)docNumericID
          generationsBelow: (unsigned)minGenToKeep
{
    if (![_fmdb executeUpdate: @"DELETE FROM revs WHERE doc_id=? AND revid < ? AND current=0",
          @(docNumericID), $sprintf(@"%u-", minGenToKeep)]) {
        Warn(@"SQLite error %d pruning generations < %d of doc %llu",
             _fmdb.lastErrorCode, minGenToKeep, docNumericID);
        return 0;
    }
    return _fmdb.changes;
}


- (NSSet*) findAllAttachmentKeys: (NSError**)outError {
    CBL_FMResultSet* r = [_fmdb executeQuery: @"SELECT json FROM revs WHERE no_attachments != 1"];
    if (!r) {
        CBLStatusToOutNSError(self.lastDbStatus, outError);
        return nil;
    }
    NSMutableSet* allKeys = [NSMutableSet set];
    while ([r next]) {
        NSDictionary* rev = [CBLJSON JSONObjectWithData: [r dataNoCopyForColumnIndex: 0]
                                                options: 0 error: NULL];
        [rev.cbl_attachments enumerateKeysAndObjectsUsingBlock:^(id key, NSDictionary* att, BOOL *stop) {
            CBLBlobKey blobKey;
            if ([CBL_Attachment digest: att[@"digest"] toBlobKey: &blobKey]) {
                NSData* keyData = [[NSData alloc] initWithBytes: &blobKey length: sizeof(blobKey)];
                [allKeys addObject: keyData];
            }
        }];
    }
    [r close];
    return allKeys;
}


/** Purges specific revisions, which deletes them completely from the local database _without_ adding a "tombstone" revision. It's as though they were never there.
    @param docsToRevs  A dictionary mapping document IDs to arrays of revision IDs.
    @param outResult  On success will point to an NSDictionary with the same form as docsToRev, containing the doc/revision IDs that were actually removed. */
- (CBLStatus) purgeRevisions: (NSDictionary*)docsToRevs
                      result: (NSDictionary**)outResult
{
    // <http://wiki.apache.org/couchdb/Purge_Documents>
    NSMutableDictionary* result = $mdict();
    if (outResult)
        *outResult = result;
    if (docsToRevs.count == 0)
        return kCBLStatusOK;
    return [self inTransaction: ^CBLStatus {
        for (NSString* docID in docsToRevs) {
            SInt64 docNumericID = [self getDocNumericID: docID];
            if (!docNumericID) {
                continue;  // no such document; skip it
            }
            NSArray* revsPurged;
            NSArray* revIDs = $castIf(NSArray, docsToRevs[docID]);
            if (!revIDs) {
                return kCBLStatusBadParam;
            } else if (revIDs.count == 0) {
                revsPurged = @[];
            } else if ([revIDs containsObject: @"*"]) {
                // Delete all revisions if magic "*" revision ID is given:
                if (![_fmdb executeUpdate: @"DELETE FROM revs WHERE doc_id=?",
                                           @(docNumericID)]) {
                    return self.lastDbError;
                }
                revsPurged = @[@"*"];
                
            } else {
                // Iterate over all the revisions of the doc, in reverse sequence order.
                // Keep track of all the sequences to delete, i.e. the given revs and ancestors,
                // but not any non-given leaf revs or their ancestors.
                CBL_FMResultSet* r = [_fmdb executeQuery: @"SELECT revid, sequence, parent FROM revs "
                                                       "WHERE doc_id=? ORDER BY sequence DESC",
                                  @(docNumericID)];
                if (!r)
                    return self.lastDbError;
                NSMutableSet* seqsToPurge = [NSMutableSet set];
                NSMutableSet* seqsToKeep = [NSMutableSet set];
                NSMutableSet* revsToPurge = [NSMutableSet set];
                while ([r next]) {
                    NSString* revID = [r stringForColumnIndex: 0];
                    id sequence = @([r longLongIntForColumnIndex: 1]);
                    id parent = @([r longLongIntForColumnIndex: 2]);
                    if (([seqsToPurge containsObject: sequence] || [revIDs containsObject:revID]) &&
                            ![seqsToKeep containsObject: sequence]) {
                        // Purge it and maybe its parent:
                        [seqsToPurge addObject: sequence];
                        [revsToPurge addObject: revID];
                        if ([parent longLongValue] > 0)
                            [seqsToPurge addObject: parent];
                    } else {
                        // Keep it and its parent:
                        [seqsToPurge removeObject: sequence];
                        [revsToPurge removeObject: revID];
                        [seqsToKeep addObject: parent];
                    }
                }
                [r close];
                [seqsToPurge minusSet: seqsToKeep];

                LogTo(Database, @"Purging doc '%@' revs (%@); asked for (%@)",
                      docID, [revsToPurge.allObjects componentsJoinedByString: @", "],
                      [revIDs componentsJoinedByString: @", "]);

                if (seqsToPurge.count) {
                    // Now delete the sequences to be purged.
                    NSString* sql = $sprintf(@"DELETE FROM revs WHERE sequence in (%@)",
                                           [seqsToPurge.allObjects componentsJoinedByString: @","]);
                    _fmdb.shouldCacheStatements = NO;
                    BOOL ok = [_fmdb executeUpdate: sql];
                    _fmdb.shouldCacheStatements = YES;
                    if (!ok)
                        return self.lastDbError;
                    if ((NSUInteger)_fmdb.changes != seqsToPurge.count)
                        Warn(@"purgeRevisions: Only %i sequences deleted of (%@)",
                             _fmdb.changes, [seqsToPurge.allObjects componentsJoinedByString:@","]);
                }
                revsPurged = revsToPurge.allObjects;
            }
#if 1
            // Result is just the _given_ rev IDs that were removed
            result[docID] = [revIDs my_filter:^int(NSString* revID) {
                return [revsPurged containsObject: revID];
            }];
#else
            // Alternate: Result is all rev IDs removed (including ancestors)
            result[docID] = revsPurged;
#endif
        }
        return kCBLStatusOK;
    }];
}


#pragma mark - VIEWS:


- (id<CBL_ViewStorage>) viewStorageNamed: (NSString*)name
                                  create: (BOOL)create
{
    return [[CBL_SQLiteViewStorage alloc] initWithDBStorage: self name: name create: create];
}


- (NSArray*) allViewNames {
    CBL_FMResultSet* r = [_fmdb executeQuery: @"SELECT name FROM views"];
    if (!r)
        return nil;
    NSMutableArray* names = $marray();
    while ([r next])
        [names addObject: [r stringForColumnIndex: 0]];
    [r close];
    return names;
}


@end




/*    Adapted from http://sqlite.org/fts3.html#appendix_a (public domain)
 *    removing the column-weights feature (because we only have one column)
 **
 ** SQLite user defined function to use with matchinfo() to calculate the
 ** relevancy of an FTS match. The value returned is the relevancy score
 ** (a real value greater than or equal to zero). A larger value indicates
 ** a more relevant document.
 **
 ** The overall relevancy returned is the sum of the relevancies of each
 ** column value in the FTS table. The relevancy of a column value is the
 ** sum of the following for each reportable phrase in the FTS query:
 **
 **   (<hit count> / <global hit count>)
 **
 ** where <hit count> is the number of instances of the phrase in the
 ** column value of the current row and <global hit count> is the number
 ** of instances of the phrase in the same column of all rows in the FTS
 ** table.
 */
static void CBLComputeFTSRank(sqlite3_context *pCtx, int nVal, sqlite3_value **apVal) {
    const uint32_t *aMatchinfo;                /* Return value of matchinfo() */
    uint32_t nCol;
    uint32_t nPhrase;                    /* Number of phrases in the query */
    uint32_t iPhrase;                    /* Current phrase */
    double score = 0.0;             /* Value to return */

    /*  Set aMatchinfo to point to the array
     ** of unsigned integer values returned by FTS function matchinfo. Set
     ** nPhrase to contain the number of reportable phrases in the users full-text
     ** query, and nCol to the number of columns in the table.
     */
    aMatchinfo = (const uint32_t*)sqlite3_value_blob(apVal[0]);
    nPhrase = aMatchinfo[0];
    nCol = aMatchinfo[1];

    /* Iterate through each phrase in the users query. */
    for(iPhrase=0; iPhrase<nPhrase; iPhrase++){
        uint32_t iCol;                     /* Current column */

        /* Now iterate through each column in the users query. For each column,
         ** increment the relevancy score by:
         **
         **   (<hit count> / <global hit count>)
         **
         ** aPhraseinfo[] points to the start of the data for phrase iPhrase. So
         ** the hit count and global hit counts for each column are found in
         ** aPhraseinfo[iCol*3] and aPhraseinfo[iCol*3+1], respectively.
         */
        const uint32_t *aPhraseinfo = &aMatchinfo[2 + iPhrase*nCol*3];
        for(iCol=0; iCol<nCol; iCol++){
            uint32_t nHitCount = aPhraseinfo[3*iCol];
            uint32_t nGlobalHitCount = aPhraseinfo[3*iCol+1];
            if( nHitCount>0 ){
                score += ((double)nHitCount / (double)nGlobalHitCount);
            }
        }
    }

    sqlite3_result_double(pCtx, score);
    return;
}
