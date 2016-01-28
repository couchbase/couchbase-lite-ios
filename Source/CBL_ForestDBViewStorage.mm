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
#import "CBLForestBridge.h"


@interface CBL_ForestDBViewStorage () <CBL_QueryRowStorage>
@end


#define kViewIndexPathExtension @"viewindex"

// Close the index db after it's inactive this many seconds
#define kCloseDelay 60.0


@implementation CBL_ForestDBViewStorage
{
    CBL_ForestDBStorage* _dbStorage;
    NSString* _path;
    C4View* _view;
}

@synthesize delegate=_delegate, name=_name;


static NSRegularExpression* kViewNameRegex;


+ (void) initialize {
    if (self == [CBL_ForestDBViewStorage class]) {
        NSString* stemmer = CBLStemmerNameForCurrentLocale();
        if (stemmer)
            c4key_setDefaultFullTextLanguage(string2slice(stemmer), $equal(stemmer, @"english"));

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

        // Somewhat of a hack: There probably won't be a file at the exact _path because ForestDB
        // likes to append ".0" etc., but there will be a file with a ".meta" extension:
        NSString* metaPath = [_path stringByAppendingPathExtension: @"meta"];
        if (![[NSFileManager defaultManager] fileExistsAtPath: metaPath isDirectory: NULL]) {
            if (!create || ![self openIndexWithOptions: kC4DB_Create status: NULL])
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
    [self closeIndex];
    return YES;
}


- (NSUInteger) totalRows {
    if (![self openIndex: NULL])
        return 0;
    return (NSUInteger) c4view_getTotalRows(_view);
}


- (SequenceNumber) lastSequenceIndexed {
    if (![self openIndex: NULL]) // in case the _mapVersion changed, invalidating the index
        return -1;
    return c4view_getLastSequenceIndexed(_view);
}


- (SequenceNumber) lastSequenceChangedAt {
    if (![self openIndex: NULL]) // in case the _mapVersion changed, invalidating the index
        return -1;
    return c4view_getLastSequenceChangedAt(_view);
}


#pragma mark - INDEX MANAGEMENT:


static void onCompactCallback(void *context, bool compacting) {
    auto storage = (__bridge CBL_ForestDBViewStorage*)context;
    Log(@"View '%@' of db '%@' %s compaction",
        storage.name,
        storage->_dbStorage.directory.lastPathComponent,
        (compacting ?"starting" :"finished"));
}


// Opens the index. You MUST call this (or a method that calls it) before dereferencing _view.
- (C4View*) openIndex: (CBLStatus*)outStatus {
    return _view ?: [self openIndexWithOptions: 0 status: outStatus];
}


// Opens the index, specifying ForestDB database flags
- (C4View*) openIndexWithOptions: (C4DatabaseFlags)flags
                          status: (CBLStatus*)outStatus
{
    C4Slice mapVersion = string2slice(_delegate.mapVersion);

    if (_view) {
        // Check if version has changed:
        c4view_setMapVersion(_view, mapVersion);

    } else {
        auto delegate = _delegate;
        if (_dbStorage.autoCompact)
            flags |= kC4DB_AutoCompact;
        CBLSymmetricKey* encKey = _dbStorage.encryptionKey;
        C4EncryptionKey c4encKey = symmetricKey2Forest(encKey);
        C4Error c4err;

        _view = c4view_open((C4Database*)_dbStorage.forestDatabase,
                             string2slice(_path),
                             string2slice(_name),
                             mapVersion,
                             flags,
                             (encKey ? &c4encKey : NULL),
                             &c4err);
        if (!_view) {
            Warn(@"Unable to open index of %@: %d/%d", self, c4err.domain, c4err.code);
            if (outStatus)
                *outStatus = err2status(c4err);
            return NULL;
        }

        c4view_setOnCompactCallback(_view, onCompactCallback, (__bridge void*)self);
        c4view_setDocumentType(_view, string2slice(delegate.documentType));

        [self closeIndexSoon];
        LogTo(View, @"%@: Opened index %p", self, _view);
    }
    return _view;
}


- (void) closeIndex {
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(closeIndex)
                                               object: nil];
    if (_view) {
        LogTo(View, @"%@: Closing index", self);
        c4view_close(_view, NULL);
        _view = NULL;
    }
}

- (void) closeIndexSoon {
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(closeIndex)
                                               object: nil];
    [self performSelector: @selector(closeIndex) withObject: nil afterDelay: kCloseDelay];
}


