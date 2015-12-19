//
//  CBL_ViewStorage.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/13/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

extern "C" {
#import "CBL_ForestDBViewStorage.h"
#import "CBL_ForestDBStorage.h"
#import "CBLSpecialKey.h"
#import "CouchbaseLitePrivate.h"
#import "CBLInternal.h"
#import "CBLMisc.h"
#import "ExceptionUtils.h"
#import "CBLSymmetricKey.h"
#import "MYAction.h"
}
#import <CBForest/CBForest.hh>
#import <CBForest/GeoIndex.hh>
#import <CBForest/MapReduceDispatchIndexer.hh>
#import <CBForest/Tokenizer.hh>
using namespace cbforest;
#import "CBLForestBridge.h"
using namespace couchbase_lite;


@interface CBL_ForestDBViewStorage () <CBL_QueryRowStorage>
@end


#define kViewIndexPathExtension @"viewindex"

// Close the index db after it's inactive this many seconds
#define kCloseDelay 60.0


static geohash::area geoRectToArea(CBLGeoRect rect) {
    return geohash::area(geohash::coord(rect.min.y, rect.min.x),        // lat/lon order
                         geohash::coord(rect.max.y, rect.max.x));
}

static CBLGeoRect areaToGeoRect(geohash::area area) {
    return CBLGeoRect{{area.longitude.min, area.latitude.min},
                      {area.longitude.max, area.latitude.max}};
}


#pragma mark - C++ MAP/REDUCE GLUE:


class CocoaMappable : public Mappable {
public:
    explicit CocoaMappable(const Document& doc, NSDictionary* dict)
    :Mappable(doc), body(dict)
    { }

    __strong NSDictionary* body;
};

class CocoaIndexer : public MapReduceIndexer {
public:
    CocoaIndexer() { }

    void addDocType(const alloc_slice& type) {
        _docTypes.push_back(type);
    }

    void clearDocTypes() {
        _docTypes.clear();
    }

    virtual void addDocument(const Document& cppDoc) {
        bool indexIt = true;
        VersionedDocument::Flags flags;
        revid revID;
        slice docType;
        if (!VersionedDocument::readMeta(cppDoc, flags, revID, docType)) {
            indexIt = false;
        } else if (flags & VersionedDocument::kDeleted) {
            indexIt = false;
        } else if (cppDoc.key().hasPrefix(slice("_design/"))) {
            indexIt = false; // design docs don't get indexed!
        } else if (_docTypes.size() > 0) {
            if (std::find(_docTypes.begin(), _docTypes.end(), docType) == _docTypes.end())
                indexIt = false;
        }

        if (indexIt) {
            @autoreleasepool {
                VersionedDocument vdoc(_indexes[0]->sourceStore(), cppDoc);
                const Revision* node = vdoc.currentRevision();
                NSMutableDictionary* body = [CBLForestBridge bodyOfNode: node];
                body[@"_local_seq"] = @(node->sequence);

                if (vdoc.hasConflict()) {
                    NSArray* conflicts = [CBLForestBridge getCurrentRevisionIDs: vdoc
                                                                 includeDeleted: NO];
                    if (conflicts.count > 1)
                        body[@"_conflicts"] = [conflicts subarrayWithRange:
                                               NSMakeRange(1, conflicts.count - 1)];
                }

                LogTo(ViewVerbose, @"Mapping %@ rev %@", body.cbl_id, body.cbl_rev);
                CocoaMappable mappable(cppDoc, body);
                addMappable(mappable);
            }
        } else {
            // Have to at least run a nil doc through addMappable, to remove obsolete old rows
            CocoaMappable mappable(cppDoc, nil);
            addMappable(mappable);
        }
    }

private:
    std::vector<alloc_slice> _docTypes;
};


class MapReduceBridge : public MapFn {
public:
    CBLMapBlock mapBlock;
    NSString* viewName;
    NSString* documentType;
    CBLViewIndexType indexType;

