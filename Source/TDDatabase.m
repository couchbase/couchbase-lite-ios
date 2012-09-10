//
// TDDatabase.m
// TouchDB
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

#import <TouchDB/TDDatabase.h>
#import "TDDatabase+Attachments.h"
#import "TDInternal.h"
#import <TouchDB/TDRevision.h>
#import "TDCollateJSON.h"
#import "TDBlobStore.h"
#import "TDPuller.h"
#import "TDPusher.h"
#import "TDMisc.h"

#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"


NSString* const TDDatabaseWillCloseNotification = @"TDDatabaseWillClose";
NSString* const TDDatabaseWillBeDeletedNotification = @"TDDatabaseWillBeDeleted";


@implementation TDDatabase


static BOOL removeItemIfExists(NSString* path, NSError** outError) {
    NSFileManager* fmgr = [NSFileManager defaultManager];
    return [fmgr removeItemAtPath: path error: outError] || ![fmgr fileExistsAtPath: path];
}


- (NSString*) attachmentStorePath {
    return [[_path stringByDeletingPathExtension] stringByAppendingString: @" attachments"];
}


+ (TDDatabase*) createEmptyDBAtPath: (NSString*)path {
    if (!removeItemIfExists(path, NULL))
        return nil;
    TDDatabase *db = [[[self alloc] initWithPath: path] autorelease];
    if (!removeItemIfExists(db.attachmentStorePath, NULL))
        return nil;
    if (![db open])
        return nil;
    return db;
}


- (id) initWithPath: (NSString*)path {
    if (self = [super init]) {
        Assert([path hasPrefix: @"/"], @"Path must be absolute");
        _path = [path copy];
        _name = [path.lastPathComponent.stringByDeletingPathExtension copy];
        _fmdb = [[FMDatabase alloc] initWithPath: _path];
        _fmdb.busyRetryTimeout = 10;
#if DEBUG
        _fmdb.logsErrors = YES;
#else
        _fmdb.logsErrors = WillLogTo(TDDatabase);
#endif
        _fmdb.traceExecution = WillLogTo(TDDatabaseVerbose);
    }
    return self;
}

- (NSString*) description {
    return $sprintf(@"%@[%@]", [self class], _path);
}

- (BOOL) exists {
    return [[NSFileManager defaultManager] fileExistsAtPath: _path];
}


- (BOOL) replaceWithDatabaseFile: (NSString*)databasePath
                 withAttachments: (NSString*)attachmentsPath
                           error: (NSError**)outError
{
    Assert(!_open, @"Already-open database cannot be replaced");
    NSString* dstAttachmentsPath = self.attachmentStorePath;
    NSFileManager* fmgr = [NSFileManager defaultManager];
    return [fmgr copyItemAtPath: databasePath toPath: _path error: outError] &&
           removeItemIfExists(dstAttachmentsPath, outError) &&
           (!attachmentsPath || [fmgr copyItemAtPath: attachmentsPath 
                                              toPath: dstAttachmentsPath
                                               error: outError]);
}


- (BOOL) initialize: (NSString*)statements {
    for (NSString* statement in [statements componentsSeparatedByString: @";"]) {
        if (statement.length && ![_fmdb executeUpdate: statement]) {
            Warn(@"TDDatabase: Could not initialize schema of %@ -- May be an old/incompatible format. "
                  "SQLite error: %@", _path, _fmdb.lastErrorMessage);
            [_fmdb close];
            return NO;
        }
    }
    return YES;
}

