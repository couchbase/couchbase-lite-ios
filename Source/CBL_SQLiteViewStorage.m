//
//  CBL_SQLiteViewStorage.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/16/15.
//
//

#import "CBL_SQLiteViewStorage.h"
#import "CBL_SQLiteStorage.h"
#import "CBLSpecialKey.h"
#import "CBLQuery+FullTextSearch.h"
#import "CBLQuery+Geo.h"
#import "CBLCollateJSON.h"
#import "CouchbaseLitePrivate.h"
#import "CBLInternal.h"
#import "ExceptionUtils.h"

#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "FMResultSet.h"


@implementation CBL_SQLiteViewStorage
{
    __weak CBL_SQLiteStorage* _dbStorage;
    int _viewID;
    CBLViewCollation _collation;
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
    if (fmdb.changes)
        return YES;     // created new view
    if (![fmdb executeUpdate: @"UPDATE views SET version=?, lastSequence=0, total_docs=0 "
          "WHERE name=? AND version!=?",
          version, _name, version]) {
        return NO;
    }
    return YES;
}


- (void) deleteIndex {
    if (self.viewID <= 0)
        return;
    CBL_SQLiteStorage* db = _dbStorage;
    CBLStatus status = [db inTransaction: ^CBLStatus {
        if ([db.fmdb executeUpdate: @"DELETE FROM maps WHERE view_id=?",
                                     @(_viewID)]) {
            [db.fmdb executeUpdate: @"UPDATE views SET lastsequence=0, total_docs=0 WHERE view_id=?",
                                     @(_viewID)];
        }
        return db.lastDbStatus;
    }];
    if (CBLStatusIsError(status))
        Warn(@"Error status %d removing index of %@", status, self);
}


- (void) deleteView {
    [_dbStorage.fmdb executeUpdate: @"DELETE FROM views WHERE name=?", _name];
    _viewID = 0;
}


- (int) viewID {
    if (_viewID < 0)
        _viewID = [_dbStorage.fmdb intForQuery: @"SELECT view_id FROM views WHERE name=?", _name];
    return _viewID;
}


