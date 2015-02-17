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
#import "CouchbaseLitePrivate.h"
#import "ExceptionUtils.h"

#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "sqlite3_unicodesn_tokenizer.h"


#define kDBFilename @"db.sqlite3"

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


static void CBLComputeFTSRank(sqlite3_context *pCtx, int nVal, sqlite3_value **apVal);


@implementation CBL_SQLiteStorage
{
    NSString* _directory;
    __weak CBLManager* _manager;
    BOOL _readOnly;
    NSCache* _docIDs;
}

@synthesize delegate=_delegate, autoCompact=_autoCompact,
            maxRevTreeDepth=_maxRevTreeDepth, fmdb=_fmdb;


+ (void) initialize {
    // Test the features of the actual SQLite implementation at runtime. This is necessary because
    // the app might be linked with a custom version of SQLite (like SQLCipher) instead of the
    // system library, so the actual version/features may differ from what was declared in
    // sqlite3.h at compile time.
    if (self == [CBL_SQLiteStorage class]) {
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
        Assert(sqlite3_libversion_number() >= 3007000,
               @"SQLite library is too old (%s); needs to be at least 3.7", sqlite3_libversion());
        Assert(sqlite3_compileoption_used("SQLITE_ENABLE_FTS3")
                    || sqlite3_compileoption_used("SQLITE_ENABLE_FTS4"),
               @"SQLite isn't built with full-text indexing (FTS3 or FTS4)");
        Assert(sqlite3_compileoption_used("SQLITE_ENABLE_RTREE"),
               @"SQLite isn't built with geo-indexing (R-tree)");
    }
}


#pragma mark - OPEN/CLOSE:


- (BOOL) databaseExistsIn: (NSString*)directory {
    NSString* dbPath = [directory stringByAppendingPathComponent: kDBFilename];
    return [[NSFileManager defaultManager] fileExistsAtPath: dbPath isDirectory: NULL];
}


/** Opens storage. Files will be created in the directory, which must already exist. */
- (BOOL) openInDirectory: (NSString*)directory
                readOnly: (BOOL)readOnly
                 manager: (CBLManager*)manager
                   error: (NSError**)error
{
    _directory = [directory copy];
    _readOnly = readOnly;
    _manager = manager;
    NSString* path = [_directory stringByAppendingPathComponent: kDBFilename];
    _fmdb = [[CBL_FMDatabase alloc] initWithPath: path];
    _fmdb.dispatchQueue = manager.dispatchQueue;
    _fmdb.databaseLock = [manager.shared lockForDatabaseNamed: path];
#if DEBUG
    _fmdb.logsErrors = YES;
#else
    _fmdb.logsErrors = WillLogTo(CBLDatabase);
#endif
    _fmdb.traceExecution = WillLogTo(CBLDatabaseVerbose);

    _docIDs = [[NSCache alloc] init];
    _docIDs.countLimit = kDocIDCacheSize;

    return [self open: error];
}


- (BOOL) runStatements: (NSString*)statements error: (NSError**)outError {
    for (NSString* quotedStatement in [statements componentsSeparatedByString: @";"]) {
        NSString* statement = [quotedStatement stringByReplacingOccurrencesOfString: @"|"
                                                                         withString: @";"];
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
    CBLSymmetricKey* encryptionKey = _delegate.encryptionKey;

    LogTo(CBLDatabase, @"Open %@ (flags=%X%@)",
          _fmdb.databasePath, flags, (encryptionKey ? @", encryption key given" : nil));
    if (![_fmdb openWithFlags: flags]) {
        if (outError) *outError = self.fmdbError;
        return NO;
    }

    if (![self decryptWithKey: encryptionKey error: outError])
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
            return ReturnNSErrorFromCBLStatus(kCBLStatusNotImplemented,  outError);
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
                    *outError = CBLStatusToNSError(kCBLStatusUnauthorized, nil);
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
            return ReturnNSErrorFromCBLStatus(kCBLStatusUnauthorized, outError);
    }
    return YES;
}
#endif


