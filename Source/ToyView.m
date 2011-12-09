//
//  ToyView.m
//  ToyCouch
//
//  Created by Jens Alfke on 12/8/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "ToyView.h"
#import "ToyDB_Internal.h"

#import "FMDatabase.h"
#import "FMResultSet.h"


const ToyDBQueryOptions kDefaultToyDBQueryOptions = {
    nil, nil, 0, INT_MAX, NO, NO, NO
};


@implementation ToyView


- (id) initWithDatabase: (ToyDB*)db name: (NSString*)name {
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


- (BOOL) setMapBlock: (ToyMapBlock)mapBlock version:(NSString *)version {
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


- (BOOL) updateIndex {
    LogTo(View, @"Re-indexing view %@ ...", _name);
    Assert(_mapBlock, @"Cannot reindex view '%@' which has no map block set", _name);
    
    int viewID = self.viewID;
    if (viewID <= 0)
        return NO;
    
    [_db beginTransaction];
    BOOL ok = NO;
    
    __block SequenceNumber sequence = 0;
    __block BOOL emitFailed = NO;
    FMDatabase* fmdb = _db.fmdb;
    FMResultSet* r = nil;
    
    SequenceNumber lastSequence = self.lastSequenceIndexed;
    if (!lastSequence < 0)
        goto exit;
    sequence = lastSequence;
    
    // This is the emit() block, which gets called from within the user-defined map() block
    // that's called down below.
    ToyEmitBlock emit = ^(id key, id value) {
        if (!key)
            return;
        NSString* keyJSON = toJSONString(key);
        NSString* valueJSON = toJSONString(value);
        LogTo(View, @"    emit(%@, %@)", keyJSON, valueJSON);
        if (![fmdb executeUpdate: @"INSERT INTO maps (view_id, sequence, key, value) VALUES "
                                    "(?, ?, ?, ?)",
                                    $object(viewID), $object(sequence), keyJSON, valueJSON])
            emitFailed = YES;
    };
    
    // If the lastSequence has been reset to 0, make sure to remove any leftover rows:
    if (lastSequence == 0) {
        if (![fmdb executeUpdate: @"DELETE FROM maps WHERE view_id=?",
                                  $object(_viewID)])
            goto exit;
    }

    
    // Now scan every revision added since the last time the view was indexed:
    r = [fmdb executeQuery: @"SELECT sequence, parent, current, deleted, json FROM docs "
                             "WHERE sequence>?",
                             $object(lastSequence)];
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
    if (![fmdb executeUpdate: @"UPDATE views SET lastSequence=? WHERE view_id=?",
                               $object(sequence), $object(viewID)])
        goto exit;
        
    LogTo(View, @"...Finished re-indexing view %@ up to sequence %lld", _name, sequence);
    ok = YES;
    
exit:
    [r close];
    if (!ok) {
        Warn(@"ToyDB: Failed to rebuild view '%@'", _name);
        _db.transactionFailed = YES;
    }
    [_db endTransaction];
    return ok;
}


#pragma mark - QUERYING:


- (NSDictionary*) queryWithOptions: (const ToyDBQueryOptions*)options {
    if (!options)
        options = &kDefaultToyDBQueryOptions;
    
    if (![self updateIndex])
        return nil;

    SequenceNumber update_seq = 0;
    if (options->updateSeq)
        update_seq = self.lastSequenceIndexed; // TODO: needs to be atomic with the following SELECT
    
    NSMutableString* sql = [NSMutableString stringWithString: @"SELECT key, value, docs.docid"];
    if (options->includeDocs)
        [sql appendString: @", docs.json"];
    [sql appendString: @" FROM maps, docs "
                        "WHERE maps.view_id=? AND docs.sequence = maps.sequence ORDER BY key"];
    if (options->descending)
        [sql appendString: @" DESC"];
    [sql appendString: @" LIMIT ? OFFSET ?"];
    
    FMResultSet* r = [_db.fmdb executeQuery: sql, $object(_viewID),
                                             $object(options->limit), $object(options->skip)];
    if (!r)
        return nil;
    
    NSMutableArray* rows = $marray();
    while ([r next]) {
        NSData* key = fromJSON([r dataForColumnIndex: 0]);
        NSData* value = fromJSON([r dataForColumnIndex: 1]);
        NSString* docID = [r stringForColumnIndex: 2];
        NSDictionary* docContents = nil;
        if (options->includeDocs)
            docContents = fromJSON([r dataForColumnIndex: 3]);
        NSDictionary* change = $dict({@"id",  docID},
                                     {@"key", key},
                                     {@"value", value},
                                     {@"doc", docContents});
        [rows addObject: change];
    }
    [r close];
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
