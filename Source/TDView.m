//
//  TDView.m
//  TouchDB
//
//  Created by Jens Alfke on 12/8/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TDView.h"
#import "TDInternal.h"

#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "FMResultSet.h"


#define kReduceBatchSize 100


const TDQueryOptions kDefaultTDQueryOptions = {
    .limit = UINT_MAX,
    .inclusiveEnd = YES
    // everything else will default to nil/0/NO
};


static id<TDViewCompiler> sCompiler;


@implementation TDView


- (id) initWithDatabase: (TDDatabase*)db name: (NSString*)name {
    Assert(db);
    Assert(name.length);
    self = [super init];
    if (self) {
        _db = db;
        _name = [name copy];
        _viewID = -1;  // means 'unknown'
    }
    return self;
}


- (void)dealloc {
    [_name release];
    [_mapBlock release];
    [_reduceBlock release];
    [super dealloc];
}


@synthesize database=_db, name=_name, mapBlock=_mapBlock, reduceBlock=_reduceBlock,
            collation=_collation, mapContentOptions=_mapContentOptions;


- (int) viewID {
    if (_viewID < 0)
        _viewID = [_db.fmdb intForQuery: @"SELECT view_id FROM views WHERE name=?", _name];
    return _viewID;
}


- (SequenceNumber) lastSequenceIndexed {
    return [_db.fmdb longLongForQuery: @"SELECT lastSequence FROM views WHERE name=?", _name];
}


- (BOOL) setMapBlock: (TDMapBlock)mapBlock
         reduceBlock: (TDReduceBlock)reduceBlock
             version: (NSString *)version
{
    Assert(mapBlock);
    Assert(version);
    [_mapBlock autorelease];
    _mapBlock = [mapBlock copy];
    [_reduceBlock autorelease];
    _reduceBlock = [reduceBlock copy];
    
    if (![_db open])
        return NO;

    // Update the version column in the db. This is a little weird looking because we want to
    // avoid modifying the db if the version didn't change, and because the row might not exist yet.
    FMDatabase* fmdb = _db.fmdb;
    if (![fmdb executeUpdate: @"INSERT OR IGNORE INTO views (name, version) VALUES (?, ?)", 
                              _name, version])
        return NO;
    if (fmdb.changes)
        return YES;     // created new view
    if (![fmdb executeUpdate: @"UPDATE views SET version=?, lastSequence=0 "
                               "WHERE name=? AND version!=?", 
                              version, _name, version])
        return NO;
    return (fmdb.changes > 0);
}


- (void) removeIndex {
    if (self.viewID <= 0)
        return;
    [_db beginTransaction];
    [_db.fmdb executeUpdate: @"DELETE FROM maps WHERE view_id=?",
                             @(_viewID)];
    [_db.fmdb executeUpdate: @"UPDATE views SET lastsequence=0 WHERE view_id=?",
                             @(_viewID)];
    [_db endTransaction: YES];
}


- (void) deleteView {
    [_db deleteViewNamed: _name];
    _viewID = 0;
}


- (void) databaseClosing {
    _db = nil;
    _viewID = 0;
}


#pragma mark - INDEXING:


static NSString* toJSONString( id object ) {
    if (!object)
        return nil;
    return [TDJSON stringWithJSONObject: object
                                options: TDJSONWritingAllowFragments
                                  error: NULL];
}


static id fromJSON( NSData* json ) {
    if (!json)
        return nil;
    return [TDJSON JSONObjectWithData: json 
                              options: TDJSONReadingAllowFragments
                                error: NULL];
}


- (BOOL) stale {
    return self.lastSequenceIndexed < _db.lastSequence;
}


