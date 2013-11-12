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
#import "CBLCollateJSON.h"
#import "CBLCanonicalJSON.h"
#import "CBLMisc.h"
#import "CBLGeometry.h"

#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "FMResultSet.h"
#import "ExceptionUtils.h"

#include "sqlite3_unicodesn_tokenizer.h"


static void CBLComputeFTSRank(sqlite3_context *pCtx, int nVal, sqlite3_value **apVal);


// Special key object returned by CBLMapKey.
@interface CBLSpecialKey : NSObject
- (instancetype) initWithText: (NSString*)text;
@property (readonly, nonatomic) NSString* text;
- (instancetype) initWithPoint: (CBLGeoPoint)point;
- (instancetype) initWithRect: (CBLGeoRect)rect;
- (instancetype) initWithGeoJSON: (NSDictionary*)geoJSON;
@property (readonly, nonatomic) CBLGeoRect rect;
@property (readonly, nonatomic) NSData* geoJSONData;
@end


id CBLTextKey(NSString* text) {
    return [[CBLSpecialKey alloc] initWithText: text];
}

id CBLGeoPointKey(double x, double y) {
    return [[CBLSpecialKey alloc] initWithPoint: (CBLGeoPoint){x,y}];
}

id CBLGeoRectKey(double x0, double y0, double x1, double y1) {
    return [[CBLSpecialKey alloc] initWithRect: (CBLGeoRect){{x0,y0},{x1,y1}}];
}

id CBLGeoJSONKey(NSDictionary* geoJSON) {
    id key = [[CBLSpecialKey alloc] initWithGeoJSON: geoJSON];
    if (!key)
        Warn(@"CBLGeoJSONKey doesn't recognize %@",
             [CBLJSON stringWithJSONObject: geoJSON options:0 error: NULL]);
    return key;
}


@implementation CBLView (Internal)


+ (void) registerFunctions:(CBLDatabase *)db {
    sqlite3* dbHandle = db.fmdb.sqliteHandle;
    register_unicodesn_tokenizer(dbHandle);
    sqlite3_create_function(dbHandle, "ftsrank", 1, SQLITE_ANY, NULL,
                            CBLComputeFTSRank, NULL, NULL);
}


#if DEBUG
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


