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


@implementation CBLView (Querying)


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
    
    CBLDatabase* db = _weakDB;
    CBL_FMDatabase* fmdb = db.fmdb;
    fmdb.bindNSDataAsString = YES;
    CBL_FMResultSet* r = [fmdb executeQuery: sql withArgumentsInArray: args];
    fmdb.bindNSDataAsString = NO;
    if (!r)
        return db.lastDbError;

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


// Should this query be run as grouped/reduced?
- (BOOL) groupOrReduceWithOptions: (CBLQueryOptions*) options {
    if (options->group || options->groupLevel > 0)
        return YES;
    else if (options->reduceSpecified)
        return options->reduce;
    else
        return (self.reduceBlock != nil); // Reduce defaults to true iff there's a reduce block
}


/** Main internal call to query a view. */
- (NSArray*) _queryWithOptions: (CBLQueryOptions*)options
                        status: (CBLStatus*)outStatus
{
    if (!options)
        options = [CBLQueryOptions new];
    NSArray* rows;
    if (options.fullTextQuery)
        rows = [self _fullTextQueryWithOptions: options status: outStatus];
    else if ([self groupOrReduceWithOptions: options])
        rows = [self _reducedQueryWithOptions: options status: outStatus];
    else
        rows = [self _regularQueryWithOptions: options status: outStatus];
    LogTo(View, @"Query %@: Returning %u rows", _name, (unsigned)rows.count);
    return rows;
}


BOOL CBLValueIsEntireDoc(NSData* valueData) {
    return valueData.length == 1 && *(const char*)valueData.bytes == '*';
}


BOOL CBLRowPassesFilter(CBLDatabase* db, CBLQueryRow* row, CBLQueryOptions* options) {
    if (options.filter) {
        row.database = db; // temporary; this may not be the final database instance
        if (![options.filter evaluateWithObject: row]) {
            LogTo(ViewVerbose, @"   ... on 2nd thought, filter predicate skipped that row");
            return NO;
        }
        row.database = nil;
    }
    return YES;
}


- (NSArray*) _regularQueryWithOptions: (CBLQueryOptions*)options
                               status: (CBLStatus*)outStatus
{
    CBLDatabase* db = _weakDB;
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
            if (valueData && !CBLValueIsEntireDoc(valueData))
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
                                          docProperties: docContents];
        } else {
            row = [[CBLQueryRow alloc] initWithDocID: docID
                                            sequence: sequence
                                                 key: keyData
                                               value: valueData
                                       docProperties: docContents];
        }
        
        if (CBLRowPassesFilter(db, row, options))
            [rows addObject: row];
        return kCBLStatusOK;
    }];

    return rows;
}


/** Runs a full-text query of a view, using the FTS4 table. */
- (NSArray*) _fullTextQueryWithOptions: (const CBLQueryOptions*)options
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

    CBLDatabase* db = _weakDB;
    CBL_FMResultSet* r = [db.fmdb executeQuery: sql, options.fullTextQuery, @(self.viewID),
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
        if (CBLRowPassesFilter(db, row, options))
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


- (NSMutableArray*) _reducedQueryWithOptions: (CBLQueryOptions*)options
                                      status: (CBLStatus*)outStatus
{
    CBLDatabase* db = _weakDB;
    unsigned groupLevel = options->groupLevel;
    bool group = options->group || groupLevel > 0;
    if (options->reduceSpecified) {
        if (options->reduce && !self.reduceBlock) {
            Warn(@"Cannot use reduce option in view %@ which has no reduce block defined",
                 _name);
            *outStatus = kCBLStatusBadParam;
            return nil;
        }
    }

    CBLReduceBlock reduce = self.reduceBlock;
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
                                                        docProperties: nil];
                if (CBLRowPassesFilter(db, row, options))
                    [rows addObject: row];
                [keysToReduce removeAllObjects];
                [valuesToReduce removeAllObjects];
            }
            lastKeyData = [keyData copy];
        }
        LogTo(ViewVerbose, @"Query %@: Will reduce row with key=%@, value=%@",
              _name, [keyData my_UTF8ToString], [valueData my_UTF8ToString]);

        id valueOrData = valueData;
        if (valuesToReduce && CBLValueIsEntireDoc(valueData)) {
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
                                                docProperties: nil];
        if (CBLRowPassesFilter(db, row, options))
            [rows addObject: row];
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


@end
