//
//  CBL_SQLiteViewStorage.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/16/15.
//  Copyright (c) 2011-2015 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBL_SQLiteViewStorage.h"
#import "CBL_SQLiteStorage.h"
#import "CBLSpecialKey.h"
#import "CBLQuery+FullTextSearch.h"
#import "CBLQuery+Geo.h"
#import "CBLCollateJSON.h"
#import "CouchbaseLitePrivate.h"
#import "CBLInternal.h"
#import "CBLMisc.h"
#import "ExceptionUtils.h"

#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "FMResultSet.h"


@implementation CBL_SQLiteViewStorage
{
    __weak CBL_SQLiteStorage* _dbStorage;
    int _viewID;
    CBLViewCollation _collation;
    NSString* _mapTableName;
    BOOL _initializedFullTextSchema, _initializedRTreeSchema;
    NSString* _emitSQL;
}

@synthesize name=_name, delegate=_delegate;


- (instancetype) initWithDBStorage: (CBL_SQLiteStorage*)dbStorage
                              name: (NSString*)name
                            create: (BOOL)create
{
    self = [super init];
    if (self) {
        _name = [name copy];
        _dbStorage = dbStorage;
        _viewID = -1;  // means 'unknown'
        _collation = kCBLViewCollationUnicode;

        if (!create && self.viewID <= 0)
            return nil;
    }
    return self;
}


- (void) close {
    _dbStorage = nil;
    _viewID = -1;
}


- (BOOL) setVersion: (NSString*)version {
    // Update the version column in the db. This is a little weird looking because we want to
    // avoid modifying the db if the version didn't change, and because the row might not exist yet.
    CBL_FMDatabase* fmdb = _dbStorage.fmdb;
    if (![fmdb executeUpdate: @"INSERT OR IGNORE INTO views (name, version, total_docs) "
          "VALUES (?, ?, ?)",
          _name, version, @(0)]) {
        return NO;
    }
    if (fmdb.changes) {
        [self createIndex];
        return YES;     // created new view
    }
    if (![fmdb executeUpdate: @"UPDATE views SET version=?, lastSequence=0, total_docs=0 "
          "WHERE name=? AND version!=?",
          version, _name, version]) {
        return NO;
    }
    return YES;
}


// The name of the map table is dynamic, based on the ID of the view. This method replaces a '#'
// with the view ID in a query string.
- (NSString*) queryString: (NSString*)sql {
    return [sql stringByReplacingOccurrencesOfString: @"#" withString: self.mapTableName
                                             options: 0 range:NSMakeRange(0, sql.length)];
}


- (BOOL) runStatements: (NSString*)sql error: (NSError**)outError {
    CBL_SQLiteStorage* db = _dbStorage;
    return [db inTransaction: ^CBLStatus {
        if ([_dbStorage runStatements: [self queryString: sql] error: outError])
            return kCBLStatusOK;
        else {
            return db.lastDbStatus;
        }
    }] == kCBLStatusOK;
}


- (void) createIndex {
    NSString* sql = @"\
        CREATE TABLE IF NOT EXISTS 'maps_#' (\
            sequence INTEGER NOT NULL REFERENCES revs(sequence) ON DELETE CASCADE,\
            key TEXT NOT NULL COLLATE JSON,\
            value TEXT,\
            fulltext_id INTEGER, \
            bbox_id INTEGER, \
            geokey BLOB)";
    NSError* error;
    if (![self runStatements: sql error: &error])
        Warn(@"Couldn't create view index `%@`: %@", _name, error.my_compactDescription);
}

- (void) finishCreatingIndex {
    NSString* sql = @"\
        CREATE INDEX IF NOT EXISTS 'maps_#_keys' on 'maps_#'(key COLLATE JSON);\
        CREATE INDEX IF NOT EXISTS 'maps_#_sequence' ON 'maps_#'(sequence)";
    NSError* error;
    if (![self runStatements: sql error: &error])
        Warn(@"Couldn't create view SQL index `%@`: %@", _name, error.my_compactDescription);
}


- (void) deleteIndex {
    if (self.viewID <= 0)
        return;
    NSString* sql = @"\
        DROP TABLE IF EXISTS 'maps_#';\
        UPDATE views SET lastSequence=0, total_docs=0 WHERE view_id=#";
    NSError* error;
    if (![self runStatements: sql error: &error])
        Warn(@"Couldn't delete view index `%@`: %@", _name, error.my_compactDescription);
}


- (BOOL) createFullTextSchema {
    if (_initializedFullTextSchema)
        return YES;
    if (!sqlite3_compileoption_used("SQLITE_ENABLE_FTS3")
            && !sqlite3_compileoption_used("SQLITE_ENABLE_FTS4")) {
        Warn(@"Can't index full text: SQLite isn't built with FTS3 or FTS4 module");
        return NO;
    }

    // Derive the stemmer language name based on the current locale's language.
    NSString* stemmerName = CBLStemmerNameForCurrentLocale();
    NSString* stemmer = @"";
    if (stemmerName)
        stemmer = $sprintf(@"\"stemmer=%@\"", stemmerName);

    NSString* sql = $sprintf(@"\
        CREATE VIRTUAL TABLE IF NOT EXISTS fulltext \
            USING fts4(content, tokenize=unicodesn %@);\
        CREATE INDEX IF NOT EXISTS  'maps_#_by_fulltext' ON 'maps_#'(fulltext_id); \
        CREATE TRIGGER IF NOT EXISTS 'del_maps_#_fulltext' \
            DELETE ON 'maps_#' WHEN old.fulltext_id not null BEGIN \
                DELETE FROM fulltext WHERE rowid=old.fulltext_id| END", stemmer);
    //OPT: Would be nice to use partial indexes but that requires SQLite 3.8 and makes
    // the db file only readable by SQLite 3.8+, i.e. the file would not be portable to
    // iOS 8 which only has SQLite 3.7 :(
    // On the above index we could add "WHERE fulltext_id not null".
    NSError* error;
    if (![self runStatements: sql error: &error]) {
        Warn(@"Error initializing fts4 schema: %@", error.my_compactDescription);
        return NO;
    }
    _initializedFullTextSchema = YES;
    return YES;
}


