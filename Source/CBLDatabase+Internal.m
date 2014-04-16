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

#import <CBForest/CBForest.h>

#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "MYBlockUtils.h"
#import "ExceptionUtils.h"


NSString* const CBL_DatabaseChangesNotification = @"CBLDatabaseChanges";
NSString* const CBL_DatabaseWillCloseNotification = @"CBL_DatabaseWillClose";
NSString* const CBL_DatabaseWillBeDeletedNotification = @"CBL_DatabaseWillBeDeleted";

#define kDocIDCacheSize 1000

#define kSQLiteBusyTimeout 5.0 // seconds

#define kTransactionMaxRetries 10
#define kTransactionRetryDelay 0.050


@implementation CBLDatabase (Internal)


#if 0
+ (void) initialize {
    if (self == [CBLDatabase class]) {
        int i = 0;
        while (NULL != (const char *opt = sqlite3_compileoption_get(i++)))
               Log(@"SQLite has option '%s'", opt);
    }
}
#endif


- (CBL_FMDatabase*) fmdb {
    return _fmdb;
}

- (CBForestDB*) forestDB {
    return _forest;
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


+ (BOOL) deleteDatabaseFilesAtPath: (NSString*)dbDir error: (NSError**)outError {
    return CBLRemoveFileIfExists(dbDir, outError);
}


#if DEBUG
+ (instancetype) createEmptyDBAtPath: (NSString*)dir {
    if (![self deleteDatabaseFilesAtPath: dir error: NULL])
        return nil;
    CBLDatabase *db = [[self alloc] initWithDir: dir name: nil manager: nil readOnly: NO];
    if (![db open: nil])
        return nil;
    return db;
}
#endif


- (instancetype) _initWithDir: (NSString*)dirPath
                         name: (NSString*)name
                      manager: (CBLManager*)manager
                     readOnly: (BOOL)readOnly
{
    if (self = [super init]) {
        Assert([dirPath hasPrefix: @"/"], @"Path must be absolute");
        _dir = [dirPath copy];
        _manager = manager;
        _name = name ?: [dirPath.lastPathComponent.stringByDeletingPathExtension copy];
        _readOnly = readOnly;

        NSString* fmdbPath = [dirPath stringByAppendingPathComponent: @"db.sqlite"];
        _fmdb = [[CBL_FMDatabase alloc] initWithPath: fmdbPath];
        _fmdb.dispatchQueue = manager.dispatchQueue;
        _fmdb.busyRetryTimeout = kSQLiteBusyTimeout;
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

        if (0) {
            // Appease the static analyzer by using these category ivars in this source file:
            _pendingAttachmentsByDigest = nil;
        }
    }
    return self;
}

- (NSString*) description {
    return $sprintf(@"%@[<%p>%@]", [self class], self, self.name);
}

- (BOOL) exists {
    return [[NSFileManager defaultManager] fileExistsAtPath: _dir];
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
                  "SQLite error: %@", _dir, _fmdb.lastErrorMessage);
            [_fmdb close];
            return NO;
        }
    }
    return YES;
}


- (BOOL) openForest: (NSError**)outError {
    NSString* forestPath = [_dir stringByAppendingPathComponent: @"db.forest"];
    CBForestFileOptions options = _readOnly ? kCBForestDBReadOnly : kCBForestDBCreate;
    _forest = [[CBForestDB alloc] initWithFile: forestPath
                                       options: options
                                         error: outError];
    _forest.documentClass = [CBForestVersions class];
    return (_forest != nil);
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

    int flags =  SQLITE_OPEN_FILEPROTECTION_COMPLETEUNLESSOPEN;
    if (_readOnly)
        flags |= SQLITE_OPEN_READONLY;
    else
        flags |= SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE;
    LogTo(CBLDatabase, @"Open %@ (flags=%X)", _dir, flags);
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
    
    // Stuff we need to initialize every time the database opens:
    if (![self initialize: @"PRAGMA foreign_keys = ON;" error: outError])
        return NO;
    return YES;
}


