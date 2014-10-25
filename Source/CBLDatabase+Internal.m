//
//  CBLDatabase+Internal.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/19/10.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLDatabase+Internal.h"
#import "CBLDatabase+Attachments.h"
#import "CBLInternal.h"
#import "CBLModel_Internal.h"
#import "CBL_Revision.h"
#import "CBLDatabaseChange.h"
#import "CBLCollateJSON.h"
#import "CBL_BlobStore.h"
#import "CBL_Puller.h"
#import "CBL_Pusher.h"
#import "CBL_Shared.h"
#import "CBLMisc.h"
#import "CBLDatabase.h"
#import "CouchbaseLitePrivate.h"

#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "MYBlockUtils.h"
#import "MYReadWriteLock.h"
#import "ExceptionUtils.h"


NSString* const CBL_DatabaseChangesNotification = @"CBLDatabaseChanges";
NSString* const CBL_DatabaseWillCloseNotification = @"CBL_DatabaseWillClose";
NSString* const CBL_DatabaseWillBeDeletedNotification = @"CBL_DatabaseWillBeDeleted";

NSString* const CBL_PrivateRunloopMode = @"CouchbaseLitePrivate";
NSArray* CBL_RunloopModes;

#define kDocIDCacheSize 1000

#define kSQLiteBusyTimeout 5.0 // seconds

#define kTransactionMaxRetries 10
#define kTransactionRetryDelay 0.050


@implementation CBLDatabase (Internal)


+ (void) initialize {
    if (self == [CBLDatabase class]) {
        CBL_RunloopModes = @[NSRunLoopCommonModes, CBL_PrivateRunloopMode];
#if 0
        Log(@"SQLite version %s", sqlite3_libversion());
        int i = 0;
        const char* opt;
        while (NULL != (opt = sqlite3_compileoption_get(i++)))
               Log(@"SQLite has option '%s'", opt);
#endif
    }
}


- (CBL_FMDatabase*) fmdb {
    return _fmdb;
}

- (CBL_BlobStore*) attachmentStore {
    return _attachments;
}

- (NSDate*) startTime {
    return _startTime;
}


- (CBL_Shared*)shared {
#if DEBUG
    if (_manager)
        return _manager.shared;
    // For unit testing purposes we create databases without managers (see createEmptyDBAtPath(),
    // below.) Allow the .shared property to work in this state by creating a per-db instance:
    if (!_debug_shared)
        _debug_shared = [[CBL_Shared alloc] init];
    return _debug_shared;
#else
    return _manager.shared;
#endif
}


+ (BOOL) deleteDatabaseFilesAtPath: (NSString*)dbPath error: (NSError**)outError {
    // Make sure to delete the SQLite side-files as well as the main db file!
    return CBLRemoveFileIfExists(dbPath, outError)
        && CBLRemoveFileIfExists([dbPath stringByAppendingString: @"-wal"], outError)
        && CBLRemoveFileIfExists([dbPath stringByAppendingString: @"-shm"], outError)
        && CBLRemoveFileIfExists([self attachmentStorePath: dbPath], outError);
}


#if DEBUG
+ (instancetype) createEmptyDBAtPath: (NSString*)path {
    if (![self deleteDatabaseFilesAtPath: path error: NULL])
        return nil;
    CBLDatabase *db = [[self alloc] initWithPath: path name: nil manager: nil readOnly: NO];
    if (!CBLRemoveFileIfExists(db.attachmentStorePath, NULL))
        return nil;
    if (![db open: nil])
        return nil;
    return db;
}
#endif


- (instancetype) _initWithPath: (NSString*)path
                          name: (NSString*)name
                       manager: (CBLManager*)manager
                      readOnly: (BOOL)readOnly
{
    if (self = [super init]) {
        Assert([path hasPrefix: @"/"], @"Path must be absolute");
        _path = [path copy];
        _manager = manager;
        _name = name ?: [path.lastPathComponent.stringByDeletingPathExtension copy];
        _readOnly = readOnly;
        _fmdb = [[CBL_FMDatabase alloc] initWithPath: _path];
        _fmdb.dispatchQueue = manager.dispatchQueue;
        _fmdb.databaseLock = [self.shared lockForDatabaseNamed: _name];
#if DEBUG
        _fmdb.logsErrors = YES;
#else
        _fmdb.logsErrors = WillLogTo(CBLDatabase);
#endif
        _fmdb.traceExecution = WillLogTo(CBLDatabaseVerbose);

        _docIDs = [[NSCache alloc] init];
        _docIDs.countLimit = kDocIDCacheSize;
        _dispatchQueue = manager.dispatchQueue;
        if (!_dispatchQueue)
            _thread = [NSThread currentThread];
        _startTime = [NSDate date];
    }
    return self;
}

