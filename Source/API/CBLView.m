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
#import "CBLSpecialKey.h"
#import "CBL_Shared.h"
#import "CBLInternal.h"
#import "CBLCollateJSON.h"
#import "CBJSONEncoder.h"
#import "CBLMisc.h"
#import "ExceptionUtils.h"
}
#import <CBForest/CBForest.hh>
#import <CBForest/GeoIndex.hh>
#import <CBForest/MapReduceDispatchIndexer.hh>
#import <CBForest/Tokenizer.hh>
using namespace forestdb;
#import "CBLForestBridge.h"


// Size of ForestDB buffer cache allocated for a view index
#define kViewBufferCacheSize (8*1024*1024)

// Close the index db after it's inactive this many seconds
#define kCloseDelay 60.0


// GROUP_VIEWS_BY_DEFAULT alters the behavior of -viewsInGroup and thus which views will be
// re-indexed together. If it's defined, all views with no "/" in the name are treated as a single
// group and will be re-indexed together. If it's not defined, such views aren't in any group
// and will be re-indexed only individually. (The latter matches the CBL 1.0 behavior and
// avoids unexpected slowdowns if an app suddenly has all its views re-index at once.)
#undef GROUP_VIEWS_BY_DEFAULT


static inline NSString* viewNameToFileName(NSString* viewName) {
    if ([viewName hasPrefix: @"."] || [viewName rangeOfString: @":"].length > 0)
        return nil;
    viewName = [viewName stringByReplacingOccurrencesOfString: @"/" withString: @":"];
    return [viewName stringByAppendingPathExtension: kViewIndexPathExtension];
}

static NSString* toJSONStr(id obj) {
    if (!obj)
        return @"nil";
    return [CBLJSON stringWithJSONObject: obj options: CBLJSONWritingAllowFragments error: nil];
}


#pragma mark - C++ MAP/REDUCE GLUE:


class CocoaMappable : public Mappable {
public:
    explicit CocoaMappable(const Document& doc, NSDictionary* dict)
    :Mappable(doc), body(dict)
    { }

    __strong NSDictionary* body;
};

NSString* const kCBLViewChangeNotification = @"CBLViewChange";

class CocoaIndexer : public MapReduceIndexer {
public:
    CocoaIndexer(std::vector<MapReduceIndex*> indexes, Transaction &t)
    :MapReduceIndexer(indexes, t),
     _sourceStore(indexes[0]->sourceStore())
    { }

    virtual void addDocument(const Document& cppDoc) {
        if (VersionedDocument::flagsOfDocument(cppDoc) & VersionedDocument::kDeleted) {
            CocoaMappable mappable(cppDoc, nil);
            addMappable(mappable);
        } else {
            @autoreleasepool {
                VersionedDocument vdoc(_sourceStore, cppDoc);
                const Revision* node = vdoc.currentRevision();
                NSDictionary* body = [CBLForestBridge bodyOfNode: node
                                                         options: kCBLIncludeLocalSeq];
                LogTo(ViewVerbose, @"Mapping %@ rev %@", body.cbl_id, body.cbl_rev);
                CocoaMappable mappable(cppDoc, body);
                addMappable(mappable);
            }
        }
    }

private:
    KeyStore _sourceStore;
};


class MapReduceBridge : public MapFn {
public:
    CBLMapBlock mapBlock;
    NSString* viewName;
    CBLViewIndexType indexType;

    virtual void operator() (const Mappable& mappable, EmitFn& emitFn) {
        NSDictionary* doc = ((CocoaMappable&)mappable).body;
        if (!doc)
            return;
        CBLMapEmitBlock emit = ^(id key, id value) {
            if (indexType == kCBLFullTextIndex) {
                Assert([key isKindOfClass: [NSString class]]);
                LogTo(ViewVerbose, @"    emit(\"%@\", %@)", key, toJSONStr(value));
                emitTextTokens(key, value, doc, emitFn);
            } else if ([key isKindOfClass: [CBLSpecialKey class]]) {
                CBLSpecialKey *specialKey = key;
                LogTo(ViewVerbose, @"    emit(%@, %@)", specialKey, toJSONStr(value));
                NSString* text = specialKey.text;
                if (text) {
                    emitTextTokens(text, value, doc, emitFn);
                } else {
                    emitGeo(specialKey.rect, value, doc, emitFn);
                }
            } else if (key) {
                LogTo(ViewVerbose, @"    emit(%@, %@)  to %@", toJSONStr(key), toJSONStr(value), viewName);
                callEmit(key, value, doc, emitFn);
            }
        };
        mapBlock(doc, emit);  // Call the apps' map block!
    }

private:
    void emitTextTokens(NSString* text, id value, NSDictionary* doc, EmitFn& emitFn) {
        if (!_tokenizer)
            _tokenizer = new Tokenizer("en", true);
        for (TokenIterator i(*_tokenizer, nsstring_slice(text), true); i; ++i) {
            NSString* token = [[NSString alloc] initWithBytes: i.token().data()
                                                       length: i.token().length()
                                                     encoding: NSUTF8StringEncoding];
            value = @[@(i.wordOffset()), @(i.wordLength())];
            callEmit(token, value, doc, emitFn);
        }
    }

