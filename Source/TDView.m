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


const TDQueryOptions kDefaultTDQueryOptions = {
    nil, nil, 0, INT_MAX, NO, NO, NO
};


@implementation TDView


- (id) initWithDatabase: (TDDatabase*)db name: (NSString*)name {
    Assert(db);
    Assert(name.length);
    self = [super init];
    if (self) {
        _db = [db retain];
        _name = [name copy];
        _viewID = -1;  // means 'unknown'
    }
    return self;
}


- (void)dealloc {
    [_db release];
    [_name release];
    [super dealloc];
}


@synthesize database=_db, name=_name, mapBlock=_mapBlock;


- (int) viewID {
    if (_viewID < 0)
        _viewID = [_db.fmdb intForQuery: @"SELECT view_id FROM views WHERE name=?", _name];
    return _viewID;
}


- (SequenceNumber) lastSequenceIndexed {
    return [_db.fmdb longLongForQuery: @"SELECT lastSequence FROM views WHERE name=?", _name];
}


- (BOOL) setMapBlock: (TDMapBlock)mapBlock version:(NSString *)version {
    Assert(mapBlock);
    Assert(version);
    [_mapBlock release];
    _mapBlock = [mapBlock copy];

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
                             $object(_viewID)];
    [_db.fmdb executeUpdate: @"UPDATE views SET lastsequence=0 WHERE view_id=?",
                             $object(_viewID)];
    [_db endTransaction];
}


- (void) deleteView {
    [_db deleteViewNamed: _name];
    _viewID = 0;
}


#pragma mark - INDEXING:


static NSString* toJSONString( id object ) {
    if (!object)
        return nil;
    // NSJSONSerialization won't write fragments, so if I get one wrap it in an array first:
    BOOL wrapped = NO;
    if (![object isKindOfClass: [NSDictionary class]] && ![object isKindOfClass: [NSArray class]]) {
        wrapped = YES;
        object = $array(object);
    }
    NSData* json = [NSJSONSerialization dataWithJSONObject: object options: 0 error: nil];
    if (wrapped)
        json = [json subdataWithRange: NSMakeRange(1, json.length - 2)];
    return [json my_UTF8ToString];
}


static id fromJSON( NSData* json ) {
    if (!json)
        return nil;
    return [NSJSONSerialization JSONObjectWithData: json 
                                           options: NSJSONReadingAllowFragments
                                             error: nil];
}


- (TDStatus) updateIndex {
    LogTo(View, @"Re-indexing view %@ ...", _name);
    Assert(_mapBlock, @"Cannot reindex view '%@' which has no map block set", _name);
    
    int viewID = self.viewID;
    if (viewID <= 0)
        return 404;
    
    [_db beginTransaction];
    FMResultSet* r = nil;
    TDStatus status = 500;
    @try {
        
        __block BOOL emitFailed = NO;
        __block unsigned inserted = 0;
        FMDatabase* fmdb = _db.fmdb;
        
        // First remove obsolete emitted results from the 'maps' table:
        const SequenceNumber lastSequence = self.lastSequenceIndexed;
        __block SequenceNumber sequence = lastSequence;
        if (lastSequence < 0)
            return 500;
        BOOL ok;
        if (lastSequence == 0) {
            // If the lastSequence has been reset to 0, make sure to remove all map results:
            ok = [fmdb executeUpdate: @"DELETE FROM maps WHERE view_id=?", $object(_viewID)];
        } else {
            // Delete all obsolete map results (ones from since-replaced revisions):
            ok = [fmdb executeUpdate: @"DELETE FROM maps WHERE view_id=? AND sequence IN ("
                                            "SELECT parent FROM revs WHERE sequence>? "
                                                "AND parent>0 AND parent<=?)",
                                      $object(_viewID), $object(lastSequence), $object(lastSequence)];
        }
        if (!ok)
            return 500;
        unsigned deleted = fmdb.changes;
        
        // This is the emit() block, which gets called from within the user-defined map() block
        // that's called down below.
        TDMapEmitBlock emit = ^(id key, id value) {
            if (!key)
                return;
            NSString* keyJSON = toJSONString(key);
            NSString* valueJSON = toJSONString(value);
            LogTo(View, @"    emit(%@, %@)", keyJSON, valueJSON);
            if ([fmdb executeUpdate: @"INSERT INTO maps (view_id, sequence, key, value) VALUES "
                                        "(?, ?, ?, ?)",
                                        $object(viewID), $object(sequence), keyJSON, valueJSON])
                ++inserted;
            else
                emitFailed = YES;
        };
        
        // Now scan every revision added since the last time the view was indexed:
        r = [fmdb executeQuery: @"SELECT revs.doc_id, sequence, docid, revid, json FROM revs, docs "
                                 "WHERE sequence>? AND current!=0 AND deleted=0 "
                                 "AND revs.doc_id = docs.doc_id "
                                 "ORDER BY revs.doc_id, revid DESC",
                                 $object(lastSequence)];
        if (!r)
            return 500;

        int64_t lastDocID = 0;
        while ([r next]) {
            @autoreleasepool {
                int64_t doc_id = [r longLongIntForColumnIndex: 0];
                if (doc_id != lastDocID) {
                    // Only look at the first-iterated revision of any document, because this is the
                    // one with the highest revid, hence the "winning" revision of a conflict.
                    lastDocID = doc_id;
                    
                    // Reconstitute the document as a dictionary:
                    sequence = [r longLongIntForColumnIndex: 1];
                    NSString* docID = [r stringForColumnIndex: 2];
                    NSString* revID = [r stringForColumnIndex: 3];
                    NSData* json = [r dataForColumnIndex: 4];
                    NSDictionary* properties = [_db documentPropertiesFromJSON: json
                                                                         docID: docID revID:revID
                                                                      sequence: sequence];
                    if (properties) {
                        // Call the user-defined map() to emit new key/value pairs from this revision:
                        LogTo(View, @"  call map for sequence=%lld...", sequence);
                        _mapBlock(properties, emit);
                        if (emitFailed)
                            return 500;
                    }
                }
            }
        }
        
        // Finally, record the last revision sequence number that was indexed:
        SequenceNumber dbMaxSequence = _db.lastSequence;
        if (![fmdb executeUpdate: @"UPDATE views SET lastSequence=? WHERE view_id=?",
                                   $object(dbMaxSequence), $object(viewID)])
            return 500;
        
        LogTo(View, @"...Finished re-indexing view %@ to #%lld (deleted %u, added %u)",
              _name, dbMaxSequence, deleted, inserted);
        status = 200;
        
    } @finally {
        [r close];
        if (status >= 300) {
            Warn(@"TouchDB: Failed to rebuild view '%@': %d", _name, status);
            _db.transactionFailed = YES;
        }
        [_db endTransaction];
    }
    return status;
}


