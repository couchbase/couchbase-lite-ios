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
#import "CBL_Shared.h"
#import "CBLInternal.h"
#import "CouchbaseLitePrivate.h"
#import "CBLCollateJSON.h"
#import "CBJSONEncoder.h"
#import "CBLMisc.h"
#import "CBLGeometry.h"

#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "FMResultSet.h"
#import "ExceptionUtils.h"

#include "sqlite3_unicodesn_tokenizer.h"


// GROUP_VIEWS_BY_DEFAULT alters the behavior of -viewsInGroup and thus which views will be
// re-indexed together. If it's defined, all views with no "/" in the name are treated as a single
// group and will be re-indexed together. If it's not defined, such views aren't in any group
// and will be re-indexed only individually. (The latter matches the CBL 1.0 behavior and
// avoids unexpected slowdowns if an app suddenly has all its views re-index at once.)
#undef GROUP_VIEWS_BY_DEFAULT


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


@implementation CBLQueryOptions

@synthesize startKey, endKey, startKeyDocID, endKeyDocID, keys, fullTextQuery, filter;

- (instancetype)init {
    self = [super init];
    if (self) {
        limit = kCBLQueryOptionsDefaultLimit;
        inclusiveStart = YES;
        inclusiveEnd = YES;
        fullTextRanking = YES;
        // everything else will default to nil/0/NO
    }
    return self;
}

@end




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

// for unit tests only
- (void) forgetMapBlock {
    CBLDatabase* db = _weakDB;
    CBL_Shared* shared = db.shared;
    [shared setValue: nil
             forType: @"map" name: _name inDatabaseNamed: db.name];
    [shared setValue: nil
             forType: @"reduce" name: _name inDatabaseNamed: db.name];
}
#endif

//- (void) setMapContentOptions:(CBLContentOptions)mapContentOptions {
//    _mapContentOptions = (uint8_t)mapContentOptions;
//}
//
//- (CBLContentOptions) mapContentOptions {
//    return _mapContentOptions;
//}


- (CBLStatus) compileFromDesignDoc {
    if (self.registeredMapBlock != nil)
        return kCBLStatusOK;

    // see if there's a design doc with a CouchDB-style view definition we can compile:
    NSString* language;
    NSDictionary* viewProps = $castIf(NSDictionary, [_weakDB getDesignDocFunction: self.name
                                                                              key: @"views"
                                                                         language: &language]);
    if (!viewProps)
        return kCBLStatusNotFound;
    LogTo(View, @"%@: Attempting to compile %@ from design doc", self.name, language);
    if (![CBLView compiler])
        return kCBLStatusNotImplemented;
    return [self compileFromProperties: viewProps language: language];
}


- (CBLStatus) compileFromProperties: (NSDictionary*)viewProps language: (NSString*)language {
    if (!language)
        language = @"javascript";
    NSString* mapSource = viewProps[@"map"];
    if (!mapSource)
        return kCBLStatusNotFound;
    CBLMapBlock mapBlock = [[CBLView compiler] compileMapFunction: mapSource language: language];
    if (!mapBlock) {
        Warn(@"View %@ could not compile %@ map fn: %@", _name, language, mapSource);
        return kCBLStatusCallbackError;
    }
    NSString* reduceSource = viewProps[@"reduce"];
    CBLReduceBlock reduceBlock = NULL;
    if (reduceSource) {
        reduceBlock = [[CBLView compiler] compileReduceFunction: reduceSource language: language];
        if (!reduceBlock) {
            Warn(@"View %@ could not compile %@ map fn: %@", _name, language, reduceSource);
            return kCBLStatusCallbackError;
        }
    }

    // Version string is based on a digest of the properties:
    NSError* error;
    NSString* version = CBLHexSHA1Digest([CBJSONEncoder canonicalEncoding: viewProps error: &error]);
    [self setMapBlock: mapBlock reduceBlock: reduceBlock version: version];

    NSDictionary* options = $castIf(NSDictionary, viewProps[@"options"]);
    _collation = ($equal(options[@"collation"], @"raw")) ? kCBLViewCollationRaw
                                                         : kCBLViewCollationUnicode;
    return kCBLStatusOK;
}