- (BOOL) createRTreeSchema {
    if (_initializedRTreeSchema)
        return YES;
    if (!sqlite3_compileoption_used("SQLITE_ENABLE_RTREE")) {
        Warn(@"Can't geo-query: SQLite isn't built with Rtree module");
        return NO;
    }
    NSString* sql = @"\
        CREATE VIRTUAL TABLE IF NOT EXISTS bboxes USING rtree(rowid, x0, x1, y0, y1);\
        CREATE TRIGGER IF NOT EXISTS 'del_maps_#_bbox' \
            DELETE ON 'maps_#' WHEN old.bbox_id not null BEGIN \
            DELETE FROM bboxes WHERE rowid=old.bbox_id| END";
    NSError* error;
    if (![self runStatements: sql error: &error]) {
        Warn(@"Error initializing rtree schema: %@", error.my_compactDescription);
        return NO;
    }
    _initializedRTreeSchema = YES;
    return YES;
}


- (void) deleteView {
    CBL_SQLiteStorage* db = _dbStorage;
    [db inTransaction: ^CBLStatus {
        [self deleteIndex];
        [db.fmdb executeUpdate: @"DELETE FROM views WHERE name=?", _name];
        return db.lastDbStatus;
    }];
    _viewID = 0;
}


- (int) viewID {
    if (_viewID < 0)
        _viewID = [_dbStorage.fmdb intForQuery: @"SELECT view_id FROM views WHERE name=?", _name];
    return _viewID;
}


- (NSString*) mapTableName {
    if (!_mapTableName) {
        [self viewID];
        Assert(_viewID > 0);
        _mapTableName = $sprintf(@"%d", _viewID);
    }
    return _mapTableName;
}


- (NSUInteger) totalRows {
    CBL_FMDatabase* fmdb = _dbStorage.fmdb;
    NSInteger totalRows = [fmdb intForQuery: @"SELECT total_docs FROM views WHERE name=?", _name];
    if (totalRows == -1) { // means unknown
        [self createIndex];
        totalRows = [fmdb intForQuery: [self queryString: @"SELECT COUNT(*) FROM 'maps_#'"]];
        [fmdb executeUpdate: @"UPDATE views SET total_docs=? WHERE view_id=?",
                                @(totalRows), @(self.viewID)];
    }
    Assert(totalRows >= 0);
    return totalRows;
}


- (SequenceNumber) lastSequenceIndexed {
    return [_dbStorage.fmdb longLongForQuery: @"SELECT lastSequence FROM views WHERE name=?", _name];
}


- (SequenceNumber) lastSequenceChangedAt {
    return self.lastSequenceIndexed;
    //FIX: Should store this properly; it helps optimize CBLLiveQuery
}


#pragma mark - INDEXING:


- (CBLStatus) updateIndexes: (NSArray*)inputViews { // array of CBL_ViewStorage
    LogTo(View, @"Checking indexes of (%@) for %@", viewNames(inputViews), _name);
    CBL_SQLiteStorage* dbStorage = _dbStorage;
    CBL_FMDatabase* fmdb = dbStorage.fmdb;

    CBLStatus status = [dbStorage inTransaction: ^CBLStatus {
        // If the view the update is for doesn't need any update, don't do anything:
        const SequenceNumber dbMaxSequence = dbStorage.lastSequence;
        const SequenceNumber forViewLastSequence = self.lastSequenceIndexed;
        if (forViewLastSequence >= dbMaxSequence)
            return kCBLStatusNotModified;
        
        // Check whether we need to update at all,
        // and remove obsolete emitted results from the 'maps' table:
        SequenceNumber minLastSequence = dbMaxSequence;
        SequenceNumber viewLastSequence[inputViews.count];
        unsigned deletedCount = 0;
        int i = 0;
        NSMutableSet* docTypes = [NSMutableSet set];
        NSMutableDictionary* viewDocTypes = nil;
        BOOL allDocTypes = NO;
        NSMutableDictionary* viewTotalRows = [[NSMutableDictionary alloc] init];
        NSMutableArray* views = [[NSMutableArray alloc] initWithCapacity: inputViews.count];
        NSMutableArray* mapBlocks = [[NSMutableArray alloc] initWithCapacity: inputViews.count];
        for (CBL_SQLiteViewStorage* view in inputViews) {
            id<CBL_ViewStorageDelegate> delegate = view.delegate;
            CBLMapBlock mapBlock = delegate.mapBlock;
            if (mapBlock == NULL) {
                Assert(view != self,
                       @"Cannot index view %@: no map block registered",
                       view.name);
                LogVerbose(View, @"    %@ has no map block; skipping it", view.name);
                continue;
            }

            [views addObject: view];
            [mapBlocks addObject: mapBlock];

            int viewID = view.viewID;
            Assert(viewID > 0, @"View '%@' not found in database", view.name);

            NSUInteger totalRows = view.totalRows;
            viewTotalRows[@(viewID)] = @(totalRows);

            SequenceNumber last = (view==self) ? forViewLastSequence : view.lastSequenceIndexed;
            viewLastSequence[i++] = last;
            if (last < 0) {
                return dbStorage.lastDbError;
            } else if (last < dbMaxSequence) {
                if (last == 0)
                    [view createIndex];
                minLastSequence = MIN(minLastSequence, last);
                LogVerbose(View, @"    %@ last indexed at #%lld", view.name, last);

                NSString* docType = delegate.documentType;
                if (docType) {
                    [docTypes addObject: docType];
                    if (!viewDocTypes)
                        viewDocTypes = [NSMutableDictionary dictionary];
                    viewDocTypes[view.name] = docType;
                } else {
                    allDocTypes = YES; // can't filter by doc_type
                }

                BOOL ok;
                if (last == 0) {
                    // If the lastSequence has been reset to 0, make sure to remove all map results:
                    ok = [fmdb executeUpdate: [view queryString: @"DELETE FROM 'maps_#'"]];
                } else {
                    [dbStorage optimizeSQLIndexes]; // ensures query will use the right indexes
                    // Delete all obsolete map results (ones from since-replaced revisions):
                    ok = [fmdb executeUpdate:
                          [view queryString: @"DELETE FROM 'maps_#' WHERE sequence IN ("
                                                "SELECT parent FROM revs WHERE sequence>? "
                                                    "AND +parent>0 AND +parent<=?)"],
                          @(last), @(last)];
                }
                if (!ok)
                    return dbStorage.lastDbError;
                
                // Update #deleted rows
                int changes = fmdb.changes;
                deletedCount += changes;
                
                // Only count these deletes as changes if this isn't a view reset to 0
                if (last != 0) {
                    viewTotalRows[@(viewID)] = @([viewTotalRows[@(viewID)] intValue] - changes);
                }
            }
        }
        if (minLastSequence == dbMaxSequence)
            return kCBLStatusNotModified;

        LogTo(View, @"Updating indexes of (%@) from #%lld to #%lld ...",
              viewNames(views), minLastSequence, dbMaxSequence);

        // This is the emit() block, which gets called from within the user-defined map() block
        // that's called down below.
        __block CBL_SQLiteViewStorage* curView;
        __block NSMutableDictionary* curDoc;
        __block SequenceNumber sequence = minLastSequence;
        __block CBLStatus emitStatus = kCBLStatusOK;
        __block unsigned insertedCount = 0;
        CBLMapEmitBlock emit = ^(id key, id value) {
            int status = [curView _emitKey: key
                                     value: value
                                valueIsDoc: (value == curDoc)
                               forSequence: sequence];
            if (status != kCBLStatusOK)
                emitStatus = status;
            else {
                viewTotalRows[@(curView.viewID)] = @([viewTotalRows[@(curView.viewID)] intValue] + 1);
                insertedCount++;
            }
        };

        // Now scan every revision added since the last time the views were indexed:
        BOOL checkDocTypes = docTypes.count > 1 || (allDocTypes && docTypes.count > 0);
        NSMutableString* sql = [@"SELECT revs.doc_id, sequence, docid, revid, json, deleted " mutableCopy];
        if (checkDocTypes)
            [sql appendString: @", doc_type "];
        [sql appendString: @"FROM revs, docs WHERE sequence>? AND current!=0 "];
        if (minLastSequence == 0)
            [sql appendString: @"AND deleted=0 "];
        if (!allDocTypes && docTypes.count > 0)
            [sql appendFormat: @"AND doc_type IN (%@) ", CBLJoinSQLQuotedStrings(docTypes.allObjects)];
        [sql appendString: @"AND revs.doc_id = docs.doc_id "
                            "ORDER BY revs.doc_id, deleted, revid DESC"];
        CBL_FMResultSet* r = [fmdb executeQuery: sql, @(minLastSequence)];
        if (!r)
            return dbStorage.lastDbError;

        BOOL keepGoing = [r next]; // Go to first result row
        while (keepGoing) {
            @autoreleasepool {
                // Get row values now, before the code below advances 'r':
                int64_t doc_id = [r longLongIntForColumnIndex: 0];
                sequence = [r longLongIntForColumnIndex: 1];
                NSString* docID = [r stringForColumnIndex: 2];
                if ([docID hasPrefix: @"_design/"]) {     // design docs don't get indexed!
                    keepGoing = [r next];
                    continue;
                }
                NSString* revID = [r stringForColumnIndex: 3];
                NSData* json = [r dataForColumnIndex: 4];
                BOOL deleted = [r boolForColumnIndex: 5];
                NSString* docType = checkDocTypes ? [r stringForColumnIndex: 6] : nil;

                // Skip rows with the same doc_id -- these are losing conflicts.
                NSMutableArray* conflicts = nil;
                while ((keepGoing = [r next]) && [r longLongIntForColumnIndex: 0] == doc_id) {
                    if (!deleted) {
                        // Conflict revisions:
                        if (!conflicts)
                            conflicts = $marray();
                        [conflicts addObject: [r stringForColumnIndex: 3]];
                    }
                }

                SequenceNumber realSequence = sequence; // because sequence may be changed, below
                if (minLastSequence > 0) {
                    // Find conflicts with documents from previous indexings.
                    CBL_FMResultSet* r2 = [fmdb executeQuery:
                                    @"SELECT revid, sequence FROM revs "
                                     "WHERE doc_id=? AND sequence<=? AND current!=0 AND deleted=0 "
                                     "ORDER BY revID DESC",
                                    @(doc_id), @(minLastSequence)];
                    if (!r2) {
                        [r close];
                        return dbStorage.lastDbError;
                    }
                    if ([r2 next]) {
                        NSString* oldRevID = [r2 stringForColumnIndex:0];
                        // This is the revision that used to be the 'winner'.
                        // Remove its emitted rows:
                        SequenceNumber oldSequence = [r2 longLongIntForColumnIndex: 1];
                        for (CBL_SQLiteViewStorage* view in views) {
                            [fmdb executeUpdate: [view queryString: @"DELETE FROM 'maps_#' WHERE sequence=?"],
                                                 @(oldSequence)];
                            int changes = fmdb.changes;
                            deletedCount += changes;
                            viewTotalRows[@(view.viewID)] =
                                @([viewTotalRows[@(view.viewID)] intValue] - changes);
                        }
                        if (deleted || CBLCompareRevIDs(oldRevID, revID) > 0) {
                            // It still 'wins' the conflict, so it's the one that
                            // should be mapped [again], not the current revision!
                            revID = oldRevID;
                            deleted = NO;
                            sequence = oldSequence;
                            json = [fmdb dataForQuery: @"SELECT json FROM revs WHERE sequence=?",
                                    @(sequence)];
                        }
                        if (!deleted) {
                            // Conflict revisions:
                            if (!conflicts)
                                conflicts = $marray();
                            [conflicts addObject: oldRevID];
                            while ([r2 next])
                                [conflicts addObject: [r2 stringForColumnIndex:0]];
                        }
                    }
                    [r2 close];
                }

                if (deleted)
                    continue;

                // Get the document properties, to pass to the map function:
                curDoc = [dbStorage documentPropertiesFromJSON: json
                                                    docID: docID revID:revID
                                                  deleted: NO
                                                 sequence: sequence];
                if (!curDoc) {
                    Warn(@"Failed to parse JSON of doc %@ rev %@", docID, revID);
                    continue;
                }
                curDoc[@"_local_seq"] = @(sequence);

                if (conflicts)
                    curDoc[@"_conflicts"] = conflicts;

                // Call the user-defined map() to emit new key/value pairs from this revision:
                int i = -1;
                for (curView in views) {
                    ++i;
                    if (viewLastSequence[i] < realSequence) {
                        if (checkDocTypes) {
                            NSString* viewDocType = viewDocTypes[curView.name];
                            if (viewDocType && ![viewDocType isEqual: docType])
                                continue; // skip; view's documentType doesn't match this doc
                        }
                        LogVerbose(View, @"#%lld: map \"%@\" for view %@...",
                              sequence, docID, curView.name);
                        @try {
                            ((CBLMapBlock)mapBlocks[i])(curDoc, emit);
                        } @catch (NSException* x) {
                            MYReportException(x, @"map block of view %@, on doc %@",
                                              curView.name, curDoc);
                            // don't abort; continue to next doc
                        }
                        if (CBLStatusIsError(emitStatus)) {
                            [r close];
                            return emitStatus;
                        }
                    }
                }
                curView = nil;
            }
        }
        [r close];
        
        // Finally, record the last revision sequence number that was indexed and update #rows:
        for (CBL_SQLiteViewStorage* view in views) {
            [view finishCreatingIndex];
            int newTotalRows = [viewTotalRows[@(view.viewID)] intValue];
            Assert(newTotalRows >= 0);
            if (![fmdb executeUpdate: @"UPDATE views SET lastSequence=?, total_docs=? WHERE view_id=?",
                                       @(dbMaxSequence), @(newTotalRows), @(view.viewID)])
                return dbStorage.lastDbError;
        }
        
        LogTo(View, @"...Finished re-indexing (%@) to #%lld (deleted %u, added %u)",
              viewNames(views), dbMaxSequence, deletedCount, insertedCount);
        return kCBLStatusOK;
    }];
    
    if (status >= kCBLStatusBadRequest)
        Warn(@"CouchbaseLite: Failed to rebuild views (%@): %d", viewNames(inputViews), status);
    return status;
}


