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


// Close the index db after it's inactive this many seconds
#define kCloseDelay 60.0


static inline NSString* viewNameToFileName(NSString* viewName) {
    if ([viewName hasPrefix: @"."] || [viewName rangeOfString: @":"].length > 0)
        return nil;
    viewName = [viewName stringByReplacingOccurrencesOfString: @"/" withString: @":"];
    return [viewName stringByAppendingPathExtension: kViewIndexPathExtension];
}


@implementation CBLView
{
    NSString* _path;
    CBForestMapReduceIndex* _index;
}


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
        _path = [db.dir stringByAppendingPathComponent: viewNameToFileName(_name)];
        _mapContentOptions = kCBLIncludeLocalSeq;
        if (0) { // appease static analyzer
            _collation = 0;
        }

        if (![[NSFileManager defaultManager] fileExistsAtPath: _path isDirectory: NULL]) {
            if (!create || ![self openIndexWithOptions: kCBForestDBCreate])
                return nil;
            [self closeIndexSoon];
        }

#if TARGET_OS_IPHONE
        // On iOS, close the index when there's a low-memory notification:
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(closeIndex)
                             name: UIApplicationDidReceiveMemoryWarningNotification object: nil];
#endif
    }
    return self;
}


#if TARGET_OS_IPHONE
- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}
#endif


@synthesize name=_name, indexFilePath=_path;


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%@/%@]", self.class, _weakDB.name, _name];
}



#if DEBUG
- (void) setCollation: (CBLViewCollation)collation {
    _collation = collation;
}
#endif


- (CBLDatabase*) database {
    return _weakDB;
}


- (CBForestMapReduceIndex*) index {
    [self closeIndexSoon];
    return _index ?: [self openIndexWithOptions: 0];
}


- (CBForestMapReduceIndex*) openIndexWithOptions: (CBForestFileOptions)options {
    Assert(!_index);
    CBForestDBConfig config = {
        .bufferCacheSize = 16*1024*1024,
        .walThreshold = 4096,
        .enableSequenceTree = YES
    };
    NSError* error;
    _index = [[CBForestMapReduceIndex alloc] initWithFile: _path
                                                  options: options
                                                   config: &config
                                                    error: &error];
    if (_index)
        LogTo(View, @"%@: Opened %@", self, _index);
    else
        Warn(@"Unable to open index of %@: %@", self, error);
    return _index;
}


- (void) closeIndex {
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(closeIndex)
                                               object: nil];
    if (_index) {
        [_index close];
        _index = nil;
        LogTo(View, @"%@: Closed index db", self);
    }
}

- (void) closeIndexSoon {
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(closeIndex)
                                               object: nil];
    [self performSelector: @selector(closeIndex) withObject: nil afterDelay: kCloseDelay];
}


- (SequenceNumber) lastSequenceIndexed {
    self.index.mapVersion = self.mapVersion; // Because change of mapVersion resets lastSequenceIndexed
    return self.index.lastSequenceIndexed;
}


- (CBLMapBlock) mapBlock {
    CBLDatabase* db = _weakDB;
    return [db.shared valueForType: @"map" name: _name inDatabaseNamed: db.name];
}

- (NSString*) mapVersion {
    CBLDatabase* db = _weakDB;
    return [db.shared valueForType: @"mapVersion" name: _name inDatabaseNamed: db.name];
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

    BOOL changed = ![version isEqualToString: self.mapVersion];

    CBLDatabase* db = _weakDB;
    CBL_Shared* shared = db.shared;
    [shared setValue: [mapBlock copy]
             forType: @"map" name: _name inDatabaseNamed: db.name];
    [shared setValue: version
             forType: @"mapVersion" name: _name inDatabaseNamed: db.name];
    [shared setValue: [reduceBlock copy]
             forType: @"reduce" name: _name inDatabaseNamed: db.name];
    return changed;
}


- (BOOL) setMapBlock: (CBLMapBlock)mapBlock version: (NSString *)version {
    return [self setMapBlock: mapBlock reduceBlock: nil version: version];
}


- (BOOL) stale {
    return self.lastSequenceIndexed < _weakDB.lastSequenceNumber;
}


- (void) deleteIndex {
    NSError* error;
    if (self.index && ![_index erase: &error])
        Warn(@"Error deleting index of %@: %@", self, error);
}


- (void) deleteView {
    [self closeIndex];
    [[NSFileManager defaultManager] removeItemAtPath: _path error: NULL];
    [_weakDB forgetViewNamed: _name];
}


- (void) databaseClosing {
    [self closeIndex];
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
