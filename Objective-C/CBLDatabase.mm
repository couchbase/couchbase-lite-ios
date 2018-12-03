//
//  CBLDatabase.m
//  CouchbaseLite
//
//  Copyright (c) 2016 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLDatabase.h"
#import "c4BlobStore.h"
#import "c4Observer.h"
#import "CBLCoreBridge.h"
#import "CBLDatabase+Internal.h"
#import "CBLDocument+Internal.h"
#import "CBLDocumentChangeNotifier.h"
#import "CBLChangeListenerToken.h"
#import "CBLDocumentFragment.h"
#import "CBLIndex+Internal.h"
#import "CBLQuery+Internal.h"
#import "CBLMisc.h"
#import "CBLStringBytes.h"
#import "CBLStatus.h"
#import "CBLLog+Admin.h"
#import "CBLVersion.h"
#import "fleece/Fleece.hh"

#ifdef COUCHBASE_ENTERPRISE
#import "CBLDatabase+EncryptionInternal.h"
#endif

using namespace fleece;

#define kDBExtension @"cblite2"

// How long to wait after a database opens before expiring docs
#define kHousekeepingDelayAfterOpening 3.0

@implementation CBLDatabase {
    NSString* _name;
    CBLDatabaseConfiguration* _config;
    
    C4DatabaseObserver* _dbObs;
    CBLChangeNotifier<CBLDatabaseChange*>* _dbChangeNotifier;
    NSMutableDictionary<NSString*,CBLDocumentChangeNotifier*>* _docChangeNotifiers;
}


@synthesize name=_name;
@synthesize dispatchQueue=_dispatchQueue;
@synthesize queryQueue=_queryQueue;
@synthesize c4db=_c4db, sharedKeys=_sharedKeys;
@synthesize replications=_replications, activeReplications=_activeReplications;
@synthesize liveQueries= _liveQueries;


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


+ (void) initialize {
    if (self == [CBLDatabase class]) {
        NSLog(@"%@", [CBLVersion userAgent]);
        CBLLog_Init();
    }
}


- (instancetype) initWithName: (NSString*)name
                        error: (NSError**)outError {
    return [self initWithName: name config: nil error: outError];
}