    void emitGeo(CBLGeoRect rect, id value, NSDictionary* doc, EmitFn& emitFn) {
        geohash::area area(geohash::coord(rect.min.x, rect.min.y),
                           geohash::coord(rect.max.x, rect.max.y));
        Collatable collKey, collValue;
        collKey << area.mid(); // HACK: Can only emit points for now
        if (value == doc)
            collValue.addSpecial(); // placeholder for doc
        else if (value)
            collValue << value;
        emitFn(collKey, collValue);
    }

    void callEmit(id key, id value, NSDictionary* doc, EmitFn& emitFn) {
        Collatable collKey, collValue;
        collKey << key;
        if (value == doc)
            collValue.addSpecial(); // placeholder for doc
        else if (value)
            collValue << value;
        emitFn(collKey, collValue);
    }

    Tokenizer* _tokenizer;
};



@implementation CBLQueryOptions

@synthesize startKey, endKey, startKeyDocID, endKeyDocID, keys, filter, fullTextQuery;

- (instancetype)init {
    self = [super init];
    if (self) {
        limit = UINT_MAX;
        inclusiveStart = YES;
        inclusiveEnd = YES;
        fullTextRanking = YES;
        // everything else will default to nil/0/NO
    }
    return self;
}

@end



#pragma mark -

@implementation CBLView
{
    NSString* _path;
    Database* _indexDB;
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
    Assert(!_indexDB);
    Assert(!_index);
    auto config = Database::defaultConfig();
    config.buffercache_size = kViewBufferCacheSize;
    config.wal_threshold = 8192;
    config.wal_flush_before_commit = true;
    config.seqtree_opt = YES;
    config.compaction_threshold = 50;
    try {
        _indexDB = new Database(_path.fileSystemRepresentation, options, config);
        _index = new MapReduceIndex(_indexDB, "index", *_weakDB.forestDB);
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
    LogTo(View, @"%@: Opened index %p (type %d)", self, _index, _index->indexType());
    return _index;
}


- (void) closeIndex {
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(closeIndex)
                                               object: nil];
    if (_indexDB)
        LogTo(View, @"%@: Closing index db", self);
    delete _indexDB;
    _indexDB = NULL;
    delete _index;
    _index = NULL;
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
        Transaction t(_indexDB);
        _index->erase(t);
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
    if (changed) {
        // update any live queries that might be listening to this view, now that it has changed
        [self postPublicChangeNotification];
    }
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
    NSError* error;
    NSString* version = CBLHexSHA1Digest([CBJSONEncoder canonicalEncoding: viewProps error: NULL]);
    if (!version) {
        Warn(@"View %@ has invalid JSON values: %@", _name, error);
        return NO;
    }

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


- (NSArray*) viewsInGroup {
    int (^filter)(CBLView* view);
    NSRange slash = [_name rangeOfString: @"/"];
    if (slash.length > 0) {
        // Return all the views whose name starts with the same prefix before the slash:
        NSString* prefix = [_name substringToIndex: NSMaxRange(slash)];
        filter = ^int(CBLView* view) {
            return [view.name hasPrefix: prefix];
        };
    } else {
#ifdef GROUP_VIEWS_BY_DEFAULT
        // Return all the views that don't have a slash in their names:
        filter = ^int(CBLView* view) {
            return [view.name rangeOfString: @"/"].length == 0;
        };
#else
        // Without GROUP_VIEWS_BY_DEFAULT, views with no "/" in the name aren't in any group:
        return @[self];
#endif
    }
    return [_weakDB.allViews my_filter: filter];
}


- (void) setupIndex {
    _mapReduceBridge.mapBlock = self.mapBlock;
    _mapReduceBridge.viewName = _name;
    _mapReduceBridge.indexType = _indexType;
    (void)self.index; // open db
    {
        Transaction t(_indexDB);
        _index->setup(t, _indexType, &_mapReduceBridge, self.mapVersion.UTF8String);
    }
}


/** Updates the view's index, if necessary. (If no changes needed, returns kCBLStatusNotModified.)*/
- (CBLStatus) updateIndex {
    return [self updateIndexes: self.viewsInGroup];
}

- (CBLStatus) updateIndexAlone {
    return [self updateIndexes: @[self]];
}

- (CBLStatus) updateIndexes: (NSArray*)views {
    try {
        std::vector<MapReduceIndex*> indexes;
        for (CBLView* view in views) {
            [view setupIndex];
            CBLMapBlock mapBlock = view.mapBlock;
            Assert(mapBlock, @"Cannot reindex view '%@' which has no map block set", _name);
            MapReduceIndex* index = view.index;
            if (!index)
                return kCBLStatusNotFound;
            indexes.push_back(index);
        }
        (void)self.index;
        bool updated;
        {
            Transaction t(_indexDB);
            CocoaIndexer indexer(indexes, t);
            indexer.triggerOnIndex(_index);
            updated = indexer.run();
        }
        return updated ? kCBLStatusOK : kCBLStatusNotModified;
    } catch (forestdb::error x) {
        Warn(@"Error indexing %@: ForestDB error %d", self, x.status);
        return CBLStatusFromForestDBStatus(x.status);
    } catch (...) {
        Warn(@"Unexpected exception indexing %@", self);
        return kCBLStatusException;
    }
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


#pragma mark - QUERYING:


- (NSUInteger) totalRows {
    return (NSUInteger) self.index->rowCount();
}


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
