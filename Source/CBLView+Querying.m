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
#import "CBLMisc.h"

#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "FMResultSet.h"
#import "ExceptionUtils.h"


#define kReduceBatchSize 100


const CBLQueryOptions kDefaultCBLQueryOptions = {
    .limit = UINT_MAX,
    .inclusiveEnd = YES,
    .fullTextRanking = YES
    // everything else will default to nil/0/NO
};


static NSString* toJSONString( id object ) {
    if (!object)
        return nil;
    return [CBLJSON stringWithJSONObject: object
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


@implementation CBLView (Querying)


#pragma mark - QUERYING:


/** Generates and runs the SQL SELECT statement for a view query, and returns its iterator. */
- (CBL_FMResultSet*) resultSetWithOptions: (const CBLQueryOptions*)options
                               status: (CBLStatus*)outStatus
{
    if (!options)
        options = &kDefaultCBLQueryOptions;

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
    NSMutableArray* args = $marray(@(_viewID));

    if (options->keys) {
        [sql appendString:@" AND key in ("];
        NSString* item = @"?";
        for (NSString * key in options->keys) {
            [sql appendString: item];
            item = @",?";
            [args addObject: toJSONString(key)];
        }
        [sql appendString:@")"];
    }
    
    id minKey = options->startKey, maxKey = options->endKey;
    BOOL inclusiveMin = YES, inclusiveMax = options->inclusiveEnd;
    if (options->descending) {
        minKey = maxKey;
        maxKey = options->startKey;
        inclusiveMin = inclusiveMax;
        inclusiveMax = YES;
    }
    if (minKey) {
        [sql appendString: (inclusiveMin ? @" AND key >= ?" : @" AND key > ?")];
        [sql appendString: collationStr];
        [args addObject: toJSONString(minKey)];
    }
    if (maxKey) {
        [sql appendString: (inclusiveMax ? @" AND key <= ?" :  @" AND key < ?")];
        [sql appendString: collationStr];
        [args addObject: toJSONString(maxKey)];
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

    [sql appendString: @" LIMIT ? OFFSET ?"];
    int limit = (options->limit != kDefaultCBLQueryOptions.limit) ? options->limit : -1;
    [args addObject: @(limit)];
    [args addObject: @(options->skip)];

    LogTo(View, @"Query %@: %@\n\tArguments: %@", _name, sql, args);
    
    CBLDatabase* db = _weakDB;
    CBL_FMResultSet* r = [db.fmdb executeQuery: sql withArgumentsInArray: args];
    if (!r)
        *outStatus = db.lastDbError;
    return r;
}


/** Main internal call to query a view. */
- (NSArray*) _queryWithOptions: (const CBLQueryOptions*)options
                        status: (CBLStatus*)outStatus
{
    if (!options)
        options = &kDefaultCBLQueryOptions;

    if (options->fullTextQuery)
        return [self _queryFullText: options status: outStatus];
    
    CBL_FMResultSet* r = [self resultSetWithOptions: options status: outStatus];
    if (!r)
        return nil;
    
    NSMutableArray* rows;

    unsigned groupLevel = options->groupLevel;
    bool group = options->group || groupLevel > 0;
    bool reduce;
    if (options->reduceSpecified) {
        reduce = options->reduce;
        if (reduce && !self.reduceBlock) {
            Warn(@"Cannot use reduce option in view %@ which has no reduce block defined",
                 _name);
            *outStatus = kCBLStatusBadParam;
            return nil;
        }
    } else {
        reduce = (self.reduceBlock != nil); // Reduce defaults to true iff there's a reduce block
    }

    if (reduce || group) {
        // Reduced or grouped query:
        rows = [self reducedQuery: r group: group groupLevel: groupLevel];

    } else {
        // Regular query:
        CBLDatabase* db = _weakDB;
        rows = $marray();
        while ([r next]) {
            @autoreleasepool {
                NSData* keyData = [r dataForColumnIndex: 0];
                NSData* valueData = [r dataForColumnIndex: 1];
                Assert(keyData);
                NSString* docID = [r stringForColumnIndex: 2];
                SequenceNumber sequence = [r longLongIntForColumnIndex:3];
                id docContents = nil;
                if (options->includeDocs) {
                    NSDictionary* value = $castIf(NSDictionary, fromJSON(valueData));
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
                                                  docProperties: docContents];
                } else {
                    row = [[CBLQueryRow alloc] initWithDocID: docID
                                                    sequence: sequence
                                                         key: keyData
                                                       value: valueData
                                               docProperties: docContents];
                }
                [rows addObject: row];
            }
        }
    }

    [r close];
    *outStatus = kCBLStatusOK;
    LogTo(View, @"Query %@: Returning %u rows", _name, (unsigned)rows.count);
    return rows;
}


/** Runs a full-text query of a view, using the FTS4 table. */
- (NSArray*) _queryFullText: (const CBLQueryOptions*)options
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
    int limit = (options->limit != kDefaultCBLQueryOptions.limit) ? options->limit : -1;

    CBLDatabase* db = _weakDB;
    CBL_FMResultSet* r = [db.fmdb executeQuery: sql, options->fullTextQuery, @(self.viewID),
                                                @(limit), @(options->skip)];
    if (!r) {
        *outStatus = db.lastDbError;
        return nil;
    }
    NSMutableArray* rows = [[NSMutableArray alloc] init];
    while ([r next]) {
        NSString* docID = [r stringForColumnIndex: 0];
        SequenceNumber sequence = [r longLongIntForColumnIndex: 1];
        UInt64 fulltextID = [r longLongIntForColumnIndex: 2];
        NSData* valueData = [r dataForColumnIndex: 3];
        NSString* offsets = [r stringForColumnIndex: 4];
        CBLFullTextQueryRow* row = [[CBLFullTextQueryRow alloc] initWithDocID: docID
                                                                     sequence: sequence
                                                                   fullTextID: fulltextID
                                                                 matchOffsets: offsets
                                                                        value: valueData];
        if (options->fullTextSnippets)
            row.snippet = [r stringForColumnIndex: 5];
        [rows addObject: row];
    }
    return rows;
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


- (NSMutableArray*) reducedQuery: (CBL_FMResultSet*)r group: (BOOL)group groupLevel: (unsigned)groupLevel
{
    CBLReduceBlock reduce = self.reduceBlock;
    NSMutableArray* keysToReduce = nil, *valuesToReduce = nil;
    if (reduce) {
        keysToReduce = [[NSMutableArray alloc] initWithCapacity: 100];
        valuesToReduce = [[NSMutableArray alloc] initWithCapacity: 100];
    }
    NSData* lastKeyData = nil;

    NSMutableArray* rows = $marray();
    while ([r next]) {
        @autoreleasepool {
            NSData* keyData = [r dataForColumnIndex: 0];
            NSData* valueData = [r dataForColumnIndex: 1];
            Assert(keyData);
            if (group && !groupTogether(keyData, lastKeyData, groupLevel)) {
                if (lastKeyData) {
                    // This pair starts a new group, so reduce & record the last one:
                    id key = groupKey(lastKeyData, groupLevel);
                    id reduced = callReduce(reduce, keysToReduce, valuesToReduce);
                    [rows addObject: [[CBLQueryRow alloc] initWithDocID: nil
                                                               sequence: 0
                                                                    key: key
                                                                  value: reduced
                                                          docProperties: nil]];
                    [keysToReduce removeAllObjects];
                    [valuesToReduce removeAllObjects];
                }
                lastKeyData = [keyData copy];
            }
            LogTo(ViewVerbose, @"Query %@: Will reduce row with key=%@, value=%@",
                  _name, [keyData my_UTF8ToString], [valueData my_UTF8ToString]);
            [keysToReduce addObject: keyData];
            [valuesToReduce addObject: valueData ?: $null];
        }
    }

    if (keysToReduce.count > 0) {
        // Finish the last group (or the entire list, if no grouping):
        id key = group ? groupKey(lastKeyData, groupLevel) : $null;
        id reduced = callReduce(reduce, keysToReduce, valuesToReduce);
        LogTo(ViewVerbose, @"Query %@: Reduced to key=%@, value=%@",
              _name, toJSONString(key), toJSONString(reduced));
        [rows addObject: [[CBLQueryRow alloc] initWithDocID: nil
                                                   sequence: 0
                                                        key: key
                                                      value: reduced
                                              docProperties: nil]];
    }
    return rows;
}


#pragma mark - OTHER:

// This is really just for unit tests & debugging
#if DEBUG
- (NSArray*) dump {
    if (self.viewID <= 0)
        return nil;

    CBL_FMResultSet* r = [_weakDB.fmdb executeQuery: @"SELECT sequence, key, value FROM maps "
                                                      "WHERE view_id=? ORDER BY key",
                                                     @(_viewID)];
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


@end