- (instancetype) initWithName: (NSString*)name
                       config: (nullable CBLDatabaseConfiguration*)config
                        error: (NSError**)outError {
    CBLAssertNotNil(name);
    
    self = [super init];
    if (self) {
        _name = name;
        _config = [[CBLDatabaseConfiguration alloc] initWithConfig: config readonly: YES];
        if (![self open: outError])
            return nil;
        
        NSString* qName = $sprintf(@"Database <%@>", name);
        _dispatchQueue = dispatch_queue_create(qName.UTF8String, DISPATCH_QUEUE_SERIAL);
        
        qName = $sprintf(@"Database-Query <%@>", name);
        _queryQueue = dispatch_queue_create(qName.UTF8String, DISPATCH_QUEUE_SERIAL);
        
        _replications = [NSMapTable strongToWeakObjectsMapTable];
        _activeReplications = [NSMutableSet new];
        _liveQueries = [NSMutableSet new];
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
    return _config;
}


#pragma mark - GET EXISTING DOCUMENT


- (CBLDocument*) documentWithID: (NSString*)documentID {
    return [self documentWithID: documentID error: nil];
}


#pragma mark - SUBSCRIPTION


- (CBLDocumentFragment*) objectForKeyedSubscript: (NSString*)documentID {
    return [[CBLDocumentFragment alloc] initWithDocument: [self documentWithID: documentID]];
}


#pragma mark - SAVE


- (BOOL) saveDocument: (CBLMutableDocument *)document error:(NSError **)error {
    return [self saveDocument: document
           concurrencyControl: kCBLConcurrencyControlLastWriteWins
                        error: error];
}


- (BOOL) saveDocument: (CBLMutableDocument*)document
   concurrencyControl: (CBLConcurrencyControl)concurrencyControl
                error: (NSError**)error
{
    CBLAssertNotNil(document);
    
    return [self saveDocument: document
           concurrencyControl: concurrencyControl
                   asDeletion: NO
                        error: error];
}


- (BOOL) deleteDocument: (CBLDocument*)document error: (NSError**)error {
    return [self deleteDocument: document
             concurrencyControl: kCBLConcurrencyControlLastWriteWins
                          error: error];
}


- (BOOL) deleteDocument: (CBLDocument*)document
     concurrencyControl: (CBLConcurrencyControl)concurrencyControl
                  error: (NSError**)error
{
    CBLAssertNotNil(document);
    
    return [self saveDocument: document
           concurrencyControl: concurrencyControl
                   asDeletion: YES
                        error: error];
}


- (BOOL) purgeDocument: (CBLDocument*)document error: (NSError**)error {
    CBLAssertNotNil(document);
    
    CBL_LOCK(self) {
        if (![self prepareDocument: document error: error])
            return NO;
        
        if (!document.revID)
            return createError(CBLErrorNotFound,
                               @"Document doesn't exist in the database.", error);
        
        if ([self purgeDocumentWithID:document.id error:error]) {
            [document replaceC4Doc: nil];
            return TRUE;
        }
        
        return NO;
    }
}


- (BOOL) purgeDocumentWithID: (NSString*)documentID error: (NSError**)error {
    CBLAssertNotNil(documentID);
    
    CBL_LOCK(self) {
        [self mustBeOpen];
        
        C4Transaction transaction(_c4db);
        if (!transaction.begin())
            return convertError(transaction.error(),  error);
        
        C4Error err;
        CBLStringBytes docID(documentID);
        if (c4db_purgeDoc(_c4db, docID, &err)) {
            if (!transaction.commit()) {
                return convertError(transaction.error(), error);
            }
            return YES;
        }
        return convertError(err, error);
    }
}


#pragma mark - BATCH OPERATION


- (BOOL) inBatch: (NSError**)outError usingBlock: (void (NS_NOESCAPE ^)())block {
    CBLAssertNotNil(block);
    
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
    
        if (_activeReplications.count > 0) {
            NSString* err = @"Cannot close the database. "
                "Please stop all of the replicators before closing the database.";
            return createError(CBLErrorBusy, err, outError);
        }
        
        if (_liveQueries.count > 0) {
            NSString* err = @"Cannot close the database. "
                "Please remove all of the query listeners before closing the database.";
            return createError(CBLErrorBusy, err, outError);
        }
        
        [self cancelPreviousPerformRequestsForPurgingExpiredDocuments];
    
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
        
        if (_activeReplications.count > 0) {
            NSString* err = @"Cannot delete the database. "
                "Please stop all of the replicators before deleting the database.";
            return createError(CBLErrorBusy, err, outError);
        }
        
        if (_liveQueries.count > 0) {
            NSString* err = @"Cannot delete the database. "
                "Please remove all of the query listeners before deleting the database.";
            return createError(CBLErrorBusy, err, outError);
        }
        
        [self cancelPreviousPerformRequestsForPurgingExpiredDocuments];
        
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


+ (BOOL) deleteDatabase: (NSString*)name
            inDirectory: (nullable NSString*)directory
                  error: (NSError**)outError
{
    CBLAssertNotNil(name);
    
    NSString* path = databasePath(name, directory ?: defaultDirectory());
    slice bPath(path.fileSystemRepresentation);
    C4Error err;
    return c4db_deleteAtPath(bPath, &err) || err.code==0 || convertError(err, outError);
}


+ (BOOL) databaseExists: (NSString*)name
            inDirectory: (nullable NSString*)directory
{
    CBLAssertNotNil(name);
    
    NSString* path = databasePath(name, directory ?: defaultDirectory());
    return [[NSFileManager defaultManager] fileExistsAtPath: path];
}


+ (BOOL) copyFromPath: (NSString*)path
           toDatabase: (NSString*)name
           withConfig: (nullable CBLDatabaseConfiguration*)config
                error: (NSError**)outError
{
    CBLAssertNotNil(path);
    CBLAssertNotNil(name);
    
    NSString* dir = config.directory ?: defaultDirectory();
    if (!setupDatabaseDirectory(dir, outError))
        return NO;
    
    NSString* toPathStr = databasePath(name, dir);
    slice toPath(toPathStr.fileSystemRepresentation);
    slice fromPath(path.fileSystemRepresentation);
    
    C4Error err;
    C4DatabaseConfig c4Config = c4DatabaseConfig(config ?: [CBLDatabaseConfiguration new]);
    if (!(c4db_copy(fromPath, toPath, &c4Config, &err) || err.code==0 || convertError(err, outError))) {
        NSError* removeError;
        if (![[NSFileManager defaultManager] removeItemAtPath: toPathStr error: &removeError])
            CBLWarn(Database, @"Error when deleting the copied database dir: %@", removeError);
        return NO;
    }
    return YES;
}


#pragma mark - Logging


+ (void) setLogLevel: (CBLLogLevel)level domain: (CBLLogDomain)domain {
    CBLLog_SetLevel(domain, level);
}


#pragma mark - DOCUMENT CHANGES


- (id<CBLListenerToken>) addChangeListener: (void (^)(CBLDatabaseChange*))listener {
    return [self addChangeListenerWithQueue: nil listener: listener];
}


- (id<CBLListenerToken>) addChangeListenerWithQueue: (nullable dispatch_queue_t)queue
                                           listener: (void (^)(CBLDatabaseChange*))listener
{
    CBLAssertNotNil(listener);
    
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
    CBLAssertNotNil(id);
    CBLAssertNotNil(listener);
    
    CBL_LOCK(self) {
        [self mustBeOpen];
        
        return [self addDocumentChangeListenerWithDocumentID: id listener: listener queue: queue];
    }
}


- (void) removeChangeListenerWithToken: (id<CBLListenerToken>)token {
    CBL_LOCK(self) {
        [self mustBeOpen];
        
        if (((CBLChangeListenerToken*)token).key)
            [self removeDocumentChangeListenerWithToken: token];
        else
            [self removeDatabaseChangeListenerWithToken: token];
    }
}


#pragma mark - Index:


- (NSArray<NSString*>*) indexes {
    CBL_LOCK(self) {
        [self mustBeOpen];
        
        Doc doc(c4db_getIndexes(_c4db, nullptr));
        return FLValue_GetNSObject(doc.root(), nullptr);
    }
}


- (BOOL) createIndex: (CBLIndex*)index withName: (NSString*)name error: (NSError**)outError {
    CBLAssertNotNil(index);
    CBLAssertNotNil(name);
    
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
    CBLAssertNotNil(name);
    
    CBL_LOCK(self) {
        [self mustBeOpen];
        
        CBLStringBytes bName(name);
        C4Error c4err;
        return c4db_deleteIndex(_c4db, bName, &c4err) || convertError(c4err, outError);
    }
}


#pragma mark - DOCUMENT EXPIRATION


- (BOOL) setDocumentExpirationWithID: (NSString*)documentID
                                date: (nullable NSDate*)date
                               error: (NSError**)error
{
    CBLAssertNotNil(documentID);
    
    CBL_LOCK(self) {
        UInt64 timestamp = date ? (UInt64)date.timeIntervalSince1970 : 0;
        
        C4Error err;
        CBLStringBytes docID(documentID);
        if (c4doc_setExpiration(_c4db, docID, timestamp, &err)) {
            [self scheduleDocumentExpiration: 0.0];
            return TRUE;
        }
        return convertError(err, error);
    }
}


- (nullable NSDate*) getDocumentExpirationWithID: (NSString*)documentID {
    CBLAssertNotNil(documentID);
    
    CBL_LOCK(self) {
        CBLStringBytes docID(documentID);
        UInt64 timestamp = c4doc_getExpiration(_c4db, docID);
        if (timestamp == 0) {
            return nil;
        }
        return [NSDate dateWithTimeIntervalSince1970: timestamp];
    }
}


#pragma mark - INTERNAL


- (void) mustBeOpen {
    if (_c4db == nullptr) {
        [NSException raise: NSInternalInconsistencyException
                    format: @"Attempt to perform an operation on a closed database."];
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
    if (!setupDatabaseDirectory(dir, outError))
        return NO;

    if (_name.length == 0)
        return createError(CBLErrorInvalidParameter, outError);
    NSString* path = databasePath(_name, dir);
    slice bPath(path.fileSystemRepresentation);

    C4DatabaseConfig c4config = c4DatabaseConfig(_config);
    CBLLog(Database, @"Opening %@ at path %@", self, path);
    C4Error err;
    _c4db = c4db_open(bPath, &c4config, &err);
    if (!_c4db)
        return convertError(err, outError);
    
    _sharedKeys = c4db_getFLSharedKeys(_c4db);
    
    [self scheduleDocumentExpiration: kHousekeepingDelayAfterOpening];
    
    return YES;
}


static NSString* defaultDirectory() {
    return [CBLDatabaseConfiguration defaultDirectory];
}


static NSString* databasePath(NSString* name, NSString* dir) {
    name = [[name stringByReplacingOccurrencesOfString: @"/" withString: @":"]
            stringByAppendingPathExtension: kDBExtension];
    return [dir stringByAppendingPathComponent: name];
}


static BOOL setupDatabaseDirectory(NSString* dir, NSError** outError)
{
    NSError* error;
    if (![[NSFileManager defaultManager] createDirectoryAtPath: dir
                                   withIntermediateDirectories: YES
                                                    attributes: nil
                                                         error: &error]) {
        if (!CBLIsFileExistsError(error)) {
            if (outError) *outError = error;
            return NO;
        }
    }
    return YES;
}


static C4DatabaseConfig c4DatabaseConfig (CBLDatabaseConfiguration* config) {
    C4DatabaseConfig c4config = kDBConfig;
#ifdef COUCHBASE_ENTERPRISE
    if (config.encryptionKey)
        c4config.encryptionKey = [CBLDatabase c4EncryptionKey: config.encryptionKey];
#endif
    return c4config;
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
        return createError(CBLErrorInvalidParameter,
                           @"Cannot operate on a document from another database", error);
    }
    return YES;
}


- (id<CBLListenerToken>) addDatabaseChangeListener: (void (^)(CBLDatabaseChange*))listener
                                             queue: (dispatch_queue_t)queue
{
    if (!_dbChangeNotifier) {
        _dbChangeNotifier = [CBLChangeNotifier new];
        _dbObs = c4dbobs_create(_c4db, dbObserverCallback, (__bridge void *)self);
    }
    
    return [_dbChangeNotifier addChangeListenerWithQueue: queue listener: listener];
}


- (void) removeDatabaseChangeListenerWithToken: (id<CBLListenerToken>)token {
    CBL_LOCK(self) {
        if ([_dbChangeNotifier removeChangeListenerWithToken: token] == 0) {
            c4dbobs_free(_dbObs);
            _dbObs = nil;
            _dbChangeNotifier = nil;
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
                    [_dbChangeNotifier postChange:
                        [[CBLDatabaseChange alloc] initWithDatabase: self
                                                        documentIDs: docIDs
                                                         isExternal: external] ];
                    docIDs = [NSMutableArray new];
                }
            }
            
            external = newExternal;
            for(uint32_t i = 0; i < nChanges; i++) {
                NSString *docID =slice2string(changes[i].docID);
                [docIDs addObject: docID];
            }
            c4dbobs_releaseChanges(changes, nChanges);
        } while(nChanges > 0);
    }
}