- (BOOL) open: (NSError**)outError {
    if (_isOpen)
        return YES;
    LogTo(CBLDatabase, @"Opening %@", self);

    if (![[NSFileManager defaultManager] createDirectoryAtPath: _dir
                                   withIntermediateDirectories: YES
                                                    attributes: nil
                                                         error: outError])
        return NO;

    if (![self openForest: outError])
        return NO;

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

    if (dbVersion < 10) {
        // Version 10: Add rev flag for whether it has an attachment
        NSString* sql = @"ALTER TABLE revs ADD COLUMN no_attachments BOOLEAN; \
        PRAGMA user_version = 10";
        if (![self initialize: sql error: outError])
            return NO;
        dbVersion = 10;
    }

    if (dbVersion < 11) {
        // Version 10: Add another index
        NSString* sql = @"CREATE INDEX revs_cur_deleted ON revs(current,deleted); \
                          PRAGMA user_version = 11";
        if (![self initialize: sql error: outError])
            return NO;
        dbVersion = 11;
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

- (BOOL) closeInternal {
    if (!_isOpen)
        return NO;
    
    LogTo(CBLDatabase, @"Closing <%p> %@", self, _dir);
    Assert(_transactionLevel == 0, @"Can't close database while %u transactions active",
            _transactionLevel);
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

    [_forest commit: NULL];
    [_forest close];

    if (_fmdb && ![_fmdb close])
        return NO;
    _isOpen = NO;
    _transactionLevel = 0;
    return YES;
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
    UInt64 size = 0;
    NSDictionary* attrs = [[NSFileManager defaultManager] attributesOfItemAtPath: _forest.filename
                                                                           error: NULL];
    if (!attrs)
        return 0;
    size = attrs.fileSize;

    NSString* fmdbPath = [_dir stringByAppendingPathComponent: @"db.sqlite"];
    attrs = [[NSFileManager defaultManager] attributesOfItemAtPath: fmdbPath error: NULL];
    if (!attrs)
        return 0;
    size += attrs.fileSize;

    return size + _attachments.totalDataSize;
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
    if (![_fmdb executeUpdate: $sprintf(@"SAVEPOINT tdb%d", _transactionLevel + 1)]) {
        Warn(@"Failed to create savepoint transaction!");
        return NO;
    }
    ++_transactionLevel;
    LogTo(CBLDatabase, @"Begin transaction (level %d)...", _transactionLevel);
    return YES;
}

- (BOOL) endTransaction: (BOOL)commit {
    Assert(_transactionLevel > 0);
    BOOL ok = YES;
    if (commit) {
        LogTo(CBLDatabase, @"Commit transaction (level %d)", _transactionLevel);
    } else {
        LogTo(CBLDatabase, @"CANCEL transaction (level %d)", _transactionLevel);
        if (![_fmdb executeUpdate: $sprintf(@"ROLLBACK TO tdb%d", _transactionLevel)]) {
            Warn(@"Failed to rollback transaction!");
            ok = NO;
        }
        [_changesToNotify removeAllObjects];
    }
    if (![_fmdb executeUpdate: $sprintf(@"RELEASE tdb%d", _transactionLevel)]) {
        Warn(@"Failed to release transaction!");
        ok = NO;
    }

    --_transactionLevel;

    if (_transactionLevel == 0)
        [_forest commit: NULL];

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
            if (_transactionLevel > 1)
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
    while (_transactionLevel == 0 && _isOpen && !_postingChangeNotifications
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
    if (senderDB != self && [senderDB.dir isEqualToString: _dir]) {
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
                [self closeForDeletion];
            }];
        }
    }
}


#pragma mark - GETTING DOCUMENTS:


- (NSUInteger) documentCount {
    [_forest commit: NULL]; //FIX: This is a workaround for a ForestDB bug
    return _forest.info.documentCount;
}