- (BOOL) open: (NSError**)outError {
    LogTo(CBLDatabase, @"Opening %@", self);
    if (![self openFMDB: outError])
        return NO;
    
    // Check the user_version number we last stored in the database:
    __unused int dbVersion = self.schemaVersion;
    
    // Incompatible version changes increment the hundreds' place:
    if (dbVersion >= 100) {
        Warn(@"CBLDatabase: Database version (%d) is newer than I know how to work with", dbVersion);
        [_fmdb close];
        if (outError) *outError = [NSError errorWithDomain: @"CouchbaseLite" code: 1 userInfo: nil]; //FIX: Real code
        return NO;
    }

    BOOL isNew = (dbVersion == 0);
    if (isNew && ![self initialize: @"BEGIN TRANSACTION" error: outError])
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
            CREATE VIRTUAL TABLE fulltext USING fts4(content, tokenize=unicodesn);\
            CREATE VIRTUAL TABLE bboxes USING rtree(rowid, x0, x1, y0, y1);\
            PRAGMA user_version = 17";             // at the end, update user_version
        //OPT: Would be nice to use partial indexes but that requires SQLite 3.8 and makes the
        // db file only readable by SQLite 3.8+, i.e. the file would not be portable to iOS 8
        // which only has SQLite 3.7 :(
        // On the revs_parent index we could add "WHERE parent not null".

        if (![self initialize: schema error: outError])
            return NO;
        dbVersion = 17;
    }

    if (isNew && ![self initialize: @"END TRANSACTION" error: outError])
        return NO;

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
        case SQLITE_BUSY:
        case SQLITE_LOCKED:
            return kCBLStatusDBBusy;
        case SQLITE_CORRUPT:
            return kCBLStatusCorruptError;
        case SQLITE_NOTADB:
            return kCBLStatusUnauthorized; // DB is probably encrypted (SQLCipher)
        default:
            LogTo(CBLDatabase, @"Other _fmdb.lastErrorCode %d", _fmdb.lastErrorCode);
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
    LogTo(CBLDatabase, @"Begin transaction (level %d)...", _fmdb.transactionLevel);
    return YES;
}

- (BOOL) endTransaction: (BOOL)commit {
    LogTo(CBLDatabase, @"%@ transaction (level %d)",
          (commit ? @"Commit" : @"Abort"), _fmdb.transactionLevel);

    BOOL ok = [_fmdb endTransaction: commit];
    if (!ok)
        Warn(@"Failed to end transaction!");

    [_delegate storageExitedTransaction: commit];
    return ok;
}

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


#pragma mark - DOCUMENTS:


- (CBL_MutableRevision*) getDocumentWithID: (NSString*)docID
                                revisionID: (NSString*)revID
                                   options: (CBLContentOptions)options
                                    status: (CBLStatus*)outStatus
{
    SInt64 docNumericID = [self getDocNumericID: docID];
    if (docNumericID <= 0) {
        if (outStatus) *outStatus = kCBLStatusNotFound;
        return nil;
    }

    CBL_MutableRevision* result = nil;
    CBLStatus status;
    NSMutableString* sql = [NSMutableString stringWithString: @"SELECT revid, deleted, sequence, no_attachments"];
    if (!(options & kCBLNoBody))
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
        
        if (options != kCBLNoBody) {
            NSData* json = nil;
            if (!(options & kCBLNoBody))
                json = [r dataNoCopyForColumnIndex: 4];
            if ([r boolForColumnIndex: 3]) // no_attachments == true
                options |= kCBLNoAttachments;
            [self expandStoredJSON: json intoRevision: result options: options];
        }
        status = kCBLStatusOK;
    }
    [r close];
    if (outStatus)
        *outStatus = status;
    return result;
}


- (BOOL) existsDocumentWithID: (NSString*)docID revisionID: (NSString*)revID {
    CBLStatus status;
    return [self getDocumentWithID: docID revisionID: revID options: kCBLNoBody status: &status] != nil;
}