/** The body of the emit() callback while indexing a view. */
- (CBLStatus) _emitKey: (UU id)key
                 value: (UU id)value
            valueIsDoc: (BOOL)valueIsDoc
           forSequence: (SequenceNumber)sequence
{
    CBL_SQLiteStorage* dbStorage = _dbStorage;
    CBL_FMDatabase* fmdb = dbStorage.fmdb;
    NSData* valueJSON;
    if (valueIsDoc)
        valueJSON = [[NSData alloc] initWithBytes: "*" length: 1];
    else
        valueJSON = toJSONData(value);

    NSNumber* fullTextID = nil, *bboxID = nil;
    NSData* keyJSON;
    NSData* geoKey = nil;
    if ([key isKindOfClass: [CBLSpecialKey class]]) {
        CBLSpecialKey *specialKey = key;
        LogVerbose(View, @"    emit(%@, %@)", specialKey, valueJSON.my_UTF8ToString);
        BOOL ok;
        NSString* text = specialKey.text;
        if (text) {
            if (![self createFullTextSchema])
                return kCBLStatusNotImplemented;
            ok = [fmdb executeUpdate: @"INSERT INTO fulltext (content) VALUES (?)", text];
            fullTextID = @(fmdb.lastInsertRowId);
        } else {
            if (![self createRTreeSchema])
                return kCBLStatusNotImplemented;
            CBLGeoRect rect = specialKey.rect;
            ok = [fmdb executeUpdate: @"INSERT INTO bboxes (x0,y0,x1,y1) VALUES (?,?,?,?)",
                  @(rect.min.x), @(rect.min.y), @(rect.max.x), @(rect.max.y)];
            bboxID = @(fmdb.lastInsertRowId);
            geoKey = specialKey.geoJSONData;
        }
        if (!ok)
            return dbStorage.lastDbError;
        key = nil;
    } else {
        if (!key) {
            Warn(@"emit() called with nil key; ignoring");
            return kCBLStatusOK;
        }
        keyJSON = toJSONData(key);
        LogVerbose(View, @"    emit(%@, %@)", keyJSON.my_UTF8ToString, valueJSON.my_UTF8ToString);
    }

    if (!keyJSON)
        keyJSON = [[NSData alloc] initWithBytes: "null" length: 4];

    if (!_emitSQL)
        _emitSQL = [self queryString: @"INSERT INTO 'maps_#' (sequence, key, value, "
                                       "fulltext_id, bbox_id, geokey) VALUES (?, ?, ?, ?, ?, ?)"];

    fmdb.bindNSDataAsString = YES;
    BOOL ok = [fmdb executeUpdate: _emitSQL, @(sequence), keyJSON, valueJSON,
                                             fullTextID, bboxID, geoKey];
    fmdb.bindNSDataAsString = NO;
    return ok ? kCBLStatusOK : dbStorage.lastDbError;
}