- (id<CBLListenerToken>) addDocumentChangeListenerWithDocumentID: documentID
                                                        listener: (void (^)(CBLDocumentChange*))listener
                                                           queue: (dispatch_queue_t)queue
{
    if (!_docChangeNotifiers)
        _docChangeNotifiers = [NSMutableDictionary dictionary];
    
    CBLDocumentChangeNotifier* docNotifier = _docChangeNotifiers[documentID];
    if (!docNotifier) {
        docNotifier = [[CBLDocumentChangeNotifier alloc] initWithDatabase: self
                                                               documentID: documentID];
        _docChangeNotifiers[documentID] = docNotifier;
    }
    
    CBLChangeListenerToken* token = [docNotifier addChangeListenerWithQueue: queue
                                                                   listener: listener];
    token.key = documentID;
    return token;
}


- (void) removeDocumentChangeListenerWithToken: (CBLChangeListenerToken*)token {
    CBL_LOCK(self) {
        NSString* documentID = token.key;
        CBLDocumentChangeNotifier* notifier = _docChangeNotifiers[documentID];
        if (notifier && [notifier removeChangeListenerWithToken: token] == 0) {
            [notifier stop];
            [_docChangeNotifiers removeObjectForKey:documentID];
        }
    }
}


- (void) freeC4Observer {
    c4dbobs_free(_dbObs);
    _dbObs = nullptr;
    _dbChangeNotifier = nil;

    [_docChangeNotifiers.allValues makeObjectsPerformSelector: @selector(stop)];
    _docChangeNotifiers = nil;
}


