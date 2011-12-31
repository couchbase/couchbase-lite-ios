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

#import "TDDatabase.h"
#import "TDInternal.h"
#import "TDRevision.h"
#import "TDCollateJSON.h"
#import "TDBlobStore.h"
#import "TDPuller.h"
#import "TDPusher.h"

#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"


@implementation TDDatabase


- (NSString*) attachmentStorePath {
    return [[_path stringByDeletingPathExtension] stringByAppendingString: @" attachments"];
}


+ (TDDatabase*) createEmptyDBAtPath: (NSString*)path {
    [[NSFileManager defaultManager] removeItemAtPath: path error: nil];
    TDDatabase *db = [[[self alloc] initWithPath: path] autorelease];
    [[NSFileManager defaultManager] removeItemAtPath: db.attachmentStorePath error: nil];
    if (![db open])
        return nil;
    return db;
}


- (id) initWithPath: (NSString*)path {
    if (self = [super init]) {
        _path = [path copy];
        _fmdb = [[FMDatabase alloc] initWithPath: _path];
        _fmdb.busyRetryTimeout = 10;
#if DEBUG
        _fmdb.logsErrors = YES;
#else
        _fmdb.logsErrors = WillLogTo(TouchDB);
#endif
        _fmdb.traceExecution = WillLogTo(TouchDBVerbose);
    }
    return self;
}

- (NSString*) description {
    return $sprintf(@"%@[%@]", [self class], _fmdb.databasePath);
}

- (BOOL) exists {
    return [[NSFileManager defaultManager] fileExistsAtPath: _path];
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
    if (![_fmdb open])
        return NO;
    
    // Register CouchDB-compatible JSON collation function:
    sqlite3_create_collation(_fmdb.sqliteHandle, "JSON", SQLITE_UTF8, self, TDCollateJSON);
    
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
                revid TEXT NOT NULL, \
                parent INTEGER REFERENCES revs(sequence) ON DELETE SET NULL, \
                current BOOLEAN, \
                deleted BOOLEAN DEFAULT 0, \
                json BLOB); \
            CREATE INDEX revs_by_id ON revs(revid, doc_id); \
            CREATE INDEX revs_current ON revs(doc_id, current); \
            CREATE INDEX revs_parent ON revs(parent); \
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
            PRAGMA user_version = 2";             // at the end, update user_version
        if (![self initialize: schema])
            return NO;
    } else if (dbVersion < 2) {
        // Version 2: added attachments.revpos
        NSString* sql = @"ALTER TABLE attachments ADD COLUMN revpos INTEGER DEFAULT 0; \
                          PRAGMA user_version = 2";
        if (![self initialize: sql])
            return NO;
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
    if (!_open || ![_fmdb close])
        return NO;
    _open = NO;
    return YES;
}

- (BOOL) deleteDatabase: (NSError**)outError {
    if (_open) {
        if (![self close])
            return NO;
    } else if (!self.exists) {
        return YES;
    }
    NSFileManager* fmgr = [NSFileManager defaultManager];
    return [fmgr removeItemAtPath: _path error: outError] 
        && [fmgr removeItemAtPath: self.attachmentStorePath error: outError];
}

- (void) dealloc {
    [_fmdb release];
    [_path release];
    [_views release];
    [_activeReplicators release];
    [_validations release];
    [super dealloc];
}

@synthesize fmdb=_fmdb, attachmentStore=_attachments;

- (NSString*) path {
    return _fmdb.databasePath;
}