static NSString* viewNames(NSArray* views) {
    return [[views my_map: ^(CBL_SQLiteViewStorage* view) {return view.name;}] componentsJoinedByString: @", "];
}


#pragma mark - QUERYING:


/** Main internal call to query a view. */
- (CBLQueryEnumerator*) queryWithOptions: (CBLQueryOptions*)options
                                  status: (CBLStatus*)outStatus
{
    SequenceNumber lastSeq = self.lastSequenceIndexed;
    NSArray* rows;
    if (options.fullTextQuery)
        rows = [self fullTextQueryWithOptions: options status: outStatus];
    else if ([self groupOrReduceWithOptions: options])
        rows = [self reducedQueryWithOptions: options status: outStatus];
    else
        rows = [self regularQueryWithOptions: options status: outStatus];

    if (!rows)
        return nil;
    return [[CBLQueryEnumerator alloc] initWithSequenceNumber: lastSeq rows: rows];
    //OPT: Return objects from enum as they're found, without collecting them in an array first
}


// Should this query be run as grouped/reduced?
- (BOOL) groupOrReduceWithOptions: (CBLQueryOptions*) options {
    if (options->group || options->groupLevel > 0)
        return YES;
    else if (options->reduceSpecified)
        return options->reduce;
    else
        return (_delegate.reduceBlock != nil); // Reduce defaults to true iff there's a reduce block
}


typedef CBLStatus (^QueryRowBlock)(NSData* keyData, NSData* valueData, NSString* docID,
                                   CBL_FMResultSet* r);


/** Generates and runs the SQL SELECT statement for a view query, calling the onRow callback. */
- (CBLStatus) _runQueryWithOptions: (const CBLQueryOptions*)options
                             onRow: (QueryRowBlock)onRow
{
    // OPT: It would be faster to use separate tables for raw-or ascii-collated views so that
    // they could be indexed with the right collation, instead of having to specify it here.
    NSString* collationStr = @"";
    if (_collation == kCBLViewCollationASCII)
        collationStr = @" COLLATE JSON_ASCII";
    else if (_collation == kCBLViewCollationRaw)
        collationStr = @" COLLATE JSON_RAW";

    NSMutableString* sql = [NSMutableString stringWithString: @"SELECT key, value, docid, revs.sequence"];
    if (options->includeDocs)
        [sql appendString: @", revid, json"];
    if (options->bbox) {
        if (![self createRTreeSchema])
            return kCBLStatusNotImplemented;
        [sql appendFormat: @", bboxes.x0, bboxes.y0, bboxes.x1, bboxes.y1, maps_%@.geokey",
                                 self.mapTableName];
    }
    [sql appendFormat: @" FROM 'maps_%@', revs, docs", self.mapTableName];
    if (options->bbox)
        [sql appendString: @", bboxes"];
    [sql appendString: @" WHERE 1"];
    NSMutableArray* args = $marray();

    if (options.keys) {
        [sql appendString:@" AND key in ("];
        NSString* item = @"?";
        for (NSString * key in options.keys) {
            [sql appendString: item];
            item = @",?";
            [args addObject: toJSONData(key)];
        }
        [sql appendString:@")"];
    }

    id minKey = options.minKey, maxKey = options.maxKey;
    NSString* minKeyDocID = options.startKeyDocID;
    NSString* maxKeyDocID = options.endKeyDocID;
    BOOL inclusiveMin = options->inclusiveStart, inclusiveMax = options->inclusiveEnd;
    if (options->descending) {
        inclusiveMin = options->inclusiveEnd;
        inclusiveMax = options->inclusiveStart;
        minKeyDocID = options.endKeyDocID;
        maxKeyDocID = options.startKeyDocID;
    }

    if (minKey) {
        NSData* minKeyData = toJSONData(minKey);
        [sql appendString: (inclusiveMin ? @" AND key >= ?" : @" AND key > ?")];
        [sql appendString: collationStr];
        [args addObject: minKeyData];
        if (minKeyDocID && inclusiveMin) {
            //OPT: This calls the JSON collator a 2nd time unnecessarily.
            [sql appendFormat: @" AND (key > ? %@ OR docid >= ?)", collationStr];
            [args addObject: minKeyData];
            [args addObject: minKeyDocID];
        }
    }
    if (maxKey) {
        NSData* maxKeyData = toJSONData(maxKey);
        [sql appendString: (inclusiveMax ? @" AND key <= ?" :  @" AND key < ?")];
        [sql appendString: collationStr];
        [args addObject: maxKeyData];
        if (maxKeyDocID && inclusiveMax) {
            [sql appendFormat: @" AND (key < ? %@ OR docid <= ?)", collationStr];
            [args addObject: maxKeyData];
            [args addObject: maxKeyDocID];
        }
    }

    if (options->bbox) {
        [sql appendFormat: @" AND (bboxes.x1 > ? AND bboxes.x0 < ?)"
                            " AND (bboxes.y1 > ? AND bboxes.y0 < ?)"
                            " AND bboxes.rowid = 'maps_%@'.bbox_id", self.mapTableName];
        [args addObject: @(options->bbox->min.x)];
        [args addObject: @(options->bbox->max.x)];
        [args addObject: @(options->bbox->min.y)];
        [args addObject: @(options->bbox->max.y)];
    }
    
    [sql appendFormat: @" AND revs.sequence = 'maps_%@'.sequence AND docs.doc_id = revs.doc_id "
                        "ORDER BY", self.mapTableName];
    if (options->bbox)
        [sql appendString: @" bboxes.y0, bboxes.x0"];
    else
        [sql appendString: @" key"];
    [sql appendString: collationStr];
    if (options->descending)
        [sql appendString: @" DESC"];
    [sql appendString: (options->descending ? @", docid DESC" : @", docid")];

    [sql appendString: @" LIMIT ? OFFSET ?"];
    int limit = (options->limit != kCBLQueryOptionsDefaultLimit) ? options->limit : -1;
    [args addObject: @(limit)];
    [args addObject: @(options->skip)];

    LogTo(Query, @"Query %@: %@\n\tArguments: %@", _name, sql, args);
    
    CBL_SQLiteStorage* dbStorage = _dbStorage;
    CBL_FMDatabase* fmdb = dbStorage.fmdb;
    fmdb.bindNSDataAsString = YES;
    CBL_FMResultSet* r = [fmdb executeQuery: sql withArgumentsInArray: args];
    fmdb.bindNSDataAsString = NO;
    if (!r)
        return dbStorage.lastDbError;

    // Now run the query and iterate over its rows:
    CBLStatus status = kCBLStatusOK;
    while ([r next]) {
        @autoreleasepool {
            NSData* keyData = [r dataForColumnIndex: 0];
            NSString* docID = [r stringForColumnIndex: 2];
            Assert(keyData);

            // Call the block!
            NSData* valueData = [r dataForColumnIndex: 1];
            status = onRow(keyData, valueData, docID, r);
            if (CBLStatusIsError(status))
                break;
            else if (status <= 0) {     // block can return 0 to stop the iteration without an error
                status = kCBLStatusOK;
                break;
            }
        }
    }
    [r close];
    return status;
}


