//
//  CBLView+Internal.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/8/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLView+Internal.h"
#import "CBLInternal.h"
#import "CouchbaseLitePrivate.h"
#import "CBLSpecialKey.h"
#import "CBLCollateJSON.h"
#import "CBLCanonicalJSON.h"
#import "CBLMisc.h"
#import "CBLGeometry.h"
#import "ExceptionUtils.h"
#import <CBForest/CBForest.h>


@implementation CBLView (Internal)


#if DEBUG
- (NSString*) indexFilePath {
    return _index.filename;
}

- (void) setCollation: (CBLViewCollation)collation {
    _collation = collation;
}
#endif

//- (void) setMapContentOptions:(CBLContentOptions)mapContentOptions {
//    _mapContentOptions = (uint8_t)mapContentOptions;
//}
//
//- (CBLContentOptions) mapContentOptions {
//    return _mapContentOptions;
//}


- (BOOL) compileFromProperties: (NSDictionary*)viewProps language: (NSString*)language {
    if (!language)
        language = @"javascript";
    NSString* mapSource = viewProps[@"map"];
    if (!mapSource)
        return NO;
    CBLMapBlock mapBlock = [[CBLView compiler] compileMapFunction: mapSource language: language];
    if (!mapBlock) {
        Warn(@"View %@ has unknown map function: %@", _name, mapSource);
        return NO;
    }
    NSString* reduceSource = viewProps[@"reduce"];
    CBLReduceBlock reduceBlock = NULL;
    if (reduceSource) {
        reduceBlock =[[CBLView compiler] compileReduceFunction: reduceSource language: language];
        if (!reduceBlock) {
            Warn(@"View %@ has unknown reduce function: %@", _name, reduceSource);
            return NO;
        }
    }

    // Version string is based on a digest of the properties:
    NSString* version = CBLHexSHA1Digest([CBLCanonicalJSON canonicalData: viewProps]);

    [self setMapBlock: mapBlock reduceBlock: reduceBlock version: version];

    NSDictionary* options = $castIf(NSDictionary, viewProps[@"options"]);
    _collation = ($equal(options[@"collation"], @"raw")) ? kCBLViewCollationRaw
                                                             : kCBLViewCollationUnicode;
    return YES;
}


#pragma mark - INDEXING:


/** Updates the view's index, if necessary. (If no changes needed, returns kCBLStatusNotModified.)*/
- (CBLStatus) updateIndex {
    LogTo(View, @"Re-indexing view %@ ...", _name);
    CBLDatabase* db = _weakDB;
    NSString* viewName = _name;
    CBLContentOptions contentOptions = _mapContentOptions;
    CBLMapBlock mapBlock = self.mapBlock;
    Assert(mapBlock, @"Cannot reindex view '%@' which has no map block set", _name);
    if (!_index)
        return kCBLStatusNotFound;

    _index.sourceDatabase = db.forestDB;
    _index.mapVersion = self.mapVersion;
    _index.map = ^(CBForestDocument* baseDoc, CBForestIndexEmitBlock emit) {
        CBForestVersions* doc = (CBForestVersions*)baseDoc;
        NSString *docID=doc.docID, *revID=doc.revID;
        SequenceNumber sequence = doc.sequence;
        NSData* json = [doc dataOfRevision: nil];
        NSDictionary* properties = [db documentPropertiesFromJSON: json
                                                            docID: docID
                                                            revID: revID
                                                          deleted: NO
                                                         sequence: sequence
                                                          options: contentOptions];
        if (!properties) {
            Warn(@"Failed to parse JSON of doc %@ rev %@", docID, revID);
            return;
        }

        // Call the user-defined map() to emit new key/value pairs from this revision:
        LogTo(View, @"  call map for sequence=%lld...", sequence);
        @try {
            mapBlock(properties, emit);
        } @catch (NSException* x) {
            MYReportException(x, @"map block of view '%@'", viewName);
        }
    };

    uint64_t lastSequence = _index.lastSequenceIndexed;
    NSError* error;
    BOOL ok = [_index updateIndex: &error];
    _index.map = nil;

    if (!ok)
        return kCBLStatusDBError; //FIX: Improve this
    else if (_index.lastSequenceIndexed == lastSequence)
        return kCBLStatusNotModified;
    else
        return kCBLStatusOK;
}



#if 0
/** The body of the emit() callback while indexing a view. */
- (CBLStatus) _emitKey: (id)key value: (id)value forSequence: (SequenceNumber)sequence {
    CBLDatabase* db = _weakDB;
    CBL_FMDatabase* fmdb = db.fmdb;
    NSString* valueJSON = toJSONString(value);
    NSNumber* fullTextID = nil, *bboxID = nil;
    NSString* keyJSON = @"null";
    NSData* geoKey = nil;
    if ([key isKindOfClass: [CBLSpecialKey class]]) {
        CBLSpecialKey *specialKey = key;
        LogTo(View, @"    emit( %@, %@)", specialKey, valueJSON);
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
            return db.lastDbError;
        key = nil;
    } else {
        if (key)
            keyJSON = toJSONString(key);
        LogTo(View, @"    emit(%@, %@)", keyJSON, valueJSON);
    }

    if (![fmdb executeUpdate: @"INSERT INTO maps (view_id, sequence, key, value, "
                                   "fulltext_id, bbox_id, geokey) VALUES (?, ?, ?, ?, ?, ?, ?)",
                                  @(self.viewID), @(sequence), keyJSON, valueJSON,
                                  fullTextID, bboxID, geoKey])
        return db.lastDbError;
    return kCBLStatusOK;
}