- (NSUInteger) totalRows {
    CBL_FMDatabase* fmdb = _dbStorage.fmdb;
    NSInteger totalRows = [fmdb intForQuery: @"SELECT total_docs FROM views WHERE name=?", _name];
    if (totalRows == -1) { // means unknown
        totalRows = [fmdb intForQuery: @"SELECT COUNT(view_id) FROM maps WHERE view_id=?",
                                        @(self.viewID)];
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
        unsigned deleted = 0;
        int i = 0;
        NSMutableDictionary* viewTotalRows = [[NSMutableDictionary alloc] init];
        NSMutableArray* views = [[NSMutableArray alloc] initWithCapacity: inputViews.count];
        NSMutableArray* mapBlocks = [[NSMutableArray alloc] initWithCapacity: inputViews.count];
        for (CBL_SQLiteViewStorage* view in inputViews) {
            CBLMapBlock mapBlock = view.delegate.mapBlock;
            if (mapBlock == NULL) {
                Assert(view != self,
                       @"Cannot index view %@: no map block registered",
                       view.name);
                LogTo(ViewVerbose, @"    %@ has no map block; skipping it", view.name);
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
                minLastSequence = MIN(minLastSequence, last);
                LogTo(ViewVerbose, @"    %@ last indexed at #%lld", view.name, last);
                BOOL ok;
                if (last == 0) {
                    // If the lastSequence has been reset to 0, make sure to remove all map results:
                    ok = [fmdb executeUpdate: @"DELETE FROM maps WHERE view_id=?", @(viewID)];
                } else {
                    // Delete all obsolete map results (ones from since-replaced revisions):
                    ok = [fmdb executeUpdate: @"DELETE FROM maps WHERE view_id=? AND sequence IN ("
                                                    "SELECT parent FROM revs WHERE sequence>? "
                                                        "AND parent>0 AND parent<=?)",
                                              @(viewID), @(last), @(last)];
                }
                if (!ok)
                    return dbStorage.lastDbError;
                
                // Update #deleted rows
                int changes = fmdb.changes;
                deleted += changes;
                
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
        __block NSDictionary* curDoc;
        __block SequenceNumber sequence = minLastSequence;
        __block CBLStatus emitStatus = kCBLStatusOK;
        __block unsigned inserted = 0;
        CBLMapEmitBlock emit = ^(id key, id value) {
            int status = [curView _emitKey: key
                                     value: value
                                valueIsDoc: (value == curDoc)
                               forSequence: sequence];
            if (status != kCBLStatusOK)
                emitStatus = status;
            else {
                viewTotalRows[@(curView.viewID)] = @([viewTotalRows[@(curView.viewID)] intValue] + 1);
                inserted++;
            }
        };

        // Now scan every revision added since the last time the views were indexed:
        CBL_FMResultSet* r;
        r = [fmdb executeQuery: @"SELECT revs.doc_id, sequence, docid, revid, json, no_attachments "
                                 "FROM revs, docs "
                                 "WHERE sequence>? AND current!=0 AND deleted=0 "
                                 "AND revs.doc_id = docs.doc_id "
                                 "ORDER BY revs.doc_id, revid DESC",
                                 @(minLastSequence)];
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
                BOOL noAttachments = [r boolForColumnIndex: 5];
            
                // Skip rows with the same doc_id -- these are losing conflicts.
                while ((keepGoing = [r next]) && [r longLongIntForColumnIndex: 0] == doc_id) {
                }

                SequenceNumber realSequence = sequence; // because sequence may be changed, below
                if (minLastSequence > 0) {
                    // Find conflicts with documents from previous indexings.
                    CBL_FMResultSet* r2 = [fmdb executeQuery:
                                    @"SELECT revid, sequence FROM revs "
                                     "WHERE doc_id=? AND sequence<=? AND current!=0 AND deleted=0 "
                                     "ORDER BY revID DESC "
                                     "LIMIT 1",
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
                            [fmdb executeUpdate: @"DELETE FROM maps WHERE view_id=? AND sequence=?",
                                                 @(view.viewID), @(oldSequence)];
                            int changes = fmdb.changes;
                            deleted += changes;
                            viewTotalRows[@(view.viewID)] =
                                @([viewTotalRows[@(view.viewID)] intValue] - changes);
                        }
                        if (CBLCompareRevIDs(oldRevID, revID) > 0) {
                            // It still 'wins' the conflict, so it's the one that
                            // should be mapped [again], not the current revision!
                            revID = oldRevID;
                            sequence = oldSequence;
                            json = [fmdb dataForQuery: @"SELECT json FROM revs WHERE sequence=?",
                                    @(sequence)];
                        }
                    }
                    [r2 close];
                }
                
                // Get the document properties, to pass to the map function:
                CBLContentOptions contentOptions = kCBLIncludeLocalSeq;
                if (noAttachments)
                    contentOptions |= kCBLNoAttachments;
                curDoc = [dbStorage documentPropertiesFromJSON: json
                                                    docID: docID revID:revID
                                                  deleted: NO
                                                 sequence: sequence
                                                  options: contentOptions];
                if (!curDoc) {
                    Warn(@"Failed to parse JSON of doc %@ rev %@", docID, revID);
                    continue;
                }
                
                // Call the user-defined map() to emit new key/value pairs from this revision:
                int i = 0;
                for (curView in views) {
                    if (viewLastSequence[i] < realSequence) {
                        LogTo(ViewVerbose, @"#%lld: map \"%@\" for view %@...",
                              sequence, docID, curView.name);
                        @try {
                            ((CBLMapBlock)mapBlocks[i])(curDoc, emit);
                        } @catch (NSException* x) {
                            MYReportException(x, @"map block of view '%@'", curView.name);
                            emitStatus = kCBLStatusCallbackError;
                        }
                        if (CBLStatusIsError(emitStatus)) {
                            [r close];
                            return emitStatus;
                        }
                    }
                    ++i;
                }
                curView = nil;
            }
        }
        [r close];
        
        // Finally, record the last revision sequence number that was indexed and update #rows:
        for (CBL_SQLiteViewStorage* view in views) {
            int newTotalRows = [viewTotalRows[@(view.viewID)] intValue];
            Assert(newTotalRows >= 0);
            if (![fmdb executeUpdate: @"UPDATE views SET lastSequence=?, total_docs=? WHERE view_id=?",
                                       @(dbMaxSequence), @(newTotalRows), @(view.viewID)])
                return dbStorage.lastDbError;
        }
        
        LogTo(View, @"...Finished re-indexing (%@) to #%lld (deleted %u, added %u)",
              viewNames(views), dbMaxSequence, deleted, inserted);
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
        LogTo(ViewVerbose, @"    emit(%@, %@)", specialKey, valueJSON.my_UTF8ToString);
        BOOL ok;
        NSString* text = specialKey.text;
        if (text) {
            ok = [fmdb executeUpdate: @"INSERT INTO fulltext (content) VALUES (?)", text];
            fullTextID = @(fmdb.lastInsertRowId);
        } else {
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
        keyJSON = toJSONData(key);
        LogTo(ViewVerbose, @"    emit(%@, %@)", keyJSON.my_UTF8ToString, valueJSON.my_UTF8ToString);
    }

    if (!keyJSON)
        keyJSON = [[NSData alloc] initWithBytes: "null" length: 4];

    fmdb.bindNSDataAsString = YES;
    BOOL ok = [fmdb executeUpdate: @"INSERT INTO maps (view_id, sequence, key, value, "
                                   "fulltext_id, bbox_id, geokey) VALUES (?, ?, ?, ?, ?, ?, ?)",
                                  @(self.viewID), @(sequence), keyJSON, valueJSON,
                                  fullTextID, bboxID, geoKey];
    fmdb.bindNSDataAsString = NO;
    return ok ? kCBLStatusOK : dbStorage.lastDbError;
}


