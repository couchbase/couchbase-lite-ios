//
//  CBLDatabase.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 12/15/16.
//  Copyright © 2016 Couchbase. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLDatabase.h"
#import "c4BlobStore.h"
#import "c4Observer.h"
#import "CBLCoreBridge.h"
#import "CBLDocument.h"
#import "CBLDocument+Internal.h"
#import "CBLDocumentChange.h"
#import "CBLDocumentChangeListener.h"
#import "CBLDocumentFragment.h"
#import "CBLInternal.h"
#import "CBLMisc.h"
#import "CBLPredicateQuery+Internal.h"
#import "CBLSharedKeys.hh"
#import "CBLStringBytes.h"
#import "CBLStatus.h"


#define kDBExtension @"cblite2"


@implementation CBLDatabaseConfiguration

@synthesize directory=_directory, conflictResolver = _conflictResolver, encryptionKey=_encryptionKey;
@synthesize fileProtection=_fileProtection;


- (instancetype) init {
    self = [super init];
    if (self) {
#if TARGET_OS_IPHONE
        _fileProtection = NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication;
#endif
    }
    return self;
}


- (instancetype) copyWithZone:(NSZone *)zone {
    CBLDatabaseConfiguration* o = [[self.class alloc] init];
    o.directory = _directory;
    o.conflictResolver = _conflictResolver;
    o.encryptionKey = _encryptionKey;
    o.fileProtection = _fileProtection;
    return o;
}


- (NSString*) directory {
    if (!_directory)
        _directory = defaultDirectory();
    return _directory;
}


static NSString* defaultDirectory() {
    NSSearchPathDirectory dirID = NSApplicationSupportDirectory;
#if TARGET_OS_TV
    dirID = NSCachesDirectory; // Apple TV only allows apps to store data in the Caches directory
#endif
    NSArray* paths = NSSearchPathForDirectoriesInDomains(dirID, NSUserDomainMask, YES);
    NSString* path = paths[0];
#if !TARGET_OS_IPHONE
    NSString* bundleID = [[NSBundle mainBundle] bundleIdentifier];
    NSCAssert(bundleID, @"No bundle ID");
    path = [path stringByAppendingPathComponent: bundleID];
#endif
    return [path stringByAppendingPathComponent: @"CouchbaseLite"];
}


@end


@implementation CBLDatabase {
    NSString* _name;
    CBLDatabaseConfiguration* _config;
    CBLPredicateQuery* _allDocsQuery;
    
    C4DatabaseObserver* _dbObs;
    NSMutableSet* _dbChangeListeners;
    
    NSMutableDictionary* _docObs;
    NSMutableDictionary* _docChangeListeners;
}


@synthesize name=_name;
@synthesize c4db=_c4db, sharedKeys=_sharedKeys;
@synthesize replications=_replications, activeReplications=_activeReplications;


static const C4DatabaseConfig kDBConfig = {
    .flags = (kC4DB_Create | kC4DB_AutoCompact | kC4DB_Bundled | kC4DB_SharedKeys),
    .storageEngine = kC4SQLiteStorageEngine,
    .versioning = kC4RevisionTrees,
};


static void dbObserverCallback(C4DatabaseObserver* obs, void* context) {
    CBLDatabase *db = (__bridge CBLDatabase *)context;
    dispatch_async(dispatch_get_main_queue(), ^{        //TODO: Support other queues
        [db postDatabaseChanged];
    });
}


static void docObserverCallback(C4DocumentObserver* obs, C4Slice docID, C4SequenceNumber seq,
                                void *context)
{
    CBLDatabase *db = (__bridge CBLDatabase *)context;
    dispatch_async(dispatch_get_main_queue(), ^{        //TODO: Support other queues
        [db postDocumentChanged: slice2string(docID)];
    });
}


+ (void) initialize {
    if (self == [CBLDatabase class]) {
        CBLLog_Init();
    }
}


