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
#import "CBL_ForestDBQueryEnumerator.h"


#define kViewIndexPathExtension @"viewindex"

// Close the index db after it's inactive this many seconds
#define kCloseDelay 60.0


@implementation CBL_ForestDBViewStorage
{
    CBL_ForestDBStorage* _dbStorage;
    NSString* _path;
    C4View* _view;
}

@synthesize delegate=_delegate, name=_name, dbStorage=_dbStorage;


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


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%@]", self.class, _name];
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
    CBLStatus status;
    if (![self closeIndex: &status])
        Warn(@"Couldn't close index of %@: status=%d", self, status);
}


- (BOOL) closeIndex: (CBLStatus*)outStatus {
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(closeIndexNow)
                                               object: nil];
    if (_view) {
        LogTo(View, @"%@: Closing index", self);
        C4Error c4err;
        if (!c4view_close(_view, &c4err)) {
            *outStatus = err2status(c4err);
            return NO;
        }
        _view = NULL;
    }
    return YES;
}

- (void) closeIndexNow {
    CBLStatus status;
    if (![self closeIndex: &status]) {
        if (status == kCBLStatusDBBusy) {
            LogTo(View, @"%@: ...index is busy, will retry", self);
            [self closeIndexSoon];      // Try again later if the index is currently busy
        } else {
            Warn(@"Couldn't close index of idle view %@: status=%d", self, status);
        }
    }
}

- (void) closeIndexSoon {
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(closeIndexNow)
                                               object: nil];
    [self performSelector: @selector(closeIndexNow) withObject: nil afterDelay: kCloseDelay];
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
            LogVerbose(View, @"    %@ has no map block; skipping it", view.name);
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
        LogVerbose(View, @"    emit(%@, %@)",
              keyToJSONStr(key),
              (value == body) ? @"doc" : toJSONStr(value));
        if (!key) {
            Warn(@"emit() called with nil key; ignoring");
            return;
        }
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
                     error.my_compactDescription);
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
            LogVerbose(View, @"Mapping %@ rev %@", body.cbl_id, body.cbl_rev);

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


- (CBLQueryEnumerator*) queryWithOptions: (CBLQueryOptions*)options
                                  status: (CBLStatus*)outStatus
{
    if (![self openIndex: outStatus])
        return nil;
    C4Error c4err;
    CBL_ForestDBQueryEnumerator* enumer;
    enumer = [[CBL_ForestDBQueryEnumerator alloc] initWithStorage: self
                                                           C4View: _view
                                                          options: options
                                                            error: &c4err];
    *outStatus = enumer ? kCBLStatusOK : err2status(c4err);
    return enumer;
}


// CBL_QueryRowStorage API:


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
