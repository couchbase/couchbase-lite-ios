/*
 *  ToyDB.m
 *  ToyCouch
 *
 *  Created by Jens Alfke on 6/19/10.
 *  Copyright 2010 Jens Alfke. All rights reserved.
 *
 */

#import "ToyDB.h"
#import "ToyDocument.h"
#import "ToyRev.h"

#import "FMDatabase.h"

#import "CollectionUtils.h"
#import "Test.h"


NSString* const ToyDBChangeNotification = @"ToyDBChange";


@implementation ToyDB


- (id) initWithPath: (NSString*)path {
    if (self = [super init]) {
        _path = [path copy];
        _fmdb = [[FMDatabase alloc] initWithPath: _path];
        _fmdb.busyRetryTimeout = 10;
        _fmdb.logsErrors = WillLogTo(ToyDB);
#if DEBUG
        _fmdb.crashOnErrors = YES;
#endif
        _fmdb.traceExecution = WillLogTo(ToyDBVerbose);
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
    
    // Declaring the primary key as AUTOINCREMENT means the values will always be
    // monotonically increasing, never reused. See <http://www.sqlite.org/autoinc.html>
    NSString *sql = @"CREATE TABLE IF NOT EXISTS docs ("
                     "sequence INTEGER PRIMARY KEY AUTOINCREMENT, "
                     "docid TEXT, "
                     "revid TEXT, "
                     "current INTEGER, "            // boolean
                     "deleted INTEGER DEFAULT 0, "  // boolean
                     "json BLOB)";
    if (![_fmdb executeUpdate: sql]) {
        [self close];
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
    [super dealloc];
}

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
        LogTo(ToyDB, @"Begin transaction...");
        [_fmdb beginTransaction];
        _transactionFailed = NO;
    }
}

- (void) endTransaction {
    Assert(_transactionLevel > 0);
    if (--_transactionLevel == 0) {
        if (_transactionFailed) {
            LogTo(ToyDB, @"Rolling back failed transaction!");
            [_fmdb rollback];
        } else {
            LogTo(ToyDB, @"Committing transaction");
            [_fmdb commit];
        }
    }
    _transactionFailed = NO;
}

- (BOOL) transactionFailed { return _transactionFailed; }

- (void) setTransactionFailed: (BOOL)failed {
    Assert(_transactionLevel > 0);
    Assert(failed, @"Can't clear the transactionFailed property!");
    LogTo(ToyDB, @"Current transaction failed, will abort!");
    _transactionFailed = failed;
}


#pragma mark - DOCUMENTS:


+ (BOOL) isValidDocumentID: (NSString*)str {
    // http://wiki.apache.org/couchdb/HTTP_Document_API#Documents
    return (str.length > 0);
}


- (NSUInteger) documentCount {
    NSUInteger result = NSNotFound;
    FMResultSet* r = [_fmdb executeQuery: @"SELECT COUNT(*) FROM docs WHERE current=1 AND deleted=0"];
    if ([r next]) {
        result = [r intForColumnIndex: 0];
    }
    [r close];
    return result;    
}