- (instancetype) initWithName: (NSString*)name
                        error: (NSError**)outError {
    return [self initWithName: name
                       config: [CBLDatabaseConfiguration new]
                        error: outError];
}


- (instancetype) initWithName: (NSString*)name
                       config: (nullable CBLDatabaseConfiguration*)config
                        error: (NSError**)outError {
    self = [super init];
    if (self) {
        _name = name;
        _config = config != nil? [config copy] : [CBLDatabaseConfiguration new];
        if (![self open: outError])
            return nil;
        _replications = [NSMapTable strongToWeakObjectsMapTable];
        _activeReplications = [NSMutableSet new];
    }
    return self;
}


- (instancetype) copyWithZone: (NSZone*)zone {
    return [[[self class] alloc] initWithName: _name config: _config error: nil];
}


- (void) dealloc {
    [self freeC4Observer];
    [self freeC4DB];
}


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%@]", self.class, _name];
}


- (NSString*) path {
    return _c4db != nullptr ? sliceResult2FilesystemPath(c4db_getPath(_c4db)) : nil;
}


- (uint64_t) count {
    return _c4db != nullptr ? c4db_getDocumentCount(_c4db) : 0;
}


- (CBLDatabaseConfiguration*) config {
    return [_config copy];
}


#pragma mark - GET EXISTING DOCUMENT


- (CBLDocument*) documentWithID: (NSString*)documentID {
    return [self documentWithID: documentID mustExist: YES error: nil];
}


#pragma mark - CHECK DOCUMENT EXISTS


- (BOOL) contains: (NSString*)docID {
    id doc = [self documentWithID: docID mustExist: YES error: nil];
    return doc != nil;
}


#pragma mark - SUBSCRIPTION


- (CBLDocumentFragment*) objectForKeyedSubscript: (NSString*)documentID {
    return [[CBLDocumentFragment alloc] initWithDocument: [self documentWithID: documentID]];
}


#pragma mark - SAVE


- (BOOL) saveDocument: (CBLDocument*)document error: (NSError**)error {
    if ([self prepareDocument: document error: error])
        return [document save: error];
    else
        return NO;
}


- (BOOL) deleteDocument: (CBLDocument*)document error: (NSError**)error {
    if ([self prepareDocument: document error: error])
        return [document deleteDocument: error];
    else
        return NO;
}


- (BOOL) purgeDocument: (CBLDocument *)document error: (NSError**)error {
    if ([self prepareDocument: document error: error])
        return [document purge: error];
    else
        return NO;
}


#pragma mark - BATCH OPERATION


- (BOOL) inBatch: (NSError**)outError do: (void (^)())block {
    [self mustBeOpen];
    
    C4Transaction transaction(_c4db);
    if (outError)
        *outError = nil;
    
    if (!transaction.begin())
        return convertError(transaction.error(), outError);
    
    block();
    
    if (!transaction.commit())
        return convertError(transaction.error(), outError);
    
    [self postDatabaseChanged];
    return YES;
}


#pragma mark - DATABASE MAINTENANCE


- (BOOL) close: (NSError**)outError {
    if (_c4db == nullptr)
        return YES;
    
    CBLLog(Database, @"Closing %@ at path %@", self, self.path);
    
    _allDocsQuery = nil;
    
    C4Error err;
    if (!c4db_close(_c4db, &err))
        return convertError(err, outError);
    
    [self freeC4Observer];
    [self freeC4DB];
    
    return YES;
}


- (BOOL) deleteDatabase: (NSError**)outError {
    [self mustBeOpen];
    
    C4Error err;
    if (!c4db_delete(_c4db, &err))
        return convertError(err, outError);
    
    [self freeC4Observer];
    [self freeC4DB];
    
    return YES;
}


- (BOOL) compact: (NSError**)outError {
    [self mustBeOpen];
    
    C4Error err;
    if (!c4db_compact(_c4db, &err))
        return convertError(err, outError);
    return YES;
}


