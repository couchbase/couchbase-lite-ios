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
    if (_viewID < 0) {
        FMResultSet* r = [_db.fmdb executeQuery: @"SELECT view_id FROM views WHERE name=?", _name];
        if ([r next])
            _viewID = [r intForColumnIndex: 0];
        else
            _viewID = 0;
        [r close];
    }
    return _viewID;
}


- (SequenceNumber) lastSequenceIndexed {
    FMResultSet* r = [_db.fmdb executeQuery: @"SELECT lastSequence FROM views WHERE name=?",
                                             _name];
    if (!r)
        return -1;
    SequenceNumber lastSequence = 0;
    if ([r next])
        lastSequence = [r longLongIntForColumnIndex: 0];
    [r close];
    return lastSequence;
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
    TDStatus status = 500;
    
    __block SequenceNumber sequence = 0;
    __block BOOL emitFailed = NO;
    unsigned deleted = 0;
    __block unsigned inserted = 0;
    FMDatabase* fmdb = _db.fmdb;
    FMResultSet* r = nil;
    
    const SequenceNumber lastSequence = self.lastSequenceIndexed;
    if (!lastSequence < 0)
        goto exit;
    sequence = lastSequence;
    
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
    
    // If the lastSequence has been reset to 0, make sure to remove any leftover rows:
    if (lastSequence == 0) {
        if (![fmdb executeUpdate: @"DELETE FROM maps WHERE view_id=?",
                                  $object(_viewID)])
            goto exit;
    }

    SequenceNumber dbMaxSequence = _db.lastSequence;
    
    // Now scan every revision added since the last time the view was indexed:
    r = [fmdb executeQuery: @"SELECT sequence, parent, current, deleted, json FROM revs "
                             "WHERE sequence>? "
                             "AND ((parent>0 AND parent<?) OR (current!=0 AND deleted=0))",
                             $object(lastSequence), $object(lastSequence)];
    if (!r)
        goto exit;
    while ([r next]) {
        @autoreleasepool {
            sequence = [r longLongIntForColumnIndex: 0];
            SequenceNumber parentSequence = [r longLongIntForColumnIndex: 1];
            BOOL current = [r boolForColumnIndex: 2];
            BOOL deleted = [r boolForColumnIndex: 3];
            NSData* json = [r dataForColumnIndex: 4];
            LogTo(View, @"Seq# %lld:", sequence);
            
            if (parentSequence && parentSequence <= lastSequence) {
                // Delete any map results emitted from now-obsolete revisions:
                LogTo(View, @"  delete maps for sequence=%lld", parentSequence);
                if (![fmdb executeUpdate: @"DELETE FROM maps WHERE sequence=? AND view_id=?",
                                           $object(parentSequence), $object(viewID)])
                    goto exit;
                deleted += fmdb.changes;
            }
            if (current && !deleted) {
                // Call the user-defined map() to emit new key/value pairs from this revision:
                LogTo(View, @"  call map for sequence=%lld...", sequence);
                NSDictionary* properties = [NSJSONSerialization JSONObjectWithData: json
                                                                           options: 0 error: nil];
                if (properties) {
                    _mapBlock(properties, emit);
                    if (emitFailed)
                        goto exit;
                }
            }
        }
    }
    [r close];
    r = nil;
    
    // Finally, record the last revision sequence number that was indexed:
    if (sequence > dbMaxSequence) {
        if (![fmdb executeUpdate: @"UPDATE views SET lastSequence=? WHERE view_id=?",
                                   $object(dbMaxSequence), $object(viewID)])
            goto exit;
    }
    
    LogTo(View, @"...Finished re-indexing view %@ to #%lld (deleted %u, added %u)",
          _name, dbMaxSequence, deleted, inserted);
    status = 200;
    
exit:
    [r close];
    if (status >= 300) {
        Warn(@"TouchDB: Failed to rebuild view '%@': %d", _name, status);
        _db.transactionFailed = YES;
    }
    [_db endTransaction];
    return status;
}


#pragma mark - QUERYING:


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
        [sql appendString: @", json, revs.sequence"];
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
        NSMutableDictionary* docContents = nil;
        if (options->includeDocs) {
            docContents = [NSJSONSerialization JSONObjectWithData: [r dataForColumnIndex: 3]
                                                          options: NSJSONReadingMutableContainers
                                                            error: nil];
            SequenceNumber sequence = [r longLongIntForColumnIndex: 4];
            NSDictionary* attachmentDict = [_db getAttachmentDictForSequence: sequence];
            if (attachmentDict)
                [docContents addEntriesFromDictionary: attachmentDict];
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
