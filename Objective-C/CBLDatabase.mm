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
#import "CBLDatabase+Internal.h"
#import "CBLDocument+Internal.h"
#import "CBLDocumentChangeListenerToken.h"
#import "CBLDocumentFragment.h"
#import "CBLEncryptionKey+Internal.h"
#import "CBLIndex+Internal.h"
#import "CBLQuery+Internal.h"
#import "CBLMisc.h"
#import "CBLStringBytes.h"
#import "CBLStatus.h"

using namespace fleece;

#define kDBExtension @"cblite2"

@implementation CBLDatabase {
    NSString* _name;
    CBLDatabaseConfiguration* _config;
    CBLPredicateQuery* _allDocsQuery;
    
    C4DatabaseObserver* _dbObs;
    NSMutableSet* _dbListenerTokens;
    
    NSMutableDictionary* _docObs;
    NSMutableDictionary* _docListenerTokens;
}


@synthesize name=_name;
@synthesize dispatchQueue=_dispatchQueue;
@synthesize c4db=_c4db, sharedKeys=_sharedKeys;
@synthesize replications=_replications, activeReplications=_activeReplications;


static const C4DatabaseConfig kDBConfig = {
    .flags = (kC4DB_Create | kC4DB_AutoCompact | kC4DB_SharedKeys),
    .storageEngine = kC4SQLiteStorageEngine,
    .versioning = kC4RevisionTrees,
};


static void dbObserverCallback(C4DatabaseObserver* obs, void* context) {
    CBLDatabase *db = (__bridge CBLDatabase *)context;
    dispatch_async(db.dispatchQueue, ^{
        [db postDatabaseChanged];
    });
}