- (BOOL) changeEncryptionKey: (nullable id)key error: (NSError**)outError {
    return NO; // TODO
}


+ (BOOL) deleteDatabase: (NSString*)name
            inDirectory: (nullable NSString*)directory
                  error: (NSError**)outError {
    NSString* path = databasePath(name, directory ?: defaultDirectory());
    CBLStringBytes bPath(path);
    C4Error err;
    return c4db_deleteAtPath(bPath, &kDBConfig, &err) || err.code==0 || convertError(err, outError);
}


+ (BOOL) databaseExists: (NSString*)name
            inDirectory: (nullable NSString*)directory {
    NSString* path = databasePath(name, directory ?: defaultDirectory());
    return [[NSFileManager defaultManager] fileExistsAtPath: path];
}


#pragma mark - DOCUMENT CHANGES


- (id<NSObject>) addChangeListener: (void (^)(CBLDatabaseChange*))block {
    [self mustBeOpen];
    
    return [self addDatabaseChangeListener: block];
}


- (id<NSObject>) addChangeListenerForDocumentID: (NSString*)documentID
                                     usingBlock: (void (^)(CBLDocumentChange*))block
{
    [self mustBeOpen];
    
    return [self addDocumentChangeListener: block documentID: documentID];
}


- (void) removeChangeListener: (id<NSObject>)listener {
    [self mustBeOpen];
    
    if ([listener isKindOfClass: [CBLDocumentChangeListener class]])
        [self removeDocumentChangeListener:listener];
    else
        [self removeDatabaseChangeListener:listener];
}


#pragma mark - QUERIES:


- (NSEnumerator<CBLDocument*>*) allDocuments {
    [self mustBeOpen];
    
    if (!_allDocsQuery) {
        _allDocsQuery = [[CBLPredicateQuery alloc] initWithDatabase: self];
        _allDocsQuery.orderBy = @[@"_id"];
    }
    auto e = [_allDocsQuery allDocuments: nullptr];
    Assert(e, @"allDocuments failed?!");
    return e;
}


- (CBLPredicateQuery*) createQueryWhere: (nullable id)where {
    [self mustBeOpen];
    
    auto query = [[CBLPredicateQuery alloc] initWithDatabase: self];
    query.where = where;
    return query;
}


- (BOOL) createIndexOn: (NSArray<NSExpression*>*)expressions error: (NSError**)outError {
    return [self createIndexOn: expressions type: kCBLValueIndex options: NULL error: outError];
}


- (BOOL) createIndexOn: (NSArray*)expressions
                  type: (CBLIndexType)type
               options: (const CBLIndexOptions*)options
                 error: (NSError**)outError
{
    [self mustBeOpen];
    
    static_assert(sizeof(CBLIndexOptions) == sizeof(C4IndexOptions), "Index options incompatible");
    NSData* json = [CBLPredicateQuery encodeExpressionsToJSON: expressions error: outError];
    if (!json)
        return NO;
    C4Error c4err;
    return c4db_createIndex(_c4db,
                            {json.bytes, json.length},
                            (C4IndexType)type,
                            (const C4IndexOptions*)options,
                            &c4err)
    || convertError(c4err, outError);
}


- (BOOL) deleteIndexOn: (NSArray<NSExpression*>*)expressions
                  type: (CBLIndexType)type
                 error: (NSError**)outError
{
    [self mustBeOpen];
    
    NSData* json = [CBLPredicateQuery encodeExpressionsToJSON: expressions error: outError];
    if (!json)
        return NO;
    C4Error c4err;
    return c4db_deleteIndex(_c4db, {json.bytes, json.length}, (C4IndexType)type, &c4err)
    || convertError(c4err, outError);
}


#pragma mark - INTERNAL