static NSString* toJSONString( id object ) {
    if (!object)
        return nil;
    return [CBLJSON stringWithJSONObject: object
                                options: CBLJSONWritingAllowFragments
                                  error: NULL];
}


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
            
                // Iterate over following rows with the same doc_id -- these are conflicts.
                // Skip them, but collect their revIDs:
                NSMutableArray* conflicts = nil;
                while ((keepGoing = [r next]) && [r longLongIntForColumnIndex: 0] == doc_id) {
                    if (!conflicts)
                        conflicts = $marray();
                    [conflicts addObject: [r stringForColumnIndex: 3]];
                }
            
                if (lastSequence > 0) {
                    // Find conflicts with documents from previous indexings.
                    BOOL first = YES;
                    CBL_FMResultSet* r2 = [fmdb executeQuery:
                                    @"SELECT revid, sequence FROM revs "
                                     "WHERE doc_id=? AND sequence<=? AND current!=0 AND deleted=0 "
                                     "ORDER BY revID DESC",
                                    @(doc_id), @(lastSequence)];
                    if (!r2) {
                        [r close];
                        return db.lastDbError;
                    }
                    while ([r2 next]) {
                        NSString* oldRevID = [r2 stringForColumnIndex:0];
                        if (!conflicts)
                            conflicts = $marray();
                        [conflicts addObject: oldRevID];
                        if (first) {
                            // This is the revision that used to be the 'winner'.
                            // Remove its emitted rows:
                            first = NO;
                            SequenceNumber oldSequence = [r2 longLongIntForColumnIndex: 1];
                            [fmdb executeUpdate: @"DELETE FROM maps WHERE view_id=? AND sequence=?",
                                                 @(_viewID), @(oldSequence)];
                            if (CBLCompareRevIDs(oldRevID, revID) > 0) {
                                // It still 'wins' the conflict, so it's the one that
                                // should be mapped [again], not the current revision!
                                [conflicts removeObject: oldRevID];
                                [conflicts addObject: revID];
                                revID = oldRevID;
                                sequence = oldSequence;
                                json = [fmdb dataForQuery: @"SELECT json FROM revs WHERE sequence=?",
                                        @(sequence)];
                            }
                        }
                    }
                    [r2 close];
                    
                    if (!first) {
                        // Re-sort the conflict array if we added more revisions to it:
                        [conflicts sortUsingComparator: ^(NSString *r1, NSString* r2) {
                            return CBLCompareRevIDs(r2, r1);
                        }];
                    }
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
                
                if (conflicts) {
                    // Add a "_conflicts" property if there were conflicting revisions:
                    NSMutableDictionary* mutableProps = [properties mutableCopy];
                    mutableProps[@"_conflicts"] = conflicts;
                    properties = mutableProps;
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


@end




#pragma mark -

@implementation CBLSpecialKey
{
    NSString* _text;
    CBLGeoRect _rect;
    NSData* _geoJSONData;
}

- (instancetype) initWithText: (NSString*)text {
    Assert(text != nil);
    self = [super init];
    if (self) {
        _text = text;
    }
    return self;
}

- (instancetype) initWithPoint: (CBLGeoPoint)point {
    self = [super init];
    if (self) {
        _rect = (CBLGeoRect){point, point};
        _geoJSONData = [CBLJSON dataWithJSONObject: CBLGeoPointToJSON(point) options: 0 error:NULL];
        _geoJSONData = [NSData data]; // Empty _geoJSONData means the bbox is a point
    }
    return self;
}

- (instancetype) initWithRect: (CBLGeoRect)rect {
    self = [super init];
    if (self) {
        _rect = rect;
        // Don't set _geoJSONData; if nil it defaults to the same as the bbox.
    }
    return self;
}

- (instancetype) initWithGeoJSON: (NSDictionary*)geoJSON {
    self = [super init];
    if (self) {
        if (!CBLGeoJSONBoundingBox(geoJSON, &_rect))
            return nil;
        _geoJSONData = [CBLJSON dataWithJSONObject: geoJSON options: 0 error: NULL];
    }
    return self;
}

@synthesize text=_text, rect=_rect, geoJSONData=_geoJSONData;

- (NSString*) description {
    if (_text) {
        return $sprintf(@"CBLTextKey(\"%@\")", _text);
    } else if (_rect.min.x==_rect.max.x && _rect.min.y==_rect.max.y) {
        return $sprintf(@"CBLGeoPointKey(%g, %g)", _rect.min.x, _rect.min.y);
    } else {
        return $sprintf(@"CBLGeoRectKey({%g, %g}, {%g, %g})",
                        _rect.min.x, _rect.min.y, _rect.max.x, _rect.max.y);
    }
}

@end




/*    Adapted from http://sqlite.org/fts3.html#appendix_a (public domain)
 *    removing the column-weights feature (because we only have one column)
 **
 ** SQLite user defined function to use with matchinfo() to calculate the
 ** relevancy of an FTS match. The value returned is the relevancy score
 ** (a real value greater than or equal to zero). A larger value indicates
 ** a more relevant document.
 **
 ** The overall relevancy returned is the sum of the relevancies of each
 ** column value in the FTS table. The relevancy of a column value is the
 ** sum of the following for each reportable phrase in the FTS query:
 **
 **   (<hit count> / <global hit count>)
 **
 ** where <hit count> is the number of instances of the phrase in the
 ** column value of the current row and <global hit count> is the number
 ** of instances of the phrase in the same column of all rows in the FTS
 ** table.
 */
static void CBLComputeFTSRank(sqlite3_context *pCtx, int nVal, sqlite3_value **apVal) {
    const uint32_t *aMatchinfo;                /* Return value of matchinfo() */
    uint32_t nCol;
    uint32_t nPhrase;                    /* Number of phrases in the query */
    uint32_t iPhrase;                    /* Current phrase */
    double score = 0.0;             /* Value to return */

    /*  Set aMatchinfo to point to the array
     ** of unsigned integer values returned by FTS function matchinfo. Set
     ** nPhrase to contain the number of reportable phrases in the users full-text
     ** query, and nCol to the number of columns in the table.
     */
    aMatchinfo = (const uint32_t*)sqlite3_value_blob(apVal[0]);
    nPhrase = aMatchinfo[0];
    nCol = aMatchinfo[1];

    /* Iterate through each phrase in the users query. */
    for(iPhrase=0; iPhrase<nPhrase; iPhrase++){
        uint32_t iCol;                     /* Current column */

        /* Now iterate through each column in the users query. For each column,
         ** increment the relevancy score by:
         **
         **   (<hit count> / <global hit count>)
         **
         ** aPhraseinfo[] points to the start of the data for phrase iPhrase. So
         ** the hit count and global hit counts for each column are found in
         ** aPhraseinfo[iCol*3] and aPhraseinfo[iCol*3+1], respectively.
         */
        const uint32_t *aPhraseinfo = &aMatchinfo[2 + iPhrase*nCol*3];
        for(iCol=0; iCol<nCol; iCol++){
            uint32_t nHitCount = aPhraseinfo[3*iCol];
            uint32_t nGlobalHitCount = aPhraseinfo[3*iCol+1];
            if( nHitCount>0 ){
                score += ((double)nHitCount / (double)nGlobalHitCount);
            }
        }
    }

    sqlite3_result_double(pCtx, score);
    return;
}
