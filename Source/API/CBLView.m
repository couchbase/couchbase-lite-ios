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
        _weakDB = db;
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
    return _weakDB;
}


- (int) viewID {
    if (_viewID < 0)
        _viewID = [_weakDB.fmdb intForQuery: @"SELECT view_id FROM views WHERE name=?", _name];
    return _viewID;
}


- (SequenceNumber) lastSequenceIndexed {
    return [_weakDB.fmdb longLongForQuery: @"SELECT lastSequence FROM views WHERE name=?", _name];
}


- (CBLMapBlock) mapBlock {
    CBLDatabase* db = _weakDB;
    return [db.shared valueForType: @"map" name: _name inDatabaseNamed: db.name];
}

- (CBLReduceBlock) reduceBlock {
    CBLDatabase* db = _weakDB;
    return [db.shared valueForType: @"reduce" name: _name inDatabaseNamed: db.name];
}


- (BOOL) setMapBlock: (CBLMapBlock)mapBlock
         reduceBlock: (CBLReduceBlock)reduceBlock
             version: (NSString *)version
{
    Assert(mapBlock);
    Assert(version);

    CBLDatabase* db = _weakDB;
    CBL_Shared* shared = db.shared;
    [shared setValue: [mapBlock copy]
             forType: @"map" name: _name inDatabaseNamed: db.name];
    [shared setValue: [reduceBlock copy]
             forType: @"reduce" name: _name inDatabaseNamed: db.name];

    if (![db open: nil])
        return NO;

    // Update the version column in the db. This is a little weird looking because we want to
    // avoid modifying the db if the version didn't change, and because the row might not exist yet.
    CBL_FMDatabase* fmdb = db.fmdb;
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
    return self.lastSequenceIndexed < _weakDB.lastSequenceNumber;
}


- (void) removeIndex {
    if (self.viewID <= 0)
        return;
    CBLDatabase* db = _weakDB;
    CBLStatus status = [db _inTransaction: ^CBLStatus {
        if ([db.fmdb executeUpdate: @"DELETE FROM maps WHERE view_id=?",
                                     @(_viewID)]) {
            [db.fmdb executeUpdate: @"UPDATE views SET lastsequence=0 WHERE view_id=?",
                                     @(_viewID)];
        }
        return db.lastDbStatus;
    }];
    if (CBLStatusIsError(status))
        Warn(@"Error status %d removing index of %@", status, self);
}


- (void) deleteView {
    [_weakDB deleteViewNamed: _name];
    _viewID = 0;
}


- (void) databaseClosing {
    _weakDB = nil;
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
