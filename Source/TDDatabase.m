/*
 *  TDDatabase.m
 *  TouchDB
 *
 *  Created by Jens Alfke on 6/19/10.
 *  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
 *
 */

#import "TDDatabase.h"
#import "TDInternal.h"
#import "TDRevision.h"
#import "TDView.h"
#import "TDCollateJSON.h"
#import "TDBlobStore.h"
#import "TDPuller.h"
#import "TDPusher.h"

#import "FMDatabase.h"


NSString* const TDDatabaseChangeNotification = @"TDDatabaseChange";


@interface TDValidationContext : NSObject <TDValidationContext>
{
    @private
    TDDatabase* _db;
    TDRevision* _currentRevision;
    TDStatus _errorType;
    NSString* _errorMessage;
}
- (id) initWithDatabase: (TDDatabase*)db revision: (TDRevision*)currentRevision;
@property (readonly) TDRevision* currentRevision;
@property TDStatus errorType;
@property (copy) NSString* errorMessage;
@end


@interface TDDatabase ()
- (TDRevisionList*) getAllRevisionsOfDocumentID: (NSString*)docID numericID: (SInt64)docNumericID;
- (TDStatus) validateRevision: (TDRevision*)newRev previousRevision: (TDRevision*)oldRev;
@end


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
        _fmdb.crashOnErrors = YES;
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