- (NSArray*) regularQueryWithOptions: (CBLQueryOptions*)options
                              status: (CBLStatus*)outStatus
{
    CBL_SQLiteStorage* db = _dbStorage;

    CBLQueryRowFilter filter = options.filter;
    __block unsigned limit = UINT_MAX;
    __block unsigned skip = 0;
    if (filter) {
        // #574: Custom post-filter means skip/limit apply to the filtered rows, not to the
        // underlying query, so handle them specially:
        limit = options->limit;
        skip = options->skip;
        options->limit = kCBLQueryOptionsDefaultLimit;
        options->skip = 0;
    }

    NSMutableArray* rows = $marray();
    *outStatus = [self _runQueryWithOptions: options
                                      onRow: ^CBLStatus(NSData* keyData, NSData* valueData,
                                                        NSString* docID,
                                                        CBL_FMResultSet *r)
    {
        SequenceNumber sequence = [r longLongIntForColumnIndex:3];
        CBL_Revision* docRevision = nil;
        if (options->includeDocs) {
            NSDictionary* value = nil;
            if (valueData && !CBLQueryRowValueIsEntireDoc(valueData))
                value = $castIf(NSDictionary, fromJSON(valueData));
            NSString* linkedID = value.cbl_id;
            if (linkedID) {
                // Linked document: http://wiki.apache.org/couchdb/Introduction_to_CouchDB_views#Linked_documents
                NSString* linkedRev = value.cbl_rev; // usually nil
                CBLStatus linkedStatus;
                docRevision = [db getDocumentWithID: linkedID
                                         revisionID: linkedRev
                                           withBody: YES
                                             status: &linkedStatus];
                sequence = docRevision.sequence;
            } else {
                docRevision = [_dbStorage revisionWithDocID: docID
                                                      revID: [r stringForColumnIndex: 4]
                                                    deleted: NO
                                                   sequence: sequence
                                                       json: [r dataForColumnIndex: 5]];
            }
        }
        LogVerbose(Query, @"Query %@: Found row with key=%@, value=%@, id=%@",
              _name, [keyData my_UTF8ToString], [valueData my_UTF8ToString],
              toJSONString(docID));
        CBLQueryRow* row;
        if (options->bbox) {
            CBLGeoRect bbox = {{[r doubleForColumn: @"x0"],
                                [r doubleForColumn: @"y0"]},
                               {[r doubleForColumn: @"x1"],
                                [r doubleForColumn: @"y1"]}};
            row = [[CBLGeoQueryRow alloc] initWithDocID: docID
                                               sequence: sequence
                                            boundingBox: bbox
                                            geoJSONData: [r dataForColumn: @"geokey"]
                                                  value: valueData
                                            docRevision: docRevision];
        } else {
            row = [[CBLQueryRow alloc] initWithDocID: docID
                                            sequence: sequence
                                                 key: keyData
                                               value: valueData
                                         docRevision: docRevision];
        }

        if (filter) {
            if (![self row: row passesFilter: filter])
                return kCBLStatusOK;
            if (skip > 0) {
                --skip;
                return kCBLStatusOK;
            }
        }
        
        [rows addObject: row];

        if (--limit == 0)
            return 0;  // stops the iteration
        return kCBLStatusOK;
    }];

    // If given keys, sort the output into that order, and add entries for missing keys:
    if (options.keys) {
        // Group rows by key:
        NSMutableDictionary* rowsByKey = $mdict();
        for (CBLQueryRow* row in rows) {
            NSMutableArray* rows = rowsByKey[row.key];
            if (!rows)
                rows = rowsByKey[row.key] = [[NSMutableArray alloc] init];
            [rows addObject: row];
        }
        // Now concatenate them in the order the keys are given in options:
        NSMutableArray* sortedRows = $marray();
        for (NSString* key in options.keys) {
            NSArray* rows = rowsByKey[key];
            if (rows)
                [sortedRows addObjectsFromArray: rows];
        }
        rows = sortedRows;
    }
    return rows;
}