    virtual void operator() (const Mappable& mappable, EmitFn& emitFn) {
            NSDictionary* doc = ((CocoaMappable&)mappable).body;
            if (!doc)
                return; // doc is deleted or otherwise not to be indexed
            if (documentType && ![documentType isEqual: doc[@"type"]])
                return;
            CBLMapEmitBlock emit = ^(id key, id value) {
                if (indexType == kCBLFullTextIndex) {
                    Assert([key isKindOfClass: [NSString class]]);
                    LogTo(ViewVerbose, @"    emit(\"%@\", %@)", key, toJSONStr(value));
                    emitText(key, value, doc, emitFn);
                } else if ([key isKindOfClass: [CBLSpecialKey class]]) {
                    CBLSpecialKey *specialKey = key;
                    LogTo(ViewVerbose, @"    emit(%@, %@)", specialKey, toJSONStr(value));
                    NSString* text = specialKey.text;
                    if (text) {
                        emitText(text, value, doc, emitFn);
                    } else {
                        emitGeo(specialKey, value, doc, emitFn);
                    }
                } else if (key) {
                    LogTo(ViewVerbose, @"    emit(%@, %@)  to %@", toJSONStr(key), toJSONStr(value), viewName);
                    callEmit(key, value, doc, emitFn);
                }
            };
            mapBlock(doc, emit);  // Call the apps' map block!
        }

private:
    // Emit a full-text row
    void emitText(NSString* text, id value, NSDictionary* doc, EmitFn& emitFn) {
        nsstring_slice textSlice(text);
        if (value == doc) {
            emitFn.emitTextTokens(textSlice, Index::kSpecialValue);
        } else if (value) {
            emitFn.emitTextTokens(textSlice, nsstring_slice(toJSONStr(value)));
        } else {
            emitFn.emitTextTokens(textSlice, slice::null);
        }
    }

    // Geo-index a rectangle
    void emitGeo(CBLSpecialKey* geoKey, id value, NSDictionary* doc, EmitFn& emitFn) {
        auto geoArea = geoRectToArea(geoKey.rect);
        slice geoJSON = slice(geoKey.geoJSONData);
        if (value == doc) {
            emitFn(geoArea, geoJSON, Index::kSpecialValue);
        } else if (value) {
            emitFn(geoArea, geoJSON, nsstring_slice(toJSONStr(value)));
        } else {
            emitFn(geoArea, geoJSON, slice::null);
        }
    }

    // Emit a regular key/value pair
    void callEmit(id key, id value, NSDictionary* doc, EmitFn& emitFn) {
        Collatable collKey(key);
        if (value == doc) {
            emitFn(collKey, Index::kSpecialValue);
        } else if (value) {
            emitFn(collKey, nsstring_slice(toJSONStr(value)));
        } else {
            emitFn(collKey, slice::null);
        }
    }

    static NSString* toJSONStr(id obj) {
        if (!obj)
            return @"nil";
        return [CBLJSON stringWithJSONObject: obj options: CBLJSONWritingAllowFragments error: nil];
    }

};


#pragma mark -

@implementation CBL_ForestDBViewStorage
{
    CBL_ForestDBStorage* _dbStorage;
    NSString* _path;
    Database* _indexDB;
    MapReduceIndex* _index;
    CBLViewIndexType _indexType;
    MapReduceBridge _mapReduceBridge;
}

@synthesize delegate=_delegate, name=_name;


static NSRegularExpression* kViewNameRegex;


+ (void) initialize {
    if (self == [CBL_ForestDBViewStorage class]) {
        NSString* stemmer = CBLStemmerNameForCurrentLocale();
        if (stemmer) {
            Tokenizer::defaultStemmer = stemmer.UTF8String;
            Tokenizer::defaultRemoveDiacritics = $equal(stemmer, @"english");
        }

        kViewNameRegex = [NSRegularExpression
                      regularExpressionWithPattern: @"^(.*)\\." kViewIndexPathExtension "(.\\d+)?$"
                      options: 0 error: NULL];
        Assert(kViewNameRegex);
    }
}


+ (NSString*) fileNameToViewName: (NSString*)fileName {
    NSTextCheckingResult *result = [kViewNameRegex firstMatchInString: fileName options: 0
                                                        range: NSMakeRange(0, fileName.length)];
    if (!result)
        return nil;
    NSRange r = [result rangeAtIndex: 1];
    NSString* viewName = [fileName substringWithRange: r];
    viewName = [viewName stringByReplacingOccurrencesOfString: @":" withString: @"/"];
    return viewName;
}