// Loads revision given its sequence. Assumes the given docID is valid.
- (CBL_MutableRevision*) getDocumentWithID: (NSString*)docID
                                  sequence: (SequenceNumber)sequence
                                    status: (CBLStatus*)outStatus
{
    CBL_MutableRevision* result = nil;
    CBLStatus status;
    CBL_FMResultSet *r = [_fmdb executeQuery:
                          @"SELECT revid, deleted, no_attachments, json FROM revs WHERE sequence=?",
                          @(sequence)];
    if (!r) {
        status = self.lastDbError;
    } else if (![r next]) {
        status = kCBLStatusNotFound;
    } else {
        result = [[CBL_MutableRevision alloc] initWithDocID: docID
                                                      revID: [r stringForColumnIndex: 0]
                                                    deleted: [r boolForColumnIndex: 1]];
        result.sequence = sequence;
        [self expandStoredJSON: [r dataNoCopyForColumnIndex: 3]
                  intoRevision: result
                       options: ([r boolForColumnIndex: 2] ? kCBLNoAttachments : 0)];
        status = kCBLStatusOK;
    }
    [r close];
    if (outStatus)
        *outStatus = status;
    return result;
}


- (CBLStatus) loadRevisionBody: (CBL_MutableRevision*)rev
                       options: (CBLContentOptions)options
{
    if (rev.body && options==0 && rev.sequence)
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
        status = kCBLStatusOK;
        rev.sequence = [r longLongIntForColumnIndex: 0];
        [self expandStoredJSON: [r dataNoCopyForColumnIndex: 1] intoRevision: rev options: options];
    }
    [r close];
    return status;
}


/** Inserts the _id, _rev and _attachments properties into the JSON data and stores it in rev.
 Rev must already have its revID and sequence properties set. */
- (void) expandStoredJSON: (NSData*)json
             intoRevision: (CBL_MutableRevision*)rev
                  options: (CBLContentOptions)options
{
    NSMutableDictionary* extra = $mdict();
    [self extraPropertiesForRevision: rev options: options into: extra];
    if (json.length > 0) {
        rev.asJSON = [CBLJSON appendDictionary: extra toJSONDictionaryData: json];
    } else {
        rev.properties = extra;
        if (json == nil)
            rev.missing = true;
    }
}


/** Inserts the _id, _rev, _attachments etc. properties into the dictionary 'dst'.
    Rev must already have its revID and sequence properties set. */
- (void) extraPropertiesForRevision: (CBL_Revision*)rev
                            options: (CBLContentOptions)options
                               into: (NSMutableDictionary*)dst
{
    dst[@"_id"] = rev.docID;
    dst[@"_rev"] = rev.revID;
    if (rev.deleted)
        dst[@"_deleted"] = $true;

    // Get more optional stuff to put in the properties:
    //OPT: This probably ends up making redundant SQL queries if multiple options are enabled.
    if (options & kCBLIncludeLocalSeq)
        dst[@"_local_seq"] = @(rev.sequence);

    if (options & kCBLIncludeRevs)
        dst[@"_revisions"] = [self getRevisionHistoryDict: rev startingFromAnyOf: nil];
    
    if (options & kCBLIncludeRevsInfo) {
        dst[@"_revs_info"] = [[self getRevisionHistory: rev] my_map: ^id(CBL_Revision* rev) {
            NSString* status = @"available";
            if (rev.deleted)
                status = @"deleted";
            else if (rev.missing)
                status = @"missing";
            return $dict({@"rev", [rev revID]}, {@"status", status});
        }];
    }
    
    if (options & kCBLIncludeConflicts) {
        CBL_RevisionList* revs = [self getAllRevisionsOfDocumentID: rev.docID onlyCurrent: YES];
        if (revs.count > 1) {
            dst[@"_conflicts"] = [revs.allRevisions my_map: ^(id aRev) {
                return ($equal(aRev, rev) || [(CBL_Revision*)aRev deleted]) ? nil : [aRev revID];
            }];
        }
    }
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
- (NSArray*) getRevisionHistory: (CBL_Revision*)rev {
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
                              joinQuotedStrings(revIDs));
    _fmdb.shouldCacheStatements = NO;
    NSString* ancestor = [_fmdb stringForQuery: sql, @(docNumericID), rev.revID];
    _fmdb.shouldCacheStatements = YES;
    return ancestor;
}
    

