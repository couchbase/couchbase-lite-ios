//
// CBLDatabase.m
// CouchbaseLite
//
// Created by Jens Alfke on 6/19/10.
// Copyright (c) 2011 Couchbase, Inc. All rights reserved.
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
#import "CBL_DatabaseChange.h"
#import "CBLCollateJSON.h"
#import "CBL_BlobStore.h"
#import "CBL_Puller.h"
#import "CBL_Pusher.h"
#import "CBLMisc.h"
#import "CBLDatabase.h"
#import "CouchbaseLitePrivate.h"

#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "MYBlockUtils.h"


NSString* const CBL_DatabaseChangesNotification = @"CBL_DatabaseChanges";
NSString* const CBL_DatabaseWillCloseNotification = @"CBL_DatabaseWillClose";
NSString* const CBL_DatabaseWillBeDeletedNotification = @"CBL_DatabaseWillBeDeleted";


@implementation CBLDatabase (Internal)


- (FMDatabase*) fmdb {
    return _fmdb;
}

- (CBL_BlobStore*) attachmentStore {
    return _attachments;
}


+ (instancetype) createEmptyDBAtPath: (NSString*)path {
    if (!CBLRemoveFileIfExists(path, NULL))
        return nil;
    CBLDatabase *db = [[self alloc] initWithPath: path name: nil manager: nil readOnly: NO];
    if (!CBLRemoveFileIfExists(db.attachmentStorePath, NULL))
        return nil;
    if (![db open: nil])
        return nil;
    return db;
}


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
        _fmdb = [[FMDatabase alloc] initWithPath: _path];
        _fmdb.busyRetryTimeout = 10;
#if DEBUG
        _fmdb.logsErrors = YES;
#else
        _fmdb.logsErrors = WillLogTo(CBLDatabase);
#endif
        _fmdb.traceExecution = WillLogTo(CBL_DatabaseVerbose);
        _thread = [NSThread currentThread];

        if (0) {
            // Appease the static analyzer by using these category ivars in this source file:
            _validations = nil;
            _pendingAttachmentsByDigest = nil;
        }
    }
    return self;
}

- (NSString*) description {
    return $sprintf(@"%@[%@]", [self class], _path);
}

- (BOOL) exists {
    return [[NSFileManager defaultManager] fileExistsAtPath: _path];
}


- (NSError*) fmdbError {
    NSDictionary* info = $dict({NSLocalizedDescriptionKey, _fmdb.lastErrorMessage});
    return [NSError errorWithDomain: @"SQLite" code: _fmdb.lastErrorCode userInfo: info];
}

