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

extern "C" {
#import "CouchbaseLitePrivate.h"
#import "CBLView+Internal.h"
#import "CBL_Shared.h"
#import "CBLInternal.h"
#import "CBLCollateJSON.h"
#import "CBLCanonicalJSON.h"
#import "CBLMisc.h"
#import "ExceptionUtils.h"
}
#import <CBForest/CBForest.hh>
using namespace forestdb;
#import "CBLForestBridge.h"


// Size of ForestDB buffer cache allocated for a view index
#define kViewBufferCacheSize (8*1024*1024)

// Close the index db after it's inactive this many seconds
#define kCloseDelay 60.0


static inline NSString* viewNameToFileName(NSString* viewName) {
    if ([viewName hasPrefix: @"."] || [viewName rangeOfString: @":"].length > 0)
        return nil;
    viewName = [viewName stringByReplacingOccurrencesOfString: @"/" withString: @":"];
    return [viewName stringByAppendingPathExtension: kViewIndexPathExtension];
}


class MapReduceBridge : public MapFn {
public:
    Database* db;
    CBLMapBlock mapBlock;
    virtual void operator() (const Document& cppDoc, EmitFn& emitFn) {
        if (VersionedDocument::flagsOfDocument(cppDoc) & VersionedDocument::kDeleted)
            return;
        VersionedDocument vdoc(db, cppDoc);
        const Revision* node = vdoc.currentRevision();
        @autoreleasepool {
            NSDictionary* doc = [CBLForestBridge bodyOfNode: node options: kCBLIncludeLocalSeq];
            CBLMapEmitBlock emit = ^(id key, id value) {
                if (key) {
                    Collatable collKey, collValue;
                    collKey << key;
                    if (value)
                        collValue << value;
                    emitFn(collKey, collValue);
                }
            };
            mapBlock(doc, emit);
        }
    }
};



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
    MapReduceIndex* _index;
    CBLViewIndexType _indexType;
    MapReduceBridge _mapReduceBridge;
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
        _indexType = (CBLViewIndexType)-1; // unknown
        if ((0)) { // appease static analyzer
            _collation = 0;
        }

        if (![[NSFileManager defaultManager] fileExistsAtPath: _path isDirectory: NULL]) {
            if (!create || ![self openIndexWithOptions: FDB_OPEN_FLAG_CREATE])
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


@synthesize name=_name;


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%@/%@]", self.class, _weakDB.name, _name];
}



#if DEBUG
@synthesize indexFilePath=_path;

- (void) setCollation: (CBLViewCollation)collation {
    _collation = collation;
}
#endif


- (CBLDatabase*) database {
    return _weakDB;
}


- (MapReduceIndex*) index {
    [self closeIndexSoon];
    return _index ?: [self openIndexWithOptions: 0];
}


- (MapReduceIndex*) openIndexWithOptions: (Database::openFlags)options {
    Assert(!_index);
    MapReduceIndex::config config = MapReduceIndex::defaultConfig();
    config.buffercache_size = kViewBufferCacheSize;
    config.wal_threshold = 8192;
    config.wal_flush_before_commit = true;
    config.seqtree_opt = YES;
    config.compaction_threshold = 50;
    try {
        _index = new MapReduceIndex(_path.fileSystemRepresentation, options, config,
                                    _weakDB.forestDB);
    } catch (forestdb::error x) {
        Warn(@"Unable to open index of %@: ForestDB error %d", self, x.status);
        return nil;
    } catch (...) {
        Warn(@"Unable to open index of %@: Unexpected exception", self);
        return nil;
    }

//    if (_indexType >= 0)
//        _index->indexType = _indexType;  // In case it was changed while index was closed
//    if (_indexType == kCBLFullTextIndex)
//        _index->textTokenizer = [[CBTextTokenizer alloc] init];
    LogTo(View, @"%@: Opened index %p", self, _index);
    return _index;
}


- (void) closeIndex {
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(closeIndex)
                                               object: nil];
    if (_index) {
        delete _index;
        _index = NULL;
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
    if (self.index) {
        IndexTransaction t(_index);
        t.erase();
    }
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


- (CBLViewIndexType) indexType {
    if (_index || _indexType < 0)
        _indexType = (CBLViewIndexType) self.index->indexType();
    return _indexType;
}

- (void)setIndexType:(CBLViewIndexType)indexType {
    _indexType = indexType;
}


#pragma mark - INDEXING:


- (void) setupIndex {
    _mapReduceBridge.db = _weakDB.forestDB;
    _mapReduceBridge.mapBlock = self.mapBlock;
    self.index->setup(_indexType, &_mapReduceBridge, self.mapVersion.UTF8String);
}


/** Updates the view's index, if necessary. (If no changes needed, returns kCBLStatusNotModified.)*/
- (CBLStatus) updateIndex {
    LogTo(View, @"Re-indexing view %@ ...", _name);
    CBLMapBlock mapBlock = self.mapBlock;
    Assert(mapBlock, @"Cannot reindex view '%@' which has no map block set", _name);
    MapReduceIndex* index = self.index;
    if (!index)
        return kCBLStatusNotFound;

    [self setupIndex];

    uint64_t lastSequence = index->lastSequenceIndexed();

    try {
        index->updateIndex();
    } catch (forestdb::error x) {
        Warn(@"Error indexing %@: ForestDB error %d", self, x.status);
        return CBLStatusFromForestDBStatus(x.status);
    } catch (...) {
        Warn(@"Unexpected exception indexing %@", self);
        return kCBLStatusException;
    }

    if (index->lastSequenceIndexed() == lastSequence)
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
    [self setupIndex]; // in case the _mapVersion changed, invalidating the index
    return self.index->lastSequenceIndexed();
}


- (SequenceNumber) lastSequenceChangedAt {
    [self setupIndex]; // in case the _mapVersion changed, invalidating the index
    return self.index->lastSequenceChangedAt();
}


- (BOOL) stale {
    return self.lastSequenceIndexed < _weakDB.lastSequenceNumber;
}


- (CBLQuery*) createQuery {
    return [[CBLQuery alloc] initWithDatabase: self.database view: self];
}


@end