static NSString* viewNames(NSArray* views) {
    return [[views my_map: ^(CBL_SQLiteViewStorage* view) {return view.name;}] componentsJoinedByString: @", "];
}


#pragma mark - QUERYING:


typedef CBLStatus (^QueryRowBlock)(NSData* keyData, NSData* valueData, NSString* docID,
                                   CBL_FMResultSet* r);


/** Generates and runs the SQL SELECT statement for a view query, calling the onRow callback. */
- (CBLStatus) _runQueryWithOptions: (const CBLQueryOptions*)options
                             onRow: (QueryRowBlock)onRow
{
    if (!options)
        options = [CBLQueryOptions new];

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
    if (options->bbox)
        [sql appendString: @", bboxes.x0, bboxes.y0, bboxes.x1, bboxes.y1, maps.geokey"];
    [sql appendString: @" FROM maps, revs, docs"];
    if (options->bbox)
        [sql appendString: @", bboxes"];
    [sql appendString: @" WHERE maps.view_id=?"];
    NSMutableArray* args = $marray(@(self.viewID));

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

    id minKey = options.startKey, maxKey = options.endKey;
    NSString* minKeyDocID = options.startKeyDocID;
    NSString* maxKeyDocID = options.endKeyDocID;
    BOOL inclusiveMin = options->inclusiveStart, inclusiveMax = options->inclusiveEnd;
    if (options->descending) {
        minKey = options.endKey;
        maxKey = options.startKey;
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
        maxKey = keyForPrefixMatch(maxKey, options->prefixMatchLevel);
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
        [sql appendString: @" AND (bboxes.x1 > ? AND bboxes.x0 < ?)"
                            " AND (bboxes.y1 > ? AND bboxes.y0 < ?)"
                            " AND bboxes.rowid = maps.bbox_id"];
        [args addObject: @(options->bbox->min.x)];
        [args addObject: @(options->bbox->max.x)];
        [args addObject: @(options->bbox->min.y)];
        [args addObject: @(options->bbox->max.y)];
    }
    
    [sql appendString: @" AND revs.sequence = maps.sequence AND docs.doc_id = revs.doc_id "
                        "ORDER BY"];
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

    LogTo(View, @"Query %@: %@\n\tArguments: %@", _name, sql, args);
    
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
        }
    }
    [r close];
    return status;
}


