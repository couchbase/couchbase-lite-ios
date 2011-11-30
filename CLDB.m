/*
 *  CLDB.cpp
 *  ToyCouch
 *
 *  Created by Jens Alfke on 6/19/10.
 *  Copyright 2010 Jens Alfke. All rights reserved.
 *
 */

#import "CLDB.h"
#import "CLDocument.h"

#import "FMDatabase.h"

#import "CollectionUtils.h"
#import "Test.h"


@implementation CLDB


- (id) initWithPath: (NSString*)path {
    if ((self = [super init])) {
        _fmdb = [[FMDatabase alloc] initWithPath: path];
        _fmdb.busyRetryTimeout = 10;
        _fmdb.logsErrors = YES; //TEMP
        _fmdb.traceExecution = WillLogTo(SQL);
    }
    return self;
}

- (NSString*) description {
    return $sprintf(@"%@[%@]", [self class], _fmdb.databasePath);
}

- (BOOL) open {
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

    return YES;
}

#if SQLITE_VERSION_NUMBER >= 3005000
- (BOOL) openWithFlags:(int)flags {
    return [_fmdb openWithFlags: flags];
}
#endif

- (BOOL) close {
    return [_fmdb close];
}

- (void) dealloc {
    [_fmdb release];
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
        LogTo(CLDB, @"Begin transaction...");
        [_fmdb beginTransaction];
        _transactionFailed = NO;
    }
}

- (void) endTransaction {
    Assert(_transactionLevel > 0);
    if (--_transactionLevel == 0) {
        if (_transactionFailed) {
            LogTo(CLDB, @"Rolling back failed transaction!");
            [_fmdb rollback];
        } else {
            LogTo(CLDB, @"Committing transaction");
            [_fmdb commit];
        }
    }
    _transactionFailed = NO;
}

- (BOOL) transactionFailed { return _transactionFailed; }

- (void) setTransactionFailed: (BOOL)failed {
    Assert(_transactionLevel > 0);
    Assert(failed, @"Can't clear the transactionFailed property!");
    LogTo(CLDB, @"Current transaction failed, will abort!");
    _transactionFailed = failed;
}


#pragma mark - DOCUMENTS:


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
        if (![scanner scanInt: &generation] || generation <= 0)
            return nil;
    }
    return [NSString stringWithFormat: @"%i-%@", ++generation, createUUID()];
}


- (CLDocument*) getDocumentWithID: (NSString*)docID {
    CLDocument* result = nil;
    FMResultSet *r = [_fmdb executeQuery: @"SELECT json FROM docs "
                                           "WHERE docid=? and current=1 and deleted=0 "
                                           "LIMIT 1",
                      docID];
    if ([r next])
        result = [[[CLDocument alloc] initWithJSON: [r dataForColumnIndex: 0]] autorelease];
    [r close];
    return result;
}

- (CLDocument*) getDocumentWithID: (NSString*)docID revisionID: (NSString*)revID {
    CLDocument* result = nil;
    FMResultSet *r = [_fmdb executeQuery: @"SELECT json FROM docs WHERE docid=? and revid=? "
                                           "LIMIT 1",
                      docID, revID];
    if ([r next])
        result = [[[CLDocument alloc] initWithJSON: [r dataForColumnIndex: 0]] autorelease];
    [r close];
    return result;
}


- (CLDocument*) putDocument: (CLDocument*)document  // may be nil, in which case this is a delete
                     withID: (NSString*)docID
                 revisionID: (NSString*)revID       // rev ID being replaced, or nil if an insert
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
    
    // Success!
    *outStatus = document ? 201 : 200;
    
exit:
    [r close];
    if (*outStatus >= 300)
        self.transactionFailed = YES;
    [self endTransaction];
    if (*outStatus >= 300) 
        return nil;
    return props ? [[[CLDocument alloc] initWithProperties: props] autorelease] : nil;
}

- (CLDocument*) createDocument: (CLDocument*)document
                        status: (int*)outStatus
{
    NSString* docID = document.documentID ?: [self generateDocumentID];
    return [self putDocument: document withID: docID revisionID: nil status: outStatus];
}