- (SequenceNumber) lastSequenceNumber {
    return _forest.info.lastSequence;
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


- (CBForestVersions*) _forestDocWithID: (NSString*)docID
                                status: (CBLStatus*)outStatus
{
    NSError* error;
    CBForestVersions* doc = (CBForestVersions*)[_forest documentWithID: docID
                                                               options: 0 error: &error];
    if (outStatus != NULL) {
        if (doc)
            *outStatus = kCBLStatusOK;
        else if (!error || error.code == kCBForestErrorNotFound)
            *outStatus = kCBLStatusNotFound;
        else
            *outStatus = kCBLStatusDBError;
    }
    return doc;
}


- (CBL_Revision*) getDocumentWithID: (NSString*)docID
                         revisionID: (NSString*)revID
                            options: (CBLContentOptions)options
                             status: (CBLStatus*)outStatus
{
    CBForestVersions* doc = [self _forestDocWithID: docID status: outStatus];
    if (!doc)
        return nil;
    CBForestRevisionFlags revFlags = [doc flagsOfRevision: revID];
    if (!(revFlags & kCBForestRevisionHasBody)) {
        *outStatus = kCBLStatusNotFound;
        return nil;
    }
    if (revID == nil) {
        if (revFlags & kCBForestRevisionDeleted) {
            *outStatus = kCBLStatusDeleted;
            return nil;
        }
        revID = doc.currentRevisionID;
    }

    BOOL deleted = (revFlags & kCBForestRevisionDeleted) != 0;
    CBL_MutableRevision* result = [[CBL_MutableRevision alloc] initWithDocID: docID
                                                                       revID: revID
                                                                     deleted: deleted];
    result.sequence = doc.sequence;

    if (options != kCBLNoBody) {
        NSData* json = nil;
        if (!(options & kCBLNoBody)) {
            json = [doc dataOfRevision: revID];
            if (!json) {
                *outStatus = kCBLStatusNotFound;
                return nil;
            }
        }
        [self expandStoredJSON: json intoRevision: result options: options];
    }
    *outStatus = kCBLStatusOK;
    return result;
}


- (CBL_Revision*) getDocumentWithID: (NSString*)docID
                       revisionID: (NSString*)revID
{
    CBLStatus status;
    return [self getDocumentWithID: docID revisionID: revID options: 0 status: &status];
}


- (BOOL) existsDocumentWithID: (NSString*)docID revisionID: (NSString*)revID {
    CBLStatus status;
    return [self getDocumentWithID: docID revisionID: revID options: kCBLNoBody status: &status] != nil;
}


- (CBLStatus) loadRevisionBody: (CBL_MutableRevision*)rev
                       options: (CBLContentOptions)options
{
    if (rev.body && options==0)
        return kCBLStatusOK;  // no-op
    Assert(rev.docID && rev.revID);

    CBLStatus status;
    CBForestVersions* doc = [self _forestDocWithID: rev.docID status: &status];
    if (!doc)
        return status;
    if ([doc flagsOfRevision: rev.revID] == 0)
        return kCBLStatusNotFound;
    [self expandStoredJSON: [doc dataOfRevision: rev.revID] intoRevision: rev options: options];
    return kCBLStatusOK;
}


- (CBL_Revision*) revisionByLoadingBody: (CBL_Revision*)rev
                                options: (CBLContentOptions)options
                                 status: (CBLStatus*)outStatus
{
    if (rev.body && options==0)
        return rev;  // no-op
    CBL_MutableRevision* nuRev = rev.mutableCopy;
    CBLStatus status = [self loadRevisionBody: nuRev options: options];
    if (outStatus)
        *outStatus = status;
    if (CBLStatusIsError(status))
        nuRev = nil;
    return nuRev;
}


- (NSString*) _indexedTextWithID: (UInt64)fullTextID {
    if (fullTextID == 0)
        return nil;
    return [_fmdb stringForQuery: @"SELECT content FROM fulltext WHERE rowid=?", @(fullTextID)];
}


#pragma mark - HISTORY:


- (CBL_Revision*) getParentRevision: (CBL_Revision*)rev {
    Assert(rev.docID && rev.revID);
    CBForestVersions* doc = [self _forestDocWithID: rev.docID status: NULL];
    if (!doc)
        return nil;
    NSString* parentID = [doc parentIDOfRevision: rev.revID];
    if (!parentID)
        return nil;
    BOOL parentDeleted = ([doc flagsOfRevision: parentID] & kCBForestRevisionDeleted) != 0;
    return [[CBL_Revision alloc] initWithDocID: rev.docID
                                         revID: parentID
                                       deleted: parentDeleted];
}


- (CBL_RevisionList*) getAllRevisionsOfDocumentID: (NSString*)docID
                                      onlyCurrent: (BOOL)onlyCurrent
{
    CBForestVersions* doc = [self _forestDocWithID: docID status: NULL];
    if (!doc)
        return nil;
    NSArray* revIDs = onlyCurrent ? doc.currentRevisionIDs : doc.allRevisionIDs;
    CBL_RevisionList* revs = [[CBL_RevisionList alloc] init];
        for (NSString* revID in revIDs) {
        [revs addRev: [[CBL_Revision alloc] initWithDocID: docID
                                                    revID: revID
                                                  deleted: [doc isRevisionDeleted: revID]]];
    }
    return revs;
}


- (NSArray*) getPossibleAncestorRevisionIDs: (CBL_Revision*)rev
                                      limit: (unsigned)limit
                            onlyAttachments: (BOOL)onlyAttachments // unimplemented
{
    unsigned generation = rev.generation;
    if (generation <= 1)
        return nil;

    CBForestVersions* doc = [self _forestDocWithID: rev.docID status: NULL];
    if (!doc)
        return nil;
    NSMutableArray* revIDs = $marray();
    for (NSString* possibleRevID in doc.allRevisionIDs) {
        if ([CBL_Revision generationFromRevID: possibleRevID] < generation) {
            [revIDs addObject: possibleRevID];
            if (limit && revIDs.count >= limit)
                break;
        }
    }
    return revIDs;
}


- (NSString*) findCommonAncestorOf: (CBL_Revision*)rev withRevIDs: (NSArray*)revIDs {
    unsigned generation = rev.generation;
    if (generation <= 1)
        return nil;

    CBForestVersions* doc = [self _forestDocWithID: rev.docID status: NULL];
    if (!doc)
        return nil;

    revIDs = [revIDs sortedArrayUsingComparator: ^NSComparisonResult(NSString* id1, NSString* id2) {
        return CBLCompareRevIDs(id2, id1); // descending order of generation
    }];
    for (NSString* possibleRevID in revIDs) {
        if ([doc flagsOfRevision: possibleRevID] != 0) {
            if ([CBL_Revision generationFromRevID: possibleRevID] < generation) {
                return possibleRevID;
            }
        }
    }
    return nil;
}
    

- (NSArray*) getRevisionHistory: (CBL_Revision*)rev {
    NSString* docID = rev.docID;
    NSString* revID = rev.revID;
    Assert(revID && docID);

    CBForestVersions* doc = [self _forestDocWithID: rev.docID status: NULL];
    if (!doc)
        return @[];

    NSMutableArray* history = $marray();
    for (NSString* ancestorID in [doc historyOfRevision: revID]) {
        CBForestRevisionFlags flags = [doc flagsOfRevision: ancestorID];
        BOOL deleted = (flags & kCBForestRevisionDeleted) != 0;
        CBL_MutableRevision* rev = [[CBL_MutableRevision alloc] initWithDocID: docID
                                                                        revID: ancestorID
                                                                      deleted: deleted];
        rev.missing = (flags & kCBForestRevisionHasBody) == 0;
        [history addObject: rev];
    }
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


const CBLChangesOptions kDefaultCBLChangesOptions = {UINT_MAX, 0, NO, NO, YES};


- (CBL_RevisionList*) changesSinceSequence: (SequenceNumber)lastSequence
                                   options: (const CBLChangesOptions*)options
                                    filter: (CBLFilterBlock)filter
                                    params: (NSDictionary*)filterParams
{
    // http://wiki.apache.org/couchdb/HTTP_database_API#Changes
    if (!options) options = &kDefaultCBLChangesOptions;
    CBForestEnumerationOptions forestOpts = {
        .limit = options->limit,
        .inclusiveEnd = YES,
        .includeDeleted = YES,
    };
    BOOL includeDocs = options->includeDocs || options->includeConflicts || (filter != NULL);
    if (!includeDocs)
        forestOpts.contentOptions |= kCBForestDBMetaOnly;

    CBL_RevisionList* changes = [[CBL_RevisionList alloc] init];
    [_forest enumerateDocsFromSequence: lastSequence+1
                            toSequence: kCBForestMaxSequence
                               options: &forestOpts error: NULL
                             withBlock: ^(CBForestDocument *baseDoc, BOOL *stop)
    {
        CBForestVersions* doc = (CBForestVersions*)baseDoc;
        NSArray* revisions;
        if (options->includeConflicts) {
            revisions = doc.currentRevisionIDs;
            revisions = [revisions sortedArrayUsingComparator:^NSComparisonResult(id r1, id r2) {
                return CBLCompareRevIDs(r1, r2);
            }];
        } else {
            revisions = @[doc.revID];
        }
        for (NSString* revID in revisions) {
            BOOL deleted;
            if (options->includeConflicts)
                deleted = [doc isRevisionDeleted: revID];
            else
                deleted = (doc.flags & kCBForestDocDeleted) != 0;
            CBL_MutableRevision* rev = [[CBL_MutableRevision alloc] initWithDocID: doc.docID
                                                                            revID: revID
                                                                          deleted: deleted];
            rev.sequence = doc.sequence; //FIX ???
            if (includeDocs) {
                [self expandStoredJSON: [doc dataOfRevision: revID]
                          intoRevision: rev
                               options: options->contentOptions];
            }
            if ([self runFilter: filter params: filterParams onRevision: rev])
                [changes addRev: rev];
        }
    }];
    return changes;
}


#pragma mark - FILTERS:


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
// Note: Public view methods like -viewNamed: are in CBLDatabase.m.


- (NSArray*) allViews {
    NSArray* filenames = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: _dir
                                                                             error: NULL];
    return [filenames my_map: ^id(NSString* filename) {
        NSString* viewName = [CBLView fileNameToViewName: filename];
        if (!viewName)
            return nil;
        return [self existingViewNamed: viewName];
    }];
}


- (void) forgetViewNamed: (NSString*)name {
    [_views removeObjectForKey: name];
}


- (CBLView*) makeAnonymousView {
    for (;;) {
        NSString* name = $sprintf(@"$anon$%lx", random());
        if (![self existingViewNamed: name])
            return [self viewNamed: name];
    }
}

- (CBLView*) compileViewNamed: (NSString*)viewName status: (CBLStatus*)outStatus {
    CBLView* view = [self existingViewNamed: viewName];
    if (view && view.mapBlock)
        return view;
    
    // No CouchbaseLite view is defined, or it hasn't had a map block assigned;
    // see if there's a CouchDB view definition we can compile:
    NSString* language;
    NSDictionary* viewProps = $castIf(NSDictionary, [self getDesignDocFunction: viewName
                                                                           key: @"views"
                                                                      language: &language]);
    if (!viewProps) {
        *outStatus = kCBLStatusNotFound;
        return nil;
    } else if (![CBLView compiler]) {
        *outStatus = kCBLStatusNotImplemented;
        return nil;
    }
    view = [self viewNamed: viewName];
    if (![view compileFromProperties: viewProps language: language]) {
        *outStatus = kCBLStatusCallbackError;
        return nil;
    }
    return view;
}


//FIX: This has a lot of code in common with -[CBLView queryWithOptions:status:]. Unify the two!
- (NSArray*) getAllDocs: (const CBLQueryOptions*)options {
    if (!options)
        options = &kDefaultCBLQueryOptions;
    CBForestEnumerationOptions forestOpts = {
        .skip = options->skip,
        .limit = options->limit,
        .inclusiveEnd = options->inclusiveEnd,
        .onlyConflicts = (options->allDocsMode == kCBLOnlyConflicts),
    };
    id minKey = options->startKey, maxKey = options->endKey;
    __block BOOL inclusiveMin = YES;
    if (options->descending) {
        minKey = maxKey;
        maxKey = options->startKey;
        inclusiveMin = options->inclusiveEnd;
        forestOpts.inclusiveEnd = YES;
    }

    // Here's the block that adds a document to the output:
    NSMutableArray* rows = $marray();
    CBForestDocIterator addDocBlock = ^(CBForestDocument *baseDoc, BOOL *stop)
    {
        CBForestVersions* doc = (CBForestVersions*)baseDoc;
        if (!inclusiveMin) {
            inclusiveMin = YES;
            if (minKey && [doc.docID isEqual: minKey])
                return;
        }

        NSString *docID = doc.docID, *revID = doc.revID;
        BOOL deleted = (doc.flags & kCBForestDocDeleted) != 0;
        SequenceNumber sequence = doc.sequence;

        NSDictionary* docContents = nil;
        if (options->includeDocs) {
            // Fill in the document contents:
            NSData* json = [doc dataOfRevision: nil];
            docContents = [self documentPropertiesFromJSON: json
                                                     docID: docID
                                                     revID: revID
                                                   deleted: deleted
                                                  sequence: sequence
                                                   options: options->content];
            Assert(docContents);
        }

        NSArray* conflicts = nil;
        if (options->allDocsMode >= kCBLShowConflicts) {
            conflicts = doc.currentRevisionIDs;
            if (conflicts.count == 1)
                conflicts = nil;
        }

        NSDictionary* value = $dict({@"rev", revID},
                                    {@"deleted", (deleted ?$true : nil)},
                                    {@"_conflicts", conflicts});  // (not found in CouchDB)
        CBLQueryRow* row = [[CBLQueryRow alloc] initWithDocID: docID
                                                     sequence: sequence
                                                          key: docID
                                                        value: value
                                                docProperties: docContents];
        if (options->descending)
            [rows insertObject: row atIndex: 0];
        else
            [rows addObject: row];
    };

    if (options->keys) {
        // If given keys, look up each doc and add it:
        for (NSString* docID in options->keys) {
            @autoreleasepool {
                CBForestVersions* doc = (CBForestVersions*)[_forest documentWithID: docID
                                                                           options: 0
                                                                             error: NULL];
                if (doc) {
                    addDocBlock(doc, NULL);
                } else {
                    // Add a placeholder for for a nonexistent doc:
                    [rows addObject: [[CBLQueryRow alloc] initWithDocID: nil
                                                               sequence: 0
                                                                    key: docID
                                                                  value: nil
                                                          docProperties: nil]];
                }
            }
        }
    } else {
        // If not given keys, enumerate all docs from minKey to maxKey:
        [_forest enumerateDocsFromID: minKey toID: maxKey options: &forestOpts error: NULL
                           withBlock: addDocBlock];
    }
    return rows;
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
