//
//  CBL_ViewStorage.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/13/15.
//
//

extern "C" {
#import "CBL_ForestDBViewStorage.h"
#import "CBL_ForestDBStorage.h"
#import "CBLSpecialKey.h"
#import "CouchbaseLitePrivate.h"
#import "CBLMisc.h"
#import "ExceptionUtils.h"
}
#import <CBForest/CBForest.hh>
#import <CBForest/GeoIndex.hh>
#import <CBForest/MapReduceDispatchIndexer.hh>
#import <CBForest/Tokenizer.hh>
using namespace forestdb;
#import "CBLForestBridge.h"


@interface CBL_ForestDBViewStorage () <CBL_QueryRowStorage>
@end


#define kViewIndexPathExtension @"viewindex"

// Size of ForestDB buffer cache allocated for a view index
#define kViewBufferCacheSize (8*1024*1024)

// Close the index db after it's inactive this many seconds
#define kCloseDelay 60.0


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
                emitFn.emitTextTokens(nsstring_slice(key));
            } else if ([key isKindOfClass: [CBLSpecialKey class]]) {
                CBLSpecialKey *specialKey = key;
                LogTo(ViewVerbose, @"    emit(%@, %@)", specialKey, toJSONStr(value));
                NSString* text = specialKey.text;
                if (text) {
                    emitFn.emitTextTokens(nsstring_slice(text));
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
    // Geo-index a rectangle
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

    // Emit a regular key/value pair
    void callEmit(id key, id value, NSDictionary* doc, EmitFn& emitFn) {
        Collatable collKey, collValue;
        collKey << key;
        if (value == doc)
            collValue.addSpecial(); // placeholder for doc
        else if (value)
            collValue << value;
        emitFn(collKey, collValue);
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


+ (NSString*) fileNameToViewName: (NSString*)fileName {
    if (![fileName.pathExtension isEqualToString: kViewIndexPathExtension])
        return nil;
    if ([fileName hasPrefix: @"."])
        return nil;
    NSString* viewName = fileName.stringByDeletingPathExtension;
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


- (void) close {
    [self closeIndex];
}


- (BOOL) setVersion: (NSString*)version {
    return YES;
}


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


#pragma mark - INDEX MANAGEMENT:


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
        Database* db = (Database*)_dbStorage.forestDatabase;
        _index = new MapReduceIndex(_indexDB, "index", *db);
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


- (void) deleteIndex {
    if (self.index) {
        Transaction t(_indexDB);
        _index->erase(t);
    }
}


- (void) deleteView {
    [self closeIndex];
    [[NSFileManager defaultManager] removeItemAtPath: _path error: NULL];
}


- (CBLViewIndexType) indexType {
    if (_index || _indexType < 0)
        _indexType = (CBLViewIndexType) self.index->indexType();
    return _indexType;
}

- (void)setIndexType:(CBLViewIndexType)indexType {
    _indexType = indexType;
}


- (void) setupIndex {
    id<CBL_ViewStorageDelegate> delegate = _delegate;
    if (!delegate)
        return;
    _mapReduceBridge.mapBlock = delegate.mapBlock;
    _mapReduceBridge.viewName = _name;
    _mapReduceBridge.indexType = _indexType;
    (void)self.index; // open db
    {
        Transaction t(_indexDB);
        _index->setup(t, _indexType, &_mapReduceBridge, delegate.mapVersion.UTF8String);
    }
}


static NSString* viewNames(NSArray* views) {
    return [[views my_map: ^(CBLView* view) {return view.name;}] componentsJoinedByString: @", "];
}


- (CBLStatus) updateIndexes: (NSArray*)views {
    LogTo(View, @"Checking indexes of (%@) for %@", viewNames(views), _name);
    try {
        std::vector<MapReduceIndex*> indexes;
        for (CBL_ForestDBViewStorage* viewStorage in views) {
            [viewStorage setupIndex];
            CBLMapBlock mapBlock = viewStorage.delegate.mapBlock;
            MapReduceIndex* index = viewStorage.index;
            if (mapBlock && index)
                indexes.push_back(index);
            else
                LogTo(ViewVerbose, @"    %@ has no map block; skipping it", viewStorage.name);
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


// This is really just for unit tests & debugging
#if DEBUG
- (NSArray*) dump {
    MapReduceIndex* index = self.index;
    if (!index)
        return nil;
    NSMutableArray* result = $marray();

    IndexEnumerator e = [self _runForestQueryWithOptions: [CBLQueryOptions new]];
    while (e.next()) {
        [result addObject: $dict({@"key", CBLJSONString(e.key().readNSObject())},
                                 {@"value", CBLJSONString(e.value().readNSObject())},
                                 {@"seq", @(e.sequence())})];
    }
    return result;
}
#endif


#pragma mark - QUERYING:


/** Starts a view query, returning a CBForest enumerator. */
- (IndexEnumerator) _runForestQueryWithOptions: (CBLQueryOptions*)options
{
    MapReduceIndex* index = self.index;
    Assert(index);
    DocEnumerator::Options forestOpts = DocEnumerator::Options::kDefault;
    forestOpts.skip = options->skip;
    if (options->limit != kCBLQueryOptionsDefaultLimit)
        forestOpts.limit = options->limit;
    forestOpts.descending = options->descending;
    forestOpts.inclusiveStart = options->inclusiveStart;
    forestOpts.inclusiveEnd = options->inclusiveEnd;
    if (options.keys) {
        std::vector<KeyRange> collatableKeys;
        for (id key in options.keys)
            collatableKeys.push_back(Collatable(key));
        return IndexEnumerator(index,
                               collatableKeys,
                               forestOpts);
    } else {
        id endKey = keyForPrefixMatch(options.endKey, options->prefixMatchLevel);
        return IndexEnumerator(index,
                               Collatable(options.startKey),
                               nsstring_slice(options.startKeyDocID),
                               Collatable(endKey),
                               nsstring_slice(options.endKeyDocID),
                               forestOpts);
    }
}


- (CBLQueryIteratorBlock) regularQueryWithOptions: (CBLQueryOptions*)options
                                           status: (CBLStatus*)outStatus
{
    if (!self.index) {
        *outStatus = kCBLStatusNotFound;
        return nil;
    }
    CBLQueryRowFilter filter = options.filter;
    __block IndexEnumerator e = [self _runForestQueryWithOptions: options];

    *outStatus = kCBLStatusOK;
    return ^CBLQueryRow*() {
        while (e.next()) {
            id docContents = nil;
            id key = e.key().readNSObject();
            id value = nil;
            NSString* docID = (NSString*)e.docID();
            SequenceNumber sequence = e.sequence();

            if (options->includeDocs) {
                NSDictionary* valueDict = nil;
                NSString* linkedID = nil;
                if (e.value().peekTag() == CollatableReader::kMap) {
                    value = e.value().readNSObject();
                    valueDict = $castIf(NSDictionary, value);
                    linkedID = valueDict.cbl_id;
                }
                if (linkedID) {
                    // Linked document: http://wiki.apache.org/couchdb/Introduction_to_CouchDB_views#Linked_documents
                    NSString* linkedRev = valueDict.cbl_rev; // usually nil
                    CBLStatus linkedStatus;
                    CBL_Revision* linked = [_dbStorage getDocumentWithID: linkedID
                                                      revisionID: linkedRev
                                                         options: options->content
                                                          status: &linkedStatus];
                    docContents = linked ? linked.properties : $null;
                    sequence = linked.sequence;
                } else {
                    CBLStatus status;
                    CBL_Revision* rev = [_dbStorage getDocumentWithID: docID revisionID: nil
                                                      options: options->content status: &status];
                    docContents = rev.properties;
                }
            }

            if (!value)
                value = e.value().data().copiedNSData();

            LogTo(QueryVerbose, @"Query %@: Found row with key=%@, value=%@, id=%@",
                  _name, CBLJSONString(key), value, CBLJSONString(docID));
            auto row = [[CBLQueryRow alloc] initWithDocID: docID
                                                 sequence: sequence
                                                      key: key
                                                    value: value
                                            docProperties: docContents
                                                  storage: self];
            if (!filter || filter(row))
                return row;
        }
        return nil;
    };
}


// Changes a maxKey into one that also extends to any key it matches as a prefix.
static id keyForPrefixMatch(id key, unsigned depth) {
    if (depth < 1)
        return key;
    if ([key isKindOfClass: [NSString class]]) {
        // Kludge: prefix match a string by appending max possible character value to it
        return [key stringByAppendingString: @"\uffffffff"];
    } else if ([key isKindOfClass: [NSArray class]]) {
        NSMutableArray* nuKey = [key mutableCopy];
        if (depth == 1) {
            [nuKey addObject: @{}];
        } else {
            id lastObject = keyForPrefixMatch(nuKey.lastObject, depth-1);
            [nuKey replaceObjectAtIndex: nuKey.count-1 withObject: lastObject];
        }
        return nuKey;
    } else {
        return key;
    }
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

    if (!self.index) {
        *outStatus = kCBLStatusNotFound;
        return nil;
    }
    __block IndexEnumerator e = [self _runForestQueryWithOptions: options];

    *outStatus = kCBLStatusOK;
    return ^CBLQueryRow*() {
        CBLQueryRow* row = nil;
        do {
            id key = e.next() ? e.key().readNSObject() : nil;
            if (lastKey && (!key || (group && !groupTogether(lastKey, key, groupLevel)))) {
                // key doesn't match lastKey; emit a grouped/reduced row for what came before:
                row = [[CBLQueryRow alloc] initWithDocID: nil
                                        sequence: 0
                                             key: (group ? groupKey(lastKey, groupLevel) : $null)
                                           value: callReduce(reduce, keysToReduce,valuesToReduce)
                                   docProperties: nil
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
                CollatableReader collatableValue = e.value();
                id value;
                if (collatableValue.peekTag() == CollatableReader::kSpecial) {
                    CBLStatus status;
                    CBL_Revision* rev = [_dbStorage getDocumentWithID: (NSString*)e.docID()
                                                             sequence: e.sequence()
                                                               status: &status];
                    if (!rev)
                        Warn(@"%@: Couldn't load doc for row value: status %d", self, status);
                    value = rev.properties;
                } else {
                    value = collatableValue.readNSObject();
                }
                [valuesToReduce addObject: (value ?: $null)];
                //TODO: Reduce the keys/values when there are too many; then rereduce at end
            }

            lastKey = key;
        } while (!row && lastKey);
        return row;
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
    MapReduceIndex* index = self.index;
    if (!index) {
        *outStatus = kCBLStatusNotFound;
        return nil;
//    } else if (index->indexType() != kCBLFullTextIndex) {
//        *outStatus = kCBLStatusBadRequest;
//        return nil;
    }

    NSMutableArray* result = $marray();
    @autoreleasepool {
        // Tokenize the query string:
        LogTo(QueryVerbose, @"Full-text search for \"%@\":", options.fullTextQuery);
        std::vector<std::string> queryTokens;
        std::vector<KeyRange> collatableKeys;
        Tokenizer tokenizer("en", true);
        for (TokenIterator i(tokenizer, nsstring_slice(options.fullTextQuery), true); i; ++i) {
            collatableKeys.push_back(Collatable(i.token()));
            queryTokens.push_back(i.token());
            LogTo(QueryVerbose, @"    token: \"%s\"", i.token().c_str());
        }

        LogTo(QueryVerbose, @"Iterating index...");
        NSMutableDictionary* docRows = [[NSMutableDictionary alloc] init];
        *outStatus = kCBLStatusOK;
        DocEnumerator::Options forestOpts = DocEnumerator::Options::kDefault;
        for (IndexEnumerator e = IndexEnumerator(index, collatableKeys, forestOpts); e.next(); ) {
            std::string token;
            unsigned fullTextID;
            size_t wordStart, wordLength;
            e.getTextToken(token, wordStart, wordLength, fullTextID);
            NSString* docID = (NSString*)e.docID();

            id key = fullTextID > 0 ? @[docID, @(fullTextID)] : docID;
            CBLFullTextQueryRow* row = docRows[key];
            if (!row) {
                row = [[CBLFullTextQueryRow alloc] initWithDocID: docID
                                                        sequence: e.sequence()
                                                      fullTextID: fullTextID
                                                         storage: self];
                docRows[key] = row;
            }

            auto termIndex = std::find(queryTokens.begin(), queryTokens.end(), token)
                                - queryTokens.begin();
            [row addTerm: termIndex atRange: NSMakeRange(wordStart, wordLength)];
            if (row.matchCount == queryTokens.size()) {
                // Row must contain _all_ the search terms to be a hit
                [result addObject: row];
            }
        };
    }

    NSEnumerator* rowEnum = result.objectEnumerator;
    return ^CBLQueryRow*() {
        return rowEnum.nextObject;
    };
}


#pragma mark - CBL_QueryRowStorage API:


- (BOOL) rowValueIsEntireDoc: (NSData*)valueData {
    return valueData.length == 1 && *(uint8_t*)valueData.bytes == CollatableReader::kSpecial;
}


- (id) parseRowValue: (NSData*)valueData {
    CollatableReader reader((slice(valueData)));
    return reader.readNSObject();
}


- (NSDictionary*) documentPropertiesWithID: (NSString*)docID
                                  sequence: (SequenceNumber)sequence
                                    status: (CBLStatus*)outStatus
{
    return [_dbStorage getDocumentWithID: docID sequence: sequence status: outStatus].properties;
}


- (NSData*) fullTextForDocument: (NSString*)docID
                       sequence: (SequenceNumber)sequence
                     fullTextID: (UInt64)fullTextID
{
    alloc_slice valueSlice = self.index->readFullText((nsstring_slice)docID, sequence, (unsigned)fullTextID);
    if (valueSlice.size == 0) {
        Warn(@"%@: Couldn't find full text for doc <%@>, seq %llu, fullTextID %llu",
             self, docID, sequence, fullTextID);
        return nil;
    }
    CollatableReader value(valueSlice);
    return value.readString().copiedNSData();
}


@end