- (CBLQueryIteratorBlock) regularQueryWithOptions: (CBLQueryOptions*)options
                                           status: (CBLStatus*)outStatus
{
    CBL_SQLiteStorage* db = _dbStorage;
    NSMutableArray* rows = $marray();
    *outStatus = [self _runQueryWithOptions: options
                                      onRow: ^CBLStatus(NSData* keyData, NSData* valueData,
                                                        NSString* docID,
                                                        CBL_FMResultSet *r)
    {
        SequenceNumber sequence = [r longLongIntForColumnIndex:3];
        id docContents = nil;
        if (options->includeDocs) {
            NSDictionary* value = nil;
            if (valueData && ![self rowValueIsEntireDoc: valueData])
                value = $castIf(NSDictionary, fromJSON(valueData));
            NSString* linkedID = value.cbl_id;
            if (linkedID) {
                // Linked document: http://wiki.apache.org/couchdb/Introduction_to_CouchDB_views#Linked_documents
                NSString* linkedRev = value.cbl_rev; // usually nil
                CBLStatus linkedStatus;
                CBL_Revision* linked = [db getDocumentWithID: linkedID
                                                  revisionID: linkedRev
                                                     options: options->content
                                                      status: &linkedStatus];
                docContents = linked ? linked.properties : $null;
                sequence = linked.sequence;
            } else {
                docContents = [db documentPropertiesFromJSON: [r dataNoCopyForColumnIndex: 5]
                                                       docID: docID
                                                       revID: [r stringForColumnIndex: 4]
                                                     deleted: NO
                                                    sequence: sequence
                                                     options: options->content];
            }
        }
        LogTo(ViewVerbose, @"Query %@: Found row with key=%@, value=%@, id=%@",
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
                                          docProperties: docContents
                                                storage: self];
        } else {
            row = [[CBLQueryRow alloc] initWithDocID: docID
                                            sequence: sequence
                                                 key: keyData
                                               value: valueData
                                       docProperties: docContents
                                             storage: self];
        }
        
        if (!options.filter || options.filter(row))
            [rows addObject: row];
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

    //OPT: Return objects from enum as they're found, without collecting them in an array first
    return queryIteratorBlockFromArray(rows);
}


/** Runs a full-text query of a view, using the FTS4 table. */
- (CBLQueryIteratorBlock) fullTextQueryWithOptions: (const CBLQueryOptions*)options
                                            status: (CBLStatus*)outStatus
{
    NSMutableString* sql = [@"SELECT docs.docid, maps.sequence, maps.fulltext_id, maps.value, "
                             "offsets(fulltext)" mutableCopy];
    if (options->fullTextSnippets)
        [sql appendString: @", snippet(fulltext, '\001','\002','…')"];
    [sql appendString: @" FROM maps, fulltext, revs, docs "
                        "WHERE fulltext.content MATCH ? AND maps.fulltext_id = fulltext.rowid "
                        "AND maps.view_id = ? "
                        "AND revs.sequence = maps.sequence AND docs.doc_id = revs.doc_id "];
    if (options->fullTextRanking)
        [sql appendString: @"ORDER BY - ftsrank(matchinfo(fulltext)) "];
    else
        [sql appendString: @"ORDER BY maps.sequence "];
    if (options->descending)
        [sql appendString: @" DESC"];
    [sql appendString: @" LIMIT ? OFFSET ?"];
    int limit = (options->limit != kCBLQueryOptionsDefaultLimit) ? options->limit : -1;

    CBL_SQLiteStorage* dbStorage = _dbStorage;
    CBL_FMResultSet* r = [dbStorage.fmdb executeQuery: sql, options.fullTextQuery, @(self.viewID),
                                                @(limit), @(options->skip)];
    if (!r) {
        *outStatus = dbStorage.lastDbError;
        return nil;
    }
    NSMutableArray* rows = [[NSMutableArray alloc] init];
    while ([r next]) {
        @autoreleasepool {
            NSString* docID = [r stringForColumnIndex: 0];
            SequenceNumber sequence = [r longLongIntForColumnIndex: 1];
            UInt64 fulltextID = [r longLongIntForColumnIndex: 2];
//            NSData* valueData = [r dataForColumnIndex: 3];
            CBLFullTextQueryRow* row = [[CBLFullTextQueryRow alloc] initWithDocID: docID
                                                                         sequence: sequence
                                                                       fullTextID: fulltextID
                                                                          storage: self];
            // Parse the offsets as a space-delimited list of numbers, into an NSArray.
            // (See http://sqlite.org/fts3.html#section_4_1 )
            NSArray* offsets = [[r stringForColumnIndex: 4] componentsSeparatedByString: @" "];
            for (NSUInteger i = 0; i+3 < offsets.count; i += 4) {
                NSUInteger term     = [offsets[i+1] integerValue];
                NSUInteger location = [offsets[i+2] integerValue];
                NSUInteger length   = [offsets[i+3] integerValue];
                [row addTerm: term atRange: NSMakeRange(location, length)];
            }

//            if (options->fullTextSnippets)
//                row.snippet = [r stringForColumnIndex: 5];
            if (!options.filter || options.filter(row))
                [rows addObject: row];
        }
    }

    //OPT: Return objects from enum as they're found, without collecting them in an array first
    return queryIteratorBlockFromArray(rows);
}


// Changes a maxKey into one that also extends to any key it matches as a prefix.
static id keyForPrefixMatch(id key, unsigned depth) {
    if (depth < 1)
        return key;
    if ([key isKindOfClass: [NSString class]]) {
        // Kludge: prefix match a string by appending max possible character value to it
        return [key stringByAppendingString: @"\uffffffff"];
    } else if ([key isKindOfClass: [NSArray class]]) {
        NSMutableArray* nuKey = [key mutableCopy];
        if (depth == 1) {
            [nuKey addObject: @{}];
        } else {
            id lastObject = keyForPrefixMatch(nuKey.lastObject, depth-1);
            [nuKey replaceObjectAtIndex: nuKey.count-1 withObject: lastObject];
        }
        return nuKey;
    } else {
        return key;
    }
}


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
    return [CBLJSON dataWithJSONObject: object
                               options: CBLJSONWritingAllowFragments
                                 error: NULL];
}