#pragma mark - QUERYING:


//FIX: This has a lot of code in common with -[TDDatabase getAllDocs:]. Unify the two!
- (NSDictionary*) queryWithOptions: (const TDQueryOptions*)options
                            status: (TDStatus*)outStatus
{
    if (!options)
        options = &kDefaultTDQueryOptions;
    
    *outStatus = [self updateIndex];
    if (*outStatus >= 300)
        return nil;

    SequenceNumber update_seq = 0;
    if (options->updateSeq)
        update_seq = self.lastSequenceIndexed; // TODO: needs to be atomic with the following SELECT
    
    NSMutableString* sql = [NSMutableString stringWithString: @"SELECT key, value, docid"];
    if (options->includeDocs)
        [sql appendString: @", revid, json, revs.sequence"];
    [sql appendString: @" FROM maps, revs, docs "
                        "WHERE maps.view_id=? AND revs.sequence = maps.sequence "
                        "AND docs.doc_id = revs.doc_id "
                        "ORDER BY key"];
    if (options->descending)
        [sql appendString: @" DESC"];
    [sql appendString: @" LIMIT ? OFFSET ?"];
    
    FMResultSet* r = [_db.fmdb executeQuery: sql, $object(_viewID),
                                             $object(options->limit), $object(options->skip)];
    if (!r) {
        *outStatus = 500;
        return nil;
    }
    
    NSMutableArray* rows = $marray();
    while ([r next]) {
        NSData* key = fromJSON([r dataForColumnIndex: 0]);
        NSData* value = fromJSON([r dataForColumnIndex: 1]);
        NSString* docID = [r stringForColumnIndex: 2];
        NSDictionary* docContents = nil;
        if (options->includeDocs) {
            docContents = [_db documentPropertiesFromJSON: [r dataForColumnIndex: 4]
                                                    docID: docID
                                                    revID: [r stringForColumnIndex: 3]
                                                 sequence: [r longLongIntForColumnIndex: 5]];
        }
        NSDictionary* change = $dict({@"id",  docID},
                                     {@"key", key},
                                     {@"value", value},
                                     {@"doc", docContents});
        [rows addObject: change];
    }
    [r close];
    *outStatus = 200;
    NSUInteger totalRows = rows.count;      //??? Is this true, or does it ignore limit/offset?
    return $dict({@"rows", $object(rows)},
                 {@"total_rows", $object(totalRows)},
                 {@"offset", $object(options->skip)},
                 {@"update_seq", update_seq ? $object(update_seq) : nil});
}


- (NSArray*) dump {
    if (self.viewID <= 0)
        return nil;

    FMResultSet* r = [_db.fmdb executeQuery: @"SELECT sequence, key, value FROM maps "
                                              "WHERE view_id=? ORDER BY key",
                                             $object(_viewID)];
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


@end