static inline NSString* viewNameToFileName(NSString* viewName) {
    if ([viewName hasPrefix: @"."] || [viewName rangeOfString: @":"].length > 0)
        return nil;
    viewName = [viewName stringByReplacingOccurrencesOfString: @"/" withString: @":"];
    return [viewName stringByAppendingPathExtension: kViewIndexPathExtension];
}


- (instancetype) initWithDBStorage: (CBL_ForestDBStorage*)dbStorage
                              name: (NSString*)name
                            create: (BOOL)create
{
    Assert(dbStorage);
    Assert(name.length);
    self = [super init];
    if (self) {
        _dbStorage = dbStorage;
        _name = [name copy];
        _path = [dbStorage.directory stringByAppendingPathComponent: viewNameToFileName(_name)];
        _indexType = (CBLViewIndexType)-1; // unknown

        // Somewhat of a hack: There probably won't be a file at the exact _path because ForestDB
        // likes to append ".0" etc., but there will be a file with a ".meta" extension:
        NSString* metaPath = [_path stringByAppendingPathExtension: @"meta"];
        if (![[NSFileManager defaultManager] fileExistsAtPath: metaPath isDirectory: NULL]) {
            if (!create || ![self openIndexWithCreate: YES status: NULL])
                return nil;
        }
    }
    return self;
}


- (void) close {
    [self closeIndex];
    [_dbStorage forgetViewStorageNamed: _name];
}


- (BOOL) setVersion: (NSString*)version {
    return YES;
}


- (NSUInteger) totalRows {
    if (![self openIndex: NULL])
        return 0;
    return (NSUInteger) _index->rowCount();
}


- (SequenceNumber) lastSequenceIndexed {
    if (![self setupIndex: NULL]) // in case the _mapVersion changed, invalidating the index
        return -1;
    return _index->lastSequenceIndexed();
}


- (SequenceNumber) lastSequenceChangedAt {
    if (![self setupIndex: NULL]) // in case the _mapVersion changed, invalidating the index
        return -1;
    return _index->lastSequenceChangedAt();
}


#pragma mark - INDEX MANAGEMENT:


- (Database::config) config {
    auto config = Database::defaultConfig(); // +[CBL_ForestDBStorage initialize] sets defaults
    config.seqtree_opt = FDB_SEQTREE_NOT_USE; // indexes don't need by-sequence ordering
    if (!_dbStorage.autoCompact)
        config.compaction_mode = FDB_COMPACTION_MANUAL;
    if (_dbStorage.readOnly)
        config.flags |= FDB_OPEN_FLAG_RDONLY;
    return config;
}


// Opens the index. You MUST call this (or a method that calls it) before dereferencing _index.
- (MapReduceIndex*) openIndex: (CBLStatus*)outStatus {
    if (_index)
        return _index;
    return [self openIndexWithCreate: NO status: outStatus];
}