- (C4BlobStore*) getBlobStore: (NSError**)outError {
    if (![self mustBeOpen: outError])
        return nil;
    C4Error err;
    C4BlobStore *blobStore = c4db_getBlobStore(_c4db, &err);
    if (!blobStore)
        convertError(err, outError);
    return blobStore;
}


#pragma mark - PRIVATE


- (BOOL) open: (NSError**)outError {
    if (_c4db)
        return YES;
    
    NSString* dir = _config.directory;
    Assert(dir != nil);
    if (![self setupDirectory: dir
               fileProtection: _config.fileProtection
                        error: outError])
        return NO;
    
    NSString* path = databasePath(_name, dir);
    CBLStringBytes bPath(path);
    
    C4DatabaseConfig c4config = kDBConfig;
    if (_config.encryptionKey != nil) {
        CBLSymmetricKey* key = [[CBLSymmetricKey alloc]
                                initWithKeyOrPassword: _config.encryptionKey];
        c4config.encryptionKey = symmetricKey2C4Key(key);
    }
    
    CBLLog(Database, @"Opening %@ at path %@", self, path);
    C4Error err;
    _c4db = c4db_open(bPath, &c4config, &err);
    if (!_c4db)
        return convertError(err, outError);
    
    _sharedKeys = cbl::SharedKeys(_c4db);
    
    return YES;
}


static NSString* databasePath(NSString* name, NSString* dir) {
    name = [[name stringByReplacingOccurrencesOfString: @"/" withString: @":"]
            stringByAppendingPathExtension: kDBExtension];
    NSString* path = [dir stringByAppendingPathComponent: name];
    return path.stringByStandardizingPath;
}


- (BOOL) setupDirectory: (NSString*)dir
         fileProtection: (NSDataWritingOptions)fileProtection
                  error: (NSError**)outError
{
    NSDictionary* attributes = nil;
#if TARGET_OS_IPHONE
    // Set the iOS file protection mode of the manager's top-level directory.
    // This mode will be inherited by all files created in that directory.
    NSString* protection;
    switch (fileProtection & NSDataWritingFileProtectionMask) {
        case NSDataWritingFileProtectionNone:
            protection = NSFileProtectionNone;
            break;
        case NSDataWritingFileProtectionComplete:
            protection = NSFileProtectionComplete;
            break;
        case NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication:
            protection = NSFileProtectionCompleteUntilFirstUserAuthentication;
            break;
        default:
            protection = NSFileProtectionCompleteUnlessOpen;
            break;
    }
    attributes = @{NSFileProtectionKey: protection};
#endif
    
    NSError* error;
    if (![[NSFileManager defaultManager] createDirectoryAtPath: dir
                                   withIntermediateDirectories: YES
                                                    attributes: attributes
                                                         error: &error]) {
        if (!CBLIsFileExistsError(error)) {
            if (outError) *outError = error;
            return NO;
        }
    }
    
    if (attributes) {
        // TODO: Optimization - Check the existing file protection level.
        if (![[NSFileManager defaultManager] setAttributes: attributes
                                              ofItemAtPath: dir
                                                     error: outError])
            return NO;
    }
    
    return YES;
}


- (void) mustBeOpen {
    if (_c4db == nullptr) {
        [NSException raise: NSInternalInconsistencyException
                    format: @"Database is not open."];
    }
}


- (BOOL) mustBeOpen: (NSError**)outError {
    return _c4db != nullptr || convertError({LiteCoreDomain, kC4ErrorNotOpen}, outError);
}


- (nullable CBLDocument*) documentWithID: (NSString*)documentID
                               mustExist: (bool)mustExist
                                   error: (NSError**)outError
{
    [self mustBeOpen];
    
    return [[CBLDocument alloc] initWithDatabase: self
                                      documentID: documentID
                                       mustExist: mustExist
                                           error: outError];
}


- (BOOL) prepareDocument: (CBLDocument*)document error: (NSError**)error {
    [self mustBeOpen];
    
    if (!document.database) {
        document.database = self;
    } else if (document.database != self) {
        return createError(kCBLStatusForbidden,
                           @"The document is from the different database.", error);
    }
    return YES;
}