- (NSString*) description {
    return $sprintf(@"%@[<%p>%@]", [self class], self, self.name);
}

- (BOOL) exists {
    return [[NSFileManager defaultManager] fileExistsAtPath: _path];
}


- (NSError*) fmdbError {
    NSDictionary* info = $dict({NSLocalizedDescriptionKey, _fmdb.lastErrorMessage});
    return [NSError errorWithDomain: @"SQLite" code: _fmdb.lastErrorCode userInfo: info];
}

- (BOOL) initialize: (NSString*)statements error: (NSError**)outError {
    for (NSString* quotedStatement in [statements componentsSeparatedByString: @";"]) {
        NSString* statement = [quotedStatement stringByReplacingOccurrencesOfString: @"|"
                                                                         withString: @";"];
        if (statement.length && ![_fmdb executeUpdate: statement]) {
            if (outError) *outError = self.fmdbError;
            Warn(@"CBLDatabase: Could not initialize schema of %@ -- May be an old/incompatible format. "
                  "SQLite error: %@", _path, _fmdb.lastErrorMessage);
            [_fmdb close];
            return NO;
        }
    }
    return YES;
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
#if TARGET_OS_IPHONE
    switch (_manager.fileProtection) {
        case NSDataWritingFileProtectionNone:
            flags |= SQLITE_OPEN_FILEPROTECTION_NONE;
            break;
        case NSDataWritingFileProtectionComplete:
            flags |= SQLITE_OPEN_FILEPROTECTION_COMPLETE;
            break;
        case NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication:
            flags |= SQLITE_OPEN_FILEPROTECTION_COMPLETEUNTILFIRSTUSERAUTHENTICATION;
            break;
        default:
            flags |= SQLITE_OPEN_FILEPROTECTION_COMPLETEUNLESSOPEN;
            break;
    }
#endif
    if (_readOnly)
        flags |= SQLITE_OPEN_READONLY;
    else
        flags |= SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE;
    LogTo(CBLDatabase, @"Open %@ (flags=%X)", _path, flags);
    if (![_fmdb openWithFlags: flags]) {
        if (outError) *outError = self.fmdbError;
        return NO;
    }

    // Register CouchDB-compatible JSON collation functions:
    sqlite3_create_collation(_fmdb.sqliteHandle, "JSON", SQLITE_UTF8,
                             kCBLCollateJSON_Unicode, CBLCollateJSON);
    sqlite3_create_collation(_fmdb.sqliteHandle, "JSON_RAW", SQLITE_UTF8,
                             kCBLCollateJSON_Raw, CBLCollateJSON);
    sqlite3_create_collation(_fmdb.sqliteHandle, "JSON_ASCII", SQLITE_UTF8,
                             kCBLCollateJSON_ASCII, CBLCollateJSON);
    sqlite3_create_collation(_fmdb.sqliteHandle, "REVID", SQLITE_UTF8,
                             NULL, CBLCollateRevIDs);

    [CBLView registerFunctions: self];
    
    // Stuff we need to initialize every time the database opens:
    if (![self initialize: @"PRAGMA foreign_keys = ON;" error: outError])
        return NO;
    return YES;
}