#pragma mark - INDEXING:


- (NSArray*) viewsInGroup {
    int (^filter)(CBLView* view);
    NSRange slash = [_name rangeOfString: @"/"];
    if (slash.length > 0) {
        // Return all the views whose name starts with the same prefix before the slash:
        NSString* prefix = [_name substringToIndex: NSMaxRange(slash)];
        filter = ^int(CBLView* view) {
            return [view.name hasPrefix: prefix];
        };
    } else {
#ifdef GROUP_VIEWS_BY_DEFAULT
        // Return all the views that don't have a slash in their names:
        filter = ^int(CBLView* view) {
            return [view.name rangeOfString: @"/"].length == 0;
        };
#else
        // Without GROUP_VIEWS_BY_DEFAULT, views with no "/" in the name aren't in any group:
        return @[self];
#endif
    }
    return [_weakDB.allViews my_filter: filter];
}


static inline NSData* toJSONData( UU id object ) {
    if (!object)
        return nil;
    return [CBLJSON dataWithJSONObject: object
                               options: CBLJSONWritingAllowFragments
                                 error: NULL];
}


/** The body of the emit() callback while indexing a view. */
- (CBLStatus) _emitKey: (UU id)key
                 value: (UU id)value
            valueIsDoc: (BOOL)valueIsDoc
           forSequence: (SequenceNumber)sequence
{
    CBLDatabase* db = _weakDB;
    CBL_FMDatabase* fmdb = db.fmdb;
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
            return db.lastDbError;
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
    return ok ? kCBLStatusOK : db.lastDbError;
}


- (CBLStatus) updateIndex {
    return [_weakDB updateIndexes: self.viewsInGroup forView: self];
}


- (CBLStatus) updateIndexAlone {
    return [_weakDB updateIndexes: @[self] forView: self];
}


@end


@implementation CBLDatabase (ViewIndexing)