// This doesn't delete the index database, just erases it
- (void) deleteIndex {
    if ([self openIndex: NULL]) {
        c4view_eraseIndex(_view, NULL);
    }
}


// Deletes the index without notifying the main storage that the view is gone
- (BOOL) deleteViewFiles: (NSError**)outError {
    [self closeIndex];
    C4DatabaseFlags flags = 0;
    if (_dbStorage.autoCompact)
        flags |= kC4DB_AutoCompact;
    C4Error c4err;
    if (!c4view_deleteAtPath(string2slice(_path), flags, &c4err))
        return err2OutNSError(c4err, outError);
    return YES;
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
        if (![self openIndexWithOptions: kC4DB_Create status: &status])
            return CBLStatusToOutNSError(status, outError);
        [self closeIndex];
        return YES;
    }];
    return action;
}


#pragma mark - INDEXING:


static NSString* viewNames(NSArray* views) {
    return [[views my_map: ^(CBLView* view) {return view.name;}] componentsJoinedByString: @", "];
}

static NSString* toJSONStr(id obj) { // only used for logging
    if (!obj)
        return @"nil";
    return [CBLJSON stringWithJSONObject: obj options: CBLJSONWritingAllowFragments error: nil];
}

static NSString* keyToJSONStr(id key) { // only used for logging
    if ([key isKindOfClass: [CBLSpecialKey class]])
        return [key description];
    else
        return toJSONStr(key);
}


- (CBLStatus) updateIndexes: (NSArray*)views {
    LogTo(View, @"Checking indexes of (%@) for %@", viewNames(views), _name);

    // Build arrays of map blocks and C4Views:
    NSUInteger viewCount = views.count;
    NSMutableArray<CBLMapBlock>* maps = [NSMutableArray arrayWithCapacity: viewCount];
    C4View* c4views[viewCount];
    size_t i = 0;
    for (CBL_ForestDBViewStorage* view in views) {
        CBLMapBlock mapBlock = view->_delegate.mapBlock;
        if (!mapBlock) {
            LogTo(ViewVerbose, @"    %@ has no map block; skipping it", view.name);
            continue;
        }
        [maps addObject: mapBlock];

        CBLStatus status;
        C4View* c4view = [view openIndexWithOptions: 0 status: &status];
        if (!c4view)
            return status;
        c4views[i++] = c4view;
    }
    viewCount = i;

    C4Error c4err;
    CLEANUP(C4Indexer) *indexer = c4indexer_begin((C4Database*)_dbStorage.forestDatabase,
                                                  c4views, viewCount, &c4err);
    if (!indexer)
        return err2status(c4err);
    c4indexer_triggerOnView(indexer, _view);

    // Create the doc enumerator:
    SequenceNumber latestSequence = 0;
    CLEANUP(C4DocEnumerator) *e = c4indexer_enumerateDocuments(indexer, &c4err);
    if (!e) {
        if (c4err.code != 0)
            return err2status(c4err);
        LogTo(View, @"... Finished re-indexing (%@) -- already up-to-date", viewNames(views));
        return kCBLStatusNotModified;
    }

    // Set up the emit block:
    __block NSMutableDictionary* body;
    NSMutableArray* emittedJSONValues = [NSMutableArray new];
    CLEANUP(C4KeyValueList)* emitted = c4kv_new();
    CBLMapEmitBlock emit = ^(id key, id value) {
        LogTo(ViewVerbose, @"    emit(%@, %@)",
              keyToJSONStr(key),
              (value == body) ? @"doc" : toJSONStr(value));
        C4Slice valueSlice;
        if (value == body) {
            valueSlice = kC4PlaceholderValue;
        } else if (value) {
            NSError* error;
            NSData* valueJSON = [CBLJSON dataWithJSONObject: value
                                                    options: CBLJSONWritingAllowFragments
                                                      error: &error];
            if (!valueJSON) {
                Warn(@"emit() called with invalid value: %@",
                     error.localizedDescription);
                return;
            }
            [emittedJSONValues addObject: valueJSON];  // keep it alive
            valueSlice = data2slice(valueJSON);
        } else {
            valueSlice = kC4SliceNull;
        }
        CLEANUP(C4Key) *c4key = id2key(key);
        c4kv_add(emitted, c4key, valueSlice);
    };

    // Now enumerate the docs:
    while (c4enum_next(e, &c4err)) {
        @autoreleasepool {
            // For each updated document:
            CLEANUP(C4Document) *doc = c4enum_getDocument(e, &c4err);
            if (!doc)
                break;
            latestSequence = doc->sequence;

            // Skip design docs
            if (doc->docID.size >= 8 && memcmp(doc->docID.buf, "_design/", 8) == 0)
                continue;

            // Read the document body:
            body = [CBLForestBridge bodyOfSelectedRevision: doc];
            body[@"_id"] = slice2string(doc->docID);
            body[@"_rev"] = slice2string(doc->revID);
            body[@"_local_seq"] = @(doc->sequence);
            if (doc->flags & kConflicted) {
                body[@"_conflicts"] = [CBLForestBridge getCurrentRevisionIDs: doc
                                                              includeDeleted: NO
                                                               onlyConflicts: YES];
            }
            LogTo(ViewVerbose, @"Mapping %@ rev %@", body.cbl_id, body.cbl_rev);

            // Feed it to each view's map function:
            for (unsigned curViewIndex = 0; curViewIndex < viewCount; ++curViewIndex) {
                if (viewCount == 1 || c4indexer_shouldIndexDocument(indexer, curViewIndex, doc)) {
                    @try {
                        maps[curViewIndex](body, emit);
                        // ...and emit the new key/value pairs to the index:
                        if (!c4indexer_emitList(indexer, doc, curViewIndex, emitted, &c4err))
                            return err2status(c4err);
                    } @catch (NSException* x) {
                        MYReportException(x, @"map block of view %@, on doc %@",
                                          [views[i] name], body);
                    }
                    c4kv_reset(emitted);
                    [emittedJSONValues removeAllObjects];
                }
            }
        }
    }
    if (c4err.code != 0)
        return err2status(c4err);

    // Finish up:
    c4indexer_end(indexer, true, &c4err);
    indexer = NULL; // keep CLEANUP from double-disposing it
    LogTo(View, @"... Finished re-indexing (%@) to #%lld", viewNames(views), latestSequence);
    return kCBLStatusOK;
}