/** Updates the view's index, if necessary. (If no changes needed, returns kCBLStatusNotModified.)*/
- (CBLStatus) updateIndex {
    LogTo(View, @"Re-indexing view %@ ...", _name);
    CBLMapBlock mapBlock = self.mapBlock;
    Assert(mapBlock, @"Cannot reindex view '%@' which has no map block set", _name);
    
    int viewID = self.viewID;
    if (viewID <= 0)
        return kCBLStatusNotFound;
    CBLDatabase* db = _weakDB;
    
    CBLStatus status = [db _inTransaction: ^CBLStatus {
        // Check whether we need to update at all:
        const SequenceNumber lastSequence = self.lastSequenceIndexed;
        const SequenceNumber dbMaxSequence = db.lastSequenceNumber;
        if (lastSequence == dbMaxSequence) {
            return kCBLStatusNotModified;
        }

        __block CBLStatus emitStatus = kCBLStatusOK;
        __block unsigned inserted = 0;
        CBL_FMDatabase* fmdb = db.fmdb;
        
        // First remove obsolete emitted results from the 'maps' table:
        __block SequenceNumber sequence = lastSequence;
        if (lastSequence < 0)
            return db.lastDbError;
        BOOL ok;
        if (lastSequence == 0) {
            // If the lastSequence has been reset to 0, make sure to remove all map results:
            ok = [fmdb executeUpdate: @"DELETE FROM maps WHERE view_id=?", @(_viewID)];
        } else {
            // Delete all obsolete map results (ones from since-replaced revisions):
            ok = [fmdb executeUpdate: @"DELETE FROM maps WHERE view_id=? AND sequence IN ("
                                            "SELECT parent FROM revs WHERE sequence>? "
                                                "AND parent>0 AND parent<=?)",
                                      @(_viewID), @(lastSequence), @(lastSequence)];
        }
        if (!ok)
            return db.lastDbError;
#ifndef MY_DISABLE_LOGGING
        unsigned deleted = fmdb.changes;
#endif
        
        // This is the emit() block, which gets called from within the user-defined map() block
        // that's called down below.
        CBLMapEmitBlock emit = ^(id key, id value) {
            int status = [self _emitKey: key value: value forSequence: sequence];
            if (status != kCBLStatusOK)
                emitStatus = status;
            else
                inserted++;
        };

        // Now scan every revision added since the last time the view was indexed:
        CBL_FMResultSet* r;
        r = [fmdb executeQuery: @"SELECT revs.doc_id, sequence, docid, revid, json, no_attachments "
                                 "FROM revs, docs "
                                 "WHERE sequence>? AND current!=0 AND deleted=0 "
                                 "AND revs.doc_id = docs.doc_id "
                                 "ORDER BY revs.doc_id, revid DESC",
                                 @(lastSequence)];
        if (!r)
            return db.lastDbError;

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
            
                if (lastSequence > 0) {
                    // Find conflicts with documents from previous indexings.
                    CBL_FMResultSet* r2 = [fmdb executeQuery:
                                    @"SELECT revid, sequence FROM revs "
                                     "WHERE doc_id=? AND sequence<=? AND current!=0 AND deleted=0 "
                                     "ORDER BY revID DESC "
                                     "LIMIT 1",
                                    @(doc_id), @(lastSequence)];
                    if (!r2) {
                        [r close];
                        return db.lastDbError;
                    }
                    if ([r2 next]) {
                        NSString* oldRevID = [r2 stringForColumnIndex:0];
                        // This is the revision that used to be the 'winner'.
                        // Remove its emitted rows:
                        SequenceNumber oldSequence = [r2 longLongIntForColumnIndex: 1];
                        [fmdb executeUpdate: @"DELETE FROM maps WHERE view_id=? AND sequence=?",
                                             @(_viewID), @(oldSequence)];
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
                CBLContentOptions contentOptions = _mapContentOptions;
                if (noAttachments)
                    contentOptions |= kCBLNoAttachments;
                NSDictionary* properties = [db documentPropertiesFromJSON: json
                                                                     docID: docID revID:revID
                                                                   deleted: NO
                                                                  sequence: sequence
                                                                   options: contentOptions];
                if (!properties) {
                    Warn(@"Failed to parse JSON of doc %@ rev %@", docID, revID);
                    continue;
                }
                
                // Call the user-defined map() to emit new key/value pairs from this revision:
                LogTo(View, @"  call map for sequence=%lld...", sequence);
                @try {
                    mapBlock(properties, emit);
                } @catch (NSException* x) {
                    MYReportException(x, @"map block of view '%@'", _name);
                    emitStatus = kCBLStatusCallbackError;
                }
                if (CBLStatusIsError(emitStatus)) {
                    [r close];
                    return emitStatus;
                }
            }
        }
        [r close];
        
        // Finally, record the last revision sequence number that was indexed:
        if (![fmdb executeUpdate: @"UPDATE views SET lastSequence=? WHERE view_id=?",
                                   @(dbMaxSequence), @(viewID)])
            return db.lastDbError;
        
        LogTo(View, @"...Finished re-indexing view %@ to #%lld (deleted %u, added %u)",
              _name, dbMaxSequence, deleted, inserted);
        return kCBLStatusOK;
    }];
    
    if (status >= kCBLStatusBadRequest)
        Warn(@"CouchbaseLite: Failed to rebuild view '%@': %d", _name, status);
    return status;
}
#endif

@end