- (int) deleteDocumentWithID: (NSString*)docID 
                  revisionID: (NSString*)revID
{
    NSParameterAssert(docID);
    NSParameterAssert(revID);
    int status;
    [self putDocument: nil withID: docID revisionID: revID status: &status];
    return status;
}


- (int) compact {
    return [_fmdb executeUpdate: @"DELETE FROM docs WHERE current=0"] ? 200 : 500;
}


#pragma mark - CHANGES:


- (NSArray*) changesSinceSequence: (int)lastSequence limit: (int)limit {
    FMResultSet* r = [_fmdb executeQuery: @"SELECT sequence, docid, revid, deleted FROM docs "
                                           "WHERE sequence > ? AND current=1 LIMIT ?",
                                          $object(lastSequence), $object(limit)];
    if (!r)
        return nil;
    NSMutableArray* changes = $marray();
    while ([r next]) {
        NSDictionary* change = $dict({@"seq", $object([r intForColumnIndex: 0])},
                                     {@"id",  [r stringForColumnIndex: 1]},
                                     {@"rev", [r stringForColumnIndex: 2]},
                                     {@"deleted", [r boolForColumnIndex: 3] ? $true : nil});
        [changes addObject: change];
    }
    return changes;
}


- (NSArray*) changesSinceSequence: (int)lastSequence {
    return [self changesSinceSequence: lastSequence limit: INT_MAX];
}


@end




TestCase(CLDB) {
    // Start with a fresh database in /tmp:
    NSString* kPath = @"/tmp/toycouch_test.sqlite3";
    [[NSFileManager defaultManager] removeItemAtPath: kPath error: nil];
    CLDB *db = [[CLDB alloc] initWithPath: kPath];
    CAssert([db open]);
    CAssert(![db error]);
    
    // Create a document:
    NSMutableDictionary* props = $mdict({@"foo", $object(1)}, {@"bar", $false});
    CLDocument* doc = [[[CLDocument alloc] initWithProperties: props] autorelease];
    int status;
    doc = [db createDocument: doc status: &status];
    CAssertEq(status, 201);
    NSString* docID = doc.documentID;
    NSString* revID = doc.revisionID;
    Log(@"Doc got _id=%@ _rev=%@", docID, revID);
    CAssert(docID.length >= 10);
    CAssert(revID.length >= 10);
    CAssert([revID hasPrefix: @"1-"]);
    
    // Read it back:
    CLDocument* readDoc = [db getDocumentWithID: docID];
    CAssert(readDoc != nil);
    CAssertEqual(readDoc.properties, doc.properties);
    
    // Now update it:
    [props setObject: @"updated!" forKey: @"status"];
    doc = [[[CLDocument alloc] initWithProperties: props] autorelease];
    CLDocument* docRev1 = doc;
    NSString* revID1 = revID;
    doc = [db putDocument: doc withID: docID revisionID: revID status: &status];
    CAssertEq(status, 201);
    CAssertEqual(doc.documentID, docID);
    revID = doc.revisionID;
    Log(@"Doc got _id=%@ _rev=%@", docID, revID);
    CAssert(revID.length >= 10);
    CAssert([revID hasPrefix: @"2-"]);
    
    // Read it back:
    readDoc = [db getDocumentWithID: docID];
    CAssert(readDoc != nil);
    CAssertEqual(readDoc.properties, doc.properties);
    
    // Try to update the first rev, which should fail:
    doc = [db putDocument: docRev1 withID: docID revisionID: revID1 status: &status];
    CAssertEq(status, 409);
    CAssertNil(doc);
    
    // Delete it:
    status = [db deleteDocumentWithID: docID revisionID: revID];
    CAssertEq(status, 200);
    
    // Read it back (should fail):
    readDoc = [db getDocumentWithID: docID];
    CAssertNil(readDoc);
    
    NSArray* changes = [db changesSinceSequence: 0 limit: INT_MAX];
    NSLog(@"Changes = %@", changes);
    CAssertEq(changes.count, 1u);
    
    CAssert([db close]);
}