static NSString* joinQuotedStrings(NSArray* strings) {
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
                             "ORDER BY revs.doc_id, revid DESC",
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
            
            CBL_MutableRevision* rev = [[CBL_MutableRevision alloc] initWithDocID: [r stringForColumnIndex: 2]
                                                          revID: [r stringForColumnIndex: 3]
                                                        deleted: [r boolForColumnIndex: 4]];
            rev.sequence = [r longLongIntForColumnIndex: 0];
            if (includeDocs) {
                [self expandStoredJSON: [r dataNoCopyForColumnIndex: 5]
                          intoRevision: rev
                               options: options->contentOptions];
            }
            if (!filter || filter(rev))
                [changes addRev: rev];
        }
    }
    [r close];
    
    if (options->sortBySequence) {
        [changes sortBySequence];
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
                             joinQuotedStrings(revs.allRevIDs),
                             joinQuotedStrings(revs.allDocIDs));
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


- (CBLQueryIteratorBlock) getAllDocs: (CBLQueryOptions*)options
                              status: (CBLStatus*)outStatus
{
    if (!options)
        options = [CBLQueryOptions new];
    BOOL includeDocs = (options->includeDocs || options.filter);
    BOOL includeDeletedDocs = (options->allDocsMode == kCBLIncludeDeleted);
    
    // Generate the SELECT statement, based on the options:
    BOOL cacheQuery = YES;
    NSMutableString* sql = [@"SELECT revs.doc_id, docid, revid, sequence" mutableCopy];
    if (includeDocs)
        [sql appendString: @", json, no_attachments"];
    if (includeDeletedDocs)
        [sql appendString: @", deleted"];
    [sql appendString: @" FROM revs, docs WHERE"];
    if (options.keys) {
        if (options.keys.count == 0)
            return ^CBLQueryRow*() { return nil; };
        [sql appendFormat: @" revs.doc_id IN (SELECT doc_id FROM docs WHERE docid IN (%@)) AND", joinQuotedStrings(options.keys)];
        cacheQuery = NO; // we've put hardcoded key strings in the query
    }
    [sql appendString: @" docs.doc_id = revs.doc_id AND current=1"];
    if (!includeDeletedDocs)
        [sql appendString: @" AND deleted=0"];

    NSMutableArray* args = $marray();
    id minKey = options.startKey, maxKey = options.endKey;
    BOOL inclusiveMin = YES, inclusiveMax = options->inclusiveEnd;
    if (options->descending) {
        minKey = maxKey;
        maxKey = options.startKey;
        inclusiveMin = inclusiveMax;
        inclusiveMax = YES;
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
    if (!r)
        return nil;
    
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

            NSDictionary* docContents = nil;
            if (includeDocs) {
                // Fill in the document contents:
                NSData* json = [r dataNoCopyForColumnIndex: 4];
                CBLContentOptions contentOptions = options->content;
                if ([r boolForColumnIndex: 5])
                    contentOptions |= kCBLNoAttachments; // doc has no attachments
                docContents = [self documentPropertiesFromJSON: json
                                                         docID: docID
                                                         revID: revID
                                                       deleted: deleted
                                                      sequence: sequence
                                                       options: contentOptions];
                Assert(docContents);
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
                                                    docProperties: docContents
                                                          storage: nil];
            if (options.keys)
                docs[docID] = row;
            else if (!options.filter || options.filter(row))
                [rows addObject: row];
        }
    }
    [r close];

    // If given doc IDs, sort the output into that order, and add entries for missing docs:
    if (options.keys) {
        for (NSString* docID in options.keys) {
            CBLQueryRow* change = docs[docID];
            if (!change) {
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
                change = [[CBLQueryRow alloc] initWithDocID: (value ?docID :nil)
                                                   sequence: 0
                                                        key: docID
                                                      value: value
                                              docProperties: nil
                                                    storage: nil];
            }
            if (!options.filter || options.filter(change))
                [rows addObject: change];
        }
    }

    //OPT: Return objects from enum as they're found, without collecting them in an array first
    NSEnumerator* rowEnum = rows.objectEnumerator;
    return ^CBLQueryRow*() {
        return rowEnum.nextObject;
    };
}