- (BOOL) open: (NSError**)outError {
    if (_isOpen)
        return YES;
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

    if (dbVersion < 1) {
        // First-time initialization:
        // (Note: Declaring revs.sequence as AUTOINCREMENT means the values will always be
        // monotonically increasing, never reused. See <http://www.sqlite.org/autoinc.html>)
        NSString *schema = @"\
            CREATE TABLE docs ( \
                doc_id INTEGER PRIMARY KEY, \
                docid TEXT UNIQUE NOT NULL); \
            CREATE INDEX docs_docid ON docs(docid); \
            CREATE TABLE revs ( \
                sequence INTEGER PRIMARY KEY AUTOINCREMENT, \
                doc_id INTEGER NOT NULL REFERENCES docs(doc_id) ON DELETE CASCADE, \
                revid TEXT NOT NULL COLLATE REVID, \
                parent INTEGER REFERENCES revs(sequence) ON DELETE SET NULL, \
                current BOOLEAN, \
                deleted BOOLEAN DEFAULT 0, \
                json BLOB, \
                UNIQUE (doc_id, revid)); \
            CREATE INDEX revs_current ON revs(doc_id, current); \
            CREATE INDEX revs_parent ON revs(parent); \
            CREATE TABLE localdocs ( \
                docid TEXT UNIQUE NOT NULL, \
                revid TEXT NOT NULL COLLATE REVID, \
                json BLOB); \
            CREATE INDEX localdocs_by_docid ON localdocs(docid); \
            CREATE TABLE views ( \
                view_id INTEGER PRIMARY KEY, \
                name TEXT UNIQUE NOT NULL,\
                version TEXT, \
                lastsequence INTEGER DEFAULT 0); \
            CREATE INDEX views_by_name ON views(name); \
            CREATE TABLE maps ( \
                view_id INTEGER NOT NULL REFERENCES views(view_id) ON DELETE CASCADE, \
                sequence INTEGER NOT NULL REFERENCES revs(sequence) ON DELETE CASCADE, \
                key TEXT NOT NULL COLLATE JSON, \
                value TEXT); \
            CREATE INDEX maps_keys on maps(view_id, key COLLATE JSON); \
            CREATE TABLE attachments ( \
                sequence INTEGER NOT NULL REFERENCES revs(sequence) ON DELETE CASCADE, \
                filename TEXT NOT NULL, \
                key BLOB NOT NULL, \
                type TEXT, \
                length INTEGER NOT NULL, \
                revpos INTEGER DEFAULT 0); \
            CREATE INDEX attachments_by_sequence on attachments(sequence, filename); \
            CREATE TABLE replicators ( \
                remote TEXT NOT NULL, \
                push BOOLEAN, \
                last_sequence TEXT, \
                UNIQUE (remote, push)); \
            PRAGMA user_version = 3";             // at the end, update user_version
        if (![self initialize: schema error: outError])
            return NO;
        dbVersion = 3;
    }
    
    if (dbVersion < 2) {
        // Version 2: added attachments.revpos
        NSString* sql = @"ALTER TABLE attachments ADD COLUMN revpos INTEGER DEFAULT 0; \
                          PRAGMA user_version = 2";
        if (![self initialize: sql error: outError])
            return NO;
        dbVersion = 2;
    }
    
    if (dbVersion < 3) {
        // Version 3: added localdocs table
        NSString* sql = @"CREATE TABLE IF NOT EXISTS localdocs ( \
                            docid TEXT UNIQUE NOT NULL, \
                            revid TEXT NOT NULL, \
                            json BLOB); \
                            CREATE INDEX IF NOT EXISTS localdocs_by_docid ON localdocs(docid); \
                          PRAGMA user_version = 3";
        if (![self initialize: sql error: outError])
            return NO;
        dbVersion = 3;
    }
    
    if (dbVersion < 4) {
        // Version 4: added 'info' table
        NSString* sql = $sprintf(@"CREATE TABLE info ( \
                                     key TEXT PRIMARY KEY, \
                                     value TEXT); \
                                   INSERT INTO INFO (key, value) VALUES ('privateUUID', '%@');\
                                   INSERT INTO INFO (key, value) VALUES ('publicUUID',  '%@');\
                                   PRAGMA user_version = 4",
                                 CBLCreateUUID(), CBLCreateUUID());
        if (![self initialize: sql error: outError])
            return NO;
        dbVersion = 4;
    }

    if (dbVersion < 5) {
        // Version 5: added encoding for attachments
        NSString* sql = @"ALTER TABLE attachments ADD COLUMN encoding INTEGER DEFAULT 0; \
                          ALTER TABLE attachments ADD COLUMN encoded_length INTEGER; \
                          PRAGMA user_version = 5";
        if (![self initialize: sql error: outError])
            return NO;
        dbVersion = 5;
    }

    if (dbVersion < 6) {
        // Version 6: enable Write-Ahead Log (WAL) <http://sqlite.org/wal.html>
        NSString* sql = @"PRAGMA journal_mode=WAL; \
        PRAGMA user_version = 6";
        if (![self initialize: sql error: outError])
            return NO;
        dbVersion = 6;
    }

    if (dbVersion < 7) {
        // Version 7: enable full-text search
        // Note: Apple's SQLite build does not support the icu or unicode61 tokenizers :(
        // OPT: Could add compress/decompress functions to make stored content smaller
        NSString* sql = @"CREATE VIRTUAL TABLE fulltext USING fts4(content, tokenize=unicodesn); \
                          ALTER TABLE maps ADD COLUMN fulltext_id INTEGER; \
                          CREATE INDEX IF NOT EXISTS maps_by_fulltext ON maps(fulltext_id); \
                          CREATE TRIGGER del_fulltext DELETE ON maps WHEN old.fulltext_id not null \
                                BEGIN DELETE FROM fulltext WHERE rowid=old.fulltext_id| END;\
                          PRAGMA user_version = 7";
        if (![self initialize: sql error: outError])
            return NO;
        dbVersion = 7;
    }

    // (Version 8 was an older version of the geo index)

    if (dbVersion < 9) {
        // Version 9: Add geo-query index
        NSString* sql = @"CREATE VIRTUAL TABLE bboxes USING rtree(rowid, x0, x1, y0, y1); \
                        ALTER TABLE maps ADD COLUMN bbox_id INTEGER; \
                        ALTER TABLE maps ADD COLUMN geokey BLOB; \
                        CREATE TRIGGER del_bbox DELETE ON maps WHEN old.bbox_id not null \
                        BEGIN DELETE FROM bboxes WHERE rowid=old.bbox_id| END;\
                        PRAGMA user_version = 9";
        if (![self initialize: sql error: outError])
            return NO;
        dbVersion = 9;
    }

    if (dbVersion < 10) {
        // Version 10: Add rev flag for whether it has an attachment
        NSString* sql = @"ALTER TABLE revs ADD COLUMN no_attachments BOOLEAN; \
        PRAGMA user_version = 10";
        if (![self initialize: sql error: outError])
            return NO;
        dbVersion = 10;
    }

    // (Version 11 used to create the index revs_cur_deleted, which is obsoleted in version 16)

    if (dbVersion < 12) {
        // Version 12: Because of a bug fix that changes JSON collation, invalidate view indexes
        NSString* sql = @"DELETE FROM maps; UPDATE views SET lastsequence=0; \
                          PRAGMA user_version = 12";
        if (![self initialize: sql error: outError])
            return NO;
        dbVersion = 12;
    }
    
    if (dbVersion < 13) {
        // Version 13: Add rows to track number of rows in the views
        NSString* sql = @"ALTER TABLE views ADD COLUMN total_docs INTEGER DEFAULT -1; \
                          PRAGMA user_version = 13";
        if (![self initialize: sql error: outError])
            return NO;
        dbVersion = 13;
    }
    
    if (dbVersion < 14) {
        // Version 14: Add index for getting a document with doc and rev id
        NSString* sql = @"CREATE INDEX IF NOT EXISTS revs_by_docid_revid ON revs(doc_id, revid desc, current, deleted); \
        PRAGMA user_version = 14";
        if (![self initialize: sql error: outError])
            return NO;
        dbVersion = 14;
    }

    if (dbVersion < 15) {
        // Version 15: Add sequence index on maps and attachments for revs(sequence) on DELETE CASCADE
        NSString* sql = @"CREATE INDEX maps_sequence ON maps(sequence); \
                          CREATE INDEX attachments_sequence ON attachments(sequence); \
                          PRAGMA user_version = 15";
        if (![self initialize: sql error: outError])
            return NO;
        dbVersion = 15;
    }

    if (dbVersion < 16) {
        // Version 16: Fix the very suboptimal index revs_cur_deleted.
        // The new revs_current is an optimal index for finding the winning revision of a doc.
        NSString* sql = @"DROP INDEX IF EXISTS revs_current; \
                          DROP INDEX IF EXISTS revs_cur_deleted; \
                          CREATE INDEX revs_current ON revs(doc_id, current desc, deleted, revid desc);\
                          PRAGMA user_version = 16";
        if (![self initialize: sql error: outError])
            return NO;
        dbVersion = 16;
    }

    if (isNew && ![self initialize: @"END TRANSACTION" error: outError])
        return NO;

#if DEBUG
    _fmdb.crashOnErrors = YES;
#endif

    // Open attachment store:
    NSString* attachmentsPath = self.attachmentStorePath;
    _attachments = [[CBL_BlobStore alloc] initWithPath: attachmentsPath error: outError];
    if (!_attachments) {
        Warn(@"%@: Couldn't open attachment store at %@", self, attachmentsPath);
        [_fmdb close];
        return NO;
    }
#if TARGET_OS_IPHONE
    _attachments.fileProtection = _manager.fileProtection;
#endif

    _isOpen = YES;

    _fmdb.shouldCacheStatements = YES;      // Saves the time to recompile SQL statements

    // Listen for _any_ CBLDatabase changing, so I can detect changes made to my database
    // file by other instances (running on other threads presumably.)
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(dbChanged:)
                                                 name: CBL_DatabaseChangesNotification
                                               object: nil];
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(dbChanged:)
                                                 name: CBL_DatabaseWillBeDeletedNotification
                                               object: nil];
    return YES;
}