// This is really just for unit tests & debugging
#if DEBUG
- (NSArray*) dump {
    C4View* index = [self openIndex: NULL];
    if (!index)
        return nil;
    NSMutableArray* result = $marray();

    C4Error c4err;
    CLEANUP(C4QueryEnumerator)* e = c4view_query(_view, NULL, &c4err);
    if (!e)
        return nil;
    while (c4queryenum_next(e, &c4err)) {
        CLEANUP(C4SliceResult) json = c4key_toJSON(&e->key);
        [result addObject: $dict({@"key", slice2string(json)},
                                 {@"value", slice2string(e->value)},
                                 {@"seq", @(e->docSequence)})];

    }
    return c4err.code ? nil : result;
}
#endif


#pragma mark - QUERYING:


/** Starts a view query, returning a CBForest enumerator. */
- (C4QueryEnumerator*) _forestQueryWithOptions: (CBLQueryOptions*)options
                                         error: (C4Error*)outError
{
    Assert(_view); // caller MUST call -openIndex: first
    C4QueryOptions forestOpts = kC4DefaultQueryOptions;
    forestOpts.skip = options->skip;
    if (options->limit != kCBLQueryOptionsDefaultLimit)
        forestOpts.limit = options->limit;
    forestOpts.descending = options->descending;
    forestOpts.inclusiveStart = options->inclusiveStart;
    forestOpts.inclusiveEnd = options->inclusiveEnd;
    forestOpts.startKeyDocID = string2slice(options.startKeyDocID);
    forestOpts.endKeyDocID = string2slice(options.endKeyDocID);

    id startKey = options.startKey, endKey = options.endKey;
    __strong id &maxKey = options->descending ? startKey : endKey;
    maxKey = CBLKeyForPrefixMatch(maxKey, options->prefixMatchLevel);
    forestOpts.startKey = id2key(startKey);
    forestOpts.endKey = id2key(endKey);

    if (options->bbox) {
        return c4view_geoQuery(_view, geoRect2Area(*options->bbox), outError);
    } else if (options.fullTextQuery) {
        return c4view_fullTextQuery(_view, string2slice(options.fullTextQuery),
                                    kC4SliceNull, &forestOpts, outError);
    } else {
        if (options.keys) {
            forestOpts.keysCount = options.keys.count;
            forestOpts.keys = (const C4Key**)malloc(forestOpts.keysCount * sizeof(C4Key*));
            NSUInteger i = 0;
            for (id keyObj in options.keys) {
                forestOpts.keys[i++] = id2key(keyObj);
            }
        }

        C4QueryEnumerator *e = c4view_query(_view, &forestOpts, outError);

        // Clean up allocated keys on the way out:
        if (forestOpts.keys) {
            for (NSUInteger i = 0; i < forestOpts.keysCount; i++)
                c4key_free((C4Key*)forestOpts.keys[i]);
            free(forestOpts.keys);
        }

        return e;
    }
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

    C4Error c4err;
    __block C4QueryEnumerator *e = [self _forestQueryWithOptions: options error: &c4err];
    if (!e) {
        *outStatus = err2status(c4err);
        return nil;
    }

    *outStatus = kCBLStatusOK;
    return ^CBLQueryRow*() {
        // This is the block that returns the next row:
        if (e == nil)
            return nil;
        if (limit-- == 0) {
            c4queryenum_free(e);
            e = nil;
            return nil;
        }
        C4Error c4err;
        while (c4queryenum_next(e, &c4err)) {
            CBL_Revision* docRevision = nil;
            id key = key2id(e->key);
            id value = nil;
            NSString* docID = slice2string(e->docID);
            SequenceNumber sequence = e->docSequence;

            if (options->includeDocs) {
                NSDictionary* valueDict = nil;
                NSString* linkedID = nil;
                if (e->value.size > 0 && ((char*)e->value.buf)[0] == '{') {
                    value = slice2jsonObject(e->value, 0);
                    valueDict = $castIf(NSDictionary, value);
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
                value = slice2data(e->value);
            LogTo(QueryVerbose, @"Query %@: Found row with key=%@, value=%@, id=%@",
                  _name, CBLJSONString(key), value, CBLJSONString(docID));
            
            // Create a CBLQueryRow:
            CBLQueryRow* row;
            if (options->bbox) {
                row = [[CBLGeoQueryRow alloc] initWithDocID: docID
                                                   sequence: sequence
                                                boundingBox: area2GeoRect(e->geoBBox)
                                                geoJSONData: slice2data(e->geoJSON)
                                                      value: value
                                                docRevision: docRevision
                                                    storage: self];
            } else if (options.fullTextQuery) {
                CBLFullTextQueryRow *ftrow;
                ftrow = [[CBLFullTextQueryRow alloc] initWithDocID: docID
                                                        sequence: e->docSequence
                                                      fullTextID: e->fullTextID
                                                           value: value
                                                         storage: self];
                for (NSUInteger t = 0; t < e->fullTextTermCount; t++) {
                    const C4FullTextTerm *term = &e->fullTextTerms[t];
                    [ftrow addTerm: term->termIndex atRange: {term->start, term->length}];
                }
                row = ftrow;
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

        // End of enumeration:
        c4queryenum_free(e);
        e = nil;
        return nil;
    };
}


- (CBLQueryIteratorBlock) fullTextQueryWithOptions: (CBLQueryOptions*)options
                                            status: (CBLStatus*)outStatus
{
    return [self regularQueryWithOptions: options status: outStatus];
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
    C4Error c4err;
    __block C4QueryEnumerator *e = [self _forestQueryWithOptions: options error: &c4err];
    if (!e) {
        *outStatus = err2status(c4err);
        return nil;
    }

    *outStatus = kCBLStatusOK;
    return ^CBLQueryRow*() {
        // This is the block that returns the next row:
        CBLQueryRow* row = nil;
        do {
            if (!e)
                return nil;
            id key = nil;
            C4Error c4err;
            if (c4queryenum_next(e, &c4err)) {
                key = key2id(e->key);
            } else {
                c4queryenum_free(e);
                e = NULL;
                if (c4err.code)
                    break;
            }

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
                id value = nil;
                if (c4SliceEqual(e->value, kC4PlaceholderValue)) {
                    CBLStatus status;
                    value = [_dbStorage getBodyWithID: slice2string(e->docID)
                                             sequence: e->docSequence
                                               status: &status];
                    if (!value)
                        Warn(@"%@: Couldn't load doc for row value: status %d", self, status);
                } else if (e->value.size > 0) {
                    value = slice2jsonObject(e->value, CBLJSONReadingAllowFragments);
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
    C4Error c4err;
    C4SliceResult valueSlice = c4view_fullTextMatched(_view, string2slice(docID),
                                                      sequence, (unsigned)fullTextID,
                                                      &c4err);
    if (!valueSlice.buf) {
        Warn(@"%@: Couldn't find full text for doc <%@>, seq %llu, fullTextID %llu (err %d/%d)",
             self, docID, sequence, fullTextID, c4err.domain, c4err.code);
        return nil;
    }
    return slice2dataAdopt(valueSlice);
}


@end
