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
#import "ExceptionUtils.h"

#import <CBForest/CBForest.h>


// Close the index db after it's inactive this many seconds
#define kCloseDelay 60.0


static inline NSString* viewNameToFileName(NSString* viewName) {
    if ([viewName hasPrefix: @"."] || [viewName rangeOfString: @":"].length > 0)
        return nil;
    viewName = [viewName stringByReplacingOccurrencesOfString: @"/" withString: @":"];
    return [viewName stringByAppendingPathExtension: kViewIndexPathExtension];
}



@implementation CBLQueryOptions

@synthesize startKey, endKey, startKeyDocID, endKeyDocID, keys, fullTextQuery;

- (instancetype)init {
    self = [super init];
    if (self) {
        limit = UINT_MAX;
        inclusiveEnd = YES;
        fullTextRanking = YES;
        // everything else will default to nil/0/NO
    }
    return self;
}

@end




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


- (void) databaseClosing {
    [self closeIndex];
    _weakDB = nil;
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


#pragma mark - CONFIGURATION:


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


static id<CBLViewCompiler> sCompiler;


+ (void) setCompiler: (id<CBLViewCompiler>)compiler {
    sCompiler = compiler;
}

+ (id<CBLViewCompiler>) compiler {
    return sCompiler;
}


- (BOOL) compileFromProperties: (NSDictionary*)viewProps language: (NSString*)language {
    if (!language)
        language = @"javascript";
    NSString* mapSource = viewProps[@"map"];
    if (!mapSource)
        return NO;
    CBLMapBlock mapBlock = [[CBLView compiler] compileMapFunction: mapSource language: language];
    if (!mapBlock) {
        Warn(@"View %@ has unknown map function: %@", _name, mapSource);
        return NO;
    }
    NSString* reduceSource = viewProps[@"reduce"];
    CBLReduceBlock reduceBlock = NULL;
    if (reduceSource) {
        reduceBlock =[[CBLView compiler] compileReduceFunction: reduceSource language: language];
        if (!reduceBlock) {
            Warn(@"View %@ has unknown reduce function: %@", _name, reduceSource);
            return NO;
        }
    }

    // Version string is based on a digest of the properties:
    NSString* version = CBLHexSHA1Digest([CBLCanonicalJSON canonicalData: viewProps]);

    [self setMapBlock: mapBlock reduceBlock: reduceBlock version: version];

    NSDictionary* options = $castIf(NSDictionary, viewProps[@"options"]);
    _collation = ($equal(options[@"collation"], @"raw")) ? kCBLViewCollationRaw
                                                             : kCBLViewCollationUnicode;
    return YES;
}


#pragma mark - INDEXING:


/** Updates the view's index, if necessary. (If no changes needed, returns kCBLStatusNotModified.)*/
- (CBLStatus) updateIndex {
    LogTo(View, @"Re-indexing view %@ ...", _name);
    CBLDatabase* db = _weakDB;
    NSString* viewName = _name;
    CBLContentOptions contentOptions = _mapContentOptions;
    CBLMapBlock mapBlock = self.mapBlock;
    Assert(mapBlock, @"Cannot reindex view '%@' which has no map block set", _name);
    CBForestMapReduceIndex* index = self.index;
    if (!index)
        return kCBLStatusNotFound;

    index.sourceDatabase = db.forestDB;
    index.mapVersion = self.mapVersion;
    index.map = ^(CBForestDocument* baseDoc, NSData* data, CBForestIndexEmitBlock emit) {
        CBForestVersions* doc = (CBForestVersions*)baseDoc;
        NSString *docID=doc.docID, *revID=doc.revID;
        SequenceNumber sequence = doc.sequence;
        NSData* json = [doc dataOfRevision: nil];
        NSDictionary* properties = [db documentPropertiesFromJSON: json
                                                            docID: docID
                                                            revID: revID
                                                          deleted: NO
                                                         sequence: sequence
                                                          options: contentOptions];
        if (!properties) {
            Warn(@"Failed to parse JSON of doc %@ rev %@", docID, revID);
            return;
        }

        // Call the user-defined map() to emit new key/value pairs from this revision:
        LogTo(View, @"  call map for sequence=%lld...", sequence);
        @try {
            mapBlock(properties, emit);
        } @catch (NSException* x) {
            MYReportException(x, @"map block of view '%@'", viewName);
        }
    };

    uint64_t lastSequence = index.lastSequenceIndexed;
    NSError* error;
    BOOL ok = [index updateIndex: &error];
    index.map = nil;

    if (!ok)
        return kCBLStatusDBError; //FIX: Improve this
    else if (index.lastSequenceIndexed == lastSequence)
        return kCBLStatusNotModified;
    else
        return kCBLStatusOK;
}


+ (NSNumber*) totalValues: (NSArray*)values {
    double total = 0;
    for (NSNumber* value in values)
        total += value.doubleValue;
    return @(total);
}


#pragma mark - QUERYING:


- (SequenceNumber) lastSequenceIndexed {
    self.index.mapVersion = self.mapVersion; // Because change of mapVersion resets lastSequenceIndexed
    return self.index.lastSequenceIndexed;
}


- (BOOL) stale {
    return self.lastSequenceIndexed < _weakDB.lastSequenceNumber;
}


- (CBLQuery*) createQuery {
    return [[CBLQuery alloc] initWithDatabase: self.database view: self];
}


@end