- (BOOL) open {
    if (_open)
        return YES;
    int flags = SQLITE_OPEN_FILEPROTECTION_COMPLETEUNLESSOPEN;
    if (_readOnly)
        flags |= SQLITE_OPEN_READONLY;
    else
        flags |= SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE;
    LogTo(TDDatabase, @"Open %@ (flags=%X)", _path, flags);
    if (![_fmdb openWithFlags: flags])
        return NO;
    
    // Register CouchDB-compatible JSON collation functions:
    sqlite3_create_collation(_fmdb.sqliteHandle, "JSON", SQLITE_UTF8,
                             kTDCollateJSON_Unicode, TDCollateJSON);
    sqlite3_create_collation(_fmdb.sqliteHandle, "JSON_RAW", SQLITE_UTF8,
                             kTDCollateJSON_Raw, TDCollateJSON);
    sqlite3_create_collation(_fmdb.sqliteHandle, "JSON_ASCII", SQLITE_UTF8,
                             kTDCollateJSON_ASCII, TDCollateJSON);
    sqlite3_create_collation(_fmdb.sqliteHandle, "REVID", SQLITE_UTF8,
                             NULL, TDCollateRevIDs);
    
    // Stuff we need to initialize every time the database opens:
    if (![self initialize: @"PRAGMA foreign_keys = ON;"])
        return NO;
    
    // Check the user_version number we last stored in the database:
    int dbVersion = [_fmdb intForQuery: @"PRAGMA user_version"];
    
    // Incompatible version changes increment the hundreds' place:
    if (dbVersion >= 100) {
        Warn(@"TDDatabase: Database version (%d) is newer than I know how to work with", dbVersion);
        [_fmdb close];
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
        if (![self initialize: schema])
            return NO;
        dbVersion = 3;
    }
    
    if (dbVersion < 2) {
        // Version 2: added attachments.revpos
        NSString* sql = @"ALTER TABLE attachments ADD COLUMN revpos INTEGER DEFAULT 0; \
                          PRAGMA user_version = 2";
        if (![self initialize: sql])
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
        if (![self initialize: sql])
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
                                 TDCreateUUID(), TDCreateUUID());
        if (![self initialize: sql])
            return NO;
        dbVersion = 4;
    }

    if (dbVersion < 5) {
        // Version 5: added encoding for attachments
        NSString* sql = @"ALTER TABLE attachments ADD COLUMN encoding INTEGER DEFAULT 0; \
                          ALTER TABLE attachments ADD COLUMN encoded_length INTEGER; \
                          PRAGMA user_version = 5";
        if (![self initialize: sql])
            return NO;
        dbVersion = 5;
    }
    
    if (dbVersion < 6) {
        // Version 6: enable Write-Ahead Log (WAL) <http://sqlite.org/wal.html>
        NSString* sql = @"PRAGMA journal_mode=WAL; \
                          PRAGMA user_version = 6";
        if (![self initialize: sql])
            return NO;
        //dbVersion = 6;
    }

#if DEBUG
    _fmdb.crashOnErrors = YES;
#endif
    
    // Open attachment store:
    NSString* attachmentsPath = self.attachmentStorePath;
    NSError* error;
    _attachments = [[TDBlobStore alloc] initWithPath: attachmentsPath error: &error];
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
    
    LogTo(TDDatabase, @"Close %@", _path);
    [[NSNotificationCenter defaultCenter] postNotificationName: TDDatabaseWillCloseNotification
                                                        object: self];
    for (TDView* view in _views.allValues)
        [view databaseClosing];
    setObj(&_views, nil);
    for (TDReplicator* repl in [_activeReplicators.copy autorelease])
        [repl databaseClosing];
    setObj(&_activeReplicators, nil);
    
    if (![_fmdb close])
        return NO;
    _open = NO;
    _transactionLevel = 0;
    return YES;
}

- (BOOL) deleteDatabase: (NSError**)outError {
    LogTo(TDDatabase, @"Deleting %@", _path);
    [[NSNotificationCenter defaultCenter] postNotificationName: TDDatabaseWillBeDeletedNotification
                                                        object: self];
    if (_open) {
        if (![self close])
            return NO;
    } else if (!self.exists) {
        return YES;
    }
    return removeItemIfExists(_path, outError) 
        && removeItemIfExists(self.attachmentStorePath, outError);
}

- (void) dealloc {
    if (_open) {
        //Warn(@"%@ dealloced without being closed first!", self);
        [self close];
    }
    [_fmdb release];
    [_path release];
    [_name release];
    [_views release];
    [_activeReplicators release];
    [_validations release];
    [_filters release];
    [_attachments release];
    [_pendingAttachmentsByDigest release];
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [super dealloc];
}

@synthesize path=_path, name=_name, fmdb=_fmdb, attachmentStore=_attachments, readOnly=_readOnly;


- (UInt64) totalDataSize {
    NSDictionary* attrs = [[NSFileManager defaultManager] attributesOfItemAtPath: _path error: NULL];
    if (!attrs)
        return 0;
    return attrs.fileSize + _attachments.totalDataSize;
}