- (BOOL) initialize: (NSString*)statements error: (NSError**)outError {
    for (NSString* statement in [statements componentsSeparatedByString: @";"]) {
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


- (BOOL) openFMDB: (NSError**)outError {
    int flags = SQLITE_OPEN_FILEPROTECTION_COMPLETEUNLESSOPEN;
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

    // Stuff we need to initialize every time the database opens:
    if (![self initialize: @"PRAGMA foreign_keys = ON;" error: outError])
        return NO;
    return YES;
}


- (BOOL) open: (NSError**)outError {
    if (_open)
        return YES;
    if (![self openFMDB: outError])
        return NO;
    
    // Check the user_version number we last stored in the database:
    int dbVersion = [_fmdb intForQuery: @"PRAGMA user_version"];
    
    // Incompatible version changes increment the hundreds' place:
    if (dbVersion >= 100) {
        Warn(@"CBLDatabase: Database version (%d) is newer than I know how to work with", dbVersion);
        [_fmdb close];
        if (outError) *outError = [NSError errorWithDomain: @"CouchbaseLite" code: 1 userInfo: nil]; //FIX: Real code
        return NO;
    }
    
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
        //dbVersion = 6;
    }

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

    _open = YES;
    return YES;
}

- (BOOL) close {
    if (!_open)
        return NO;
    
    LogTo(CBLDatabase, @"Close %@", _path);
    [[NSNotificationCenter defaultCenter] postNotificationName: CBL_DatabaseWillCloseNotification
                                                        object: self];
    for (CBLView* view in _views.allValues)
        [view databaseClosing];
    
    _views = nil;
    for (CBL_Replicator* repl in _activeReplicators.copy)
        [repl databaseClosing];
    
    _activeReplicators = nil;
    
    if (![_fmdb close])
        return NO;
    _open = NO;
    _transactionLevel = 0;
    return YES;
}


- (UInt64) totalDataSize {
    NSDictionary* attrs = [[NSFileManager defaultManager] attributesOfItemAtPath: _path error: NULL];
    if (!attrs)
        return 0;
    return attrs.fileSize + _attachments.totalDataSize;
}


- (NSString*) privateUUID {
    return [_fmdb stringForQuery: @"SELECT value FROM info WHERE key='privateUUID'"];
}

- (NSString*) publicUUID {
    return [_fmdb stringForQuery: @"SELECT value FROM info WHERE key='publicUUID'"];
}


#pragma mark - TRANSACTIONS:


- (BOOL) beginTransaction {
    if (![_fmdb executeUpdate: $sprintf(@"SAVEPOINT tdb%d", _transactionLevel + 1)])
        return NO;
    ++_transactionLevel;
    LogTo(CBLDatabase, @"Begin transaction (level %d)...", _transactionLevel);
    return YES;
}

- (BOOL) endTransaction: (BOOL)commit {
    Assert(_transactionLevel > 0);
    if (commit) {
        LogTo(CBLDatabase, @"Commit transaction (level %d)", _transactionLevel);
    } else {
        LogTo(CBLDatabase, @"CANCEL transaction (level %d)", _transactionLevel);
        if (![_fmdb executeUpdate: $sprintf(@"ROLLBACK TO tdb%d", _transactionLevel)])
            return NO;
        [_changesToNotify removeAllObjects];
    }
    if (![_fmdb executeUpdate: $sprintf(@"RELEASE tdb%d", _transactionLevel)])
        return NO;
    --_transactionLevel;
    [self postChangeNotifications];
    return YES;
}

- (CBLStatus) _inTransaction: (CBLStatus(^)())block {
    CBLStatus status;
    [self beginTransaction];
    @try {
        status = block();
    } @catch (NSException* x) {
        Warn(@"Exception raised during -inTransaction: %@", x);
        status = kCBLStatusException;
    } @finally {
        [self endTransaction: !CBLStatusIsError(status)];
    }
    return status;
}


/** Posts a local NSNotification of a new revision of a document. */
- (void) notifyChange: (CBL_DatabaseChange*)change {
    if (!_changesToNotify)
        _changesToNotify = [[NSMutableArray alloc] init];
    [_changesToNotify addObject: change];
    [self postChangeNotifications];
}


- (void) postChangeNotifications {
    if (_transactionLevel == 0 && _changesToNotify.count > 0) {
        LogTo(CBLDatabase, @"Posting %u change notifications", (unsigned)_changesToNotify.count);
        NSArray* changes = _changesToNotify;
        _changesToNotify = nil;
        [[NSNotificationCenter defaultCenter] postNotificationName: CBL_DatabaseChangesNotification
                                                            object: self
                                                          userInfo: $dict({@"changes", changes})];
        for (CBL_DatabaseChange* change in changes)
            [self postPublicChangeNotification: change];
    }
}


- (void) dbChanged: (NSNotification*)n {
    CBLDatabase* senderDB = n.object;
    // Was this posted by a _different_ CBLDatabase instance on the same database as me?
    if (senderDB != self && [senderDB.path isEqualToString: _path]) {
        for (CBL_DatabaseChange* change in (n.userInfo)[@"changes"]) {
            // CBL_Revision objects have mutable state inside, so copy this one first:
            CBL_DatabaseChange* copiedChange = [change copy];
            MYOnThread(_thread, ^{
                [self notifyChange: copiedChange];
            });
        }
    }
}


#pragma mark - GETTING DOCUMENTS:


- (NSUInteger) documentCount {
    NSUInteger result = NSNotFound;
    FMResultSet* r = [_fmdb executeQuery: @"SELECT COUNT(DISTINCT doc_id) FROM revs "
                                           "WHERE current=1 AND deleted=0"];
    if ([r next]) {
        result = [r intForColumnIndex: 0];
    }
    [r close];
    return result;    
}


- (SequenceNumber) lastSequenceNumber {
    return [_fmdb longLongForQuery: @"SELECT MAX(sequence) FROM revs"];
}


/** Inserts the _id, _rev and _attachments properties into the JSON data and stores it in rev.
    Rev must already have its revID and sequence properties set. */
- (NSDictionary*) extraPropertiesForRevision: (CBL_Revision*)rev options: (CBLContentOptions)options
{
    NSString* docID = rev.docID;
    NSString* revID = rev.revID;
    SequenceNumber sequence = rev.sequence;
    Assert(revID);
    Assert(sequence > 0);
    
    // Get attachment metadata, and optionally the contents:
    NSDictionary* attachmentsDict = [self getAttachmentDictForSequence: sequence
                                                               options: options];
    
    // Get more optional stuff to put in the properties:
    //OPT: This probably ends up making redundant SQL queries if multiple options are enabled.
    id localSeq=nil, revs=nil, revsInfo=nil, conflicts=nil;
    if (options & kCBLIncludeLocalSeq)
        localSeq = @(sequence);

    if (options & kCBLIncludeRevs) {
        revs = [self getRevisionHistoryDict: rev];
    }
    
    if (options & kCBLIncludeRevsInfo) {
        revsInfo = [[self getRevisionHistory: rev] my_map: ^id(CBL_Revision* rev) {
            NSString* status = @"available";
            if (rev.deleted)
                status = @"deleted";
            else if (rev.missing)
                status = @"missing";
            return $dict({@"rev", [rev revID]}, {@"status", status});
        }];
    }
    
    if (options & kCBLIncludeConflicts) {
        CBL_RevisionList* revs = [self getAllRevisionsOfDocumentID: docID onlyCurrent: YES];
        if (revs.count > 1) {
            conflicts = [revs.allRevisions my_map: ^(id aRev) {
                return ($equal(aRev, rev) || [(CBL_Revision*)aRev deleted]) ? nil : [aRev revID];
            }];
        }
    }

    return $dict({@"_id", docID},
                 {@"_rev", revID},
                 {@"_deleted", (rev.deleted ? $true : nil)},
                 {@"_attachments", attachmentsDict},
                 {@"_local_seq", localSeq},
                 {@"_revisions", revs},
                 {@"_revs_info", revsInfo},
                 {@"_conflicts", conflicts});
}


/** Inserts the _id, _rev and _attachments properties into the JSON data and stores it in rev.
 Rev must already have its revID and sequence properties set. */
- (void) expandStoredJSON: (NSData*)json
             intoRevision: (CBL_Revision*)rev
                  options: (CBLContentOptions)options
{
    NSDictionary* extra = [self extraPropertiesForRevision: rev options: options];
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
    CBL_Revision* rev = [[CBL_Revision alloc] initWithDocID: docID revID: revID deleted: deleted];
    rev.sequence = sequence;
    rev.missing = (json == nil);
    NSDictionary* extra = [self extraPropertiesForRevision: rev options: options];
    if (json.length == 0 || (json.length==2 && memcmp(json.bytes, "{}", 2)==0))
        return extra;      // optimization, and workaround for issue #44
    NSMutableDictionary* docProperties = [CBLJSON JSONObjectWithData: json
                                                            options: CBLJSONReadingMutableContainers
                                                              error: NULL];
    if (!docProperties) {
        Warn(@"Unparseable JSON for doc=%@, rev=%@: %@", docID, revID, [json my_UTF8ToString]);
        return extra;
    }
    [docProperties addEntriesFromDictionary: extra];
    return docProperties;
}


- (CBL_Revision*) getDocumentWithID: (NSString*)docID
                       revisionID: (NSString*)revID
                          options: (CBLContentOptions)options
                           status: (CBLStatus*)outStatus
{
    CBL_Revision* result = nil;
    CBLStatus status;
    NSMutableString* sql = [NSMutableString stringWithString: @"SELECT revid, deleted, sequence"];
    if (!(options & kCBLNoBody))
        [sql appendString: @", json"];
    if (revID)
        [sql appendString: @" FROM revs, docs "
               "WHERE docs.docid=? AND revs.doc_id=docs.doc_id AND revid=? AND json notnull LIMIT 1"];
    else
        [sql appendString: @" FROM revs, docs "
               "WHERE docs.docid=? AND revs.doc_id=docs.doc_id and current=1 and deleted=0 "
               "ORDER BY revid DESC LIMIT 1"];
    FMResultSet *r = [_fmdb executeQuery: sql, docID, revID];
    if (!r) {
        status = kCBLStatusDBError;
    } else if (![r next]) {
        if (!revID && [self getDocNumericID: docID] > 0)
            status = kCBLStatusDeleted;
        else
            status = kCBLStatusNotFound;
    } else {
        if (!revID)
            revID = [r stringForColumnIndex: 0];
        BOOL deleted = [r boolForColumnIndex: 1];
        result = [[CBL_Revision alloc] initWithDocID: docID revID: revID deleted: deleted];
        result.sequence = [r longLongIntForColumnIndex: 2];
        
        if (options != kCBLNoBody) {
            NSData* json = nil;
            if (!(options & kCBLNoBody))
                json = [r dataNoCopyForColumnIndex: 3];
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


- (BOOL) existsDocumentWithID: (NSString*)docID revisionID: (NSString*)revID {
    CBLStatus status;
    return [self getDocumentWithID: docID revisionID: revID options: kCBLNoBody status: &status] != nil;
}


- (CBLStatus) loadRevisionBody: (CBL_Revision*)rev
                      options: (CBLContentOptions)options
{
    if (rev.body && options==0 && rev.sequence)
        return kCBLStatusOK;
    Assert(rev.docID && rev.revID);
    FMResultSet *r = [_fmdb executeQuery: @"SELECT sequence, json FROM revs, docs "
                            "WHERE revid=? AND docs.docid=? AND revs.doc_id=docs.doc_id LIMIT 1",
                            rev.revID, rev.docID];
    if (!r)
        return kCBLStatusDBError;
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


- (SInt64) getDocNumericID: (NSString*)docID {
    Assert(docID);
    return [_fmdb longLongForQuery: @"SELECT doc_id FROM docs WHERE docid=?", docID];
}


- (SequenceNumber) getSequenceOfDocument: (SInt64)docNumericID
                                revision: (NSString*)revID
                             onlyCurrent: (BOOL)onlyCurrent
{
    NSString* sql = $sprintf(@"SELECT sequence FROM revs WHERE doc_id=? AND revid=? %@ LIMIT 1",
                             (onlyCurrent ? @"AND current=1" : @""));
    return [_fmdb longLongForQuery: sql, @(docNumericID), revID];
}


#pragma mark - HISTORY:


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
    FMResultSet* r = [_fmdb executeQuery: sql, @(docNumericID)];
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


static NSArray* revIDsFromResultSet(FMResultSet* r) {
    if (!r)
        return nil;
    NSMutableArray* revIDs = $marray();
    while ([r next])
        [revIDs addObject: [r stringForColumnIndex: 0]];
    [r close];
    return revIDs;
}


- (NSArray*) getPossibleAncestorRevisionIDs: (CBL_Revision*)rev limit: (unsigned)limit {
    int generation = rev.generation;
    if (generation <= 1)
        return nil;
    SInt64 docNumericID = [self getDocNumericID: rev.docID];
    if (docNumericID <= 0)
        return nil;
    int sqlLimit = limit > 0 ? (int)limit : -1;     // SQL uses -1, not 0, to denote 'no limit'
    FMResultSet* r = [_fmdb executeQuery:
                      @"SELECT revid FROM revs WHERE doc_id=? and revid < ?"
                       " and deleted=0 and json not null"
                       " ORDER BY sequence DESC LIMIT ?",
                      @(docNumericID), $sprintf(@"%d-", generation), @(sqlLimit)];
    return revIDsFromResultSet(r);
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
    return [_fmdb stringForQuery: sql, @(docNumericID), rev.revID];
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
    
    FMResultSet* r = [_fmdb executeQuery: @"SELECT sequence, parent, revid, deleted, json isnull "
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
            CBL_Revision* rev = [[CBL_Revision alloc] initWithDocID: docID revID: revID deleted: deleted];
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

- (NSDictionary*) getRevisionHistoryDict: (CBL_Revision*)rev {
    return makeRevisionHistoryDict([self getRevisionHistory: rev]);
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
    FMResultSet* r = [_fmdb executeQuery: @"SELECT revid, deleted FROM revs"
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
    FMResultSet* r = [_fmdb executeQuery: sql, @(lastSequence)];
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
            
            CBL_Revision* rev = [[CBL_Revision alloc] initWithDocID: [r stringForColumnIndex: 2]
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
    CBLRevision* publicRev = [[CBLRevision alloc] initWithDatabase: self revision: rev];
    return filter(publicRev, filterParams);
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
    [self defineFilter: filterName asBlock: filter];
    return filter;
}


#pragma mark - VIEWS:


- (NSArray*) allViews {
    FMResultSet* r = [_fmdb executeQuery: @"SELECT name FROM views"];
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
        return kCBLStatusDBError;
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
    if (![CBLView compiler]) {
        *outStatus = kCBLStatusNotFound;
        return nil;
    }
    NSString* language;
    NSDictionary* viewProps = $castIf(NSDictionary, [self getDesignDocFunction: tdViewName
                                                                           key: @"views"
                                                                      language: &language]);
    if (!viewProps) {
        *outStatus = kCBLStatusNotFound;
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
- (NSArray*) getAllDocs: (const CBLQueryOptions*)options {
    if (!options)
        options = &kDefaultCBLQueryOptions;
    
    // Generate the SELECT statement, based on the options:
    NSMutableString* sql = [@"SELECT revs.doc_id, docid, revid" mutableCopy];
    if (options->includeDocs)
        [sql appendString: @", json, sequence"];
    if (options->includeDeletedDocs)
        [sql appendString: @", deleted"];
    [sql appendString: @" FROM revs, docs WHERE"];
    if (options->keys)
        [sql appendFormat: @" docid IN (%@) AND", [CBLDatabase joinQuotedStrings: options->keys]];
    [sql appendString: @" docs.doc_id = revs.doc_id AND current=1"];
    if (!options->includeDeletedDocs)
        [sql appendString: @" AND deleted=0"];

    NSMutableArray* args = $marray();
    id minKey = options->startKey, maxKey = options->endKey;
    BOOL inclusiveMin = YES, inclusiveMax = options->inclusiveEnd;
    if (options->descending) {
        minKey = maxKey;
        maxKey = options->startKey;
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
                       (options->includeDeletedDocs ? @"deleted ASC," : @"")];
    [args addObject: @(options->limit)];
    [args addObject: @(options->skip)];
    
    // Now run the database query:
    FMResultSet* r = [_fmdb executeQuery: sql withArgumentsInArray: args];
    if (!r)
        return nil;
    
    int64_t lastDocID = 0;
    NSMutableArray* rows = $marray();
    NSMutableDictionary* docs = options->keys ? $mdict() : nil;
    while ([r next]) {
        @autoreleasepool {
            // Only count the first rev for a given doc (the rest will be losing conflicts):
            int64_t docNumericID = [r longLongIntForColumnIndex: 0];
            if (docNumericID == lastDocID)
                continue;
            lastDocID = docNumericID;
            
            NSString* docID = [r stringForColumnIndex: 1];
            NSString* revID = [r stringForColumnIndex: 2];
            BOOL deleted = options->includeDeletedDocs && [r boolForColumn: @"deleted"];
            NSDictionary* docContents = nil;
            if (options->includeDocs) {
                // Fill in the document contents:
                NSData* json = [r dataNoCopyForColumnIndex: 3];
                SequenceNumber sequence = [r longLongIntForColumnIndex: 4];
                docContents = [self documentPropertiesFromJSON: json
                                                         docID: docID
                                                         revID: revID
                                                       deleted: deleted
                                                      sequence: sequence
                                                       options: options->content];
                Assert(docContents);
            }
            NSDictionary* value = $dict({@"rev", revID},
                                        {@"deleted", (deleted ?$true : nil)});
            CBL_QueryRow* change = [[CBL_QueryRow alloc] initWithDocID: docID
                                                                 key: docID
                                                               value: value
                                                          properties: docContents];
            if (options->keys)
                docs[docID] = change;
            else
                [rows addObject: change];
        }
    }
    [r close];

    // If given doc IDs, sort the output into that order, and add entries for missing docs:
    if (options->keys) {
        for (NSString* docID in options->keys) {
            CBL_QueryRow* change = docs[docID];
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
                change = [[CBL_QueryRow alloc] initWithDocID: (value ?docID :nil)
                                                        key: docID
                                                      value: value
                                                 properties: nil];
            }
            [rows addObject: change];
        }
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