- (id<NSObject>) addDatabaseChangeListener: (void (^)(CBLDatabaseChange*))block {
    if (!_dbChangeListeners) {
        _dbChangeListeners = [NSMutableSet set];
        _dbObs = c4dbobs_create(_c4db, dbObserverCallback, (__bridge void *)self);
    }
    
    CBLChangeListener* listener = [[CBLChangeListener alloc] initWithBlock: block];
    [_dbChangeListeners addObject: listener];
    return listener;
}


- (void) removeDatabaseChangeListener: (id<NSObject>)listener {
    [_dbChangeListeners removeObject:listener];
    
    if (_dbChangeListeners.count == 0) {
        c4dbobs_free(_dbObs);
        _dbObs = nil;
        _dbChangeListeners = nil;
    }
}


- (void) postDatabaseChanged {
    if (!_dbObs || !_c4db || c4db_isInTransaction(_c4db))
        return;
    
    const uint32_t kMaxChanges = 100u;
    C4DatabaseChange changes[kMaxChanges];
    bool external = false;
    uint32_t nChanges = 0u;
    NSMutableArray* docIDs = [NSMutableArray new];
    do {
        // Read changes in batches of kMaxChanges:
        bool newExternal;
        nChanges = c4dbobs_getChanges(_dbObs, changes, kMaxChanges, &newExternal);
        if (nChanges == 0 || external != newExternal || docIDs.count > 1000) {
            if(docIDs.count > 0) {
                CBLDatabaseChange* change = [[CBLDatabaseChange alloc] initWithDocumentIDs: docIDs
                                                                                isExternal: external];
                for (CBLChangeListener* listener in _dbChangeListeners) {
                    void (^block)(CBLDatabaseChange*) = listener.block;
                    block(change);
                }
                docIDs = [NSMutableArray new];
            }
        }
        
        external = newExternal;
        for(uint32_t i = 0; i < nChanges; i++) {
            NSString *docID =slice2string(changes[i].docID);
            [docIDs addObject: docID];
        }
    } while(nChanges > 0);
}


- (id<NSObject>) addDocumentChangeListener: (void (^)(CBLDocumentChange*))block
                                documentID: (NSString*)documentID
{
    if (!_docChangeListeners)
        _docChangeListeners = [NSMutableDictionary dictionary];
    
    NSMutableSet* listeners = _docChangeListeners[documentID];
    if (!listeners) {
        listeners = [NSMutableSet set];
        [_docChangeListeners setObject: listeners forKey: documentID];
        
        CBLStringBytes bDocID(documentID);
        C4DocumentObserver* o =
        c4docobs_create(_c4db, bDocID, docObserverCallback, (__bridge void *)self);
        
        if (!_docObs)
            _docObs = [NSMutableDictionary dictionary];
        [_docObs setObject: [NSValue valueWithPointer: o] forKey: documentID];
    }
    
    id listener = [[CBLDocumentChangeListener alloc] initWithDocumentID: documentID
                                                              withBlock: block];
    [listeners addObject: listener];
    return listener;
}


- (void) removeDocumentChangeListener: (CBLDocumentChangeListener*)listener {
    NSString* documentID = listener.documentID;
    NSMutableSet* listeners = _docChangeListeners[documentID];
    if (listeners) {
        [listeners removeObject: listener];
        if (listeners.count == 0) {
            NSValue* obsValue = [_docObs objectForKey: documentID];
            if (obsValue) {
                C4DocumentObserver* obs = (C4DocumentObserver*)obsValue.pointerValue;
                c4docobs_free(obs);
            }
            [_docObs removeObjectForKey: documentID];
            [_docChangeListeners removeObjectForKey:documentID];
        }
    }
}