- (BOOL) open {
    if (_open)
        return YES;
    if (![_fmdb open])
        return NO;
    
    // Register CouchDB-compatible JSON collation function:
    sqlite3_create_collation(_fmdb.sqliteHandle, "JSON", SQLITE_UTF8, self, TDCollateJSON);
    
    // ***** THIS IS THE SQL DATABASE SCHEMA! *****
    NSString *sql = @"\
        PRAGMA foreign_keys = ON; \
        CREATE TABLE IF NOT EXISTS docs ( \
            doc_id INTEGER PRIMARY KEY, \
            docid TEXT UNIQUE NOT NULL); \
        CREATE INDEX IF NOT EXISTS docs_docid ON docs(docid); \
        CREATE TABLE IF NOT EXISTS revs ( \
            sequence INTEGER PRIMARY KEY AUTOINCREMENT, \
            doc_id INTEGER NOT NULL REFERENCES docs(doc_id) ON DELETE CASCADE, \
            revid TEXT NOT NULL, \
            parent INTEGER REFERENCES revs(sequence) ON DELETE SET NULL, \
            current BOOLEAN, \
            deleted BOOLEAN DEFAULT 0, \
            json BLOB); \
        CREATE INDEX IF NOT EXISTS revs_by_id ON revs(revid, doc_id); \
        CREATE INDEX IF NOT EXISTS revs_current ON revs(doc_id, current); \
        CREATE INDEX IF NOT EXISTS revs_parent ON revs(parent); \
        CREATE TABLE IF NOT EXISTS views ( \
            view_id INTEGER PRIMARY KEY, \
            name TEXT UNIQUE NOT NULL,\
            version TEXT, \
            lastsequence INTEGER DEFAULT 0); \
        CREATE INDEX IF NOT EXISTS views_by_name ON views(name); \
        CREATE TABLE IF NOT EXISTS maps ( \
            view_id INTEGER NOT NULL REFERENCES views(view_id) ON DELETE CASCADE, \
            sequence INTEGER NOT NULL REFERENCES revs(sequence) ON DELETE CASCADE, \
            key TEXT NOT NULL COLLATE JSON, \
            value TEXT); \
        CREATE INDEX IF NOT EXISTS maps_keys on maps(view_id, key COLLATE JSON); \
        CREATE TABLE IF NOT EXISTS attachments ( \
            sequence INTEGER NOT NULL REFERENCES revs(sequence) ON DELETE CASCADE, \
            filename TEXT NOT NULL, \
            key BLOB NOT NULL); \
        CREATE INDEX IF NOT EXISTS attachments_by_sequence on attachments(sequence, filename); \
        CREATE TABLE IF NOT EXISTS replicators ( \
            remote TEXT NOT NULL, \
            push BOOLEAN, \
            last_sequence TEXT, \
            UNIQUE (remote, push))";
    // Declaring revs.sequence as AUTOINCREMENT means the values will always be
    // monotonically increasing, never reused. See <http://www.sqlite.org/autoinc.html>
    for (NSString* statement in [sql componentsSeparatedByString: @";"]) {
        if (statement.length && ![_fmdb executeUpdate: statement]) {
            [self close];
            return NO;
        }
    }
    
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

#if SQLITE_VERSION_NUMBER >= 3005000
- (BOOL) openWithFlags:(int)flags {
    return [_fmdb openWithFlags: flags];
}
#endif

- (BOOL) close {
    if (!_open || ![_fmdb close])
        return NO;
    _open = NO;
    return YES;
}

- (void) dealloc {
    [_fmdb release];
    [_path release];
    [_views release];
    [_activeReplicators release];
    [super dealloc];
}

@synthesize fmdb=_fmdb, attachmentStore=_attachments;

- (NSString*) path {
    return _fmdb.databasePath;
}

- (NSString*) name {
    return _fmdb.databasePath.lastPathComponent.stringByDeletingPathExtension;
}

- (int) error {
    return _fmdb.lastErrorCode;
}

- (NSString*) errorMessage {
    return _fmdb.lastErrorMessage;
}


- (void) beginTransaction {
    if (++_transactionLevel == 1) {
        LogTo(TDDatabase, @"Begin transaction...");
        [_fmdb beginTransaction];
        _transactionFailed = NO;
    }
}

- (void) endTransaction {
    Assert(_transactionLevel > 0);
    if (--_transactionLevel == 0) {
        if (_transactionFailed) {
            LogTo(TDDatabase, @"Rolling back failed transaction!");
            [_fmdb rollback];
        } else {
            LogTo(TDDatabase, @"Committing transaction");
            [_fmdb commit];
        }
    }
    _transactionFailed = NO;
}

- (BOOL) transactionFailed { return _transactionFailed; }

- (void) setTransactionFailed: (BOOL)failed {
    Assert(_transactionLevel > 0);
    Assert(failed, @"Can't clear the transactionFailed property!");
    LogTo(TDDatabase, @"Current transaction failed, will abort!");
    _transactionFailed = failed;
}


#pragma mark - GETTING DOCUMENTS:


- (TDRevision*) getDocumentWithID: (NSString*)docID {
    return [self getDocumentWithID: docID revisionID: nil];
}

- (TDRevision*) getDocumentWithID: (NSString*)docID revisionID: (NSString*)revID {
    TDRevision* result = nil;
    NSString* sql;
    if (revID)
        sql = @"SELECT revid, deleted, json FROM revs, docs "
               "WHERE docs.docid=? AND revs.doc_id=docs.doc_id AND revid=? LIMIT 1";
    else
        sql = @"SELECT revid, deleted, json FROM revs, docs "
               "WHERE docs.docid=? AND revs.doc_id=docs.doc_id and current=1 and deleted=0 "
               "ORDER BY revid DESC LIMIT 1";
    FMResultSet *r = [_fmdb executeQuery: sql, docID, revID];
    if ([r next]) {
        if (!revID)
            revID = [r stringForColumnIndex: 0];
        BOOL deleted = [r boolForColumnIndex: 1];
        NSData* json = [r dataForColumnIndex: 2];
        result = [[[TDRevision alloc] initWithDocID: docID revID: revID deleted: deleted] autorelease];
        if (json)
            result.asJSON = json;
    }
    [r close];
    return result;
}


- (TDStatus) loadRevisionBody: (TDRevision*)rev {
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
        NSData* json = [r dataForColumnIndex: 1];
        if (json)
            rev.asJSON = json;
    }
    [r close];
    return status;
}


- (TDStatus) compact {
    // Can't delete any rows because that would lose revision tree history.
    // But we can remove the JSON of non-current revisions, which is most of the space.
    return [_fmdb executeUpdate: @"UPDATE revs SET json=null WHERE current=0"] ? 200 : 500;
}


#pragma mark - PUTTING DOCUMENTS:


+ (BOOL) isValidDocumentID: (NSString*)str {
    // http://wiki.apache.org/couchdb/HTTP_Document_API#Documents
    return (str.length > 0);
}


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
    FMResultSet* r = [_fmdb executeQuery: @"SELECT sequence FROM revs ORDER BY sequence DESC LIMIT 1"];
    if (!r)
        return NSNotFound;
    SequenceNumber result = 0;
    if ([r next])
        result = [r longLongIntForColumnIndex: 0];
    [r close];
    return result;    
}


static NSString* createUUID() {
    CFUUIDRef uuid = CFUUIDCreate(NULL);
    NSString* str = NSMakeCollectable(CFUUIDCreateString(NULL, uuid));
    CFRelease(uuid);
    return [str autorelease];
}

- (NSString*) generateDocumentID {
    return createUUID();
}

- (NSString*) generateNextRevisionID: (NSString*)revID {
    // Revision IDs have a generation count, a hyphen, and a UUID.
    int generation = 0;
    if (revID) {
        NSScanner* scanner = [[NSScanner alloc] initWithString: revID];
        bool ok = [scanner scanInt: &generation] && generation > 0;
        [scanner release];
        if (!ok)
            return nil;
    }
    NSString* digest = createUUID();  //TODO: Generate canonical digest of body
    return [NSString stringWithFormat: @"%i-%@", ++generation, digest];
}


- (void) notifyChange: (TDRevision*)rev source: (NSURL*)source
{
    NSDictionary* userInfo = $dict({@"rev", rev},
                                   {@"seq", $object(rev.sequence)},
                                   {@"source", source});
    [[NSNotificationCenter defaultCenter] postNotificationName: TDDatabaseChangeNotification
                                                        object: self
                                                      userInfo: userInfo];
}


- (SInt64) insertDocumentID: (NSString*)docID {
    if (![_fmdb executeUpdate: @"INSERT INTO docs (docid) VALUES (?)", docID])
        return -1;
    return _fmdb.lastInsertRowId;
}

- (SInt64) getDocNumericID: (NSString*)docID {
    FMResultSet* r = [_fmdb executeQuery: @"SELECT doc_id FROM docs WHERE docid=?", docID];
    if (!r)
        return -1;
    SInt64 result = [r next] ? [r longLongIntForColumnIndex: 0] : 0;
    [r close];
    return result;
}

- (SInt64) getOrInsertDocNumericID: (NSString*)docID {
    SInt64 docNumericID = [self getDocNumericID: docID];
    if (docNumericID == 0)
        docNumericID = [self insertDocumentID: docID];
    return docNumericID;
}


// Raw row insertion. Returns new sequence, or 0 on error
- (SequenceNumber) insertRevision: (TDRevision*)rev
                     docNumericID: (SInt64)docNumericID
                   parentSequence: (SequenceNumber)parentSequence
                          current: (BOOL)current
                             JSON: (NSData*)json
{
    if (![_fmdb executeUpdate: @"INSERT INTO revs (doc_id, revid, parent, current, deleted, json) "
                                "VALUES (?, ?, ?, ?, ?, ?)",
                               $object(docNumericID),
                               rev.revID,
                               (parentSequence ? $object(parentSequence) : nil ),
                               $object(current),
                               $object(rev.deleted),
                               json])
        return 0;
    return _fmdb.lastInsertRowId;
}