- (void) _close {
    if (_isOpen) {
        LogTo(CBLDatabase, @"Closing <%p> %@", self, _path);

        // Don't want any models trying to save themselves back to the db. (Generally there shouldn't
        // be any, because the public -close: method saves changes first.)
        for (CBLModel* model in _unsavedModelsMutable.copy)
            model.needsSave = false;
        _unsavedModelsMutable = nil;

        [[NSNotificationCenter defaultCenter] postNotificationName: CBL_DatabaseWillCloseNotification
                                                            object: self];
        [[NSNotificationCenter defaultCenter] removeObserver: self
                                                        name: CBL_DatabaseChangesNotification
                                                      object: nil];
        [[NSNotificationCenter defaultCenter] removeObserver: self
                                                        name: CBL_DatabaseWillBeDeletedNotification
                                                      object: nil];
        for (CBLView* view in _views.allValues)
            [view databaseClosing];
        
        _views = nil;
        for (CBL_Replicator* repl in _activeReplicators.copy)
            [repl databaseClosing];
        
        _activeReplicators = nil;
        
        [_fmdb close]; // this returns BOOL, but its implementation never returns NO
        _isOpen = NO;

        [[NSNotificationCenter defaultCenter] removeObserver: self];
        [self _clearDocumentCache];
        _modelFactory = nil;
    }
    [_manager _forgetDatabase: self];
}


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
        default:
            LogTo(CBLDatabase, @"Other _fmdb.lastErrorCode %d", _fmdb.lastErrorCode);
            return kCBLStatusDBError;
    }
}