static void docObserverCallback(C4DocumentObserver* obs, C4Slice docID, C4SequenceNumber seq,
                                void *context)
{
    CBLDatabase *db = (__bridge CBLDatabase *)context;
    dispatch_async(db.dispatchQueue, ^{
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
        
        NSString* qName = $sprintf(@"Database <%@>", name);
        _dispatchQueue = dispatch_queue_create(qName.UTF8String, DISPATCH_QUEUE_SERIAL);
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
    CBL_LOCK(self) {
        return _c4db != nullptr ? sliceResult2FilesystemPath(c4db_getPath(_c4db)) : nil;
    }
}


- (uint64_t) count {
    CBL_LOCK(self) {
        return _c4db != nullptr ? c4db_getDocumentCount(_c4db) : 0;
    }
}


- (CBLDatabaseConfiguration*) config {
    return [_config copy];
}


#pragma mark - GET EXISTING DOCUMENT


- (CBLDocument*) documentWithID: (NSString*)documentID {
    return [self documentWithID: documentID error: nil];
}


#pragma mark - CHECK DOCUMENT EXISTS


- (BOOL) containsDocumentWithID: (NSString*)docID {
    return [self documentWithID: docID error: nil] != nil;
}


#pragma mark - SUBSCRIPTION


- (CBLDocumentFragment*) objectForKeyedSubscript: (NSString*)documentID {
    return [[CBLDocumentFragment alloc] initWithDocument: [self documentWithID: documentID]];
}


#pragma mark - SAVE


- (CBLDocument*) saveDocument: (CBLMutableDocument*)document error: (NSError**)error {
    return [self saveDocument: document asDeletion: NO error: error];
}


- (BOOL) deleteDocument: (CBLDocument*)document error: (NSError**)error {
    return [self saveDocument: document asDeletion: YES error: error] != nil;
}


- (BOOL) purgeDocument: (CBLDocument*)document error: (NSError**)error {
    CBL_LOCK(self) {
        if (![self prepareDocument: document error: error])
            return NO;
        
        if (!document.exists)
            return createError(kCBLStatusNotFound, error);
        
        C4Transaction transaction(self.c4db);
        if (!transaction.begin())
            return convertError(transaction.error(),  error);
        
        C4Error err;
        if (c4doc_purgeRevision(document.c4Doc.rawDoc, C4Slice(), &err) >= 0) {
            if (c4doc_save(document.c4Doc.rawDoc, 0, &err)) {
                // Save succeeded; now commit:
                if (!transaction.commit())
                    return convertError(transaction.error(), error);
                
                return YES;
            }
        }
        return convertError(err, error);
    }
}


#pragma mark - BATCH OPERATION


- (BOOL) inBatch: (NSError**)outError usingBlock: (void (^)())block {
    CBL_LOCK(self) {
        [self mustBeOpen];
        
        C4Transaction transaction(_c4db);
        if (outError)
            *outError = nil;
        
        if (!transaction.begin())
            return convertError(transaction.error(), outError);
        
        block();
        
        if (!transaction.commit())
            return convertError(transaction.error(), outError);
    }
    
    [self postDatabaseChanged];
    
    return YES;
}


#pragma mark - DATABASE MAINTENANCE


- (BOOL) close: (NSError**)outError {
    CBL_LOCK(self) {
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
}


- (BOOL) delete: (NSError**)outError {
    CBL_LOCK(self) {
        [self mustBeOpen];
        
        C4Error err;
        if (!c4db_delete(_c4db, &err))
            return convertError(err, outError);
        
        [self freeC4Observer];
        [self freeC4DB];
        
        return YES;
    }
}


- (BOOL) compact: (NSError**)outError {
    CBL_LOCK(self) {
        [self mustBeOpen];
        
        C4Error err;
        if (!c4db_compact(_c4db, &err))
            return convertError(err, outError);
        return YES;
    }
}


- (BOOL) setEncryptionKey: (nullable CBLEncryptionKey*)key error: (NSError**)outError {
    CBL_LOCK(self) {
        [self mustBeOpen];
        
        C4Error err;
        C4EncryptionKey encKey = c4EncryptionKey(key);
        if (!c4db_rekey(_c4db, &encKey, &err))
            return convertError(err, outError);
        
        return YES;
    }
}


+ (BOOL) deleteDatabase: (NSString*)name
            inDirectory: (nullable NSString*)directory
                  error: (NSError**)outError
{
    NSString* path = databasePath(name, directory ?: defaultDirectory());
    slice bPath(path.fileSystemRepresentation);
    C4Error err;
    return c4db_deleteAtPath(bPath, &err) || err.code==0 || convertError(err, outError);
}


+ (BOOL) databaseExists: (NSString*)name
            inDirectory: (nullable NSString*)directory {
    NSString* path = databasePath(name, directory ?: defaultDirectory());
    return [[NSFileManager defaultManager] fileExistsAtPath: path];
}


+ (BOOL) copyFromPath: (NSString*)path
           toDatabase: (NSString*)name
           withConfig: (nullable CBLDatabaseConfiguration*)config
                error: (NSError**)outError
{
    NSString* toPathStr = databasePath(name, config.directory ?: defaultDirectory());
    slice toPath(toPathStr.fileSystemRepresentation);
    slice fromPath(path.fileSystemRepresentation);

    C4Error err;
    C4DatabaseConfig c4Config = c4DatabaseConfig(config ?: [CBLDatabaseConfiguration new]);
    if (c4db_copy(fromPath, toPath, &c4Config, &err) || err.code==0 || convertError(err, outError)) {
        BOOL success = setupDatabaseDirectory(toPathStr, config.fileProtection, outError);
        if (!success) {
            NSError* removeError;
            if (![[NSFileManager defaultManager] removeItemAtPath: toPathStr error: &removeError])
                CBLWarn(Database, @"Error when deleting the copied database dir: %@", removeError);
        }
        return success;
    } else
        return NO;
}


#pragma mark - Logging


+ (void) setLogLevel: (CBLLogLevel)level domain: (CBLLogDomain)domain {
    C4LogLevel c4level = level != kCBLLogLevelNone ? (C4LogLevel)level : kC4LogNone;
    switch (domain) {
        case kCBLLogDomainAll:
            CBLSetLogLevel(Database, c4level);
            CBLSetLogLevel(DB, c4level);
            CBLSetLogLevel(Query, c4level);
            CBLSetLogLevel(SQL, c4level);
            CBLSetLogLevel(Sync, c4level);
            CBLSetLogLevel(BLIP, c4level);
            CBLSetLogLevel(Actor, c4level);
            CBLSetLogLevel(WebSocket, c4level);
            break;
        case kCBLLogDomainDatabase:
            CBLSetLogLevel(Database, c4level);
            CBLSetLogLevel(DB, c4level);
            break;
        case kCBLLogDomainQuery:
            CBLSetLogLevel(Query, c4level);
            CBLSetLogLevel(SQL, c4level);
            break;
        case kCBLLogDomainReplicator:
            CBLSetLogLevel(Sync, c4level);
            break;
        case kCBLLogDomainNetwork:
            CBLSetLogLevel(BLIP, c4level);
            CBLSetLogLevel(Actor, c4level);
            CBLSetLogLevel(WebSocket, c4level);
        default:
            break;
    }
}


#pragma mark - DOCUMENT CHANGES


- (id<CBLListenerToken>) addChangeListener: (void (^)(CBLDatabaseChange*))listener {
    return [self addChangeListenerWithQueue: nil listener: listener];
}


- (id<CBLListenerToken>) addChangeListenerWithQueue: (nullable dispatch_queue_t)queue
                                           listener: (void (^)(CBLDatabaseChange*))listener
{
    CBL_LOCK(self) {
        [self mustBeOpen];
        
        return [self addDatabaseChangeListener: listener queue: queue];
    }
}


- (id<CBLListenerToken>) addDocumentChangeListenerWithID: (NSString*)id
                                                listener: (void (^)(CBLDocumentChange*))listener
{
    return [self addDocumentChangeListenerWithID: id queue: nil listener: listener];
}


- (id<CBLListenerToken>) addDocumentChangeListenerWithID: (NSString*)id
                                                   queue: (nullable dispatch_queue_t)queue
                                                listener: (void (^)(CBLDocumentChange*))listener
{
    CBL_LOCK(self) {
        [self mustBeOpen];
        
        return [self addDocumentChangeListenerWithDocumentID: id listener: listener queue: queue];
    }
}


- (void) removeChangeListenerWithToken: (id<CBLListenerToken>)token {
    CBL_LOCK(self) {
        [self mustBeOpen];
        
        if ([token isKindOfClass: [CBLDocumentChangeListenerToken class]])
            [self removeDocumentChangeListenerWithToken: token];
        else
            [self removeDatabaseChangeListenerWithToken: token];
    }
}


#pragma mark - Index:


- (NSArray<NSString*>*) indexes {
    CBL_LOCK(self) {
        [self mustBeOpen];
        
        C4SliceResult data = c4db_getIndexes(_c4db, nullptr);
        FLValue value = FLValue_FromTrustedData((FLSlice)data);
        return FLValue_GetNSObject(value, _sharedKeys, nullptr);
    }
}


- (BOOL) createIndex: (CBLIndex*)index withName: (NSString*)name error: (NSError**)outError {
    CBL_LOCK(self) {
        [self mustBeOpen];
        
        NSData* json = [NSJSONSerialization dataWithJSONObject: index.indexItems
                                                       options: 0
                                                         error: outError];
        if (!json)
            return NO;
        
        CBLStringBytes bName(name);
        C4IndexType type = index.indexType;
        C4IndexOptions options = index.indexOptions;
        
        C4Error c4err;
        return c4db_createIndex(_c4db, bName, {json.bytes, json.length}, type, &options, &c4err) ||
        convertError(c4err, outError);
    }
}


- (BOOL) deleteIndexForName:(NSString *)name error:(NSError **)outError {
    CBL_LOCK(self) {
        [self mustBeOpen];
        
        CBLStringBytes bName(name);
        C4Error c4err;
        return c4db_deleteIndex(_c4db, bName, &c4err) || convertError(c4err, outError);
    }
}


#pragma mark - INTERNAL


- (CBLPredicateQuery*) createQueryWhere: (nullable id)where {
    CBL_LOCK(self) {
        [self mustBeOpen];
        
        auto query = [[CBLPredicateQuery alloc] initWithDatabase: self];
        query.where = where;
        return query;
    }
}


- (C4BlobStore*) getBlobStore: (NSError**)outError {
    CBL_LOCK(self) {
        if (![self mustBeOpen: outError])
            return nil;
        
        C4Error err;
        C4BlobStore *blobStore = c4db_getBlobStore(_c4db, &err);
        if (!blobStore)
            convertError(err, outError);
        return blobStore;
    }
}


#pragma mark - PRIVATE


- (BOOL) open: (NSError**)outError {
    if (_c4db)
        return YES;
    
    NSString* dir = _config.directory;
    Assert(dir != nil);
    if (!setupDatabaseDirectory(dir, _config.fileProtection, outError))
        return NO;
    
    NSString* path = databasePath(_name, dir);
    slice bPath(path.fileSystemRepresentation);

    C4DatabaseConfig c4config = c4DatabaseConfig(_config);
    CBLLog(Database, @"Opening %@ at path %@", self, path);
    C4Error err;
    _c4db = c4db_open(bPath, &c4config, &err);
    if (!_c4db)
        return convertError(err, outError);
    
    _sharedKeys = c4db_getFLSharedKeys(_c4db);
    
    return YES;
}


static NSString* defaultDirectory() {
    return [CBLDatabaseConfiguration defaultDirectory];
}


static NSString* databasePath(NSString* name, NSString* dir) {
    name = [[name stringByReplacingOccurrencesOfString: @"/" withString: @":"]
            stringByAppendingPathExtension: kDBExtension];
    NSString* path = [dir stringByAppendingPathComponent: name];
    return path.stringByStandardizingPath;
}


static BOOL setupDatabaseDirectory(NSString* dir,
                                   NSDataWritingOptions fileProtection,
                                   NSError** outError)
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
            break;
    }
    if (protection)
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


static C4DatabaseConfig c4DatabaseConfig (CBLDatabaseConfiguration* config) {
    C4DatabaseConfig c4config = kDBConfig;
    if (config.encryptionKey != nil)
        c4config.encryptionKey = c4EncryptionKey(config.encryptionKey);
    return c4config;
}


static C4EncryptionKey c4EncryptionKey(CBLEncryptionKey* key) {
    C4EncryptionKey cKey;
    if (key) {
        cKey.algorithm = kC4EncryptionAES256;
        Assert(key.key.length == sizeof(cKey.bytes), @"Invalid key size");
        memcpy(cKey.bytes, key.key.bytes, sizeof(cKey.bytes));
    } else
        cKey.algorithm = kC4EncryptionNone;
    return cKey;
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
                                   error: (NSError**)outError
{
    CBL_LOCK(self) {
        [self mustBeOpen];
        
        return [[CBLDocument alloc] initWithDatabase: self
                                          documentID: documentID
                                      includeDeleted: NO
                                               error: outError];
    }
}


// Must be called inside a lock
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


- (id<CBLListenerToken>) addDatabaseChangeListener: (void (^)(CBLDatabaseChange*))listener
                                             queue: (dispatch_queue_t)queue
{
    if (!_dbListenerTokens) {
        _dbListenerTokens = [NSMutableSet set];
        _dbObs = c4dbobs_create(_c4db, dbObserverCallback, (__bridge void *)self);
    }
    
    id token = [[CBLChangeListenerToken alloc] initWithListener: listener
                                                          queue: queue];
    
    
    [_dbListenerTokens addObject: token];
    return token;
}


- (void) removeDatabaseChangeListenerWithToken: (id<CBLListenerToken>)token {
    CBL_LOCK(self) {
        [_dbListenerTokens removeObject: token];
        
        if (_dbListenerTokens.count == 0) {
            c4dbobs_free(_dbObs);
            _dbObs = nil;
            _dbListenerTokens = nil;
        }
    }
}


- (void) postDatabaseChanged {
    CBL_LOCK(self) {
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
                    for (CBLChangeListenerToken* token in _dbListenerTokens) {
                        void (^listener)(CBLDatabaseChange*) = token.listener;
                        dispatch_async(token.queue, ^{
                            listener(change);
                        });
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
}


- (id<CBLListenerToken>) addDocumentChangeListenerWithDocumentID: documentID
                                                        listener: (void (^)(CBLDocumentChange*))listener
                                                           queue: (dispatch_queue_t)queue
{
    if (!_docListenerTokens)
        _docListenerTokens = [NSMutableDictionary dictionary];
    
    NSMutableSet* tokens = _docListenerTokens[documentID];
    if (!tokens) {
        tokens = [NSMutableSet set];
        [_docListenerTokens setObject: tokens forKey: documentID];
        
        CBLStringBytes bDocID(documentID);
        C4DocumentObserver* o =
        c4docobs_create(_c4db, bDocID, docObserverCallback, (__bridge void *)self);
        
        if (!_docObs)
            _docObs = [NSMutableDictionary dictionary];
        [_docObs setObject: [NSValue valueWithPointer: o] forKey: documentID];
    }
    
    id token = [[CBLDocumentChangeListenerToken alloc] initWithDocumentID: documentID
                                                                 listener: listener
                                                                    queue: queue];
    [tokens addObject: token];
    return token;
}


- (void) removeDocumentChangeListenerWithToken: (CBLDocumentChangeListenerToken*)token {
    CBL_LOCK(self) {
        NSString* documentID = token.documentID;
        NSMutableSet* listeners = _docListenerTokens[documentID];
        if (listeners) {
            [listeners removeObject: token];
            if (listeners.count == 0) {
                NSValue* obsValue = [_docObs objectForKey: documentID];
                if (obsValue) {
                    C4DocumentObserver* obs = (C4DocumentObserver*)obsValue.pointerValue;
                    c4docobs_free(obs);
                }
                [_docObs removeObjectForKey: documentID];
                [_docListenerTokens removeObjectForKey:documentID];
            }
        }
    }
}


- (void) postDocumentChanged: (NSString*)documentID {
    CBL_LOCK(self) {
        if (!_docObs[documentID] || !_c4db ||  c4db_isInTransaction(_c4db))
            return;
        
        CBLDocumentChange* change = [[CBLDocumentChange alloc] initWithDocumentID: documentID];
        NSSet* listeners = [_docListenerTokens objectForKey: documentID];
        for (CBLDocumentChangeListenerToken* token in listeners) {
            void (^listener)(CBLDocumentChange*) = token.listener;
            dispatch_async(token.queue, ^{
                listener(change);
            });
        }
    }
}


- (void) freeC4Observer {
    c4dbobs_free(_dbObs);
    _dbObs = nullptr;
    _dbListenerTokens = nil;
    
    for (NSValue* obsValue in _docObs.allValues) {
        C4DocumentObserver* obs = (C4DocumentObserver*)obsValue.pointerValue;
        c4docobs_free(obs);
    }
    
    _docObs = nil;
    _docListenerTokens = nil;
}


- (void) freeC4DB {
    c4db_free(_c4db);
    _c4db = nil;
}


#pragma mark - DOCUMENT SAVE AND CONFLICT RESOLUTION


// Lower-level save method. On conflict, returns YES but sets *outDoc to NULL.
- (BOOL) saveDocument: (CBLDocument*)document
                 into: (C4Document **)outDoc
             withBase: (nullable C4Document*)base
           asDeletion: (BOOL)deletion
                error: (NSError **)outError
{
    C4RevisionFlags revFlags = 0;
    if (deletion)
        revFlags = kRevDeleted;
    NSData* body = nil;
    C4Slice bodySlice = {};
    if (!deletion && !document.isEmpty) {
        // Encode properties to Fleece data:
        body = [document encode: outError];
        if (!body) {
            *outDoc = nullptr;
            return NO;
        }
        bodySlice = data2slice(body);
        auto root = FLValue_FromTrustedData(bodySlice);
        if (c4doc_dictContainsBlobs((FLDict)root, self.sharedKeys))
            revFlags |= kRevHasAttachments;
    }
    
    // Save to database:
    C4Error err;
    C4Document *c4Doc = base != nullptr ? base : document.c4Doc.rawDoc;
    if (c4Doc) {
        *outDoc = c4doc_update(c4Doc, bodySlice, revFlags, &err);
    } else {
        CBLStringBytes docID(document.id);
        *outDoc = c4doc_create(_c4db, docID, data2slice(body), revFlags, &err);
    }
    
    if (!*outDoc && !(err.domain == LiteCoreDomain && err.code == kC4ErrorConflict)) {
        // conflict is not an error, at this level
        return convertError(err, outError);
    }
    return YES;
}


// Main save document
- (CBLDocument*) saveDocument: (CBLDocument*)document
                   asDeletion: (BOOL)deletion
                        error: (NSError**)outError
{
    if (deletion && !document.exists) {
        createError(kCBLStatusNotFound, outError);
        return nil;
    }
    
    // Attempt to save. (On conflict, this will succeed but newDoc will be null.)
    NSString* docID = document.id;
    CBLDocument* doc = document, *baseDoc, *otherDoc;
    C4Document* baseRev = nil, *newDoc = nil;
    while (true) {
        CBL_LOCK(self) {
            if (![self prepareDocument: doc error: outError])
                return nil;
            
            // Begin a db transaction:
            C4Transaction transaction(_c4db);
            if (!transaction.begin()) {
                convertError(transaction.error(), outError);
                return nil;
            }
            
            if (![self saveDocument: doc into: &newDoc withBase: baseRev
                         asDeletion: deletion error: outError])
                return nil;
            
            if (newDoc) {
                // Save succeeded; now commit the transaction:
                if (!transaction.commit()) {
                    c4doc_free(newDoc);
                    convertError(transaction.error(), outError);
                    return nil;
                }
                
                auto newC4Doc = [CBLC4Document document: newDoc];
                return [[CBLDocument alloc] initWithDatabase: self
                                                  documentID: docID
                                                       c4Doc: newC4Doc];
            }
            
            // Save not succeeded as conflicting:
            if (deletion && !doc.isDeleted) {
                // Copy and mark as deleted:
                CBLMutableDocument* deletedDoc = [doc toMutable];
                [deletedDoc markAsDeleted];
                doc = deletedDoc;
            }
            
            if (doc.c4Doc)
                baseDoc = [[CBLDocument alloc] initWithDatabase: self
                                                     documentID: docID
                                                          c4Doc: doc.c4Doc];
            
            otherDoc = [[CBLDocument alloc] initWithDatabase: self
                                                  documentID: docID
                                              includeDeleted: YES
                                                       error: outError];
            if (!otherDoc)
                return nil;
            
            // Abort transaction:
            if (!transaction.abort()) {
                convertError(transaction.error(), outError);
                return nil;
            }
        }
        
        // Resolve conflict:
        id<CBLConflictResolver> resolver = self.config.conflictResolver;
        CBLConflict* conflict = [[CBLConflict alloc] initWithMine: doc
                                                           theirs: otherDoc
                                                             base: baseDoc];
        CBLDocument* resolved = [resolver resolve: conflict];
        if (!resolved) {
            convertError({LiteCoreDomain, kC4ErrorConflict}, outError);
            return nil;
        }
        
        CBL_LOCK(self) {
            CBLDocument* current = [[CBLDocument alloc] initWithDatabase: self
                                                              documentID: docID
                                                          includeDeleted: YES
                                                                   error: outError];
            if ($equal(resolved.revID, current.revID))
                return resolved; // Same as current
            
            // For saving:
            doc = resolved;
            baseRev = current.c4Doc.rawDoc;
            deletion = resolved.isDeleted;
        }
    }
}


#pragma mark - RESOLVING REPLICATED CONFLICTS:


- (bool) resolveConflictInDocument: (NSString*)docID
                     usingResolver: (id<CBLConflictResolver>)resolver
                             error: (NSError**)outError
{
    CBLDocument* doc, *otherDoc, *baseDoc;
    while (true) {
        CBL_LOCK(self) {
            // Open a transaction as a workaround to make sure that
            // the replicator commits the current changes before we
            // try to read the documents.
            // https://github.com/couchbase/couchbase-lite-core/issues/322
            C4Transaction t(_c4db);
            if (!t.begin())
                return convertError(t.error(), outError);
            
            doc = [[CBLDocument alloc] initWithDatabase: self
                                             documentID: docID
                                         includeDeleted: YES
                                                  error: outError];
            if (!doc)
                return false;
            
            // Read the conflicting remote revision:
            otherDoc = [[CBLDocument alloc] initWithDatabase: self
                                                  documentID: docID
                                              includeDeleted: YES
                                                       error: outError];
            if (!otherDoc || ![otherDoc selectConflictingRevision])
                return false;
            
            // Read the common ancestor revision (if it's available):
            baseDoc = [[CBLDocument alloc] initWithDatabase: self
                                                 documentID: docID
                                             includeDeleted: YES
                                                      error: outError];
            if (![baseDoc selectCommonAncestorOfDoc: doc andDoc: otherDoc] ||
                ![baseDoc toDictionary]) {
                baseDoc = nil;
            }
            
            if (!t.commit())
                return convertError(t.error(), outError);
        }
        
        // Call the conflict resolver:
        auto conflict = [[CBLConflict alloc] initWithMine: doc
                                                   theirs: otherDoc
                                                     base: baseDoc];
        CBLLog(Database, @"Resolving doc '%@' with %@ (mine=%@, theirs=%@, base=%@",
               docID, resolver.class, doc.revID, otherDoc.revID, baseDoc.revID);
        CBLDocument* resolved = [resolver resolve: conflict];
        if (!resolved)
            return convertError({LiteCoreDomain, kC4ErrorConflict}, outError);
        
        NSError* err;
        BOOL success = [self saveResolvedDocument: resolved
                                      forConflict: conflict
                                            error: &err];
        if ($equal(err.domain, @"LiteCore") && err.code == kC4ErrorConflict)
            continue;
        
        if (outError)
            *outError = err;
        
        return success;
    }
}


- (BOOL) saveResolvedDocument: (CBLDocument*)resolved
                  forConflict: (CBLConflict*)conflict
                        error: (NSError**)outError
{
    CBL_LOCK(self) {
        C4Transaction t(_c4db);
        if (!t.begin())
            return convertError(t.error(), outError);
        
        auto doc = conflict.mine;
        auto otherDoc = conflict.theirs;
        
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
               doc.id, (int)rawDoc->revID.size, rawDoc->revID.buf);
        
        return t.commit() || convertError(t.error(), outError);
    }
}

@end