/** Runs a full-text query of a view, using the FTS4 table. */
- (NSArray*) fullTextQueryWithOptions: (const CBLQueryOptions*)options
                               status: (CBLStatus*)outStatus
{
    if (![self createFullTextSchema]) {
        *outStatus = kCBLStatusNotImplemented;
        return nil;
    }
    NSMutableString* sql = [@"SELECT docs.docid, 'maps_#'.sequence, 'maps_#'.fulltext_id, 'maps_#'.value, "
                             "offsets(fulltext)" mutableCopy];
    if (options->fullTextSnippets)
        [sql appendString: @", snippet(fulltext, '\001','\002','…')"];
    [sql appendString: @" FROM 'maps_#', fulltext, revs, docs "
                        "WHERE fulltext.content MATCH ? AND 'maps_#'.fulltext_id = fulltext.rowid "
                        "AND revs.sequence = 'maps_#'.sequence AND docs.doc_id = revs.doc_id "];
    if (options->fullTextRanking)
        [sql appendString: @"ORDER BY - ftsrank(matchinfo(fulltext)) "];
    else
        [sql appendString: @"ORDER BY 'maps_#'.sequence "];
    if (options->descending)
        [sql appendString: @" DESC"];
    [sql appendString: @" LIMIT ? OFFSET ?"];
    int limit = (options->limit != kCBLQueryOptionsDefaultLimit) ? options->limit : -1;
    CBLQueryRowFilter filter = options.filter;

    CBL_SQLiteStorage* dbStorage = _dbStorage;
    CBL_FMResultSet* r = [dbStorage.fmdb executeQuery: [self queryString: sql],
                                                options.fullTextQuery,
                                                @(limit), @(options->skip)];
    if (!r) {
        if (dbStorage.fmdb.lastErrorCode == SQLITE_ERROR)
            *outStatus = kCBLStatusBadRequest;      // SQLITE_ERROR means invalid FTS query string
        else
            *outStatus = dbStorage.lastDbError;
        return nil;
    }
    NSMutableArray* rows = [[NSMutableArray alloc] init];
    while ([r next]) {
        @autoreleasepool {
            NSString* docID = [r stringForColumnIndex: 0];
            SequenceNumber sequence = [r longLongIntForColumnIndex: 1];
            UInt64 fulltextID = [r longLongIntForColumnIndex: 2];
            NSData* valueData = [r dataForColumnIndex: 3];
            CBLFullTextQueryRow* row = [[CBLFullTextQueryRow alloc] initWithDocID: docID
                                                                         sequence: sequence
                                                                       fullTextID: fulltextID
                                                                            value: valueData];
            // Parse the offsets as a space-delimited list of numbers, into an NSArray.
            // (See http://sqlite.org/fts3.html#section_4_1 )
            NSArray* offsets = [[r stringForColumnIndex: 4] componentsSeparatedByString: @" "];
            for (NSUInteger i = 0; i+3 < offsets.count; i += 4) {
                NSUInteger term     = [offsets[i+1] integerValue];
                NSUInteger location = [offsets[i+2] integerValue];
                NSUInteger length   = [offsets[i+3] integerValue];
                [row addTerm: term atRange: NSMakeRange(location, length)];
            }

            if (options->fullTextSnippets)
                row.snippet = [r stringForColumnIndex: 5];
            if (!filter || [self row: row passesFilter: filter])
                [rows addObject: row];
        }
    }
    return rows;
}


- (BOOL) row: (CBLQueryRow*)row passesFilter: (CBLQueryRowFilter)filter {
    //FIX: I'm not supposed to know the delegates' real classes...
    [row moveToDatabase: _dbStorage.delegate view: _delegate];
    if (!filter(row))
        return NO;
    [row _clearDatabase];
    return YES;
}


#ifndef MY_DISABLE_LOGGING
static inline NSString* toJSONString( id object ) {
    if (!object)
        return nil;
    return [CBLJSON stringWithJSONObject: object
                                 options: CBLJSONWritingAllowFragments
                                   error: NULL];
}

static inline NSData* toJSONData( id object ) {
    if (!object)
        return nil;
    NSError* error;
    NSData* json = [CBLJSON dataWithJSONObject: object
                                       options: CBLJSONWritingAllowFragments
                                         error: &error];
    if (!json)
        Warn(@"Could not convert key/value to JSON: %@ -- %@", object, error.my_compactDescription);
    return json;
}

static id fromJSON( NSData* json ) {
    if (!json)
        return nil;
    return [CBLJSON JSONObjectWithData: json
                               options: CBLJSONReadingAllowFragments
                                 error: NULL];
}
#endif


#pragma mark - REDUCING/GROUPING:


// Are key1 and key2 grouped together at this groupLevel?
static bool groupTogether(NSData* key1, NSData* key2, unsigned groupLevel) {
    if (!key1 || !key2)
        return NO;
    if (groupLevel == 0)
        groupLevel = UINT_MAX;
    return CBLCollateJSONLimited(kCBLCollateJSON_Unicode,
                                (int)key1.length, key1.bytes,
                                (int)key2.length, key2.bytes,
                                groupLevel) == 0;
}

// Returns the prefix of the key to use in the result row, at this groupLevel
static id groupKey(NSData* keyJSON, unsigned groupLevel) {
    id key = fromJSON(keyJSON);
    if (groupLevel > 0 && [key isKindOfClass: [NSArray class]] && [key count] > groupLevel)
        return [key subarrayWithRange: NSMakeRange(0, groupLevel)];
    else
        return key;
}