- (void) freeC4DB {
    c4db_free(_c4db);
    _c4db = nil;
}


#pragma mark - DOCUMENT SAVE AND CONFLICT HANDLING


- (BOOL) saveDocument: (CBLDocument*)document
   concurrencyControl: (CBLConcurrencyControl)concurrencyControl
           asDeletion: (BOOL)deletion
                error: (NSError**)outError
{
    if (deletion && !document.revID)
        return createError(CBLErrorNotFound,
                           @"Cannot delete a document that has not yet been saved", outError);
    
    CBL_LOCK(self) {
        if (![self prepareDocument: document error: outError])
            return NO;
        
        C4Document* curDoc = nil;
        C4Document* newDoc = nil;
        @try {
            // Begin a db transaction:
            C4Transaction transaction(_c4db);
            if (!transaction.begin())
                return convertError(transaction.error(), outError);
            
            if (![self saveDocument: document into: &newDoc
                   withBaseDocument: nil asDeletion: deletion error: outError])
                return NO;
            
            if (!newDoc) {
                // Handle conflict:
                if (concurrencyControl == kCBLConcurrencyControlFailOnConflict)
                    return createError(CBLErrorConflict, outError);
                
                C4Error err;
                CBLStringBytes bDocID(document.id);
                curDoc = c4doc_get(_c4db, bDocID, true, &err);
                
                // If deletion and the current doc has already been deleted
                // or doesn't exist:
                if (deletion) {
                    if (!curDoc) {
                        if (err.code == kC4ErrorNotFound)
                            return YES;
                        return convertError(err, outError);
                    } else if ((curDoc->flags & kDocDeleted) != 0) {
                        [document replaceC4Doc: [CBLC4Document document: curDoc]];
                        curDoc = nil;
                        return YES;
                    }
                }
                
                // Save changes on the current branch:
                if (!curDoc)
                    return convertError(err, outError);
                
                if (![self saveDocument: document into: &newDoc
                       withBaseDocument: curDoc asDeletion: deletion error: outError])
                    return NO;
            }
            
            if (!transaction.commit())
                return convertError(transaction.error(), outError);
            
            [document replaceC4Doc: [CBLC4Document document: newDoc]];
            newDoc = nil;
            return YES;
        }
        @finally {
            c4doc_free(curDoc);
            c4doc_free(newDoc);
        }
    }
}