- (TDRevision*) putRevision: (TDRevision*)rev
             prevRevisionID: (NSString*)prevRevID   // rev ID being replaced, or nil if an insert
                     status: (TDStatus*)outStatus
{
    Assert(!rev.revID);
    Assert(outStatus);
    NSString* docID = rev.docID;
    SInt64 docNumericID;
    BOOL deleted = rev.deleted;
    if (!rev || (prevRevID && !docID) || (deleted && !prevRevID)) {
        *outStatus = 400;
        return nil;
    }
    
    *outStatus = 500;
    [self beginTransaction];
    FMResultSet* r = nil;
    SequenceNumber parentSequence = 0;
    if (prevRevID) {
        // Replacing: make sure given prevRevID is current & find its sequence number:
        docNumericID = [self getOrInsertDocNumericID: docID];
        if (docNumericID <= 0)
            goto exit;
        r = [_fmdb executeQuery: @"SELECT sequence FROM revs "
                                  "WHERE doc_id=? AND revid=? and current=1",
                                 $object(docNumericID), prevRevID];
        if (!r)
            goto exit;
        if (![r next]) {
            // Not found: either a 404 or a 409, depending on whether there is any current revision
            *outStatus = [self getDocumentWithID: docID] ? 409 : 404;
            goto exit;
        }
        parentSequence = [r longLongIntForColumnIndex: 0];
        [r close];
        r = nil;
        
        if (_validations.count > 0) {
            // Fetch the previous revision and validate the new one against it:
            TDRevision* prevRev = [[TDRevision alloc] initWithDocID: docID revID: prevRevID
                                                            deleted: NO];
            TDStatus status = [self validateRevision: rev previousRevision: prevRev];
            [prevRev release];
            if (status >= 300) {
                *outStatus = status;
                goto exit;
            }
        }
        
        // Make replaced rev non-current:
        if (![_fmdb executeUpdate: @"UPDATE revs SET current=0 WHERE sequence=?",
                                   $object(parentSequence)])
            goto exit;
    } else if (docID) {
        // Inserting first revision, with docID given: make sure docID doesn't exist,
        // or exists but is currently deleted
        if (![self validateRevision: rev previousRevision: nil]) {
            *outStatus = 403;
            goto exit;
        }
        docNumericID = [self getOrInsertDocNumericID: docID];
        if (docNumericID <= 0)
            goto exit;
        r = [_fmdb executeQuery: @"SELECT sequence, deleted FROM revs "
                                  "WHERE doc_id=? and current=1 ORDER BY revid DESC LIMIT 1",
                                 $object(docNumericID)];
        if (!r)
            goto exit;
        if ([r next]) {
            if ([r boolForColumnIndex: 1]) {
                // Make the deleted revision no longer current:
                if (![_fmdb executeUpdate: @"UPDATE revs SET current=0 WHERE sequence=?",
                                           $object([r longLongIntForColumnIndex: 0])])
                    goto exit;
            } else {
                *outStatus = 409;
                goto exit;
            }
        }
        [r close];
        r = nil;
    } else {
        // Inserting first revision, with no docID given: generate a unique docID:
        docID = [self generateDocumentID];
        docNumericID = [self insertDocumentID: docID];
        if (docNumericID <= 0)
            goto exit;
    }
    
    // Bump the revID and update the JSON:
    NSString* newRevID = [self generateNextRevisionID: prevRevID];
    NSMutableDictionary* props = nil;
    NSData* json = nil;
    if (!rev.deleted) {
        props = [[rev.properties mutableCopy] autorelease];
        if (!props) {
            *outStatus = 400;  // bad or missing JSON
            goto exit;
        }
        [props setObject: docID forKey: @"_id"];
        [props setObject: newRevID forKey: @"_rev"];
        json = [NSJSONSerialization dataWithJSONObject: props options: 0 error: nil];
        NSAssert(json!=nil, @"Couldn't serialize document");
    }
    
    if (![_fmdb executeUpdate: @"INSERT INTO revs (doc_id, revid, parent, current, deleted, json) "
                                "VALUES (?, ?, ?, 1, ?, ?)",
                               $object(docNumericID),
                               newRevID,
                               (parentSequence ? $object(parentSequence) : nil),
                               $object(deleted),
                               json])
        goto exit;
    SequenceNumber sequence = _fmdb.lastInsertRowId;
    Assert(sequence > 0);
    
    // Success! Update the revision & its properties, with the new revID
    rev = [[rev copyWithDocID: docID revID: newRevID] autorelease];
    if (props)
        rev.properties = props;
    rev.sequence = sequence;
    *outStatus = deleted ? 200 : 201;
    
exit:
    [r close];
    if (*outStatus >= 300)
        self.transactionFailed = YES;
    [self endTransaction];
    if (*outStatus >= 300) 
        return nil;
    
    // Send a change notification:
    [self notifyChange: rev source: nil];
    return rev;
}