- (NSString*) name {
    return _fmdb.databasePath.lastPathComponent.stringByDeletingPathExtension;
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


- (TDStatus) compact {
    // Can't delete any rows because that would lose revision tree history.
    // But we can remove the JSON of non-current revisions, which is most of the space.
    Log(@"TDDatabase: Deleting JSON of old revisions...");
    if (![_fmdb executeUpdate: @"UPDATE revs SET json=null WHERE current=0"])
        return 500;
    
    Log(@"Deleting old attachments...");
    TDStatus status = [self garbageCollectAttachments];

    Log(@"Vacuuming SQLite database...");
    if (![_fmdb executeUpdate: @"VACUUM"])
        return 500;
    
    Log(@"...Finished database compaction.");
    return status;
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


/** Splices the contents of an NSDictionary into JSON data (that already represents a dict), without parsing the JSON. */
static NSData* appendDictToJSON(NSData* json, NSDictionary* dict) {
    if (!dict.count)
        return json;
    NSData* extraJson = [NSJSONSerialization dataWithJSONObject: dict options:0 error:nil];
    if (!extraJson)
        return nil;
    size_t jsonLength = json.length;
    size_t extraLength = extraJson.length;
    CAssert(jsonLength >= 2);
    CAssertEq(*(const char*)json.bytes, '{');
    if (jsonLength == 2)  // Original JSON was empty
        return extraJson;
    NSMutableData* newJson = [NSMutableData dataWithLength: jsonLength + extraLength - 1];
    if (!newJson)
        return nil;
    uint8_t* dst = newJson.mutableBytes;
    memcpy(dst, json.bytes, jsonLength - 1);                          // Copy json w/o trailing '}'
    dst += jsonLength - 1;
    *dst++ = ',';                                                     // Add a ','
    memcpy(dst, (const uint8_t*)extraJson.bytes + 1, extraLength - 1);  // Add "extra" after '{'
    return newJson;
}


/** Inserts the _id, _rev and _attachments properties into the JSON data and stores it in rev.
    Rev must already have its revID and sequence properties set. */
- (void) expandStoredJSON: (NSData*)json
             intoRevision: (TDRevision*)rev
          withAttachments: (BOOL)withAttachments
{
    if (!json)
        return;
    NSString* docID = rev.docID;
    NSString* revID = rev.revID;
    SequenceNumber sequence = rev.sequence;
    Assert(revID);
    Assert(sequence > 0);
    NSDictionary* attachmentsDict = [self getAttachmentDictForSequence: sequence
                                                           withContent: withAttachments];
    NSDictionary* extra = $dict({@"_id", docID},
                                {@"_rev", revID},
                                {@"_deleted", (rev.deleted ? $true : nil)},
                                {@"_attachments", attachmentsDict});
    rev.asJSON = appendDictToJSON(json, extra);
}


- (NSDictionary*) documentPropertiesFromJSON: (NSData*)json
                                       docID: (NSString*)docID
                                       revID: (NSString*)revID
                                    sequence: (SequenceNumber)sequence
{
    NSMutableDictionary* docProperties;
    docProperties = [NSJSONSerialization JSONObjectWithData: json
                                                    options: NSJSONReadingMutableContainers
                                                      error: nil];
    [docProperties setObject: docID forKey: @"_id"];
    [docProperties setObject: revID forKey: @"_rev"];
    [docProperties setValue: [self getAttachmentDictForSequence: sequence withContent: NO]
                     forKey: @"_attachments"];
    return docProperties;
}


- (TDRevision*) getDocumentWithID: (NSString*)docID
                       revisionID: (NSString*)revID
                  withAttachments: (BOOL)withAttachments
{
    TDRevision* result = nil;
    NSString* sql;
    if (revID)
        sql = @"SELECT revid, deleted, json, sequence FROM revs, docs "
               "WHERE docs.docid=? AND revs.doc_id=docs.doc_id AND revid=? LIMIT 1";
    else
        sql = @"SELECT revid, deleted, json, sequence FROM revs, docs "
               "WHERE docs.docid=? AND revs.doc_id=docs.doc_id and current=1 and deleted=0 "
               "ORDER BY revid DESC LIMIT 1";
    FMResultSet *r = [_fmdb executeQuery: sql, docID, revID];
    if ([r next]) {
        if (!revID)
            revID = [r stringForColumnIndex: 0];
        BOOL deleted = [r boolForColumnIndex: 1];
        NSData* json = [r dataForColumnIndex: 2];
        result = [[[TDRevision alloc] initWithDocID: docID revID: revID deleted: deleted] autorelease];
        result.sequence = [r longLongIntForColumnIndex: 3];
        [self expandStoredJSON: json intoRevision: result withAttachments: withAttachments];
    }
    [r close];
    return result;
}


- (TDStatus) loadRevisionBody: (TDRevision*)rev
              withAttachments: (BOOL)withAttachments
{
    if (rev.body)
        return 200;
    Assert(rev.docID && rev.revID);
    FMResultSet *r = [_fmdb executeQuery: @"SELECT sequence, json FROM revs, docs "
                            "WHERE revid=? AND docs.docid=? AND revs.doc_id=docs.doc_id LIMIT 1",
                            rev.revID, rev.docID];
    if (!r)
        return 500;
    TDStatus status = 404;
    if ([r next]) {
        // Found the rev. But the JSON still might be null if the database has been compacted.
        status = 200;
        rev.sequence = [r longLongIntForColumnIndex: 0];
        [self expandStoredJSON: [r dataForColumnIndex: 1] 
                  intoRevision: rev
               withAttachments: withAttachments];
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
    FMResultSet* r = [_fmdb executeQuery: sql, $object(docNumericID)];
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
    

- (NSArray*) getRevisionHistory: (TDRevision*)rev {
    NSString* docID = rev.docID;
    NSString* revID = rev.revID;
    Assert(revID && docID);

    SInt64 docNumericID = [self getDocNumericID: docID];
    if (docNumericID < 0)
        return nil;
    else if (docNumericID == 0)
        return $array();
    
    FMResultSet* r = [_fmdb executeQuery: @"SELECT sequence, parent, revid, deleted FROM revs "
                                           "WHERE doc_id=? ORDER BY sequence DESC",
                                          $object(docNumericID)];
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


- (TDRevisionList*) changesSinceSequence: (SequenceNumber)lastSequence
                                 options: (const TDQueryOptions*)options
{
    if (!options) options = &kDefaultTDQueryOptions;

    FMResultSet* r = [_fmdb executeQuery: @"SELECT sequence, docid, revid, deleted FROM revs, docs "
                                           "WHERE sequence > ? AND current=1 "
                                           "AND revs.doc_id = docs.doc_id "
                                           "ORDER BY sequence LIMIT ?",
                                          $object(lastSequence), $object(options->limit)];
    if (!r)
        return nil;
    TDRevisionList* changes = [[[TDRevisionList alloc] init] autorelease];
    while ([r next]) {
        TDRevision* rev = [[TDRevision alloc] initWithDocID: [r stringForColumnIndex: 1]
                                              revID: [r stringForColumnIndex: 2]
                                            deleted: [r boolForColumnIndex: 3]];
        rev.sequence = [r longLongIntForColumnIndex: 0];
        [changes addRev: rev];
        [rev release];
    }
    [r close];
    return changes;
}


#pragma mark - VIEWS:


- (TDView*) registerView: (TDView*)view {
    if (!view)
        return nil;
    if (!_views)
        _views = [[NSMutableDictionary alloc] init];
    [_views setObject: view forKey: view.name];
    return view;
}


- (TDView*) viewNamed: (NSString*)name {
    TDView* view = [_views objectForKey: name];
    if (view)
        return view;
    return [self registerView: [[[TDView alloc] initWithDatabase: self name: name] autorelease]];
}


- (TDView*) existingViewNamed: (NSString*)name {
    TDView* view = [_views objectForKey: name];
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
    return views;
}


- (TDStatus) deleteViewNamed: (NSString*)name {
    if (![_fmdb executeUpdate: @"DELETE FROM views WHERE name=?", name])
        return 500;
    [_views removeObjectForKey: name];
    return _fmdb.changes ? 200 : 404;
}


//FIX: This has a lot of code in common with -[TDView queryWithOptions:status:]. Unify the two!
- (NSDictionary*) getAllDocs: (const TDQueryOptions*)options {
    if (!options)
        options = &kDefaultTDQueryOptions;
    
    SequenceNumber update_seq = 0;
    if (options->updateSeq)
        update_seq = self.lastSequence;     // TODO: needs to be atomic with the following SELECT
    
    // Generate the SELECT statement, based on the options:
    NSMutableString* sql = [NSMutableString stringWithFormat:
                            @"SELECT revs.doc_id, docid, revid %@ FROM revs, docs "
                              "WHERE current=1 AND deleted=0 "
                              "AND docs.doc_id = revs.doc_id",
                             (options->includeDocs ? @", json, sequence" : @"")];
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
    
    [sql appendFormat: @" ORDER BY docid %@, revid DESC LIMIT ? OFFSET ?",
                       (options->descending ? @"DESC" : @"ASC")];
    [args addObject: $object(options->limit)];
    [args addObject: $object(options->skip)];
    
    // Now run the database query:
    FMResultSet* r = [_fmdb executeQuery: sql withArgumentsInArray: args];
    if (!r)
        return nil;
    
    int64_t lastDocID = 0;
    NSMutableArray* rows = $marray();
    while ([r next]) {
        @autoreleasepool {
            // Only count the first rev for a given doc (the rest will be losing conflicts):
            int64_t docNumericID = [r longLongIntForColumnIndex: 0];
            if (docNumericID == lastDocID)
                continue;
            lastDocID = docNumericID;
            
            NSString* docID = [r stringForColumnIndex: 1];
            NSString* revID = [r stringForColumnIndex: 2];
            NSDictionary* docContents = nil;
            if (options->includeDocs) {
                // Fill in the document contents:
                NSData* json = [r dataForColumnIndex: 3];
                SequenceNumber sequence = [r longLongIntForColumnIndex: 4];
                docContents = [self documentPropertiesFromJSON: json
                                                         docID: docID
                                                         revID: revID
                                                      sequence: sequence];
            }
            NSDictionary* change = $dict({@"id",  docID},
                                         {@"key", docID},
                                         {@"value", $dict({@"rev", revID})},
                                         {@"doc", docContents});
            [rows addObject: change];
        }
    }
    [r close];
    NSUInteger totalRows = rows.count;      //??? Is this true, or does it ignore limit/offset?
    return $dict({@"rows", $object(rows)},
                 {@"total_rows", $object(totalRows)},
                 {@"offset", $object(options->skip)},
                 {@"update_seq", update_seq ? $object(update_seq) : nil});
}


@end