// Opens the index, optionally creating it
- (MapReduceIndex*) openIndexWithCreate: (BOOL)create
                                 status: (CBLStatus*)outStatus
{
    if (!_index) {
        Assert(!_indexDB);
        auto config = self.config;
        if (create && !(config.flags & FDB_OPEN_FLAG_RDONLY))
            config.flags |= FDB_OPEN_FLAG_CREATE;

        NSError* error;
        _indexDB = [CBLForestBridge openDatabaseAtPath: _path
                                            withConfig: config
                                         encryptionKey: _dbStorage.encryptionKey
                                                 error: &error];
        if (_indexDB) {
            tryError(&error, ^{
                Database* db = (Database*)_dbStorage.forestDatabase;
                _index = new MapReduceIndex(_indexDB, "index", *db);
            });
        }
        if (!_index) {
            Warn(@"Unable to open index of %@: %@", self, error);
            if (outStatus)
                *outStatus = CBLStatusFromNSError(error, kCBLStatusDBError);
            return NULL;
        }

        [self closeIndexSoon];

    //    if (_indexType >= 0)
    //        _index->indexType = _indexType;  // In case it was changed while index was closed
    //    if (_indexType == kCBLFullTextIndex)
    //        _index->textTokenizer = [[CBTextTokenizer alloc] init];
        LogTo(View, @"%@: Opened index %p (type %d)", self, _index, _index->indexType());
        if (!_index)
            abort(); // appease static analyzer
    }
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


// This doesn't delete the index database, just erases it
- (void) deleteIndex {
    if ([self openIndex: NULL]) {
        Transaction t(_indexDB);
        _index->erase(t);
    }
}


// Deletes the index without notifying the main storage that the view is gone
- (BOOL) deleteViewFiles: (NSError**)outError {
    [self closeIndex];
    return tryError(outError, ^{
        std::string pathStr(_path.fileSystemRepresentation);
        auto config = self.config;
        Database::deleteDatabase(pathStr, config);
    });
}

// Main Storage-protocol method to delete a view
- (void) deleteView {
    if (!_dbStorage.readOnly) {
        [self deleteViewFiles: NULL];
        [_dbStorage forgetViewStorageNamed: _name];
    }
}


- (MYAction*) actionToChangeEncryptionKey {
    MYAction* action = [MYAction new];
    [action addPerform:^BOOL(NSError **outError) {
        // Close and delete the index database:
        return [self deleteViewFiles: outError];
    } backOutOrCleanUp:^BOOL(NSError **outError) {
        // Afterwards, reopen (and re-create) the index:
        CBLStatus status;
        if (![self openIndexWithCreate: YES status: &status])
            return CBLStatusToOutNSError(status, outError);
        [self closeIndex];
        return YES;
    }];
    return action;
}


/* unused
- (CBLViewIndexType) indexType {
    if (_indexType < 0 && !_index)      // If indexType unknown, load index
        (void)[self openIndex: NULL];
    if (_index)
        _indexType = (CBLViewIndexType) _index->indexType();
    return _indexType;
}

- (void)setIndexType:(CBLViewIndexType)indexType {
    _indexType = indexType;
}*/


// Opens the index and updates its map block and version string (according to my delegate's)
- (MapReduceIndex*) setupIndex: (CBLStatus*)outStatus {
    id<CBL_ViewStorageDelegate> delegate = _delegate;
    if (!delegate) {
        if (outStatus)
            *outStatus = kCBLStatusNotFound;
        return NULL;
    }
    _mapReduceBridge.mapBlock = delegate.mapBlock;
    _mapReduceBridge.viewName = _name;
    _mapReduceBridge.indexType = _indexType;
    _mapReduceBridge.documentType = delegate.documentType;
    NSString* mapVersion = delegate.mapVersion;
    MapReduceIndex* index = [self openIndex: outStatus]; // open db
    if (!index)
        return NULL;
    if (mapVersion) {
        Transaction t(_indexDB);
        index->setup(t, _indexType, &_mapReduceBridge, mapVersion.UTF8String);
    }
    return index;
}


static NSString* viewNames(NSArray* views) {
    return [[views my_map: ^(CBLView* view) {return view.name;}] componentsJoinedByString: @", "];
}


- (CBLStatus) updateIndexes: (NSArray*)views {
    LogTo(View, @"Checking indexes of (%@) for %@", viewNames(views), _name);
    return tryStatus(^{
        CBLStatus status;
        CocoaIndexer indexer;
        indexer.triggerOnIndex(_index);
        BOOL useDocTypes = YES;
        for (CBL_ForestDBViewStorage* viewStorage in views) {
            MapReduceIndex* index = [viewStorage setupIndex: &status];
            if (!index)
                return status;
            id<CBL_ViewStorageDelegate> delegate = viewStorage.delegate;
            if (!delegate.mapBlock) {
                LogTo(ViewVerbose, @"    %@ has no map block; skipping it", viewStorage.name);
                continue;
            }
            indexer.addIndex(index, new Transaction(viewStorage->_indexDB));
            if (useDocTypes) {
                NSString* docType = delegate.documentType;
                if (docType) {
                    nsstring_slice s(docType);
                    indexer.addDocType(alloc_slice(s));
                } else {
                    indexer.clearDocTypes();
                    useDocTypes = NO;
                }
            }
        }
        if (indexer.run()) {
            LogTo(View, @"... Finished re-indexing (%@) to #%lld",
                  viewNames(views), indexer.latestDbSequence());
            return kCBLStatusOK;
        } else {
            LogTo(View, @"... Nothing to do.");
            return kCBLStatusNotModified;
        }
    });
}


// This is really just for unit tests & debugging
#if DEBUG
- (NSArray*) dump {
    MapReduceIndex* index = [self openIndex: NULL];
    if (!index)
        return nil;
    NSMutableArray* result = $marray();

    IndexEnumerator *e = [self _runForestQueryWithOptions: [CBLQueryOptions new]];
    while (e->next()) {
        NSString* valueStr = (NSString*)e->value();
        Assert(valueStr || e->value().size == 0);//TEMP
        [result addObject: $dict({@"key", CBLJSONString(e->key().readNSObject())},
                                 {@"value", valueStr},
                                 {@"seq", @(e->sequence())})];
    }
    delete e;
    return result;
}
#endif


#pragma mark - QUERYING:


/** Starts a view query, returning a CBForest enumerator. */
- (IndexEnumerator*) _runForestQueryWithOptions: (CBLQueryOptions*)options
{
    Assert(_index); // caller MUST call -openIndex: first
    DocEnumerator::Options forestOpts = DocEnumerator::Options::kDefault;
    forestOpts.skip = options->skip;
    if (options->limit != kCBLQueryOptionsDefaultLimit)
        forestOpts.limit = options->limit;
    forestOpts.descending = options->descending;
    forestOpts.inclusiveStart = options->inclusiveStart;
    forestOpts.inclusiveEnd = options->inclusiveEnd;
    if (options->bbox) {
        return new GeoIndexEnumerator(_index, geoRectToArea(*options->bbox));
    } else if (options.keys) {
        std::vector<KeyRange> collatableKeys;
        for (id key in options.keys)
            collatableKeys.push_back(Collatable(key));
        return new IndexEnumerator(_index,
                                   collatableKeys,
                                   forestOpts);
    } else {
        id startKey = options.startKey, endKey = options.endKey;
        __strong id &maxKey = options->descending ? startKey : endKey;
        maxKey = CBLKeyForPrefixMatch(maxKey, options->prefixMatchLevel);
        return new IndexEnumerator(_index,
                                   Collatable(startKey),
                                   nsstring_slice(options.startKeyDocID),
                                   Collatable(endKey),
                                   nsstring_slice(options.endKeyDocID),
                                   forestOpts);
    }
}


static id parseJSONSlice(slice s) {
    NSError* error;
    id value = [CBLJSON JSONObjectWithData: s.uncopiedNSData()
                                   options: CBLJSONReadingAllowFragments error: &error];
    if (!value)
        Warn(@"Couldn't parse JSON value: %@", s.uncopiedNSData());
    return value;
}


- (CBLQueryIteratorBlock) regularQueryWithOptions: (CBLQueryOptions*)options
                                           status: (CBLStatus*)outStatus
{
    if (![self openIndex: outStatus])
        return nil;
    CBLQueryRowFilter filter = options.filter;
    __block unsigned limit = UINT_MAX;
    __block unsigned skip = 0;
    if (filter) {
        // #574: Custom post-filter means skip/limit apply to the filtered rows, not to the
        // underlying query, so handle them specially:
        limit = options->limit;
        skip = options->skip;
        options->limit = kCBLQueryOptionsDefaultLimit;
        options->skip = 0;
    }

    __block std::auto_ptr<IndexEnumerator> e ([self _runForestQueryWithOptions: options]);

    *outStatus = kCBLStatusOK;
    return ^CBLQueryRow*() {
        try{
            if (limit-- == 0)
                return nil;
            while (e->next()) {
                CBL_Revision* docRevision = nil;
                id key = e->key().readNSObject();
                id value = nil;
                NSString* docID = (NSString*)e->docID();
                SequenceNumber sequence = e->sequence();

                if (options->includeDocs) {
                    NSDictionary* valueDict = nil;
                    NSString* linkedID = nil;
                    if (e->value().size > 0 && e->value()[0] == '{') {
                        valueDict = $castIf(NSDictionary, parseJSONSlice(e->value()));
                        linkedID = valueDict.cbl_id;
                    }
                    if (linkedID) {
                        // Linked document: http://wiki.apache.org/couchdb/Introduction_to_CouchDB_views#Linked_documents
                        NSString* linkedRev = valueDict.cbl_rev; // usually nil
                        CBLStatus linkedStatus;
                        docRevision = [_dbStorage getDocumentWithID: linkedID revisionID: linkedRev
                                                           withBody: YES status: &linkedStatus];
                        sequence = docRevision.sequence;
                    } else {
                        CBLStatus status;
                        docRevision = [_dbStorage getDocumentWithID: docID revisionID: nil
                                                           withBody: YES status: &status];
                    }
                }

                if (!value)
                    value = e->value().copiedNSData();

                LogTo(QueryVerbose, @"Query %@: Found row with key=%@, value=%@, id=%@",
                      _name, CBLJSONString(key), value, CBLJSONString(docID));
                CBLQueryRow* row;
                if (options->bbox) {
                    GeoIndexEnumerator* ge = (GeoIndexEnumerator*)e.get();
                    CBLGeoRect bbox = areaToGeoRect(ge->keyBoundingBox());
                    NSData* geoJSON = ge->keyGeoJSON().copiedNSData();
                    row = [[CBLGeoQueryRow alloc] initWithDocID: docID
                                                       sequence: sequence
                                                    boundingBox: bbox
                                                    geoJSONData: geoJSON
                                                          value: value
                                                    docRevision: docRevision
                                                        storage: self];
                } else {
                    row = [[CBLQueryRow alloc] initWithDocID: docID
                                                    sequence: sequence
                                                         key: key
                                                       value: value
                                                 docRevision: docRevision
                                                     storage: self];
                }
                if (filter) {
                    if (!filter(row))
                        continue;
                    if (skip > 0) {
                        --skip;
                        continue;
                    }
                }
                // Got a row to return!
                return row;
            }
        } catch (cbforest::error x) {
            Warn(@"Unexpected ForestDB error iterating query (status %d)", x.status);
        } catch (NSException* x) {
            MYReportException(x, @"CBL_ForestDBViewStorage");
        } catch (...) {
            Warn(@"Unexpected CBForest exception iterating query");
        }
        return nil;
    };
}


#pragma mark - REDUCING/GROUPING:


- (CBLQueryIteratorBlock) reducedQueryWithOptions: (CBLQueryOptions*)options
                                           status: (CBLStatus*)outStatus
{
    unsigned groupLevel = options->groupLevel;
    bool group = options->group || groupLevel > 0;

    CBLReduceBlock reduce = _delegate.reduceBlock;
    if (options->reduceSpecified) {
        if (!options->reduce) {
            reduce = nil;
        } else if (!reduce) {
            Warn(@"Cannot use reduce option in view %@ which has no reduce block defined",
                 _name);
            *outStatus = kCBLStatusBadParam;
            return nil;
        }
    }

    __block id lastKey = nil;
    CBLQueryRowFilter filter = options.filter;
    NSMutableArray* keysToReduce = nil, *valuesToReduce = nil;
    if (reduce) {
        keysToReduce = [[NSMutableArray alloc] initWithCapacity: 100];
        valuesToReduce = [[NSMutableArray alloc] initWithCapacity: 100];
    }

    if (![self openIndex: outStatus])
        return nil;
    __block std::auto_ptr<IndexEnumerator> e([self _runForestQueryWithOptions: options]);

    *outStatus = kCBLStatusOK;
    return ^CBLQueryRow*() {
        try {
            CBLQueryRow* row = nil;
            do {
                id key = e->next() ? e->key().readNSObject() : nil;
                if (lastKey && (!key || (group && !groupTogether(lastKey, key, groupLevel)))) {
                    // key doesn't match lastKey; emit a grouped/reduced row for what came before:
                    row = [[CBLQueryRow alloc] initWithDocID: nil
                                        sequence: 0
                                             key: (group ? groupKey(lastKey, groupLevel) : $null)
                                           value: callReduce(reduce, keysToReduce,valuesToReduce)
                                     docRevision: nil
                                         storage: self];
                    LogTo(QueryVerbose, @"Query %@: Reduced row with key=%@, value=%@",
                                        _name, CBLJSONString(row.key), CBLJSONString(row.value));
                    if (filter && !filter(row))
                        row = nil;
                    [keysToReduce removeAllObjects];
                    [valuesToReduce removeAllObjects];
                }

                if (key && reduce) {
                    // Add this key/value to the list to be reduced:
                    [keysToReduce addObject: key];
                    slice rawValue = e->value();
                    id value = nil;
                    if (rawValue == Index::kSpecialValue) {
                        CBLStatus status;
                        value = [_dbStorage getBodyWithID: (NSString*)e->docID()
                                                 sequence: e->sequence()
                                                   status: &status];
                        if (!value)
                            Warn(@"%@: Couldn't load doc for row value: status %d", self, status);
                    } else if (rawValue.size > 0) {
                        value = parseJSONSlice(rawValue);
                    }
                    [valuesToReduce addObject: (value ?: $null)];
                    //TODO: Reduce the keys/values when there are too many; then rereduce at end
                }

                lastKey = key;
            } while (!row && lastKey);
            return row;
        } catch (cbforest::error x) {
            Warn(@"Unexpected ForestDB error iterating query (status %d)", x.status);
        } catch (NSException* x) {
            MYReportException(x, @"CBL_ForestDBViewStorage");
        } catch (...) {
            Warn(@"Unexpected CBForest exception iterating query");
        }
        return nil;
    };
}


#define PARSED_KEYS

// Are key1 and key2 grouped together at this groupLevel?
#ifdef PARSED_KEYS
static bool groupTogether(id key1, id key2, unsigned groupLevel) {
    if (groupLevel == 0)
        return [key1 isEqual: key2];
    if (![key1 isKindOfClass: [NSArray class]] || ![key2 isKindOfClass: [NSArray class]])
        return groupLevel == 1 && [key1 isEqual: key2];
    NSUInteger level = MIN(groupLevel, MIN([key1 count], [key2 count]));
    for (NSUInteger i = 0; i < level; i++) {
        if (![[key1 objectAtIndex: i] isEqual: [key2 objectAtIndex: i]])
            return NO;
    }
    return YES;
}

// Returns the prefix of the key to use in the result row, at this groupLevel
static id groupKey(id key, unsigned groupLevel) {
    if (groupLevel > 0 && [key isKindOfClass: [NSArray class]] && [key count] > groupLevel)
        return [key subarrayWithRange: NSMakeRange(0, groupLevel)];
    else
        return key;
}
#else
static bool groupTogether(NSData* key1, NSData* key2, unsigned groupLevel) {
    if (!key1 || !key2)
        return NO;
    if (groupLevel == 0)
        groupLevel = UINT_MAX;
    return CBLCollateJSONLimited(kCBLCollateJSON_Unicode,
                                (int)key1.length, key1.bytes,
                                (int)key2.length, key2.bytes,
                                groupLevel) == 0;
}

// Returns the prefix of the key to use in the result row, at this groupLevel
static id groupKey(NSData* keyJSON, unsigned groupLevel) {
    id key = fromJSON(keyJSON);
    if (groupLevel > 0 && [key isKindOfClass: [NSArray class]] && [key count] > groupLevel)
        return [key subarrayWithRange: NSMakeRange(0, groupLevel)];
    else
        return key;
}
#endif


// Invokes the reduce function on the parallel arrays of keys and values
static id callReduce(CBLReduceBlock reduceBlock, NSMutableArray* keys, NSMutableArray* values) {
    if (!reduceBlock)
        return nil;
    NSArray *lazyKeys, *lazyValues;
#ifdef PARSED_KEYS
    lazyKeys = keys;
#else
    keys = [[CBLLazyArrayOfJSON alloc] initWithMutableArray: keys];
#endif
    lazyValues = [[CBLLazyArrayOfJSON alloc] initWithMutableArray: values];
    @try {
        id result = reduceBlock(lazyKeys, lazyValues, NO);
        if (result)
            return result;
    } @catch (NSException *x) {
        MYReportException(x, @"reduce block");
    }
    return $null;
}


#pragma mark - FULL-TEXT:


- (CBLQueryIteratorBlock) fullTextQueryWithOptions: (CBLQueryOptions*)options
                                            status: (CBLStatus*)outStatus
{
    MapReduceIndex* index = [self openIndex: outStatus];
    if (!index) {
        return nil;
//    } else if (index->indexType() != kCBLFullTextIndex) {
//        *outStatus = kCBLStatusBadRequest;
//        return nil;
    }

    NSMutableArray* result = $marray();
    __block std::vector<size_t> termTotalCounts;
    @autoreleasepool {
        *outStatus = tryStatus(^CBLStatus{
            // Tokenize the query string:
            LogTo(QueryVerbose, @"Full-text search for \"%@\":", options.fullTextQuery);
            std::vector<std::string> queryTokens;
            std::vector<KeyRange> collatableKeys;
            Tokenizer tokenizer;
            for (TokenIterator i(tokenizer, nsstring_slice(options.fullTextQuery), true); i; ++i) {
                collatableKeys.push_back(Collatable(i.token()));
                queryTokens.push_back(i.token());
                termTotalCounts.push_back(0);
                LogTo(QueryVerbose, @"    token: \"%s\"", i.token().c_str());
            }

            LogTo(QueryVerbose, @"Iterating index...");
            NSMutableDictionary* docRows = [[NSMutableDictionary alloc] init];
            *outStatus = kCBLStatusOK;
            DocEnumerator::Options forestOpts = DocEnumerator::Options::kDefault;
            for (IndexEnumerator e(index, collatableKeys, forestOpts); e.next(); ) {
                std::string token = e.textToken();
                NSString* docID = (NSString*)e.docID();
                unsigned fullTextID;
                std::vector<size_t> matches = e.getTextTokenInfo(fullTextID);

                id key = fullTextID > 0 ? @[docID, @(fullTextID)] : docID;
                CBLFullTextQueryRow* row = docRows[key];
                if (!row) {
                    alloc_slice valueSlice = index->readFullTextValue(nsstring_slice(docID),
                                                                      e.sequence(),
                                                                      fullTextID);
                    NSData* valueData = valueSlice.copiedNSData();
                    row = [[CBLFullTextQueryRow alloc] initWithDocID: docID
                                                            sequence: e.sequence()
                                                          fullTextID: fullTextID
                                                               value: valueData
                                                             storage: self];
                    docRows[key] = row;
                }

                auto termIndex = std::find(queryTokens.begin(), queryTokens.end(), token)
                                    - queryTokens.begin();

                size_t nMatches = matches.size() / 2;
                for (size_t i = 0; i < nMatches; ++i) {
                    [row addTerm: termIndex atRange: NSMakeRange(matches[2*i], matches[2*i+1])];
                }
                termTotalCounts[termIndex] += nMatches;
            };

            // Only keep the rows that contain each term in the query (implicit AND):
            [docRows enumerateKeysAndObjectsUsingBlock:^(id key, CBLFullTextQueryRow* row, BOOL *stop) {
                if ([row containsAllTerms: queryTokens.size()])
                    [result addObject: row];
            }];
            return kCBLStatusOK;
        });
        if (CBLStatusIsError(*outStatus))
            return nil;
    }

    if (options->fullTextRanking) {
        // Compute relevance of each row:
        for (CBLFullTextQueryRow* row in result) {
            double relevance = 0.0;
            NSUInteger matchCount = row.matchCount;
            for (NSUInteger i = 0; i < matchCount; i++) {
                NSUInteger termIndex = [row termIndexOfMatch: i];
                relevance += 1.0 / termTotalCounts[termIndex];
            }
            row.relevance = (float)relevance;
        }
        // Sort by descending relevance:
        [result sortUsingComparator: ^NSComparisonResult(CBLFullTextQueryRow *a,
                                                         CBLFullTextQueryRow *b) {
            float diff = a.relevance - b.relevance;
            return diff<0.0 ? NSOrderedDescending : (diff==0.0 ? NSOrderedSame : NSOrderedAscending);
        }];
    }

    NSEnumerator* rowEnum = result.objectEnumerator;
    return ^CBLQueryRow*() {
        return rowEnum.nextObject;
    };
}


#pragma mark - CBL_QueryRowStorage API:


- (id<CBL_QueryRowStorage>) storageForQueryRow: (CBLQueryRow*)row {
    return self;
}


- (NSDictionary*) documentPropertiesWithID: (NSString*)docID
                                  sequence: (SequenceNumber)sequence
                                    status: (CBLStatus*)outStatus
{
    return [_dbStorage getBodyWithID: docID sequence: sequence status: outStatus];
}


- (NSData*) fullTextForDocument: (NSString*)docID
                       sequence: (SequenceNumber)sequence
                     fullTextID: (UInt64)fullTextID
{
    if (![self openIndex: NULL])
        return nil;
    alloc_slice valueSlice = _index->readFullText((nsstring_slice)docID, sequence, (unsigned)fullTextID);
    if (valueSlice.size == 0) {
        Warn(@"%@: Couldn't find full text for doc <%@>, seq %llu, fullTextID %llu",
             self, docID, sequence, fullTextID);
        return nil;
    }
    return valueSlice.copiedNSData();
}


@end