static id fromJSON( NSData* json ) {
    if (!json)
        return nil;
    return [CBLJSON JSONObjectWithData: json
                               options: CBLJSONReadingAllowFragments
                                 error: NULL];
}


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


- (CBLQueryIteratorBlock) reducedQueryWithOptions: (CBLQueryOptions*)options
                                           status: (CBLStatus*)outStatus
{
    CBL_SQLiteStorage* db = _dbStorage;
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
                                                        docProperties: nil
                                                              storage: self];
                if (!options.filter || options.filter(row))
                    [rows addObject: row];
                [keysToReduce removeAllObjects];
                [valuesToReduce removeAllObjects];
            }
            lastKeyData = [keyData copy];
        }
        LogTo(ViewVerbose, @"Query %@: Will reduce row with key=%@, value=%@",
              _name, [keyData my_UTF8ToString], [valueData my_UTF8ToString]);

        id valueOrData = valueData;
        if (valuesToReduce && [self rowValueIsEntireDoc: valueData]) {
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
        LogTo(ViewVerbose, @"Query %@: Reduced to key=%@, value=%@",
              _name, toJSONString(key), toJSONString(reduced));
        CBLQueryRow* row = [[CBLQueryRow alloc] initWithDocID: nil
                                                     sequence: 0
                                                          key: key
                                                        value: reduced
                                                docProperties: nil
                                                      storage: self];
        if (!options.filter || options.filter(row))
            [rows addObject: row];
    }

    //OPT: Return objects from enum as they're found, without collecting them in an array first
    return queryIteratorBlockFromArray(rows);
}


static CBLQueryIteratorBlock queryIteratorBlockFromArray(NSArray* rows) {
    NSEnumerator* rowEnum = rows.objectEnumerator;
    return ^CBLQueryRow*() {
        return rowEnum.nextObject;
    };
}


// This is really just for unit tests & debugging
#if DEBUG
- (NSArray*) dump {
    if (self.viewID <= 0)
        return nil;

    CBL_FMResultSet* r = [_dbStorage.fmdb executeQuery: @"SELECT sequence, key, value FROM maps "
                                                      "WHERE view_id=? ORDER BY key",
                                                     @(self.viewID)];
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


- (BOOL) rowValueIsEntireDoc: (NSData*)valueData {
    return valueData.length == 1 && *(const char*)valueData.bytes == '*';
}


- (id) parseRowValue: (NSData*)valueData {
    return fromJSON(valueData);
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