- (TDStatus) updateIndex {
    LogTo(View, @"Re-indexing view %@ ...", _name);
    Assert(_mapBlock, @"Cannot reindex view '%@' which has no map block set", _name);
    
    int viewID = self.viewID;
    if (viewID <= 0)
        return kTDStatusNotFound;
    
    [_db beginTransaction];
    FMResultSet* r = nil;
    TDStatus status = kTDStatusDBError;
    @try {
        // Check whether we need to update at all:
        const SequenceNumber lastSequence = self.lastSequenceIndexed;
        const SequenceNumber dbMaxSequence = _db.lastSequence;
        if (lastSequence == dbMaxSequence) {
            status = kTDStatusNotModified;
            return status;
        }

        __block BOOL emitFailed = NO;
        __block unsigned inserted = 0;
        FMDatabase* fmdb = _db.fmdb;
        
        // First remove obsolete emitted results from the 'maps' table:
        __block SequenceNumber sequence = lastSequence;
        if (lastSequence < 0)
            return kTDStatusDBError;
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
            return kTDStatusDBError;
#ifndef MY_DISABLE_LOGGING
        unsigned deleted = fmdb.changes;
#endif
        
        // This is the emit() block, which gets called from within the user-defined map() block
        // that's called down below.
        TDMapEmitBlock emit = ^(id key, id value) {
            if (!key)
                key = $null;
            NSString* keyJSON = toJSONString(key);
            NSString* valueJSON = toJSONString(value);
            LogTo(View, @"    emit(%@, %@)", keyJSON, valueJSON);
            if ([fmdb executeUpdate: @"INSERT INTO maps (view_id, sequence, key, value) VALUES "
                                        "(?, ?, ?, ?)",
                                        @(viewID), @(sequence), keyJSON, valueJSON])
                ++inserted;
            else
                emitFailed = YES;
        };
        
        // Now scan every revision added since the last time the view was indexed:
        r = [fmdb executeQuery: @"SELECT revs.doc_id, sequence, docid, revid, json FROM revs, docs "
                                 "WHERE sequence>? AND current!=0 AND deleted=0 "
                                 "AND revs.doc_id = docs.doc_id "
                                 "ORDER BY revs.doc_id, revid DESC",
                                 @(lastSequence)];
        if (!r)
            return kTDStatusDBError;

        BOOL keepGoing = [r next]; // Go to first result row
        while (keepGoing) {
            @autoreleasepool {
                // Reconstitute the document as a dictionary:
                sequence = [r longLongIntForColumnIndex: 1];
                NSString* docID = [r stringForColumnIndex: 2];
                if ([docID hasPrefix: @"_design/"]) {     // design docs don't get indexed!
                    keepGoing = [r next];
                    continue;
                }
                NSString* revID = [r stringForColumnIndex: 3];
                NSData* json = [r dataForColumnIndex: 4];
            
                // Iterate over following rows with the same doc_id -- these are conflicts.
                // Skip them, but collect their revIDs:
                int64_t doc_id = [r longLongIntForColumnIndex: 0];
                NSMutableArray* conflicts = nil;
                while ((keepGoing = [r next]) && [r longLongIntForColumnIndex: 0] == doc_id) {
                    if (!conflicts)
                        conflicts = $marray();
                    [conflicts addObject: [r stringForColumnIndex: 3]];
                }
            
                if (lastSequence > 0) {
                    // Find conflicts with documents from previous indexings.
                    BOOL first = YES;
                    FMResultSet* r2 = [fmdb executeQuery:
                                    @"SELECT revid, sequence FROM revs "
                                     "WHERE doc_id=? AND sequence<=? AND current!=0 AND deleted=0 "
                                     "ORDER BY revID DESC",
                                    @(doc_id), @(lastSequence)];
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
                            if (TDCompareRevIDs(oldRevID, revID) > 0) {
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
                            return TDCompareRevIDs(r2, r1);
                        }];
                    }
                }
                
                // Get the document properties, to pass to the map function:
                NSDictionary* properties = [_db documentPropertiesFromJSON: json
                                                                     docID: docID revID:revID
                                                                   deleted: NO
                                                                  sequence: sequence
                                                                   options: _mapContentOptions];
                if (!properties) {
                    Warn(@"Failed to parse JSON of doc %@ rev %@", docID, revID);
                    continue;
                }
                
                if (conflicts) {
                    // Add a "_conflicts" property if there were conflicting revisions:
                    NSMutableDictionary* mutableProps = [[properties mutableCopy] autorelease];
                    mutableProps[@"_conflicts"] = conflicts;
                    properties = mutableProps;
                }
                
                // Call the user-defined map() to emit new key/value pairs from this revision:
                LogTo(View, @"  call map for sequence=%lld...", sequence);
                _mapBlock(properties, emit);
                if (emitFailed)
                    return kTDStatusCallbackError;
            }
        }
        
        // Finally, record the last revision sequence number that was indexed:
        if (![fmdb executeUpdate: @"UPDATE views SET lastSequence=? WHERE view_id=?",
                                   @(dbMaxSequence), @(viewID)])
            return kTDStatusDBError;
        
        LogTo(View, @"...Finished re-indexing view %@ to #%lld (deleted %u, added %u)",
              _name, dbMaxSequence, deleted, inserted);
        status = kTDStatusOK;
        
    } @finally {
        [r close];
        if (status >= kTDStatusBadRequest)
            Warn(@"TouchDB: Failed to rebuild view '%@': %d", _name, status);
        [_db endTransaction: (status < kTDStatusBadRequest)];
    }
    return status;
}