- (BOOL) beginTransaction {
    if (![_fmdb executeUpdate: $sprintf(@"SAVEPOINT tdb%d", _transactionLevel + 1)])
        return NO;
    ++_transactionLevel;
    LogTo(TDDatabase, @"Begin transaction (level %d)...", _transactionLevel);
    return YES;
}

- (BOOL) endTransaction: (BOOL)commit {
    Assert(_transactionLevel > 0);
    if (commit) {
        LogTo(TDDatabase, @"Commit transaction (level %d)", _transactionLevel);
    } else {
        LogTo(TDDatabase, @"CANCEL transaction (level %d)", _transactionLevel);
        if (![_fmdb executeUpdate: $sprintf(@"ROLLBACK TO tdb%d", _transactionLevel)])
            return NO;
    }
    if (![_fmdb executeUpdate: $sprintf(@"RELEASE tdb%d", _transactionLevel)])
        return NO;
    --_transactionLevel;
    return YES;
}


- (TDStatus) inTransaction: (TDStatus(^)())block {
    TDStatus status;
    [self beginTransaction];
    @try {
        status = block();
    } @catch (NSException* x) {
        Warn(@"Exception raised during -inTransaction: %@", x);
        status = kTDStatusException;
    } @finally {
        [self endTransaction: !TDStatusIsError(status)];
    }
    return status;
}


- (NSString*) privateUUID {
    return [_fmdb stringForQuery: @"SELECT value FROM info WHERE key='privateUUID'"];
}