- (CBLStatus) lastDbError {
    CBLStatus status = self.lastDbStatus;
    return (status == kCBLStatusOK) ? kCBLStatusDBError : status;
}


- (UInt64) totalDataSize {
    NSDictionary* attrs = [[NSFileManager defaultManager] attributesOfItemAtPath: _path error: NULL];
    if (!attrs)
        return 0;
    return attrs.fileSize + _attachments.totalDataSize;
}


- (NSString*) infoForKey: (NSString*)key {
    return [_fmdb stringForQuery: @"SELECT value FROM info WHERE key=?", key];
}

- (CBLStatus) setInfo: (id)info forKey: (NSString*)key {
    if ([_fmdb executeUpdate: @"UPDATE info SET value=? WHERE key=?", info, key])
        return kCBLStatusOK;
    else
        return self.lastDbError;
}


- (NSString*) privateUUID {
    return [self infoForKey: @"privateUUID"];
}

- (NSString*) publicUUID {
    return [self infoForKey: @"publicUUID"];
}

#pragma mark - TRANSACTIONS & NOTIFICATIONS:


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

    if (!commit)
        [_changesToNotify removeAllObjects];
    [self postChangeNotifications];
    return ok;
}

- (CBLStatus) _inTransaction: (CBLStatus(^)())block {
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


/** Posts a local NSNotification of a new revision of a document. */
- (void) notifyChange: (CBLDatabaseChange*)change {
    LogTo(CBLDatabase, @"Added: %@ (seq=%lld)", change.addedRevision, change.addedRevision.sequence);
    if (!_changesToNotify)
        _changesToNotify = [[NSMutableArray alloc] init];
    [_changesToNotify addObject: change];
    [self postChangeNotifications];
}

/** Posts a local NSNotification of multiple new revisions. */
- (void) notifyChanges: (NSArray*)changes {
    if (!_changesToNotify)
        _changesToNotify = [[NSMutableArray alloc] init];
    [_changesToNotify addObjectsFromArray: changes];
    [self postChangeNotifications];
}


- (void) postChangeNotifications {
    // This is a 'while' instead of an 'if' because when we finish posting notifications, there
    // might be new ones that have arrived as a result of notification handlers making document
    // changes of their own (the replicator manager will do this.) So we need to check again.
    while (_fmdb.transactionLevel == 0 && _isOpen && !_postingChangeNotifications
            && _changesToNotify.count > 0)
    {
        _postingChangeNotifications = true; // Disallow re-entrant calls
        NSArray* changes = _changesToNotify;
        _changesToNotify = nil;

        if (WillLogTo(CBLDatabase)) {
            NSMutableString* seqs = [NSMutableString string];
            for (CBLDatabaseChange* change in changes) {
                if (seqs.length > 0)
                    [seqs appendString: @", "];
                SequenceNumber seq = change.addedRevision.sequence;
                if (change.echoed)
                    [seqs appendFormat: @"(%lld)", seq];
                else
                    [seqs appendFormat: @"%lld", seq];
            }
            LogTo(CBLDatabase, @"%@: Posting change notifications: seq %@", self, seqs);
        }
        
        [self postPublicChangeNotification: changes];
        [[NSNotificationCenter defaultCenter] postNotificationName: CBL_DatabaseChangesNotification
                                                            object: self
                                                          userInfo: $dict({@"changes", changes})];

        _postingChangeNotifications = false;
    }
}


- (void) dbChanged: (NSNotification*)n {
    CBLDatabase* senderDB = n.object;
    // Was this posted by a _different_ CBLDatabase instance on the same database as me?
    if (senderDB != self && [senderDB.path isEqualToString: _path]) {
        // Careful: I am being called on senderDB's thread, not my own!
        if ([[n name] isEqualToString: CBL_DatabaseChangesNotification]) {
            NSMutableArray* echoedChanges = $marray();
            for (CBLDatabaseChange* change in (n.userInfo)[@"changes"]) {
                if (!change.echoed)
                    [echoedChanges addObject: change.copy]; // copied change is marked as echoed
            }
            if (echoedChanges.count > 0) {
                LogTo(CBLDatabase, @"%@: Notified of %u changes by %@",
                      self, (unsigned)echoedChanges.count, senderDB);
                [self doAsync: ^{
                    [self notifyChanges: echoedChanges];
                }];
            }
        } else if ([[n name] isEqualToString: CBL_DatabaseWillBeDeletedNotification]) {
            [self doAsync: ^{
                LogTo(CBLDatabase, @"%@: Notified of deletion; closing", self);
                [self _close];
            }];
        }
    }
}


#pragma mark - GETTING DOCUMENTS:


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


- (SequenceNumber) lastSequenceNumber {
    // See http://www.sqlite.org/fileformat2.html#seqtab
    return [_fmdb longLongForQuery: @"SELECT seq FROM sqlite_sequence WHERE name='revs'"];
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

    // Get attachment metadata, and optionally the contents:
    if (!(options & kCBLNoAttachments)) {
        NSDictionary* attachments = [self getAttachmentDictForSequence: rev.sequence
                                                               options: options];
        if (attachments)
            dst[@"_attachments"] = attachments;
    }
    
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


- (CBL_Revision*) getDocumentWithID: (NSString*)docID
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


- (CBL_Revision*) getDocumentWithID: (NSString*)docID
                         revisionID: (NSString*)revID
{
    CBLStatus status;
    return [self getDocumentWithID: docID revisionID: revID options: 0 status: &status];
}


// Note: This method assumes the docID is correct and doesn't bother to look it up on its own.
- (CBL_Revision*) getDocumentWithID: (NSString*)docID
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


- (BOOL) existsDocumentWithID: (NSString*)docID revisionID: (NSString*)revID {
    CBLStatus status;
    return [self getDocumentWithID: docID revisionID: revID options: kCBLNoBody status: &status] != nil;
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


- (CBL_Revision*) revisionByLoadingBody: (CBL_Revision*)rev
                                options: (CBLContentOptions)options
                                 status: (CBLStatus*)outStatus
{
    if (rev.body && options==0 && rev.sequence)
        return rev;  // no-op
    CBL_MutableRevision* nuRev = rev.mutableCopy;
    CBLStatus status = [self loadRevisionBody: nuRev options: options];
    if (outStatus)
        *outStatus = status;
    if (CBLStatusIsError(status))
        nuRev = nil;
    return nuRev;
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


- (NSString*) _indexedTextWithID: (UInt64)fullTextID {
    if (fullTextID == 0)
        return nil;
    return [_fmdb stringForQuery: @"SELECT content FROM fulltext WHERE rowid=?", @(fullTextID)];
}


#pragma mark - HISTORY:


- (CBL_Revision*) getParentRevision: (CBL_Revision*)rev {
    // First get the parent's sequence:
    SequenceNumber seq = rev.sequence;
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


- (NSArray*) getPossibleAncestorRevisionIDs: (CBL_Revision*)rev
                                      limit: (unsigned)limit
                              hasAttachment: (BOOL*)outHasAttachment
{
    if (outHasAttachment)
        *outHasAttachment = NO;
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
        if (outHasAttachment && revIDs.count == 0)
            *outHasAttachment = [self sequenceHasAttachments: [r longLongIntForColumnIndex: 1]];
        [revIDs addObject: [r stringForColumnIndex: 0]];
    }
    [r close];
    return revIDs;
}


- (NSString*) findCommonAncestorOf: (CBL_Revision*)rev withRevIDs: (NSArray*)revIDs {
    if (revIDs.count == 0)
        return nil;
    SInt64 docNumericID = [self getDocNumericID: rev.docID];
    if (docNumericID <= 0)
        return nil;
    NSString* sql = $sprintf(@"SELECT revid FROM revs "
                              "WHERE doc_id=? and revid in (%@) and revid <= ? "
                              "ORDER BY revid DESC LIMIT 1", 
                              [CBLDatabase joinQuotedStrings: revIDs]);
    _fmdb.shouldCacheStatements = NO;
    NSString* ancestor = [_fmdb stringForQuery: sql, @(docNumericID), rev.revID];
    _fmdb.shouldCacheStatements = YES;
    return ancestor;
}
    

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


static NSDictionary* makeRevisionHistoryDict(NSArray* history) {
    if (!history)
        return nil;
    
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


- (NSDictionary*) getRevisionHistoryDict: (CBL_Revision*)rev
                       startingFromAnyOf: (NSArray*)ancestorRevIDs
{
    NSArray* history = [self getRevisionHistory: rev]; // (this is in reverse order, newest..oldest
    if (ancestorRevIDs.count > 0) {
        NSUInteger n = history.count;
        for (NSUInteger i = 0; i < n; ++i) {
            if ([ancestorRevIDs containsObject: [history[i] revID]]) {
                history = [history subarrayWithRange: NSMakeRange(0, i+1)];
                break;
            }
        }
    }
    return makeRevisionHistoryDict(history);
}


- (NSString*) getParentRevID: (CBL_Revision*)rev {
    Assert(rev.sequence > 0);
    return [_fmdb stringForQuery: @"SELECT parent.revid FROM revs, revs as parent"
                                   " WHERE revs.sequence=? and parent.sequence=revs.parent",
                                  @(rev.sequence)];
}


/** Returns the rev ID of the 'winning' revision of this document, and whether it's deleted. */
- (NSString*) winningRevIDOfDocNumericID: (SInt64)docNumericID
                               isDeleted: (BOOL*)outIsDeleted
                              isConflict: (BOOL*)outIsConflict // optional
{
    Assert(docNumericID > 0);
    CBL_FMResultSet* r = [_fmdb executeQuery: @"SELECT revid, deleted FROM revs"
                                           " WHERE doc_id=? and current=1"
                                           " ORDER BY deleted asc, revid desc LIMIT 2",
                                          @(docNumericID)];
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
    return revID;
}


const CBLChangesOptions kDefaultCBLChangesOptions = {UINT_MAX, 0, NO, NO, YES};


- (CBL_RevisionList*) changesSinceSequence: (SequenceNumber)lastSequence
                                 options: (const CBLChangesOptions*)options
                                  filter: (CBLFilterBlock)filter
                                  params: (NSDictionary*)filterParams
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
            if ([self runFilter: filter params: filterParams onRevision: rev])
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


- (BOOL) runFilter: (CBLFilterBlock)filter
            params: (NSDictionary*)filterParams
        onRevision: (CBL_Revision*)rev
{
    if (!filter)
        return YES;
    CBLSavedRevision* publicRev = [[CBLSavedRevision alloc] initWithDatabase: self revision: rev];
    @try {
        return filter(publicRev, filterParams);
    } @catch (NSException* x) {
        MYReportException(x, @"filter block");
        return NO;
    }
}


#pragma mark - FILTERS:


- (id) getDesignDocFunction: (NSString*)fnName
                        key: (NSString*)key
                   language: (NSString**)outLanguage
{
    NSArray* path = [fnName componentsSeparatedByString: @"/"];
    if (path.count != 2)
        return nil;
    CBL_Revision* rev = [self getDocumentWithID: [@"_design/" stringByAppendingString: path[0]]
                                    revisionID: nil];
    if (!rev)
        return nil;
    *outLanguage = rev[@"language"] ?: @"javascript";
    NSDictionary* container = $castIf(NSDictionary, rev[key]);
    return container[path[1]];
}


- (CBLFilterBlock) compileFilterNamed: (NSString*)filterName status: (CBLStatus*)outStatus {
    CBLFilterBlock filter = [self filterNamed: filterName];
    if (filter)
        return filter;
    id<CBLFilterCompiler> compiler = [CBLDatabase filterCompiler];
    if (!compiler) {
        *outStatus = kCBLStatusNotFound;
        return nil;
    }
    NSString* language;
    NSString* source = $castIf(NSString, [self getDesignDocFunction: filterName
                                                                key: @"filters"
                                                           language: &language]);
    if (!source) {
        *outStatus = kCBLStatusNotFound;
        return nil;
    }

    filter = [compiler compileFilterFunction: source language: language];
    if (!filter) {
        Warn(@"Filter %@ failed to compile", filterName);
        *outStatus = kCBLStatusCallbackError;
        return nil;
    }
    [self setFilterNamed: filterName asBlock: filter];
    return filter;
}


#pragma mark - VIEWS:


- (NSArray*) allViews {
    CBL_FMResultSet* r = [_fmdb executeQuery: @"SELECT name FROM views"];
    if (!r)
        return nil;
    NSMutableArray* views = $marray();
    while ([r next])
        [views addObject: [self viewNamed: [r stringForColumnIndex: 0]]];
    [r close];
    return views;
}


- (CBLStatus) deleteViewNamed: (NSString*)name {
    if (![_fmdb executeUpdate: @"DELETE FROM views WHERE name=?", name])
        return self.lastDbError;
    [_views removeObjectForKey: name];
    return _fmdb.changes ? kCBLStatusOK : kCBLStatusNotFound;
}


- (CBLView*) makeAnonymousView {
    for (int n = 1; true; ++n) {
        NSString* name = $sprintf(@"$anon$%d", n);
        if ([_fmdb intForQuery: @"SELECT count(*) FROM views WHERE name=?", name] <= 0)
            return [self viewNamed: name];
    }
}

- (CBLView*) compileViewNamed: (NSString*)tdViewName status: (CBLStatus*)outStatus {
    CBLView* view = [self existingViewNamed: tdViewName];
    if (view && view.mapBlock)
        return view;
    
    // No CouchbaseLite view is defined, or it hasn't had a map block assigned;
    // see if there's a CouchDB view definition we can compile:
    NSString* language;
    NSDictionary* viewProps = $castIf(NSDictionary, [self getDesignDocFunction: tdViewName
                                                                           key: @"views"
                                                                      language: &language]);
    if (!viewProps) {
        *outStatus = kCBLStatusNotFound;
        return nil;
    } else if (![CBLView compiler]) {
        *outStatus = kCBLStatusNotImplemented;
        return nil;
    }
    view = [self viewNamed: tdViewName];
    if (![view compileFromProperties: viewProps language: language]) {
        *outStatus = kCBLStatusCallbackError;
        return nil;
    }
    return view;
}


//FIX: This has a lot of code in common with -[CBLView queryWithOptions:status:]. Unify the two!
- (NSArray*) getAllDocs: (CBLQueryOptions*)options {
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
            return @[];
        [sql appendFormat: @" revs.doc_id IN (SELECT doc_id FROM docs WHERE docid IN (%@)) AND", [CBLDatabase joinQuotedStrings: options.keys]];
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
                                                    docProperties: docContents];
            if (options.keys)
                docs[docID] = row;
            else if (CBLRowPassesFilter(self, row, options))
                [rows addObject: row];
        }
    }
    [r close];

    // If given doc IDs, sort the output into that order, and add entries for missing docs:
    if (options.keys) {
        for (NSString* docID in options.keys) {
            CBLQueryRow* change = docs[docID];
            if (!change) {
                NSDictionary* value = nil;
                SInt64 docNumericID = [self getDocNumericID: docID];
                if (docNumericID > 0) {
                    BOOL deleted;
                    NSString* revID = [self winningRevIDOfDocNumericID: docNumericID
                                                             isDeleted: &deleted
                                                            isConflict: NULL];
                    if (revID)
                        value = $dict({@"rev", revID}, {@"deleted", $true});
                }
                change = [[CBLQueryRow alloc] initWithDocID: (value ?docID :nil)
                                                   sequence: 0
                                                        key: docID
                                                      value: value
                                              docProperties: nil];
            }
            if (CBLRowPassesFilter(self, change, options))
                [rows addObject: change];
        }
    }

    return rows;
}

- (void) postNotification: (NSNotification*)notification
{
    if (_dispatchQueue) {
        // NSNotificationQueue is runloop-based, doesn't work on dispatch queues. (#364)
        [self doAsync:^{
            [[NSNotificationCenter defaultCenter] postNotification: notification];
        }];
    } else {
        NSNotificationQueue* queue = [NSNotificationQueue defaultQueue];
        [queue enqueueNotification: notification
                      postingStyle: NSPostASAP
                      coalesceMask: NSNotificationNoCoalescing
                          forModes: @[NSRunLoopCommonModes]];
    }

}


@end



#pragma mark - TESTS:
#if DEBUG

static CBL_Revision* mkrev(NSString* revID) {
    return [[CBL_Revision alloc] initWithDocID: @"docid" revID: revID deleted: NO];
}


TestCase(CBL_Database_MakeRevisionHistoryDict) {
    NSArray* revs = @[mkrev(@"4-jkl"), mkrev(@"3-ghi"), mkrev(@"2-def")];
    CAssertEqual(makeRevisionHistoryDict(revs), $dict({@"ids", @[@"jkl", @"ghi", @"def"]},
                                                      {@"start", @4}));
    
    revs = @[mkrev(@"4-jkl"), mkrev(@"2-def")];
    CAssertEqual(makeRevisionHistoryDict(revs), $dict({@"ids", @[@"4-jkl", @"2-def"]}));
    
    revs = @[mkrev(@"12345"), mkrev(@"6789")];
    CAssertEqual(makeRevisionHistoryDict(revs), $dict({@"ids", @[@"12345", @"6789"]}));
}

#endif
