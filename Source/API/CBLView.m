//
//  CBLView.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/19/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CouchbaseLitePrivate.h"
#import "CBLView+Internal.h"
#import "CBL_Shared.h"
#import "CBLInternal.h"
#import "CBLCollateJSON.h"
#import "CBLMisc.h"

#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "FMResultSet.h"

NSString* const kCBLViewChangeNotification = @"CBLViewChange";

@implementation CBLView


- (instancetype) initWithDatabase: (CBLDatabase*)db name: (NSString*)name {
    Assert(db);
    Assert(name.length);
    self = [super init];
    if (self) {
        _weakDB = db;
        _name = [name copy];
        _viewID = -1;  // means 'unknown'
        _collation = 0;
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


- (NSUInteger) totalRows {
    CBLDatabase* db = _weakDB;
    NSInteger totalRows = [db.fmdb intForQuery: @"SELECT total_docs FROM views WHERE name=?", _name];
    if (totalRows == -1) { // mean unknown
        totalRows = [db.fmdb intForQuery: @"SELECT COUNT(view_id) FROM maps WHERE view_id=?",
                     @(self.viewID)];
        [db.fmdb executeUpdate: @"UPDATE views SET total_docs=? WHERE view_id=?",
            @(totalRows), @(self.viewID)];
    }
    Assert(totalRows >= 0);
    return totalRows;
}


- (SequenceNumber) lastSequenceIndexed {
    return [_weakDB.fmdb longLongForQuery: @"SELECT lastSequence FROM views WHERE name=?", _name];
}


- (CBLMapBlock) registeredMapBlock {
    CBLDatabase* db = _weakDB;
    return [db.shared valueForType: @"map" name: _name inDatabaseNamed: db.name];
}

- (CBLMapBlock) mapBlock {
    CBLMapBlock map = self.registeredMapBlock;
    if (!map)
        if ([self compileFromDesignDoc] == kCBLStatusOK)
            map = self.registeredMapBlock;
    return map;
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
    if (![fmdb executeUpdate: @"INSERT OR IGNORE INTO views (name, version, total_docs) "
                               "VALUES (?, ?, ?)",
                              _name, version, @(0)])
        return NO;
    if (fmdb.changes)
        return YES;     // created new view
    if (![fmdb executeUpdate: @"UPDATE views SET version=?, lastSequence=0, total_docs=0 "
                               "WHERE name=? AND version!=?", 
                              version, _name, version])
        return NO;
    
    if (fmdb.changes > 0) {
        // update any live queries that might be listening to this view, now that it has changed
        [self postPublicChangeNotification];
    
        return YES;
    } else {
        return NO;
    }
}


- (BOOL) setMapBlock: (CBLMapBlock)mapBlock version: (NSString *)version {
    return [self setMapBlock: mapBlock reduceBlock: nil version: version];
}


- (BOOL) stale {
    return self.lastSequenceIndexed < _weakDB.lastSequenceNumber;
}


- (void) deleteIndex {
    if (self.viewID <= 0)
        return;
    CBLDatabase* db = _weakDB;
    CBLStatus status = [db _inTransaction: ^CBLStatus {
        if ([db.fmdb executeUpdate: @"DELETE FROM maps WHERE view_id=?",
                                     @(_viewID)]) {
            [db.fmdb executeUpdate: @"UPDATE views SET lastsequence=0, total_docs=0 WHERE view_id=?",
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


- (CBLQuery*) createQuery {
    return [[CBLQuery alloc] initWithDatabase: self.database view: self];
}

- (void) postPublicChangeNotification {
    // Post the public kCBLViewChangeNotification:
    NSNotification* notification = [NSNotification notificationWithName: kCBLViewChangeNotification
                                                                 object: self
                                                               userInfo: nil];
    [_weakDB postNotification:notification];
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
