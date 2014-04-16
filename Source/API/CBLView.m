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
#import "CBLCanonicalJSON.h"
#import "CBLMisc.h"

#import <CBForest/CBForest.h>
#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "FMResultSet.h"


static inline NSString* viewNameToFileName(NSString* viewName) {
    if ([viewName hasPrefix: @"."] || [viewName rangeOfString: @":"].length > 0)
        return nil;
    viewName = [viewName stringByReplacingOccurrencesOfString: @"/" withString: @":"];
    return [viewName stringByAppendingPathExtension: kViewIndexPathExtension];
}


@implementation CBLView


+ (NSString*) fileNameToViewName: (NSString*)fileName {
    if (![fileName.pathExtension isEqualToString: kViewIndexPathExtension])
        return nil;
    if ([fileName hasPrefix: @"."])
        return nil;
    NSString* viewName = fileName.stringByDeletingPathExtension;
    viewName = [viewName stringByReplacingOccurrencesOfString: @":" withString: @"/"];
    return viewName;
}


- (instancetype) initWithDatabase: (CBLDatabase*)db name: (NSString*)name create: (BOOL)create {
    Assert(db);
    Assert(name.length);
    self = [super init];
    if (self) {
        _weakDB = db;
        _name = [name copy];
        _mapContentOptions = kCBLIncludeLocalSeq;
        if (0) { // appease static analyzer
            _collation = 0;
        }

        NSString* filename = viewNameToFileName(_name);
        if (!filename)
            return nil;
        NSString* path = [db.dir stringByAppendingPathComponent: filename];
        _index = [[CBForestMapReduceIndex alloc] initWithFile: path
                                                      options: (create ? kCBForestDBCreate : 0)
                                                        error: NULL];
        if (!_index)
            return nil;
    }
    return self;
}


@synthesize name=_name;


- (CBLDatabase*) database {
    return _weakDB;
}


- (SequenceNumber) lastSequenceIndexed {
    return _index.lastSequenceIndexed;
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


- (void) deleteIndex {
    if (!_index)
        return;
    NSString* path = _index.filename;
    [_index close];
    _index = nil;
    NSError* error;
    if( ![[NSFileManager defaultManager] removeItemAtPath: path error: &error])
        Warn(@"Error removing index of %@: %@", self, error);
    _index = [[CBForestMapReduceIndex alloc] initWithFile: path
                                                  options: kCBForestDBCreate
                                                    error: NULL];
    if (!_index)
        Warn(@"Error re-opening index of %@: %@", self, error);
}


- (void) deleteView {
    NSString* path = _index.filename;
    [_index close];
    _index = nil;
    [[NSFileManager defaultManager] removeItemAtPath: path error: NULL];
    [_weakDB forgetViewNamed: _name];
}


- (void) databaseClosing {
    [_index close];
    _index = nil;
    _weakDB = nil;
}


- (CBLQuery*) createQuery {
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