- (NSDictionary*) documentPropertiesFromJSON: (NSData*)json
                                       docID: (NSString*)docID
                                       revID: (NSString*)revID
                                     deleted: (BOOL)deleted
                                    sequence: (SequenceNumber)sequence
                                     options: (CBLContentOptions)options
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
    [self extraPropertiesForRevision: rev options: options into: docProperties];
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
{
    __block NSData* json = nil;
    if (properties) {
        json = [CBL_Revision asCanonicalJSON: properties error: NULL];
        if (!json) {
            *outStatus = kCBLStatusBadJSON;
            return nil;
        }
    } else {
        json = [NSData dataWithBytes: "{}" length: 2];
    }

    __block CBL_MutableRevision* newRev = nil;
    __block CBL_Revision* winningRev = nil;
    __block BOOL inConflict = NO;

    *outStatus = [self inTransaction: ^CBLStatus {
        // Remember, this block may be called multiple times if I have to retry the transaction.
        newRev = nil;
        winningRev = nil;
        inConflict = NO;
        NSString* prevRevID = inPrevRevID;
        NSString* docID = inDocID;

        //// PART I: In which are performed lookups and validations prior to the insert...

        // Get the doc's numeric ID (doc_id) and its current winning revision:
        SInt64 docNumericID = docID ? [self getDocNumericID: docID] : 0;
        BOOL oldWinnerWasDeletion = NO;
        BOOL wasConflicted = NO;
        NSString* oldWinningRevID = nil;
        if (docNumericID > 0) {
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
            if (docNumericID <= 0)
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
                if (docNumericID <= 0) {
                    // Doc ID doesn't exist at all; create it:
                    docNumericID = [self insertDocumentID: docID];
                    if (docNumericID <= 0)
                        return self.lastDbError;
                } else {
                    // Doc ID exists; check whether current winning revision is deleted:
                    if (oldWinnerWasDeletion) {
                        prevRevID = oldWinningRevID;
                        parentSequence = [self getSequenceOfDocument: docNumericID
                                                            revision: prevRevID
                                                         onlyCurrent: NO];
                    } else if (oldWinningRevID) {
                        // The current winning revision is not deleted, so this is a conflict
                        return kCBLStatusConflict;
                    }
                }
            } else {
                // Inserting first revision, with no docID given (POST): generate a unique docID:
                docID = CBLCreateUUID();
                docNumericID = [self insertDocumentID: docID];
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
            CBLStatus status = validationBlock(newRev, prevRev, prevRevID);
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
                                                  JSON: json];
        if (!sequence) {
            // The insert failed. If it was due to a constraint violation, that means a revision
            // already exists with identical contents and the same parent rev. We can ignore this
            // insert call, then.
            if (_fmdb.lastErrorCode != SQLITE_CONSTRAINT)
                return self.lastDbError;
            LogTo(CBLDatabase, @"Duplicate rev insertion: %@ / %@", docID, newRevID);
            newRev.body = nil;
            // don't return yet; update the parent's current just to be sure (see #509)
        }
        
        // Make replaced rev non-current:
        if (parentSequence > 0) {
            if (![_fmdb executeUpdate: @"UPDATE revs SET current=0 WHERE sequence=?",
                                       @(parentSequence)])
                return self.lastDbError;
        }

        if (!sequence)
            return kCBLStatusOK;  // duplicate rev; see above

        // Figure out what the new winning rev ID is:
            winningRev = [self winnerWithDocID: docNumericID
                                 oldWinner: oldWinningRevID oldDeleted: oldWinnerWasDeletion
                                        newRev: newRev];

        // Success!
        return deleting ? kCBLStatusOK : kCBLStatusCreated;
    }];
    
    if (CBLStatusIsError(*outStatus)) 
        return nil;
    
    //// EPILOGUE: A change notification is sent...
    [_delegate databaseStorageChanged: [[CBLDatabaseChange alloc] initWithAddedRevision: newRev
                                                                        winningRevision: winningRev
                                                                             inConflict: inConflict
                                                                                 source: nil]];
    return newRev;
}