- (void) postDocumentChanged: (NSString*)documentID {
    if (!_docObs[documentID] || !_c4db ||  c4db_isInTransaction(_c4db))
        return;
    
    CBLDocumentChange* change = [[CBLDocumentChange alloc] initWithDocumentID: documentID];
    NSSet* listeners = [_docChangeListeners objectForKey: documentID];
    for (CBLDocumentChangeListener* listener in listeners) {
        void (^block)(CBLDocumentChange*) = listener.block;
        block(change);
    }
}


- (void) freeC4Observer {
    c4dbobs_free(_dbObs);
    _dbObs = nullptr;
    _dbChangeListeners = nil;
    
    for (NSValue* obsValue in _docObs.allValues) {
        C4DocumentObserver* obs = (C4DocumentObserver*)obsValue.pointerValue;
        c4docobs_free(obs);
    }
    
    _docObs = nil;
    _docChangeListeners = nil;
}


- (void) freeC4DB {
    c4db_free(_c4db);
    _c4db = nil;
}


#pragma mark - RESOLVING REPLICATED CONFLICTS:


- (bool) resolveConflictInDocument: (NSString*)docID error: (NSError**)outError {
    C4Transaction t(_c4db);
    t.begin();

    auto doc = [[CBLReadOnlyDocument alloc] initWithDatabase: self
                                                  documentID: docID
                                                   mustExist: YES
                                                       error: outError];
    if (!doc)
        return false;

    // Read the conflicting remote revision:
    auto otherDoc = [[CBLReadOnlyDocument alloc] initWithDatabase: self
                                                       documentID: docID
                                                        mustExist: YES
                                                            error: outError];
    if (!otherDoc || ![otherDoc selectConflictingRevision])
        return false;

    // Read the common ancestor revision (if it's available):
    auto baseDoc = [[CBLReadOnlyDocument alloc] initWithDatabase: self
                                                      documentID: docID
                                                       mustExist: YES
                                                           error: outError];
    if (![baseDoc selectCommonAncestorOfDoc: doc andDoc: otherDoc] || !baseDoc.data)
        baseDoc = nil;

    // Call the conflict resolver:
    CBLReadOnlyDocument* resolved;
    if (otherDoc.isDeleted) {
        resolved = doc;
    } else if (doc.isDeleted) {
        resolved = otherDoc;
    } else {
        auto resolver = doc.effectiveConflictResolver;
        auto conflict = [[CBLConflict alloc] initWithMine: doc theirs: otherDoc base: baseDoc];
        CBLLog(Database, @"Resolving doc '%@' with %@ (mine=%@, theirs=%@, base=%@",
               docID, resolver.class, doc.revID, otherDoc.revID, baseDoc.revID);
        resolved = [resolver resolve: conflict];
        if (!resolved)
            return convertError({LiteCoreDomain, kC4ErrorConflict}, outError);
    }

    // Figure out what revision to delete and what if anything to add:
    CBLStringBytes winningRevID, losingRevID;
    NSData* mergedBody = nil;
    if (resolved == otherDoc) {
        winningRevID = otherDoc.revID;
        losingRevID = doc.revID;
    } else {
        winningRevID = doc.revID;
        losingRevID = otherDoc.revID;
        if (resolved != doc) {
            resolved.database = self;
            mergedBody = [resolved encode: outError];
            if (!mergedBody)
                return false;
        }
    }

    // Tell LiteCore to do the resolution:
    C4Document *rawDoc = doc.c4Doc.rawDoc;
    C4Error c4err;
    if (!c4doc_resolveConflict(rawDoc,
                               winningRevID,
                               losingRevID,
                               data2slice(mergedBody),
                               &c4err)
            || !c4doc_save(rawDoc, 0, &c4err)) {
        return convertError(c4err, outError);
    }
    CBLLog(Database, @"Conflict resolved as doc '%@' rev %.*s",
           docID, (int)rawDoc->revID.size, rawDoc->revID.buf);

    return t.commit() || convertError(t.error(), outError);
}


@end