// Invokes the reduce function on the parallel arrays of keys and values
static id callReduce(CBLReduceBlock reduceBlock, NSMutableArray* keys, NSMutableArray* values) {
    if (!reduceBlock)
        return nil;
    CBLLazyArrayOfJSON* lazyKeys = [[CBLLazyArrayOfJSON alloc] initWithMutableArray: keys];
    CBLLazyArrayOfJSON* lazyVals = [[CBLLazyArrayOfJSON alloc] initWithMutableArray: values];
    @try {
        id result = reduceBlock(lazyKeys, lazyVals, NO);
        if (result)
            return result;
    } @catch (NSException *x) {
        MYReportException(x, @"reduce block");
    }
    return $null;
}


- (NSArray*) reducedQueryWithOptions: (CBLQueryOptions*)options
                              status: (CBLStatus*)outStatus
{
    CBL_SQLiteStorage* db = _dbStorage;
    CBLQueryRowFilter filter = options.filter;
    unsigned groupLevel = options->groupLevel;
    bool group = options->group || groupLevel > 0;
    CBLReduceBlock reduce = _delegate.reduceBlock;
    if (options->reduceSpecified) {
        if (options->reduce && !reduce) {
            Warn(@"Cannot use reduce option in view %@ which has no reduce block defined",
                 _name);
            *outStatus = kCBLStatusBadParam;
            return nil;
        }
    }

    NSMutableArray* keysToReduce = nil, *valuesToReduce = nil;
    if (reduce) {
        keysToReduce = [[NSMutableArray alloc] initWithCapacity: 100];
        valuesToReduce = [[NSMutableArray alloc] initWithCapacity: 100];
    }
    __block NSData* lastKeyData = nil;

    NSMutableArray* rows = $marray();
    *outStatus = [self _runQueryWithOptions: options
                                      onRow: ^CBLStatus(NSData* keyData, NSData* valueData,
                                                        NSString* docID,
                                                        CBL_FMResultSet *r)
    {
        if (group && !groupTogether(keyData, lastKeyData, groupLevel)) {
            if (lastKeyData) {
                // This pair starts a new group, so reduce & record the last one:
                id key = groupKey(lastKeyData, groupLevel);
                id reduced = callReduce(reduce, keysToReduce, valuesToReduce);
                CBLQueryRow* row = [[CBLQueryRow alloc] initWithDocID: nil
                                                             sequence: 0
                                                                  key: key
                                                                value: reduced
                                                          docRevision: nil];
                if (!filter || [self row: row passesFilter: filter])
                    [rows addObject: row];
                [keysToReduce removeAllObjects];
                [valuesToReduce removeAllObjects];
            }
            lastKeyData = [keyData copy];
        }
        LogVerbose(Query, @"Query %@: Will reduce row with key=%@, value=%@",
              _name, [keyData my_UTF8ToString], [valueData my_UTF8ToString]);

        id valueOrData = valueData;
        if (valuesToReduce && CBLQueryRowValueIsEntireDoc(valueData)) {
            // map fn emitted 'doc' as value, which was stored as a "*" placeholder; expand now:
            CBLStatus status;
            CBL_Revision* rev = [db getDocumentWithID: docID
                                             sequence: [r longLongIntForColumnIndex:3]
                                               status: &status];
            if (!rev)
                Warn(@"%@: Couldn't load doc for row value: status %d", self, status);
            valueOrData = rev.properties;
        }

        [keysToReduce addObject: keyData];
        [valuesToReduce addObject: valueOrData ?: $null];
        return kCBLStatusOK;
    }];
    
    if (keysToReduce.count > 0 || lastKeyData) {
        // Finish the last group (or the entire list, if no grouping):
        id key = group ? groupKey(lastKeyData, groupLevel) : $null;
        id reduced = callReduce(reduce, keysToReduce, valuesToReduce);
        LogVerbose(Query, @"Query %@: Reduced to key=%@, value=%@",
              _name, toJSONString(key), toJSONString(reduced));
        CBLQueryRow* row = [[CBLQueryRow alloc] initWithDocID: nil
                                                     sequence: 0
                                                          key: key
                                                        value: reduced
                                                  docRevision: nil];
        if (!filter || [self row: row passesFilter: filter])
            [rows addObject: row];
    }
    return rows;
}


// This is really just for unit tests & debugging
#if DEBUG
- (NSArray*) dump {
    if (self.viewID <= 0)
        return nil;

    CBL_FMResultSet* r = [_dbStorage.fmdb executeQuery:
                          [self queryString: @"SELECT sequence, key, value FROM 'maps_#' "
                                                      "ORDER BY key"]];
    if (!r)
        return nil;
    NSMutableArray* result = $marray();
    while ([r next]) {
        [result addObject: $dict({@"seq", [r objectForColumnIndex: 0]},
                                 {@"key", [r stringForColumnIndex: 1]},
                                 {@"value", [r stringForColumnIndex: 2]})];
    }
    [r close];
    return result;
}
#endif


#pragma mark - CBL_QueryRowStorage API:


- (id<CBL_QueryRowStorage>) storageForQueryRow: (CBLQueryRow*)row {
    return self;
}


- (NSDictionary*) documentPropertiesWithID: (NSString*)docID
                                  sequence: (SequenceNumber)sequence
                                    status: (CBLStatus*)outStatus
{
    return [_dbStorage getDocumentWithID: docID sequence: sequence status: outStatus].properties;
}


- (NSData*) fullTextForDocument: (NSString*)docID
                       sequence: (SequenceNumber)sequence
                     fullTextID: (UInt64)fullTextID
{
    if (fullTextID == 0)
        return nil;
    return [_dbStorage.fmdb dataForQuery: @"SELECT content FROM fulltext WHERE rowid=?",
            @(fullTextID)];
}


@end