- (CBLStatus) forceInsert: (CBL_Revision*)inRev
          revisionHistory: (NSArray*)history
          validationBlock: (CBL_StorageValidationBlock)validationBlock
                   source: (NSURL*)source
{
    CBL_MutableRevision* rev = inRev.mutableCopy;
    rev.sequence = 0;
    NSString* docID = rev.docID;
    
    __block CBL_Revision* winningRev = nil;
    __block BOOL inConflict = NO;
    CBLStatus status = [self inTransaction: ^CBLStatus {
        // First look up the document's row-id and all locally-known revisions of it:
        CBL_RevisionList* localRevs = nil;
        NSString* oldWinningRevID = nil;
        BOOL oldWinnerWasDeletion = NO;
        SInt64 docNumericID = [self getDocNumericID: docID];
        if (docNumericID > 0) {
            localRevs = [self getAllRevisionsOfDocumentID: docID
                                                numericID: docNumericID
                                              onlyCurrent: NO];
            if (!localRevs)
                return self.lastDbError;

            // Look up which rev is the winner, before this insertion
            CBLStatus tempStatus;
            oldWinningRevID = [self winningRevIDOfDocNumericID: docNumericID
                                                     isDeleted: &oldWinnerWasDeletion
                                                    isConflict: &inConflict
                                                        status: &tempStatus];
            if (CBLStatusIsError(tempStatus))
                return tempStatus;
        } else {
            docNumericID = [self insertDocumentID: docID];
            if (docNumericID <= 0)
                return self.lastDbError;
        }

        // Validate against the latest common ancestor:
        if (validationBlock) {
            CBL_Revision* oldRev = nil;
            for (NSUInteger i = 1; i<history.count; ++i) {
                oldRev = [localRevs revWithDocID: docID revID: history[i]];
                if (oldRev)
                    break;
            }
            NSString* parentRevID = (history.count > 1) ? history[1] : nil;
            CBLStatus status = validationBlock(rev, oldRev, parentRevID);
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
            CBL_Revision* localRev = [localRevs revWithDocID: docID revID: revID];
            if (localRev) {
                // This revision is known locally. Remember its sequence as the parent of the next one:
                sequence = localRev.sequence;
                Assert(sequence > 0);
                localParentSequence = sequence;

            } else {
                // This revision isn't known, so add it:
                CBL_MutableRevision* newRev;
                NSData* json = nil;
                BOOL current = NO;
                if (i==0) {
                    // Hey, this is the leaf revision we're inserting:
                    newRev = rev;
                    json = [self encodeDocumentJSON: rev];
                    if (!json)
                        return kCBLStatusBadJSON;
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
                                           JSON: json];
                if (sequence <= 0)
                    return self.lastDbError;
            }
        }

        if (localParentSequence == sequence)
            return kCBLStatusOK;      // No-op: No new revisions were inserted.

        // Mark the latest local rev as no longer current:
        if (localParentSequence > 0) {
            if (![_fmdb executeUpdate: @"UPDATE revs SET current=0 WHERE sequence=? AND current!=0",
                  @(localParentSequence)])
                return self.lastDbError;
            if (_fmdb.changes == 0)
                inConflict = YES; // local parent wasn't a leaf, ergo we just created a branch
        }

            // Figure out what the new winning rev ID is:
            winningRev = [self winnerWithDocID: docNumericID
                                     oldWinner: oldWinningRevID
                                    oldDeleted: oldWinnerWasDeletion
                                        newRev: rev];

        return kCBLStatusCreated;
    }];

    if (!CBLStatusIsError(status)) {
        [_delegate databaseStorageChanged: [[CBLDatabaseChange alloc] initWithAddedRevision: rev
                                                                        winningRevision: winningRev
                                                                             inConflict: inConflict
                                                                                 source: source]];
    }
    return status;
}


/** Adds a new document ID to the 'docs' table. */
- (SInt64) insertDocumentID: (NSString*)docID {
    if (![_fmdb executeUpdate: @"INSERT INTO docs (docid) VALUES (?)", docID])
        return -1;
    SInt64 row = _fmdb.lastInsertRowId;
    Assert(![_docIDs objectForKey: docID]);
    [_docIDs setObject: @(row) forKey: docID];
    return row;
}