#pragma mark - QUERYING:


- (FMResultSet*) resultSetWithOptions: (const TDQueryOptions*)options
                               status: (TDStatus*)outStatus
{
    if (!options)
        options = &kDefaultTDQueryOptions;

    // OPT: It would be faster to use separate tables for raw-or ascii-collated views so that
    // they could be indexed with the right collation, instead of having to specify it here.
    NSString* collationStr = @"";
    if (_collation == kTDViewCollationASCII)
        collationStr = @" COLLATE JSON_ASCII";
    else if (_collation == kTDViewCollationRaw)
        collationStr = @" COLLATE JSON_RAW";

    NSMutableString* sql = [NSMutableString stringWithString: @"SELECT key, value, docid"];
    if (options->includeDocs)
        [sql appendString: @", revid, json, revs.sequence"];
    [sql appendString: @" FROM maps, revs, docs WHERE maps.view_id=?"];
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
    
    [sql appendString: @" AND revs.sequence = maps.sequence AND docs.doc_id = revs.doc_id "
                        "ORDER BY key"];
    [sql appendString: collationStr];
    if (options->descending)
        [sql appendString: @" DESC"];
    if (options->limit != kDefaultTDQueryOptions.limit) {
        [sql appendString: @" LIMIT ?"];
        [args addObject: @(options->limit)];
    }
    if (options->skip > 0) {
        [sql appendString: @" OFFSET ?"];
        [args addObject: @(options->skip)];
    }
    
    LogTo(View, @"Query %@: %@\n\tArguments: %@", _name, sql, args);
    
    FMResultSet* r = [_db.fmdb executeQuery: sql withArgumentsInArray: args];
    if (!r)
        *outStatus = kTDStatusDBError;
    return r;
}


// Are key1 and key2 grouped together at this groupLevel?
static bool groupTogether(id key1, id key2, unsigned groupLevel) {
    if (groupLevel == 0 || ![key1 isKindOfClass: [NSArray class]]
                        || ![key2 isKindOfClass: [NSArray class]])
        return [key1 isEqual: key2];
    unsigned end = MIN(groupLevel, MIN([key1 count], [key2 count]));
    for (unsigned i = 0; i< end; ++i) {
        if (![key1[i] isEqual: key2[i]])
            return false;
    }
    return true;
}

// Returns the prefix of the key to use in the result row, at this groupLevel
static id groupKey(id key, unsigned groupLevel) {
    if (groupLevel > 0 && [key isKindOfClass: [NSArray class]] && [key count] > groupLevel)
        return [key subarrayWithRange: NSMakeRange(0, groupLevel)];
    else
        return key;
}