// Lower-level save method. On conflict, returns YES but sets *outDoc to NULL.
- (BOOL) saveDocument: (CBLDocument*)document
                 into: (C4Document **)outDoc
     withBaseDocument: (nullable C4Document*)base
           asDeletion: (BOOL)deletion
                error: (NSError **)outError
{
    C4RevisionFlags revFlags = 0;
    if (deletion)
        revFlags = kRevDeleted;
    alloc_slice body;
    if (!deletion && !document.isEmpty) {
        // Encode properties to Fleece data:
        body = [document encode: outError];
        if (!body) {
            *outDoc = nullptr;
            return NO;
        }
        Doc doc(body, kFLTrusted, self.sharedKeys);
        if (c4doc_dictContainsBlobs(doc))
            revFlags |= kRevHasAttachments;
    }
    
    // Save to database:
    C4Error err;
    C4Document *c4Doc = base != nullptr ? base : document.c4Doc.rawDoc;
    if (c4Doc) {
        *outDoc = c4doc_update(c4Doc, body, revFlags, &err);
    } else {
        CBLStringBytes docID(document.id);
        *outDoc = c4doc_create(_c4db, docID, body, revFlags, &err);
    }
    
    if (!*outDoc && !(err.domain == LiteCoreDomain && err.code == kC4ErrorConflict)) {
        // conflict is not an error, at this level
        return convertError(err, outError);
    }
    return YES;
}


#pragma mark - RESOLVING REPLICATED CONFLICTS:


- (bool) resolveConflictInDocument: (NSString*)docID error: (NSError**)outError {
    CBL_LOCK(self) {
        C4Transaction t(_c4db);
        if (!t.begin())
            return convertError(t.error(), outError);
        
        // Read local document:
        CBLDocument* localDoc = [[CBLDocument alloc] initWithDatabase: self
                                                           documentID: docID
                                                       includeDeleted: YES
                                                                error: outError];
        if (!localDoc)
            return false;
        
        // Read the conflicting remote revision:
        CBLDocument* remoteDoc = [[CBLDocument alloc] initWithDatabase: self
                                                            documentID: docID
                                                        includeDeleted: YES
                                                                 error: outError];
        if (!remoteDoc || ![remoteDoc selectConflictingRevision])
            return false;
        
        // Resolve conflict:
        CBLLog(Sync, @"Resolving doc '%@' (mine=%@ and theirs=%@)",
               docID, localDoc.revID, remoteDoc.revID);
        
        CBLDocument* resolvedDoc = [self resolveConflictBetweenLocalDoc: localDoc
                                                           andRemoteDoc: remoteDoc];
        
        // Save resolved document:
        if (![self saveResolvedDocument: resolvedDoc
                           withLocalDoc: localDoc
                              remoteDoc: remoteDoc
                                  error: outError])
            return false;
        
        return t.commit() || convertError(t.error(), outError);
    }
}