/** Updates the view's index, if necessary. (If no changes needed, returns kCBLStatusNotModified.)*/
- (CBLStatus) updateIndexes: (NSArray*)inputViews forView: (CBLView*)forView {
    LogTo(View, @"Checking indexes of (%@) for %@", viewNames(inputViews), forView.name);

    CBLStatus status = [self _inTransaction: ^CBLStatus {
        // If the view the update is for doesn't need any update, don't do anything:
        const SequenceNumber dbMaxSequence = self.lastSequenceNumber;
        const SequenceNumber forViewLastSequence = forView.lastSequenceIndexed;
        if (forView && forViewLastSequence >= dbMaxSequence)
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
        for (CBLView* view in inputViews) {
            CBLMapBlock mapBlock = view.mapBlock;
            if (mapBlock == NULL) {
                Assert(view != forView,
                       @"Cannot index view %@: no map block registered",
                       view.name);
                LogTo(ViewVerbose, @"    %@ has no map block; skipping it", view.name);
                continue;
            }

            [views addObject: view];
            [mapBlocks addObject: mapBlock];

            int viewID = view.viewID;
            Assert(viewID > 0, @"%@ not found in database", view);

            NSUInteger totalRows = view.totalRows;
            viewTotalRows[@(viewID)] = @(totalRows);

            SequenceNumber last = (view==forView) ? forViewLastSequence : view.lastSequenceIndexed;
            viewLastSequence[i++] = last;
            if (last < 0) {
                return self.lastDbError;
            } else if (last < dbMaxSequence) {
                minLastSequence = MIN(minLastSequence, last);
                LogTo(ViewVerbose, @"    %@ last indexed at #%lld", view.name, last);
                BOOL ok;
                if (last == 0) {
                    // If the lastSequence has been reset to 0, make sure to remove all map results:
                    ok = [_fmdb executeUpdate: @"DELETE FROM maps WHERE view_id=?", @(viewID)];
                } else {
                    // Delete all obsolete map results (ones from since-replaced revisions):
                    ok = [_fmdb executeUpdate: @"DELETE FROM maps WHERE view_id=? AND sequence IN ("
                                                    "SELECT parent FROM revs WHERE sequence>? "
                                                        "AND parent>0 AND parent<=?)",
                                              @(viewID), @(last), @(last)];
                }
                if (!ok)
                    return self.lastDbError;
                
                // Update #deleted rows
                int changes = _fmdb.changes;
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
        __block CBLView* curView;
        __block NSDictionary* curDoc;
        __block SequenceNumber sequence = minLastSequence;
        __block CBLStatus emitStatus = kCBLStatusOK;
        __block unsigned inserted = 0;
        CBLMapEmitBlock emit = ^(id key, id value) {
            int status = [curView _emitKey: key value: value
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
        r = [_fmdb executeQuery: @"SELECT revs.doc_id, sequence, docid, revid, json, no_attachments "
                                 "FROM revs, docs "
                                 "WHERE sequence>? AND current!=0 AND deleted=0 "
                                 "AND revs.doc_id = docs.doc_id "
                                 "ORDER BY revs.doc_id, revid DESC",
                                 @(minLastSequence)];
        if (!r)
            return self.lastDbError;

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
                    CBL_FMResultSet* r2 = [_fmdb executeQuery:
                                    @"SELECT revid, sequence FROM revs "
                                     "WHERE doc_id=? AND sequence<=? AND current!=0 AND deleted=0 "
                                     "ORDER BY revID DESC "
                                     "LIMIT 1",
                                    @(doc_id), @(minLastSequence)];
                    if (!r2) {
                        [r close];
                        return self.lastDbError;
                    }
                    if ([r2 next]) {
                        NSString* oldRevID = [r2 stringForColumnIndex:0];
                        // This is the revision that used to be the 'winner'.
                        // Remove its emitted rows:
                        SequenceNumber oldSequence = [r2 longLongIntForColumnIndex: 1];
                        for (CBLView* view in views) {
                            [_fmdb executeUpdate: @"DELETE FROM maps WHERE view_id=? AND sequence=?",
                                                 @(view.viewID), @(oldSequence)];
                            int changes = _fmdb.changes;
                            deleted += changes;
                            viewTotalRows[@(view.viewID)] =
                                @([viewTotalRows[@(view.viewID)] intValue] - changes);
                        }
                        if (CBLCompareRevIDs(oldRevID, revID) > 0) {
                            // It still 'wins' the conflict, so it's the one that
                            // should be mapped [again], not the current revision!
                            revID = oldRevID;
                            sequence = oldSequence;
                            json = [_fmdb dataForQuery: @"SELECT json FROM revs WHERE sequence=?",
                                    @(sequence)];
                        }
                    }
                    [r2 close];
                }
                
                // Get the document properties, to pass to the map function:
                CBLContentOptions contentOptions = kCBLIncludeLocalSeq;
                if (noAttachments)
                    contentOptions |= kCBLNoAttachments;
                curDoc = [self documentPropertiesFromJSON: json
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
        for (CBLView* view in views) {
            int newTotalRows = [viewTotalRows[@(view.viewID)] intValue];
            Assert(newTotalRows >= 0);
            if (![_fmdb executeUpdate: @"UPDATE views SET lastSequence=?, total_docs=? WHERE view_id=?",
                                       @(dbMaxSequence), @(newTotalRows), @(view.viewID)])
                return self.lastDbError;
        }
        
        LogTo(View, @"...Finished re-indexing (%@) to #%lld (deleted %u, added %u)",
              viewNames(views), dbMaxSequence, deleted, inserted);
        return kCBLStatusOK;
    }];
    
    if (status >= kCBLStatusBadRequest)
        Warn(@"CouchbaseLite: Failed to rebuild views (%@): %d", viewNames(inputViews), status);
    return status;
}


static NSString* viewNames(NSArray* views) {
    return [[views my_map: ^(CBLView* view) {return view.name;}] componentsJoinedByString: @", "];
}


@end




#pragma mark - SPECIAL KEYS:


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