- (TDStatus) forceInsert: (TDRevision*)rev
         revisionHistory: (NSArray*)history  // in *reverse* order, starting with rev's revID
                  source: (NSURL*)source
{
    // First look up all locally-known revisions of this document:
    NSString* docID = rev.docID;
    SInt64 docNumericID = [self getOrInsertDocNumericID: docID];
    TDRevisionList* localRevs = [self getAllRevisionsOfDocumentID: docID numericID: docNumericID];
    if (!localRevs)
        return 500;
    NSUInteger historyCount = history.count;
    Assert(historyCount >= 1);
    
    // Validate against the latest common ancestor:
    if (_validations.count > 0) {
        TDRevision* oldRev = nil;
        for (NSUInteger i = 1; i<historyCount; ++i) {
            oldRev = [localRevs revWithDocID: docID revID: [history objectAtIndex: i]];
            if (oldRev)
                break;
        }
        TDStatus status = [self validateRevision: rev previousRevision: oldRev];
        if (status >= 300)
            return status;
    }
    
    // Walk through the remote history in chronological order, matching each revision ID to
    // a local revision. When the list diverges, start creating blank local revisions to fill
    // in the local history:
    SequenceNumber parentSequence = 0;
    for (NSInteger i = historyCount - 1; i>=0; --i) {
        NSString* revID = [history objectAtIndex: i];
        TDRevision* localRev = [localRevs revWithDocID: docID revID: revID];
        if (localRev) {
            // This revision is known locally. Remember its sequence as the parent of the next one:
            parentSequence = localRev.sequence;
            Assert(parentSequence > 0);
        } else {
            // This revision isn't known, so add it:
            TDRevision* newRev;
            NSData* json = nil;
            BOOL current = NO;
            if (i==0) {
                // Hey, this is the leaf revision we're inserting:
                newRev = rev;
                if (!rev.deleted) {
                    json = rev.asJSON;
                    if (!json)
                        return 400;
                }
                current = YES;
            } else {
                // It's an intermediate parent, so insert a stub:
                newRev = [[[TDRevision alloc] initWithDocID: docID revID: revID deleted: NO]
                                autorelease];
            }

            // Insert it:
            parentSequence = [self insertRevision: newRev
                                     docNumericID: docNumericID
                                   parentSequence: parentSequence
                                          current: current 
                                             JSON: json];
            if (parentSequence <= 0)
                return 500;
        }
    }
    
    // Record its sequence and send a change notification:
    rev.sequence = parentSequence;
    [self notifyChange: rev source: source];
    
    return 201;
}


- (void) addValidation:(TDValidationBlock)validationBlock {
    Assert(validationBlock);
    if (!_validations)
        _validations = [[NSMutableArray alloc] init];
    id copiedBlock = [validationBlock copy];
    [_validations addObject: copiedBlock];
    [copiedBlock release];
}


- (TDStatus) validateRevision: (TDRevision*)newRev previousRevision: (TDRevision*)oldRev {
    if (_validations.count == 0)
        return 200;
    TDValidationContext* context = [[TDValidationContext alloc] initWithDatabase: self
                                                                        revision: oldRev];
    TDStatus status = 200;
    for (TDValidationBlock validation in _validations) {
        if (!validation(newRev, context)) {
            status = context.errorType;
            break;
        }
    }
    [context release];
    return status;
}


#pragma mark - CHANGES:


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