- (CBLDocument*) resolveConflictBetweenLocalDoc: (CBLDocument*)localDoc
                                   andRemoteDoc: (CBLDocument*)remoteDoc {
    if (remoteDoc.isDeleted)
        return remoteDoc;
    else if (localDoc.isDeleted)
        return localDoc;
    else if (localDoc.generation > remoteDoc.generation)
        return localDoc;
    else if (localDoc.generation < remoteDoc.generation)
        return remoteDoc;
    else if ([localDoc.revID compare: remoteDoc.revID] > 0)
        return localDoc;
    else
        return remoteDoc;
}


- (BOOL) saveResolvedDocument: (CBLDocument*)resolvedDoc
                 withLocalDoc: (CBLDocument*)localDoc
                    remoteDoc: (CBLDocument*)remoteDoc
                        error: (NSError**)outError
{
    if (resolvedDoc != localDoc)
        resolvedDoc.database = self;
    
    // The remote branch has to win, so that the doc revision history matches the server's.
    CBLStringBytes winningRevID = remoteDoc.revID;
    CBLStringBytes losingRevID = localDoc.revID;
    
    alloc_slice mergedBody;
    C4RevisionFlags mergedFlags = 0;
    if (resolvedDoc != remoteDoc) {
        // Unless the remote revision is being used as-is, we need a new revision:
        mergedBody = [resolvedDoc encode: outError];
        if (!mergedBody)
            return false;
        if (resolvedDoc.isDeleted)
            mergedFlags |= kRevDeleted;
    }
    
    // Tell LiteCore to do the resolution:
    C4Document *rawDoc = localDoc.c4Doc.rawDoc;
    C4Error c4err;
    if (!c4doc_resolveConflict(rawDoc,
                               winningRevID,
                               losingRevID,
                               mergedBody,
                               mergedFlags,
                               &c4err)
        || !c4doc_save(rawDoc, 0, &c4err)) {
        return convertError(c4err, outError);
    }
    CBLLog(Sync, @"Conflict resolved as doc '%@' rev %.*s",
           localDoc.id, (int)rawDoc->revID.size, rawDoc->revID.buf);
    return YES;
}


# pragma mark DOCUMENT EXPIRATION


- (void) scheduleDocumentExpiration: (NSTimeInterval)minimumDelay {
    [self cancelPreviousPerformRequestsForPurgingExpiredDocuments];
    
    UInt64 nextExpiration = c4db_nextDocExpiration(_c4db);
    if (nextExpiration > 0) {
        NSDate* expDate = [NSDate dateWithTimeIntervalSince1970: nextExpiration];
        NSTimeInterval delay = MAX(expDate.timeIntervalSinceNow, minimumDelay);
        CBLLog(Database, @"Scheduling next doc expiration in %.3g sec", delay);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self performSelector: @selector(purgeExpiredDocuments)
                       withObject: nil
                       afterDelay: delay];
        });
    } else {
        CBLLog(Database, @"No pending doc expirations");
    }
}


- (void) purgeExpiredDocuments {
    dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        CBLLog(Database, @"Purging expired documents...");
        C4Error err;
        NSUInteger nPurged = c4db_purgeExpiredDocs(_c4db, &err);
        CBLLog(Database, @"Purged %lu expired documents", (unsigned long)nPurged);
        [self scheduleDocumentExpiration: 0.0];
    });
}


- (void) cancelPreviousPerformRequestsForPurgingExpiredDocuments {
    __weak CBLDatabase *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        CBLDatabase *strongSelf = weakSelf;
        if (strongSelf) {
            [NSObject cancelPreviousPerformRequestsWithTarget: strongSelf
                                                     selector: @selector(purgeExpiredDocuments)
                                                       object: nil];
        }
    });
}

@end