- (NSUInteger) lastSequence {
    FMResultSet* r = [_fmdb executeQuery: @"SELECT sequence FROM docs ORDER BY sequence DESC LIMIT 1"];
    if (!r)
        return NSNotFound;
    NSUInteger result = 0;
    if ([r next])
        result = [r intForColumnIndex: 0];
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


- (ToyDocument*) getDocumentWithID: (NSString*)docID {
    return [self getDocumentWithID: docID revisionID: nil];
}

- (ToyDocument*) getDocumentWithID: (NSString*)docID revisionID: (NSString*)revID {
    ToyDocument* result = nil;
    NSString* sql;
    if (revID)
        sql = @"SELECT json FROM docs WHERE docid=? and revid=? LIMIT 1";
    else
        sql = @"SELECT json FROM docs WHERE docid=? and current=1 and deleted=0 LIMIT 1";
    FMResultSet *r = [_fmdb executeQuery: sql, docID, revID];
    if ([r next])
        result = [[[ToyDocument alloc] initWithJSON: [r dataForColumnIndex: 0]] autorelease];
    [r close];
    return result;
}


- (NSDictionary*) changeDictWithSequence: (sqlite_int64)sequence
                                   docID: (NSString*)docID
                                   revID: (NSString*)revID
                                 deleted: (BOOL)deleted
{
    return $dict({@"seq", $object(sequence)},
                 {@"id",  docID},
                 {@"rev", revID},
                 {@"deleted", deleted ? $true : nil});
}

- (void) notifyChange: (NSDictionary*)changeDict
{
    [[NSNotificationCenter defaultCenter] postNotificationName: ToyDBChangeNotification
                                                        object: self
                                                      userInfo: changeDict];
}


- (ToyDocument*) putDocument: (ToyDocument*)document // may be nil, in which case this is a delete
                      withID: (NSString*)docID
              prevRevisionID: (NSString*)revID       // rev ID being replaced, or nil if an insert
                      status: (int*)outStatus
{
    NSParameterAssert(outStatus);
    if (!docID || (!document && !revID)) {
        *outStatus = 400;
        return nil;
    }
    
    *outStatus = 500;
    [self beginTransaction];
    FMResultSet* r = nil;
    if (revID) {
        // Replacing: make sure given revID is current
        if (![_fmdb executeUpdate: @"UPDATE docs SET current=0 "
                                    "WHERE docid=? AND revid=? and current=1",
                                   docID, revID])
            goto exit;
        if (_fmdb.changes == 0) {
            // This is either a 404 or a 409, depending on whether there is any current revision
            *outStatus = [self getDocumentWithID: docID] ? 409 : 404;
            goto exit;
        }
    } else {
        // Inserting: make sure docID doesn't exist, or exists but is currently deleted
        r = [_fmdb executeQuery: @"SELECT sequence, deleted FROM docs "
                                  "WHERE docid=? and current=1 LIMIT 1",
                                 docID];
        if (!r)
            goto exit;
        if ([r next]) {
            if ([r boolForColumnIndex: 1]) {
                if (![_fmdb executeUpdate: @"UPDATE docs SET current=0 WHERE sequence=?",
                                           $object([r intForColumnIndex: 0])])
                    goto exit;
            } else {
                *outStatus = 409;
                goto exit;
            }
        }
        [r close];
        r = nil;
    }
    
    // Bump the revID and update the JSON:
    revID = [self generateNextRevisionID: revID];
    NSMutableDictionary* props = nil;
    NSData* json = nil;
    if (document) {
        props = [[document.properties mutableCopy] autorelease];
        if (!props) {
            *outStatus = 400;  // bad JSON
            goto exit;
        }
        [props setObject: docID forKey: @"_id"];
        [props setObject: revID forKey: @"_rev"];
        json = [NSJSONSerialization dataWithJSONObject: props options: 0 error: nil];
        NSAssert(json!=nil, @"Couldn't serialize document");
    }
    
    if (![_fmdb executeUpdate: @"INSERT INTO docs (docid, revid, current, deleted, json) "
                                "VALUES (?, ?, 1, ?, ?)",
                               docID, revID,
                               (document ? kCFBooleanFalse : kCFBooleanTrue),
                               json])
        goto exit;
    sqlite_int64 sequence = _fmdb.lastInsertRowId;
    Assert(sequence > 0);
    
    if (!props) {
        // Create properties to return, so caller can get the new rev ID
        props = $mdict({@"_id", docID}, {@"_rev", revID});
    }
    
    // Success!
    *outStatus = document ? 201 : 200;
    
exit:
    [r close];
    if (*outStatus >= 300)
        self.transactionFailed = YES;
    [self endTransaction];
    if (*outStatus >= 300) 
        return nil;
    
    // Send a change notification:
    [self notifyChange: [self changeDictWithSequence: sequence
                                               docID: docID
                                               revID: revID
                                             deleted: (document==nil)]];
    
    return props ? [[[ToyDocument alloc] initWithProperties: props] autorelease] : nil;
}

- (ToyDocument*) createDocument: (ToyDocument*)document
                        status: (int*)outStatus
{
    NSString* docID = document.documentID ?: [self generateDocumentID];
    return [self putDocument: document withID: docID prevRevisionID: nil status: outStatus];
}

- (ToyDocument*) deleteDocumentWithID: (NSString*)docID 
                           revisionID: (NSString*)revID
                               status: (int*)outStatus
{
    return [self putDocument: nil withID: docID prevRevisionID: revID status: outStatus];
}


- (int) forceInsert: (ToyRev*)rev {
    Assert(rev);
    BOOL deleted = rev.deleted;
    NSData* json = nil;
    if (!deleted) {
        json = rev.document.asJSON;
        if (!json)
            return 400;
    }
    
    int status = 500;
    [self beginTransaction];
    if (![_fmdb executeUpdate: @"UPDATE docs SET current=0 WHERE docid=?", rev.docID])
        goto exit;
    if (![_fmdb executeUpdate: @"INSERT INTO docs (docid, revid, current, deleted, json) "
                                "VALUES (?, ?, 1, ?, ?)",
                               rev.docID, rev.revID, $object(deleted), json])
        goto exit;
    sqlite_int64 sequence = _fmdb.lastInsertRowId;
    Assert(sequence > 0);
    // Success!
    status = deleted ? 200 : 201;
    
exit:
    if (status >= 300)
        self.transactionFailed = YES;
    [self endTransaction];
    if (status < 300) {
        // Send a change notification:
        [self notifyChange: [self changeDictWithSequence: sequence
                                                   docID: rev.docID
                                                   revID: rev.revID
                                                 deleted: deleted]];
    }
    return status;
}


- (int) compact {
    return [_fmdb executeUpdate: @"DELETE FROM docs WHERE current=0"] ? 200 : 500;
}


#pragma mark - CHANGES:


- (NSArray*) changesSinceSequence: (int)lastSequence
                          options: (const ToyDBQueryOptions*)options
{
    if (!options) options = &kDefaultToyDBQueryOptions;

    FMResultSet* r = [_fmdb executeQuery: @"SELECT sequence, docid, revid, deleted FROM docs "
                                           "WHERE sequence > ? AND current=1 "
                                           "ORDER BY sequence LIMIT ?",
                                          $object(lastSequence), $object(options->limit)];
    if (!r)
        return nil;
    NSMutableArray* changes = $marray();
    while ([r next]) {
        [changes addObject: [self changeDictWithSequence: [r longLongIntForColumnIndex: 0]
                                                   docID: [r stringForColumnIndex: 1]
                                                   revID: [r stringForColumnIndex: 2]
                                                 deleted: [r boolForColumnIndex: 3] != 0]];
    }
    return changes;
}


#pragma mark - QUERIES:

// http://wiki.apache.org/couchdb/HTTP_view_API#Querying_Options


const ToyDBQueryOptions kDefaultToyDBQueryOptions = {
    nil, nil, 0, INT_MAX, NO, NO, NO
};


- (NSDictionary*) getAllDocs: (const ToyDBQueryOptions*)options {
    if (!options)
        options = &kDefaultToyDBQueryOptions;
    
    NSUInteger update_seq = 0;
    if (options->updateSeq)
        update_seq = self.lastSequence;     // TODO: needs to be atomic with the following SELECT
    
    NSString* sql = $sprintf(@"SELECT docid, revid %@ FROM docs "
                              "WHERE current=1 AND deleted=0 "
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
    NSUInteger totalRows = rows.count;      //??? Is this true, or does it ignore limit/offset?
    return $dict({@"rows", $object(rows)},
                 {@"total_rows", $object(totalRows)},
                 {@"offset", $object(options->skip)},
                 {@"update_seq", update_seq ? $object(update_seq) : nil});
}


#pragma mark - FOR REPLICATION


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


- (BOOL) findMissingRevisions: (ToyRevSet*)toyRevs {
    if (toyRevs.count == 0)
        return YES;
    
    NSMutableArray* revIDs = $marray();
    for (ToyRev* rev in toyRevs)
        [revIDs addObject: rev.revID];
    NSString* sql = $sprintf(@"SELECT docid, revid FROM docs "
                              "WHERE docid IN (%@) AND revid in (%@)",
                             joinQuoted(toyRevs.allDocIDs), joinQuoted(revIDs));
    
    FMResultSet* r = [_fmdb executeQuery: sql];
    if (!r)
        return NO;
    while ([r next]) {
        ToyRev* rev = [toyRevs revWithDocID: [r stringForColumnIndex: 0]
                                      revID: [r stringForColumnIndex: 1]];
        if (rev)
            [toyRevs removeRev: rev];
    }
    return YES;
}


@end




#pragma mark - TESTS

TestCase(ToyDB) {
    // Start with a fresh database in /tmp:
    NSString* kPath = @"/tmp/toycouch_test.sqlite3";
    [[NSFileManager defaultManager] removeItemAtPath: kPath error: nil];
    ToyDB *db = [[ToyDB alloc] initWithPath: kPath];
    CAssert([db open]);
    CAssert(![db error]);
    
    // Create a document:
    NSMutableDictionary* props = $mdict({@"foo", $object(1)}, {@"bar", $false});
    ToyDocument* doc = [[[ToyDocument alloc] initWithProperties: props] autorelease];
    int status;
    doc = [db createDocument: doc status: &status];
    CAssertEq(status, 201);
    NSString* docID = doc.documentID;
    NSString* revID = doc.revisionID;
    Log(@"Doc got _id=%@ _rev=%@", docID, revID);
    CAssert(docID.length >= 10);
    CAssert([revID hasPrefix: @"1-"]);
    
    // Read it back:
    ToyDocument* readDoc = [db getDocumentWithID: docID];
    CAssert(readDoc != nil);
    CAssertEqual(readDoc.properties, doc.properties);
    
    // Now update it:
    [props setObject: @"updated!" forKey: @"status"];
    doc = [[[ToyDocument alloc] initWithProperties: props] autorelease];
    ToyDocument* docRev1 = doc;
    NSString* revID1 = revID;
    doc = [db putDocument: doc withID: docID prevRevisionID: revID status: &status];
    CAssertEq(status, 201);
    CAssertEqual(doc.documentID, docID);
    revID = doc.revisionID;
    Log(@"Doc got _id=%@ _rev=%@", docID, revID);
    CAssert([revID hasPrefix: @"2-"]);
    
    // Read it back:
    readDoc = [db getDocumentWithID: docID];
    CAssert(readDoc != nil);
    CAssertEqual(readDoc.properties, doc.properties);
    
    // Try to update the first rev, which should fail:
    doc = [db putDocument: docRev1 withID: docID prevRevisionID: revID1 status: &status];
    CAssertEq(status, 409);
    CAssertNil(doc);
    
    // Delete it:
    doc = [db deleteDocumentWithID: docID revisionID: revID status: &status];
    CAssertEq(status, 200);
    CAssertEqual(doc.documentID, docID);
    CAssert([doc.revisionID hasPrefix: @"3-"]);
    
    // Read it back (should fail):
    readDoc = [db getDocumentWithID: docID];
    CAssertNil(readDoc);
    
    NSArray* changes = [db changesSinceSequence: 0 options: NULL];
    NSLog(@"Changes = %@", changes);
    CAssertEq(changes.count, 1u);
    
    CAssert([db close]);
    [db release];
}
