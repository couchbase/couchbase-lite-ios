//
//  CBLView.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/19/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "CouchbaseLitePrivate.h"
#import "CBLView+Internal.h"
#import "CBL_Shared.h"
#import "CBLInternal.h"
#import "CBLCollateJSON.h"
#import "CBLCanonicalJSON.h"
#import "CBLMisc.h"

#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "FMResultSet.h"


@implementation CBLView


- (instancetype) initWithDatabase: (CBLDatabase*)db name: (NSString*)name {
    Assert(db);
    Assert(name.length);
    self = [super init];
    if (self) {
        _db = db;
        _name = [name copy];
        _viewID = -1;  // means 'unknown'
        if (0) { // appease static analyzer
            _collation = 0;
            _mapContentOptions = 0;
        }
    }
    return self;
}


@synthesize name=_name;


- (CBLDatabase*) database {
    return _db;
}


- (int) viewID {
    if (_viewID < 0)
        _viewID = [_db.fmdb intForQuery: @"SELECT view_id FROM views WHERE name=?", _name];
    return _viewID;
}


- (SequenceNumber) lastSequenceIndexed {
    return [_db.fmdb longLongForQuery: @"SELECT lastSequence FROM views WHERE name=?", _name];
}


- (CBLMapBlock) mapBlock {
    return [_db.shared valueForType: @"map" name: _name inDatabaseNamed: _db.name];
}

- (CBLReduceBlock) reduceBlock {
    return [_db.shared valueForType: @"reduce" name: _name inDatabaseNamed: _db.name];
}


- (BOOL) setMapBlock: (CBLMapBlock)mapBlock
         reduceBlock: (CBLReduceBlock)reduceBlock
             version: (NSString *)version
{
    Assert(mapBlock);
    Assert(version);
    
    [_db.shared setValue: [mapBlock copy]
                 forType: @"map" name: _name inDatabaseNamed: _db.name];
    [_db.shared setValue: [reduceBlock copy]
                 forType: @"reduce" name: _name inDatabaseNamed: _db.name];

    if (![_db open: nil])
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
    return self.lastSequenceIndexed < _db.lastSequenceNumber;
}


- (void) removeIndex {
    if (self.viewID <= 0)
        return;
    CBLStatus status = [_db _inTransaction: ^CBLStatus {
        if ([_db.fmdb executeUpdate: @"DELETE FROM maps WHERE view_id=?",
                                     @(_viewID)]) {
            [_db.fmdb executeUpdate: @"UPDATE views SET lastsequence=0 WHERE view_id=?",
                                     @(_viewID)];
        }
        return _db.lastDbStatus;
    }];
    if (CBLStatusIsError(status))
        Warn(@"Error status %d removing index of %@", status, self);
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