- (TDView*) viewNamed: (NSString*)name {
    TDView* view = [_views objectForKey: name];
    if (!view) {
        view = [[[TDView alloc] initWithDatabase: self name: name] autorelease];
        if (!view)
            return nil;
        if (!_views)
            _views = [[NSMutableDictionary alloc] init];
        [_views setObject: view forKey: name];
    }
    return view;
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


- (NSDictionary*) getAllDocs: (const TDQueryOptions*)options {
    if (!options)
        options = &kDefaultTDQueryOptions;
    
    SequenceNumber update_seq = 0;
    if (options->updateSeq)
        update_seq = self.lastSequence;     // TODO: needs to be atomic with the following SELECT
    
    NSString* sql = $sprintf(@"SELECT docid, revid %@ FROM revs, docs "
                              "WHERE current=1 AND deleted=0 "
                              "AND docs.doc_id = revs.doc_id "
                              "ORDER BY docid %@ LIMIT ? OFFSET ?",
                             (options->includeDocs ? @", json" : @""),
                             (options->descending ? @"DESC" : @"ASC"));
    FMResultSet* r = [_fmdb executeQuery: sql, $object(options->limit), $object(options->skip)];
    if (!r)
        return nil;
    
    NSMutableArray* rows = $marray();
    while ([r next]) {
        NSString* docID = [r stringForColumnIndex: 0];
        NSString* revID = [r stringForColumnIndex: 1];
        NSDictionary* docContents = nil;
        if (options->includeDocs) {
            docContents = [NSJSONSerialization JSONObjectWithData: [r dataForColumnIndex: 2]
                                                          options: 0 error: nil];
        }
        NSDictionary* change = $dict({@"id",  docID},
                                     {@"key", docID},
                                     {@"value", $dict({@"rev", revID})},
                                     {@"doc", docContents});
        [rows addObject: change];
    }
    [r close];
    NSUInteger totalRows = rows.count;      //??? Is this true, or does it ignore limit/offset?
    return $dict({@"rows", $object(rows)},
                 {@"total_rows", $object(totalRows)},
                 {@"offset", $object(options->skip)},
                 {@"update_seq", update_seq ? $object(update_seq) : nil});
}


#pragma mark - ATTACHMENTS


- (BOOL) insertAttachment: (NSData*)contents
              forSequence: (SequenceNumber)sequence
                    named: (NSString*)filename
{
    TDBlobKey key;
    if (![_attachments storeBlob: contents creatingKey: &key])
        return NO;
    NSData* keyData = [NSData dataWithBytes: &key length: sizeof(key)];
    return [_fmdb executeUpdate: @"INSERT INTO attachments (sequence, filename, key) "
                                  "VALUES (?, ?, ?)",
                                 $object(sequence), filename, keyData];
}


- (NSData*) getAttachmentForSequence: (SequenceNumber)sequence
                               named: (NSString*)filename
                              status: (TDStatus*)outStatus
{
    Assert(sequence > 0);
    Assert(filename);
    FMResultSet* r = [_fmdb executeQuery:
                      @"SELECT key FROM attachments WHERE sequence=? AND filename=?",
                      $object(sequence), filename];
    if (!r) {
        *outStatus = 500;
        return nil;
    }
    if (![r next]) {
        *outStatus = 404;
        return nil;
    }
    NSData* keyData = [r dataForColumnIndex: 0];
    if (keyData.length != sizeof(TDBlobKey)) {
        Warn(@"%@: Attachment %lld.'%@' has bogus key size %d",
             self, sequence, filename, keyData.length);
        *outStatus = 500;
        return nil;
    }
    NSData* contents = [_attachments blobForKey: *(TDBlobKey*)keyData.bytes];
    if (!contents) {
        Warn(@"%@: Failed to load attachment %lld.'%@'", self, sequence, filename);
        *outStatus = 500;
    } else {
        *outStatus = 200;
    }
    return contents;
}


- (NSInteger) garbageCollectAttachments {
    // First delete attachment rows for already-cleared revisions:
    [_fmdb executeUpdate:  @"DELETE FROM attachments WHERE sequence IN "
                            "(SELECT sequence from revs WHERE json IS null)"];
    
    // Now compile all remaining attachment IDs and tell the store to delete all but these:
    FMResultSet* r = [_fmdb executeQuery: @"SELECT DISTINCT key FROM attachments"];
    if (!r)
        return -1;
    NSMutableSet* allKeys = [NSMutableSet set];
    while ([r next]) {
        [allKeys addObject: [r dataForColumnIndex: 0]];
    }
    return [_attachments deleteBlobsExceptWithKeys: allKeys];
}


#pragma mark - FOR REPLICATION


- (TDReplicator*) activeReplicatorWithRemoteURL: (NSURL*)remote
                                           push: (BOOL)push {
    TDReplicator* repl;
    for (repl in _activeReplicators) {
        if ($equal(repl.remote, remote) && repl.isPush == push)
            return repl;
    }
    return nil;
}

- (TDReplicator*) replicateWithRemoteURL: (NSURL*)remote
                                    push: (BOOL)push
                              continuous: (BOOL)continuous {
    TDReplicator* repl = [self activeReplicatorWithRemoteURL: remote push: push];
    if (repl)
        return repl;
    repl = [[TDReplicator alloc] initWithDB: self
                                     remote: remote 
                                       push: push
                                 continuous: continuous];
    if (!repl)
        return nil;
    if (!_activeReplicators)
        _activeReplicators = [[NSMutableArray alloc] init];
    [_activeReplicators addObject: repl];
    [repl start];
    [repl release];
    return repl;
}

- (void) replicatorDidStop: (TDReplicator*)repl {
    [_activeReplicators removeObjectIdenticalTo: repl];
}


- (NSString*) lastSequenceWithRemoteURL: (NSURL*)url push: (BOOL)push {
    FMResultSet* r = [_fmdb executeQuery:
                      @"SELECT last_sequence FROM replicators WHERE remote=? AND push=?",
                      url.absoluteString, $object(push)];
    NSString* lastSequence = nil;
    if ([r next])
        lastSequence = [r stringForColumnIndex: 0];
    [r close];
    return lastSequence;
}

- (BOOL) setLastSequence: (NSString*)lastSequence withRemoteURL: (NSURL*)url push: (BOOL)push {
    return [_fmdb executeUpdate: 
            @"INSERT OR REPLACE INTO replicators (remote, push, last_sequence) VALUES (?, ?, ?)",
            url.absoluteString, $object(push), lastSequence];
}


static NSString* quote(NSString* str) {
    return [str stringByReplacingOccurrencesOfString: @"'" withString: @"''"];
}

static NSString* joinQuoted(NSArray* strings) {
    if (strings.count == 0)
        return @"";
    NSMutableString* result = [NSMutableString stringWithString: @"'"];
    BOOL first = YES;
    for (NSString* str in strings) {
        if (first)
            first = NO;
        else
            [result appendString: @"','"];
        [result appendString: quote(str)];
    }
    [result appendString: @"'"];
    return result;
}


- (BOOL) findMissingRevisions: (TDRevisionList*)revs {
    if (revs.count == 0)
        return YES;
    NSString* sql = $sprintf(@"SELECT docid, revid FROM revs, docs "
                              "WHERE revid in (%@) AND docid IN (%@) "
                              "AND revs.doc_id == docs.doc_id",
                             joinQuoted(revs.allRevIDs), joinQuoted(revs.allDocIDs));
    // ?? Not sure sqlite will optimize this fully. May need a first query that looks up all
    // the numeric doc_ids from the docids.
    FMResultSet* r = [_fmdb executeQuery: sql];
    if (!r)
        return NO;
    while ([r next]) {
        TDRevision* rev = [revs revWithDocID: [r stringForColumnIndex: 0]
                                      revID: [r stringForColumnIndex: 1]];
        if (rev)
            [revs removeRev: rev];
    }
    [r close];
    return YES;
}


- (TDRevisionList*) getAllRevisionsOfDocumentID: (NSString*)docID
                                      numericID: (SInt64)docNumericID
{
    FMResultSet* r = [_fmdb executeQuery: @"SELECT sequence, revid, deleted FROM revs "
                                           "WHERE doc_id=? ORDER BY sequence DESC",
                                          $object(docNumericID)];
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

- (TDRevisionList*) getAllRevisionsOfDocumentID: (NSString*)docID {
    SInt64 docNumericID = [self getDocNumericID: docID];
    if (docNumericID < 0)
        return nil;
    else if (docNumericID == 0)
        return [[[TDRevisionList alloc] init] autorelease];  // no such document
    else
        return [self getAllRevisionsOfDocumentID: docID numericID: docNumericID];
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


@end






@implementation TDValidationContext

- (id) initWithDatabase: (TDDatabase*)db revision: (TDRevision*)currentRevision {
    self = [super init];
    if (self) {
        _db = db;
        _currentRevision = currentRevision;
        _errorType = 403;
        _errorMessage = [@"invalid document" retain];
    }
    return self;
}

- (void)dealloc {
    [_errorMessage release];
    [super dealloc];
}

- (TDRevision*) currentRevision {
    if (_currentRevision)
        [_db loadRevisionBody: _currentRevision];
    return _currentRevision;
}

@synthesize errorType=_errorType, errorMessage=_errorMessage;

@end