- (NSArray*) queryWithOptions: (const TDQueryOptions*)options
                       status: (TDStatus*)outStatus
{
    if (!options)
        options = &kDefaultTDQueryOptions;
    
    FMResultSet* r = [self resultSetWithOptions: options status: outStatus];
    if (!r)
        return nil;
    
    unsigned groupLevel = options->groupLevel;
    bool group = options->group || groupLevel > 0;
    bool reduce = options->reduce || group;

    if (reduce && !_reduceBlock && !group) {
        Warn(@"Cannot use reduce option in view %@ which has no reduce block defined", _name);
        *outStatus = kTDStatusBadParam;
        return nil;
    }
    
    NSMutableArray* rows = $marray();
    NSMutableArray* keysToReduce=nil, *valuesToReduce=nil;
    id lastKey = nil;
    if (reduce) {
        keysToReduce = [[NSMutableArray alloc] initWithCapacity: 100];
        valuesToReduce = [[NSMutableArray alloc] initWithCapacity: 100];
    }
    
    while ([r next]) {
        @autoreleasepool {
            id key = fromJSON([r dataNoCopyForColumnIndex: 0]);
            id value = fromJSON([r dataNoCopyForColumnIndex: 1]);
            Assert(key);
            if (reduce) {
                // Reduced or grouped query:
                if (group && !groupTogether(key, lastKey, groupLevel) && lastKey) {
                    // This pair starts a new group, so reduce & record the last one:
                    id reduced = _reduceBlock ? _reduceBlock(keysToReduce, valuesToReduce,NO) : nil;
                    [rows addObject: $dict({@"key", groupKey(lastKey, groupLevel)},
                                           {@"value", (reduced ?: $null)})];
                    [keysToReduce removeAllObjects];
                    [valuesToReduce removeAllObjects];
                }
                LogTo(ViewVerbose, @"Query %@: Will reduce row with key=%@, value=%@",
                      _name, toJSONString(key), toJSONString(value));
                [keysToReduce addObject: key];
                [valuesToReduce addObject: value ?: $null];
                lastKey = key;

            } else {
                // Regular query:
                NSString* docID = [r stringForColumnIndex: 2];
                id docContents = nil;
                if (options->includeDocs) {
                    NSString* linkedID = $castIf(NSDictionary, value)[@"_id"];
                    if (linkedID) {
                        // Linked document: http://wiki.apache.org/couchdb/Introduction_to_CouchDB_views#Linked_documents
                        NSString* linkedRev = value[@"_rev"]; // usually nil
                        TDStatus linkedStatus;
                        TDRevision* linked = [_db getDocumentWithID: linkedID
                                                         revisionID: linkedRev
                                                            options: options->content
                                                             status: &linkedStatus];
                        docContents = linked ? linked.properties : $null;
                    } else {
                        docContents = [_db documentPropertiesFromJSON: [r dataNoCopyForColumnIndex: 4]
                                                                docID: docID
                                                                revID: [r stringForColumnIndex: 3]
                                                              deleted: NO
                                                             sequence: [r longLongIntForColumnIndex:5]
                                                              options: options->content];
                    }
                }
                LogTo(ViewVerbose, @"Query %@: Found row with key=%@, value=%@, id=%@",
                      _name, toJSONString(key), toJSONString(value), toJSONString(docID));
                [rows addObject: $dict({@"id",  docID},
                                       {@"key", key},
                                       {@"value", value},
                                       {@"doc", docContents})];
            }
        }
    }
    
    if (reduce) {
        if (keysToReduce.count > 0) {
            // Finish the last group (or the entire list, if no grouping):
            id key = group ? groupKey(lastKey, groupLevel) : $null;
            id reduced = _reduceBlock ? _reduceBlock(keysToReduce, valuesToReduce,NO) : nil;
            LogTo(ViewVerbose, @"Query %@: Reduced to key=%@, value=%@",
                  _name, toJSONString(key), toJSONString(reduced));
            [rows addObject: $dict({@"key", key},
                                   {@"value", (reduced ?: $null)})];
        }
        [keysToReduce release];
        [valuesToReduce release];
    }
    
    [r close];
    *outStatus = kTDStatusOK;
    LogTo(View, @"Query %@: Returning %u rows", _name, (unsigned)rows.count);
    return rows;
}


// This is really just for unit tests & debugging
- (NSArray*) dump {
    if (self.viewID <= 0)
        return nil;

    FMResultSet* r = [_db.fmdb executeQuery: @"SELECT sequence, key, value FROM maps "
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


+ (NSNumber*) totalValues: (NSArray*)values {
    double total = 0;
    for (NSNumber* value in values)
        total += value.doubleValue;
    return @(total);
}


+ (void) setCompiler: (id<TDViewCompiler>)compiler {
    [sCompiler autorelease];
    sCompiler = [compiler retain];
}

+ (id<TDViewCompiler>) compiler {
    return sCompiler;
}


@end