- (NSString*) publicUUID {
    return [_fmdb stringForQuery: @"SELECT value FROM info WHERE key='publicUUID'"];
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


- (SequenceNumber) lastSequence {
    return [_fmdb longLongForQuery: @"SELECT MAX(sequence) FROM revs"];
}


/** Inserts the _id, _rev and _attachments properties into the JSON data and stores it in rev.
    Rev must already have its revID and sequence properties set. */
- (NSDictionary*) extraPropertiesForRevision: (TDRevision*)rev options: (TDContentOptions)options
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
    if (options & kTDIncludeLocalSeq)
        localSeq = @(sequence);

    if (options & kTDIncludeRevs) {
        revs = [self getRevisionHistoryDict: rev];
    }
    
    if (options & kTDIncludeRevsInfo) {
        revsInfo = [[self getRevisionHistory: rev] my_map: ^id(TDRevision* rev) {
            NSString* status = @"available";
            if (rev.deleted)
                status = @"deleted";
            else if (rev.missing)
                status = @"missing";
            return $dict({@"rev", [rev revID]}, {@"status", status});
        }];
    }
    
    if (options & kTDIncludeConflicts) {
        TDRevisionList* revs = [self getAllRevisionsOfDocumentID: docID onlyCurrent: YES];
        if (revs.count > 1) {
            conflicts = [revs.allRevisions my_map: ^(id aRev) {
                return ($equal(aRev, rev) || [(TDRevision*)aRev deleted]) ? nil : [aRev revID];
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
             intoRevision: (TDRevision*)rev
                  options: (TDContentOptions)options
{
    NSDictionary* extra = [self extraPropertiesForRevision: rev options: options];
    if (json.length > 0) {
        rev.asJSON = [TDJSON appendDictionary: extra toJSONDictionaryData: json];
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
                                     options: (TDContentOptions)options
{
    TDRevision* rev = [[TDRevision alloc] initWithDocID: docID revID: revID deleted: deleted];
    rev.sequence = sequence;
    rev.missing = (json == nil);
    NSDictionary* extra = [self extraPropertiesForRevision: rev options: options];
    [rev release];
    if (json.length == 0 || (json.length==2 && memcmp(json.bytes, "{}", 2)==0))
        return extra;      // optimization, and workaround for issue #44
    NSMutableDictionary* docProperties = [TDJSON JSONObjectWithData: json
                                                            options: TDJSONReadingMutableContainers
                                                              error: NULL];
    if (!docProperties) {
        Warn(@"Unparseable JSON for doc=%@, rev=%@: %@", docID, revID, [json my_UTF8ToString]);
        return extra;
    }
    [docProperties addEntriesFromDictionary: extra];
    return docProperties;
}


- (TDRevision*) getDocumentWithID: (NSString*)docID
                       revisionID: (NSString*)revID
                          options: (TDContentOptions)options
                           status: (TDStatus*)outStatus
{
    TDRevision* result = nil;
    NSMutableString* sql = [NSMutableString stringWithString: @"SELECT revid, deleted, sequence"];
    if (!(options & kTDNoBody))
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
        *outStatus = kTDStatusDBError;
    } else if (![r next]) {
        if (!revID && [self getDocNumericID: docID] > 0)
            *outStatus = kTDStatusDeleted;
        else
            *outStatus = kTDStatusNotFound;
    } else {
        if (!revID)
            revID = [r stringForColumnIndex: 0];
        BOOL deleted = [r boolForColumnIndex: 1];
        result = [[[TDRevision alloc] initWithDocID: docID revID: revID deleted: deleted] autorelease];
        result.sequence = [r longLongIntForColumnIndex: 2];
        
        if (options != kTDNoBody) {
            NSData* json = nil;
            if (!(options & kTDNoBody))
                json = [r dataNoCopyForColumnIndex: 3];
            [self expandStoredJSON: json intoRevision: result options: options];
        }
        *outStatus = kTDStatusOK;
    }
    [r close];
    return result;
}


- (TDRevision*) getDocumentWithID: (NSString*)docID
                       revisionID: (NSString*)revID
{
    TDStatus status;
    return [self getDocumentWithID: docID revisionID: revID options: 0 status: &status];
}


- (BOOL) existsDocumentWithID: (NSString*)docID revisionID: (NSString*)revID {
    TDStatus status;
    return [self getDocumentWithID: docID revisionID: revID options: kTDNoBody status: &status] != nil;
}


- (TDStatus) loadRevisionBody: (TDRevision*)rev
                      options: (TDContentOptions)options
{
    if (rev.body && options==0)
        return kTDStatusOK;
    Assert(rev.docID && rev.revID);
    FMResultSet *r = [_fmdb executeQuery: @"SELECT sequence, json FROM revs, docs "
                            "WHERE revid=? AND docs.docid=? AND revs.doc_id=docs.doc_id LIMIT 1",
                            rev.revID, rev.docID];
    if (!r)
        return kTDStatusDBError;
    TDStatus status = kTDStatusNotFound;
    if ([r next]) {
        // Found the rev. But the JSON still might be null if the database has been compacted.
        status = kTDStatusOK;
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


#pragma mark - HISTORY:


- (TDRevisionList*) getAllRevisionsOfDocumentID: (NSString*)docID
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
    TDRevisionList* revs = [[[TDRevisionList alloc] init] autorelease];
    while ([r next]) {
        TDRevision* rev = [[TDRevision alloc] initWithDocID: docID
                                              revID: [r stringForColumnIndex: 1]
                                            deleted: [r boolForColumnIndex: 2]];
        rev.sequence = [r longLongIntForColumnIndex: 0];
        [revs addRev: rev];
        [rev release];
    }
    [r close];
    return revs;
}

- (TDRevisionList*) getAllRevisionsOfDocumentID: (NSString*)docID
                                    onlyCurrent: (BOOL)onlyCurrent
{
    SInt64 docNumericID = [self getDocNumericID: docID];
    if (docNumericID < 0)
        return nil;
    else if (docNumericID == 0)
        return [[[TDRevisionList alloc] init] autorelease];  // no such document
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


- (NSArray*) getPossibleAncestorRevisionIDs: (TDRevision*)rev limit: (unsigned)limit {
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


- (NSString*) findCommonAncestorOf: (TDRevision*)rev withRevIDs: (NSArray*)revIDs {
    if (revIDs.count == 0)
        return nil;
    SInt64 docNumericID = [self getDocNumericID: rev.docID];
    if (docNumericID <= 0)
        return nil;
    NSString* sql = $sprintf(@"SELECT revid FROM revs "
                              "WHERE doc_id=? and revid in (%@) and revid <= ? "
                              "ORDER BY revid DESC LIMIT 1", 
                              [TDDatabase joinQuotedStrings: revIDs]);
    return [_fmdb stringForQuery: sql, @(docNumericID), rev.revID];
}
    

- (NSArray*) getRevisionHistory: (TDRevision*)rev {
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
            TDRevision* rev = [[TDRevision alloc] initWithDocID: docID revID: revID deleted: deleted];
            rev.sequence = sequence;
            rev.missing = [r boolForColumnIndex: 4];
            [history addObject: rev];
            [rev release];
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
    for (TDRevision* rev in history) {
        int revNo;
        NSString* suffix;
        if ([TDRevision parseRevID: rev.revID intoGeneration: &revNo andSuffix: &suffix]) {
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

- (NSDictionary*) getRevisionHistoryDict: (TDRevision*)rev {
    return makeRevisionHistoryDict([self getRevisionHistory: rev]);
}


- (NSString*) getParentRevID: (TDRevision*)rev {
    Assert(rev.sequence > 0);
    return [_fmdb stringForQuery: @"SELECT parent.revid FROM revs, revs as parent"
                                   " WHERE revs.sequence=? and parent.sequence=revs.parent",
                                  @(rev.sequence)];
}


/** Returns the rev ID of the 'winning' revision of this document, and whether it's deleted. */
- (NSString*) winningRevIDOfDocNumericID: (SInt64)docNumericID
                               isDeleted: (BOOL*)outIsDeleted
{
    Assert(docNumericID > 0);
    FMResultSet* r = [_fmdb executeQuery: @"SELECT revid, deleted FROM revs"
                                           " WHERE doc_id=? and current=1"
                                           " ORDER BY deleted asc, revid desc LIMIT 1",
                                          @(docNumericID)];
    NSString* revID = nil;
    if ([r next]) {
        revID = [r stringForColumnIndex: 0];
        *outIsDeleted = [r boolForColumnIndex: 1];
    } else {
        *outIsDeleted = NO;
    }
    [r close];
    return revID;
}


const TDChangesOptions kDefaultTDChangesOptions = {UINT_MAX, 0, NO, NO, YES};


- (TDRevisionList*) changesSinceSequence: (SequenceNumber)lastSequence
                                 options: (const TDChangesOptions*)options
                                  filter: (TDFilterBlock)filter
                                  params: (NSDictionary*)filterParams
{
    // http://wiki.apache.org/couchdb/HTTP_database_API#Changes
    if (!options) options = &kDefaultTDChangesOptions;
    BOOL includeDocs = options->includeDocs || (filter != NULL);

    NSString* sql = $sprintf(@"SELECT sequence, revs.doc_id, docid, revid, deleted %@ FROM revs, docs "
                             "WHERE sequence > ? AND current=1 "
                             "AND revs.doc_id = docs.doc_id "
                             "ORDER BY revs.doc_id, revid DESC",
                             (includeDocs ? @", json" : @""));
    FMResultSet* r = [_fmdb executeQuery: sql, @(lastSequence)];
    if (!r)
        return nil;
    TDRevisionList* changes = [[[TDRevisionList alloc] init] autorelease];
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
            
            TDRevision* rev = [[TDRevision alloc] initWithDocID: [r stringForColumnIndex: 2]
                                                          revID: [r stringForColumnIndex: 3]
                                                        deleted: [r boolForColumnIndex: 4]];
            rev.sequence = [r longLongIntForColumnIndex: 0];
            if (includeDocs) {
                [self expandStoredJSON: [r dataNoCopyForColumnIndex: 5]
                          intoRevision: rev
                               options: options->contentOptions];
            }
            if (!filter || filter(rev, filterParams))
                [changes addRev: rev];
            [rev release];
        }
    }
    [r close];
    
    if (options->sortBySequence) {
        [changes sortBySequence];
        [changes limit: options->limit];
    }
    return changes;
}


- (void) defineFilter: (NSString*)filterName asBlock: (TDFilterBlock)filterBlock {
    if (!_filters)
        _filters = [[NSMutableDictionary alloc] init];
    [_filters setValue: [[filterBlock copy] autorelease] forKey: filterName];
}

- (TDFilterBlock) filterNamed: (NSString*)filterName {
    return _filters[filterName];
}


#pragma mark - VIEWS:


- (TDView*) registerView: (TDView*)view {
    if (!view)
        return nil;
    if (!_views)
        _views = [[NSMutableDictionary alloc] init];
    _views[view.name] = view;
    return view;
}


- (TDView*) viewNamed: (NSString*)name {
    TDView* view = _views[name];
    if (view)
        return view;
    return [self registerView: [[[TDView alloc] initWithDatabase: self name: name] autorelease]];
}


- (TDView*) existingViewNamed: (NSString*)name {
    TDView* view = _views[name];
    if (view)
        return view;
    view = [[[TDView alloc] initWithDatabase: self name: name] autorelease];
    if (!view.viewID)
        return nil;
    return [self registerView: view];
}


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


- (TDStatus) deleteViewNamed: (NSString*)name {
    if (![_fmdb executeUpdate: @"DELETE FROM views WHERE name=?", name])
        return kTDStatusDBError;
    [_views removeObjectForKey: name];
    return _fmdb.changes ? kTDStatusOK : kTDStatusNotFound;
}


//FIX: This has a lot of code in common with -[TDView queryWithOptions:status:]. Unify the two!
- (NSDictionary*) getDocsWithIDs: (NSArray*)docIDs options: (const TDQueryOptions*)options {
    if (!options)
        options = &kDefaultTDQueryOptions;
    
    SequenceNumber update_seq = 0;
    if (options->updateSeq)
        update_seq = self.lastSequence;     // TODO: needs to be atomic with the following SELECT
    
    // Generate the SELECT statement, based on the options:
    NSMutableString* sql = [[@"SELECT revs.doc_id, docid, revid" mutableCopy] autorelease];
    if (options->includeDocs)
        [sql appendString: @", json, sequence"];
    if (options->includeDeletedDocs)
        [sql appendString: @", deleted"];
    [sql appendString: @" FROM revs, docs WHERE"];
    if (docIDs)
        [sql appendFormat: @" docid IN (%@) AND", [TDDatabase joinQuotedStrings: docIDs]];
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
    NSMutableDictionary* docs = docIDs ? $mdict() : nil;
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
            NSDictionary* change = $dict({@"id",  docID},
                                         {@"key", docID},
                                         {@"value", $dict({@"rev", revID},
                                                          {@"deleted", (deleted ?$true : nil)})},
                                         {@"doc", docContents});
            if (docIDs)
                [docs setObject: change forKey: docID];
            else
                [rows addObject: change];
        }
    }
    [r close];

    // If given doc IDs, sort the output into that order, and add entries for missing docs:
    if (docIDs) {
        for (NSString* docID in docIDs) {
            NSDictionary* change = docs[docID];
            if (!change) {
                NSString* revID = nil;
                SInt64 docNumericID = [self getDocNumericID: docID];
                if (docNumericID > 0) {
                    BOOL deleted;
                    revID = [self winningRevIDOfDocNumericID: docNumericID
                                                   isDeleted: &deleted];
                }
                if (revID) {
                    change = $dict({@"id",  docID},
                                   {@"key", docID},
                                   {@"value", $dict({@"rev", revID}, {@"deleted", $true})});
                } else {
                    change = $dict({@"key", docID},
                                   {@"error", @"not_found"});
                }
            }
            [rows addObject: change];
        }
    }

    NSUInteger totalRows = rows.count;      //??? Is this true, or does it ignore limit/offset?
    return $dict({@"rows", rows},
                 {@"total_rows", @(totalRows)},
                 {@"offset", @(options->skip)},
                 {@"update_seq", update_seq ? @(update_seq) : nil});
}


- (NSDictionary*) getAllDocs: (const TDQueryOptions*)options {
    return [self getDocsWithIDs: nil options: options];
}


@end



#pragma mark - TESTS:
#if DEBUG

static TDRevision* mkrev(NSString* revID) {
    return [[[TDRevision alloc] initWithDocID: @"docid" revID: revID deleted: NO] autorelease];
}


TestCase(TDDatabase_MakeRevisionHistoryDict) {
    NSArray* revs = @[mkrev(@"4-jkl"), mkrev(@"3-ghi"), mkrev(@"2-def")];
    CAssertEqual(makeRevisionHistoryDict(revs), $dict({@"ids", @[@"jkl", @"ghi", @"def"]},
                                                      {@"start", @4}));
    
    revs = @[mkrev(@"4-jkl"), mkrev(@"2-def")];
    CAssertEqual(makeRevisionHistoryDict(revs), $dict({@"ids", @[@"4-jkl", @"2-def"]}));
    
    revs = @[mkrev(@"12345"), mkrev(@"6789")];
    CAssertEqual(makeRevisionHistoryDict(revs), $dict({@"ids", @[@"12345", @"6789"]}));
}

#endif