// Raw row insertion. Returns new sequence, or 0 on error
- (SequenceNumber) insertRevision: (CBL_Revision*)rev
                     docNumericID: (SInt64)docNumericID
                   parentSequence: (SequenceNumber)parentSequence
                          current: (BOOL)current
                   hasAttachments: (BOOL)hasAttachments
                             JSON: (NSData*)json
{
    if (![_fmdb executeUpdate: @"INSERT INTO revs (doc_id, revid, parent, current, deleted, "
          "no_attachments, json) "
          "VALUES (?, ?, ?, ?, ?, ?, ?)",
          @(docNumericID),
          rev.revID,
          (parentSequence ? @(parentSequence) : nil ),
          @(current),
          @(rev.deleted),
          @(!hasAttachments),
          json])
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


- (CBL_Revision*) winnerWithDocID: (SInt64)docNumericID
                        oldWinner: (NSString*)oldWinningRevID
                       oldDeleted: (BOOL)oldWinnerWasDeletion
                           newRev: (CBL_Revision*)newRev
{
    if (!oldWinningRevID)
        return newRev;
    NSString* newRevID = newRev.revID;
    if (!newRev.deleted) {
        if (oldWinnerWasDeletion || CBLCompareRevIDs(newRevID, oldWinningRevID) > 0)
            return newRev;   // this is now the winning live revision
    } else if (oldWinnerWasDeletion) {
        if (CBLCompareRevIDs(newRevID, oldWinningRevID) > 0)
            return newRev;  // doc still deleted, but this beats previous deletion rev
    } else {
        // Doc was alive. How does this deletion affect the winning rev ID?
        BOOL deleted;
        CBLStatus status;
        NSString* winningRevID = [self winningRevIDOfDocNumericID: docNumericID
                                                        isDeleted: &deleted
                                                       isConflict: NULL
                                                           status: &status];
        AssertEq(status, kCBLStatusOK);
        if (!$equal(winningRevID, oldWinningRevID)) {
            if ($equal(winningRevID, newRev.revID))
                return newRev;
            else {
                CBL_Revision* winningRev = [[CBL_Revision alloc] initWithDocID: newRev.docID
                                                                         revID: winningRevID
                                                                       deleted: NO];
                return winningRev;
            }
        }
    }
    return nil; // no change
}


#pragma mark - HOUSEKEEPING:


- (BOOL) compact: (NSError**)outError {
    // Can't delete any rows because that would lose revision tree history.
    // But we can remove the JSON of non-current revisions, which is most of the space.
    Log(@"CBLDatabase: Deleting JSON of old revisions...");
    if (![_fmdb executeUpdate: @"UPDATE revs SET json=null, no_attachments=1 WHERE current=0"])
        return ReturnNSErrorFromCBLStatus(self.lastDbError, outError);
    Log(@"    ... deleted %d revisions", _fmdb.changes);

    Log(@"Flushing SQLite WAL...");
    if (![_fmdb executeUpdate: @"PRAGMA wal_checkpoint(RESTART)"])
        return ReturnNSErrorFromCBLStatus(self.lastDbError, outError);

    Log(@"Vacuuming SQLite database...");
    if (![_fmdb executeUpdate: @"VACUUM"])
        return ReturnNSErrorFromCBLStatus(self.lastDbError, outError);

//    Log(@"Closing and re-opening database...");
//    [_fmdb close];
//    if (![self openFMDB: nil])
//        return ReturnNSErrorFromCBLStatus(self.lastDbError, outError);

    Log(@"...Finished database compaction.");
    return YES;
}


- (NSSet*) findAllAttachmentKeys: (NSError**)outError {
    CBL_FMResultSet* r = [_fmdb executeQuery: @"SELECT json FROM revs WHERE no_attachments != 1"];
    if (!r) {
        ReturnNSErrorFromCBLStatus(self.lastDbStatus, outError);
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

                LogTo(CBLDatabase, @"Purging doc '%@' revs (%@); asked for (%@)",
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
