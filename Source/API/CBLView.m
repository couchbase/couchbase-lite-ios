//
//  CBLView.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/19/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "CouchbaseLitePrivate.h"
#import "CBLView+Internal.h"
#import "CBLInternal.h"
#import "CBLCollateJSON.h"
#import "CBLCanonicalJSON.h"
#import "CBLMisc.h"

#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "FMResultSet.h"


@implementation CBLView


- (instancetype) initWithDatabase: (CBL_Database*)db name: (NSString*)name {
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


@synthesize name=_name, mapBlock=_mapBlock, reduceBlock=_reduceBlock;


- (CBLDatabase*) database {
    return _db.publicDatabase;
}


- (int) viewID {
    if (_viewID < 0)
        _viewID = [_db.fmdb intForQuery: @"SELECT view_id FROM views WHERE name=?", _name];
    return _viewID;
}


- (SequenceNumber) lastSequenceIndexed {
    return [_db.fmdb longLongForQuery: @"SELECT lastSequence FROM views WHERE name=?", _name];
}


- (BOOL) setMapBlock: (CBLMapBlock)mapBlock
         reduceBlock: (CBLReduceBlock)reduceBlock
             version: (NSString *)version
{
    Assert(mapBlock);
    Assert(version);
    _mapBlock = mapBlock; // copied implicitly in ARC
    _reduceBlock = reduceBlock; // copied implicitly in ARC
    
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


- (BOOL) setMapBlock: (CBLMapBlock)mapBlock version: (NSString *)version {
    return [self setMapBlock: mapBlock reduceBlock: nil version: version];
}


- (BOOL) stale {
    return self.lastSequenceIndexed < _db.lastSequence;
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


- (CBLQuery*) query {
    return [[CBLQuery alloc] initWithDatabase: self.database view: self];
}


+ (NSNumber*) totalValues: (NSArray*)values {
    double total = 0;
    for (NSNumber* value in values)
        total += value.doubleValue;
    return @(total);
}


static id<CBLViewCompiler> sCompiler;


+ (void) setCompiler: (id<CBLViewCompiler>)compiler {
    sCompiler = compiler;
}

+ (id<CBLViewCompiler>) compiler {
    return sCompiler;
}


@end
