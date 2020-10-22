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
#import "CBLLog+Internal.h"
#import "CBLLog+Admin.h"
#import "CBLVersion.h"
#import "fleece/Fleece.hh"
#import "CBLConflict+Internal.h"
#import "CBLTimer.h"
#import "CBLErrorMessage.h"
#import "Foundation+CBL.h"

#ifdef COUCHBASE_ENTERPRISE
#import "CBLDatabase+EncryptionInternal.h"
#endif

using namespace fleece;

#define kDBExtension @"cblite2"

#define msec 1000.0

// How long to wait after a database opens before expiring docs
#define kHousekeepingDelayAfterOpening 3.0

@implementation CBLDatabase {
    NSString* _name;
    CBLDatabaseConfiguration* _config;
    
    C4DatabaseObserver* _dbObs;
    CBLChangeNotifier<CBLDatabaseChange*>* _dbChangeNotifier;
    NSMutableDictionary<NSString*,CBLDocumentChangeNotifier*>* _docChangeNotifiers;
    
    BOOL _shellMode;
    dispatch_source_t _docExpiryTimer;
    
    NSMutableSet<id<CBLStoppable>>* _activeStoppables;
    
    BOOL _isClosing;
    NSCondition* _closeCondition;
}

@synthesize name=_name;
@synthesize dispatchQueue=_dispatchQueue;
@synthesize queryQueue=_queryQueue;
@synthesize c4db=_c4db, sharedKeys=_sharedKeys;

static const C4DatabaseConfig2 kDBConfig = {
    .flags = (kC4DB_Create | kC4DB_AutoCompact | kC4DB_SharedKeys),
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
        // Initialize logging
        CBLAssertNotNil(CBLLog.sharedInstance);
        CBLLogInfo(Database, @"%@", [CBLVersion userAgent]);
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
        [[self class] checkFileLogging: NO];
        
        _name = name;
        _config = [[CBLDatabaseConfiguration alloc] initWithConfig: config readonly: YES];
        if (![self open: outError])
            return nil;
        
        NSString* qName = $sprintf(@"Database <%@>", name);
        _dispatchQueue = dispatch_queue_create(qName.UTF8String, DISPATCH_QUEUE_SERIAL);
        
        qName = $sprintf(@"Database-Query <%@>", name);
        _queryQueue = dispatch_queue_create(qName.UTF8String, DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

/**
 Initialize the CBLDatabase with a give C4Database object in the shell mode. The life of the
 C4Database object will be managed by the caller. This is currently used for creating a
 CBLDictionary as an input of the predict() method of the PredictiveModel.
 */
- (instancetype) initWithC4Database: (C4Database*)c4db {
    self = [super init];
    if (self) {
        _shellMode = YES;
        _c4db = c4db;
    }
    return self;
}

- (instancetype) copyWithZone: (NSZone*)zone {
    return [[[self class] alloc] initWithName: _name config: _config error: nil];
}

- (void) dealloc {
    if (!_shellMode) {
        [self freeC4Observer];
        [self freeC4DB];
    }
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

- (BOOL) saveDocument: (CBLMutableDocument*)document error:(NSError**)error {
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
             withBaseDocument: nil
           concurrencyControl: concurrencyControl
                   asDeletion: NO
                        error: error];
}

- (BOOL) saveDocument: (CBLMutableDocument*)document
      conflictHandler: (BOOL (^)(CBLMutableDocument*, CBLDocument* nullable))conflictHandler
                error: (NSError**)error
{
    CBLAssertNotNil(document);
    CBLAssertNotNil(conflictHandler);
    
    CBLDocument* oldDoc = nil;
    NSError* err;
    while (true) {
        BOOL success = [self saveDocument: document
                         withBaseDocument: oldDoc
                       concurrencyControl: kCBLConcurrencyControlFailOnConflict
                               asDeletion: NO
                                    error: &err];
        // if it's a conflict, we will use the conflictHandler to resolve.
        if (!success && $equal(err.domain, CBLErrorDomain) && err.code == CBLErrorConflict) {
            CBL_LOCK(self) {
                oldDoc = [[CBLDocument alloc] initWithDatabase: self
                                                    documentID: document.id
                                                includeDeleted: YES
                                                         error: error];
                if (!oldDoc)
                    return createError(CBLErrorNotFound, error);
            }
            
            @try {
                if (conflictHandler(document, oldDoc.isDeleted ? nil : oldDoc)) {
                    continue;
                } else {
                    return createError(CBLErrorConflict, error);
                }
            } @catch(NSException* ex) {
                CBLWarn(Database, @"Exception while resolving through save handler. Exception: %@",
                        ex.description);
                if (error)
                    *error = [NSError errorWithDomain: CBLErrorDomain
                                                 code: CBLErrorConflict
                                             userInfo: @{NSLocalizedDescriptionKey: ex.description}];
            }
            return NO;
        } else if (!success) { // any other error, we return false with errorInfo
            if (error)
                *error = err;
            
            return NO;
        }
        
        // save didn't cause any error
        return YES;
    }
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
             withBaseDocument: nil
           concurrencyControl: concurrencyControl
                   asDeletion: YES
                        error: error];
}

- (BOOL) purgeDocument: (CBLDocument*)document error: (NSError**)error {
    CBLAssertNotNil(document);
    
    CBL_LOCK(self) {
        if (![self prepareDocument: document error: error])
            return NO;
        
        if (!document.revisionID)
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

- (BOOL) inBatch: (NSError**)outError usingBlockWithError: (void (NS_NOESCAPE ^)(NSError**))block {
    CBLAssertNotNil(block);
    
    CBL_LOCK(self) {
        [self mustBeOpen];
        
        C4Transaction transaction(_c4db);
        if (outError)
            *outError = nil;
        
        if (!transaction.begin())
            return convertError(transaction.error(), outError);
        
        NSError* err = nil;
        block(&err);
        if (err) {
            // if swift throws an error, `err` will be populated
            transaction.abort();
            return createError(CBLErrorUnexpectedError,
                               [NSString stringWithFormat: @"%@", err.localizedDescription],
                               outError);
        }
        
        if (!transaction.commit())
            return convertError(transaction.error(), outError);
    }
    
    [self postDatabaseChanged];
    
    return YES;
}

- (BOOL) inBatch: (NSError**)outError usingBlock: (void (NS_NOESCAPE ^)())block {
    CBLAssertNotNil(block);
    
    return [self inBatch: outError usingBlockWithError: ^(NSError **) { block(); }];
}

#pragma mark - DATABASE MAINTENANCE

- (BOOL) close: (NSError**)outError {
    NSArray *activeStoppables = nil;
    
    CBL_LOCK(self) {
        if ([self isClosed])
            return YES;
        
        CBLLogInfo(Database, @"Closing %@ at path %@", self, self.path);
        
        if (!_isClosing) {
            _isClosing = YES;
            
            if (!_closeCondition)
                _closeCondition = [[NSCondition alloc] init];
            
            activeStoppables = [_activeStoppables allObjects];
        }
    }
    
    // Stop all active stoppable connections:
    for (id<CBLStoppable> instance in activeStoppables) {
        [instance stop];
    }
    
    // Wait for all active replicators and live queries to stop:
    [_closeCondition lock];
    while (![self isReadyToClose]) {
        [_closeCondition wait];
    }
    [_closeCondition unlock];
    
    CBL_LOCK(self) {
        if ([self isClosed])
            return YES;
        
        // Cancel doc expiry timer:
        [self cancelDocExpiryTimer];
        
        // Free C4Observer:
        [self freeC4Observer];
        
        // Close database:
        BOOL success = YES;
        C4Error err;
        if (!c4db_close(_c4db, &err))
            success = convertError(err, outError);
        
        // Release database:
        if (success)
            [self freeC4DB];
        
        // Reset closing flag:
        _isClosing = NO;
        
        return success;
    }
}

- (BOOL) isReadyToClose {
    CBL_LOCK(self) {
        return _activeStoppables.count == 0;
    }
}

- (BOOL) delete: (NSError**)outError {
    CBL_LOCK(self) {
        [self mustBeOpen];
    }
    
    if (![self close: outError])
        return false;
    
    return [self.class deleteDatabase: self.name
                          inDirectory: self.config.directory
                                error: outError];
}

- (BOOL) performMaintenance: (CBLMaintenanceType)type error: (NSError**)outError {
    CBL_LOCK(self) {
        [self mustBeOpen];
        
        C4Error err;
        if (!c4db_maintenance(_c4db, (C4MaintenanceType)type, &err))
            return convertError(err, outError);
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
    
    C4Error err;
    CBLStringBytes n(name);
    CBLStringBytes dir(directory ?: defaultDirectory());
    return c4db_deleteNamed(n, dir, &err) || err.code==0 || convertError(err, outError);
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
    
    C4Error err;
    slice fromPath(path.fileSystemRepresentation);
    CBLStringBytes destinationName(name);
    C4DatabaseConfig2 c4Config = c4DatabaseConfig2(config ?: [CBLDatabaseConfiguration new]);
    if (!(c4db_copyNamed(fromPath, destinationName, &c4Config, &err) || err.code==0 || convertError(err, outError))) {
        NSString* toPathStr = databasePath(name, dir);
        NSError* removeError;
        if (![[NSFileManager defaultManager] removeItemAtPath: toPathStr error: &removeError])
            CBLWarn(Database, @"Error when deleting the copied database dir: %@", removeError);
        return NO;
    }
    return YES;
}

#pragma mark - Logging

+ (void) setLogLevel: (CBLLogLevel)level domain: (CBLLogDomain)domain {
    CBLWarn(Database, @"This method has been deprecated. "
            "Please use CBLDatabase.log.console instead of -setLogLevel:domain:.");
    
    CBLDatabase.log.console.domains = kCBLLogDomainAll;
    CBLDatabase.log.console.level = level;
}

+ (CBLLog*) log {
    return [CBLLog sharedInstance];
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
    CBLAssertNotNil(token);
    
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
        
        FLSliceResult res = c4db_getIndexesInfo(_c4db, nullptr);
        FLDoc doc = FLDoc_FromResultData(res, kFLTrusted, nullptr, nullslice);
        FLSliceResult_Release(res);
        
        NSArray* indexes = FLValue_GetNSObject(FLDoc_GetRoot(doc), nullptr);
        FLDoc_Release(doc);
        
        // extract only names
        NSMutableArray* ins = [NSMutableArray arrayWithCapacity: indexes.count];
        for (NSDictionary* dict in indexes) {
            [ins addObject: dict[@"name"]];
        }
        
        return [NSArray arrayWithArray: ins];
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

- (BOOL) deleteIndexForName: (NSString*)name error: (NSError**)outError {
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
                          expiration: (nullable NSDate*)date
                               error: (NSError**)error
{
    CBLAssertNotNil(documentID);
    
    CBL_LOCK(self) {
        UInt64 timestamp = date ? (UInt64)(date.timeIntervalSince1970*msec) : 0;
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
        UInt64 timestamp = c4doc_getExpiration(_c4db, docID, nullptr);
        if (timestamp == 0) {
            return nil;
        }
        return [NSDate dateWithTimeIntervalSince1970: (timestamp/msec)];
    }
}

#pragma mark - INTERNAL

// Must be called inside self lock
- (void) mustBeOpen {
    if ([self isClosed])
        [NSException raise: NSInternalInconsistencyException
                    format: @"%@", kCBLErrorMessageDBClosed];
}

- (void) mustBeOpenLocked {
    CBL_LOCK(self) {
        [self mustBeOpen];
    }
}

// Must be called inside self lock
- (void) mustBeOpenAndNotClosing {
    if ([self isClosed] || _isClosing)
        [NSException raise: NSInternalInconsistencyException
                    format: @"%@", kCBLErrorMessageDBClosed];
}

// Must be called inside self lock
- (BOOL) isClosed {
    return _c4db == nullptr;
}

- (BOOL) isClosedLocked {
    CBL_LOCK(self) {
        return [self isClosed];
    }
}

- (C4SliceResult) getPublicUUID: (NSError**)outError {
    CBL_LOCK(self) {
        if (![self mustBeOpen: outError])
            return C4SliceResult{};
        
        C4Error err = {};
        C4UUID uuid;
        if (!c4db_getUUIDs(_c4db, &uuid, nullptr, &err)) {
            convertError(err, outError);
            return C4SliceResult{};
        }
        return FLSlice_Copy({&uuid, sizeof(uuid)});
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

#pragma mark Cookie save

- (NSString*) getCookies: (NSURL*)url {
    CBL_LOCK(self) {
        C4Error err = {};
        C4Address addr = {};
        [url c4Address: &addr];
        C4SliceResult cookies = c4db_getCookies(_c4db, addr, &err);
        if (err.code != 0)
            CBLWarn(WebSocket, @"Error while getting cookies %d/%d", err.domain, err.code);
        
        if (!cookies.buf) {
            CBLLogVerbose(WebSocket, @"No cookies");
            return nil;
        }
        
        return sliceResult2string(cookies);
    }
}

- (BOOL) saveCookie: (NSString*)cookie url: (NSURL*)url {
    CBL_LOCK(self) {
        C4Error err = {};
        CBLStringBytes header(cookie);
        CBLStringBytes host(url.host);
        CBLStringBytes path(url.path.stringByDeletingLastPathComponent);
        if (!c4db_setCookie(_c4db, header, host, path, &err)) {
            CBLWarnError(WebSocket, @"Cannot save cookie %d/%d", err.domain, err.code);
            return NO;
        }
        return YES;
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
    CBLLogInfo(Database, @"Opening %@ at path %@", self, path);
    
    C4DatabaseConfig2 c4config = c4DatabaseConfig2(_config);
    C4Error err;
    CBLStringBytes n(_name);
    _c4db = c4db_openNamed(n, &c4config, &err);
    if (!_c4db)
        return convertError(err, outError);
    
    _sharedKeys = c4db_getFLSharedKeys(_c4db);
    
    [self scheduleDocumentExpiration: kHousekeepingDelayAfterOpening];
    
    return YES;
}

static NSString* defaultDirectory() {
    return [CBLDatabaseConfiguration defaultDirectory];
}

static NSString* databasePath(NSString *name, NSString *dir) {
    name = [[name stringByReplacingOccurrencesOfString: @"/" withString: @":"]
            stringByAppendingPathExtension: kDBExtension];
    return [dir stringByAppendingPathComponent: name];
}

static BOOL setupDatabaseDirectory(NSString *dir, NSError **outError)
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

static C4DatabaseConfig2 c4DatabaseConfig2 (CBLDatabaseConfiguration *config) {
    C4DatabaseConfig2 c4config = kDBConfig;
#ifdef COUCHBASE_ENTERPRISE
    if (config.encryptionKey)
        c4config.encryptionKey = [CBLDatabase c4EncryptionKey: config.encryptionKey];
#endif
    CBLStringBytes dir(config.directory);
    c4config.parentDirectory = dir;
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
                           kCBLErrorMessageDocumentAnotherDatabase, error);
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
        if (!_dbObs || !_c4db)
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
    c4db_release(_c4db);
    _c4db = nil;
}

#pragma mark - DOCUMENT SAVE AND CONFLICT HANDLING

- (BOOL) saveDocument: (CBLDocument*)document
     withBaseDocument: (nullable CBLDocument*)baseDoc
   concurrencyControl: (CBLConcurrencyControl)concurrencyControl
           asDeletion: (BOOL)deletion
                error: (NSError**)outError
{
    if (deletion && !document.revisionID)
        return createError(CBLErrorNotFound,
                           kCBLErrorMessageDeleteDocFailedNotSaved, outError);
    
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
            
            if (![self saveDocument: document into: &newDoc withBaseDocument: baseDoc.c4Doc.rawDoc
                         asDeletion: deletion error: outError])
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
            c4doc_release(curDoc);
            c4doc_release(newDoc);
        }
    }
}

// Lower-level save method. On conflict, returns YES but sets *outDoc to NULL.
- (BOOL) saveDocument: (CBLDocument*)document
                 into: (C4Document**)outDoc
     withBaseDocument: (nullable C4Document*)base
           asDeletion: (BOOL)deletion
                error: (NSError**)outError
{
    C4RevisionFlags revFlags = 0;
    if (deletion)
        revFlags = kRevDeleted;
    FLSliceResult body;
    if (!deletion && !document.isEmpty) {
        // Encode properties to Fleece data:
        body = [document encode: outError];
        if (!body.buf) {
            *outDoc = nullptr;
            return NO;
        }
        FLDoc doc = FLDoc_FromResultData(body, kFLTrusted, self.sharedKeys,
                                         nullslice);
        if (c4doc_dictContainsBlobs((FLDict)FLDoc_GetRoot(doc)))
            revFlags |= kRevHasAttachments;
        
        FLDoc_Release(doc);
    } else {
        body = [self emptyFLSliceResult];
    }
    
    // Save to database:
    C4Error err;
    C4Document *c4Doc = base != nullptr ? base : document.c4Doc.rawDoc;
    if (c4Doc) {
        *outDoc = c4doc_update(c4Doc, (FLSlice)body, revFlags, &err);
    } else {
        CBLStringBytes docID(document.id);
        *outDoc = c4doc_create(_c4db, docID, (FLSlice)body, revFlags, &err);
    }

    FLSliceResult_Release(body);
    
    if (!*outDoc && !(err.domain == LiteCoreDomain && err.code == kC4ErrorConflict)) {
        // conflict is not an error, at this level
        return convertError(err, outError);
    }
    return YES;
}

#pragma mark - Stoppable

- (void) addActiveStoppable: (id<CBLStoppable>)stoppable {
    CBL_LOCK(self) {
        [self mustBeOpenAndNotClosing];
        
        if (!_activeStoppables)
            _activeStoppables = [NSMutableSet new];
        
        [_activeStoppables addObject: stoppable];
    }
}

- (void) removeActiveStoppable: (id<CBLStoppable>)stoppable {
    CBL_LOCK(self) {
        [_activeStoppables removeObject: stoppable];
        
        if (_activeStoppables.count == 0)
            [_closeCondition broadcast];
    }
}

- (uint64_t) activeStoppableCount {
    CBL_LOCK(self) {
        return _activeStoppables.count;
    }
}

#pragma mark - RESOLVING REPLICATED CONFLICTS:

- (bool) resolveConflictInDocument: (NSString*)docID
              withConflictResolver: (id<CBLConflictResolver>)conflictResolver
                             error: (NSError**)outError {
    while (true) {
        CBLDocument* localDoc;
        CBLDocument* remoteDoc;
        
        // Get latest local and remote document revisions from DB
        CBL_LOCK(self) {
            // Read local document:
            localDoc = [[CBLDocument alloc] initWithDatabase: self documentID: docID
                                              includeDeleted: YES error: outError];
            if (!localDoc) {
                CBLWarn(Sync, @"Unable to find the document %@ during conflict resolution,\
                        skipping...", docID);
                return NO;
            }
            
            // Read the conflicting remote revision:
            remoteDoc = [[CBLDocument alloc] initWithDatabase: self documentID: docID
                                               includeDeleted: YES error: outError];
            if (!remoteDoc || ![remoteDoc selectConflictingRevision]) {
                CBLWarn(Sync, @"Unable to select conflicting revision for %@, the conflict may "
                        "have been resolved...", docID);
                // this means no conflict, so returning success
                return YES;
            }
        }
        
        conflictResolver = conflictResolver ?: [CBLConflictResolver default];
        
        // Resolve conflict:
        CBLDocument* resolvedDoc;
        @try {
            CBLLogInfo(Sync, @"Resolving doc '%@' (localDoc=%@ and remoteDoc=%@)",
                       docID, localDoc.revisionID, remoteDoc.revisionID);
            
            if (localDoc.isDeleted && remoteDoc.isDeleted) {
                resolvedDoc = remoteDoc;
            } else {
                CBLConflict* conflict = [[CBLConflict alloc] initWithID: docID
                                                          localDocument: localDoc.isDeleted ? nil : localDoc
                                                         remoteDocument: remoteDoc.isDeleted ? nil : remoteDoc];
                
                resolvedDoc = [conflictResolver resolve: conflict];
            }
            
            if (resolvedDoc && resolvedDoc.id != docID) {
                CBLWarn(Sync, @"The document ID of the resolved document '%@' is not matching "
                        "with the document ID of the conflicting document '%@'.",
                        resolvedDoc.id, docID);
            }
            
            if (resolvedDoc && resolvedDoc.database && resolvedDoc.database != self) {
                [NSException raise: NSInternalInconsistencyException
                            format: kCBLErrorMessageResolvedDocWrongDb,
                 resolvedDoc.database.name, self.name];
            }
        } @catch (NSException *ex) {
            CBLWarn(Sync, @"Exception in conflict resolver: %@", ex.description);
            *outError = [NSError errorWithDomain: CBLErrorDomain
                                            code: CBLErrorConflict
                                        userInfo: @{NSLocalizedDescriptionKey: ex.description}];
            return NO;
        }
        
        NSError* err;
        BOOL success = [self saveResolvedDocument: resolvedDoc withLocalDoc: localDoc
                                        remoteDoc: remoteDoc error: &err];
        
        if ($equal(err.domain, CBLErrorDomain) && err.code == CBLErrorConflict)
            continue;
        
        if (outError)
            *outError = err;
        
        return success;
    }
}

- (BOOL) saveResolvedDocument: (CBLDocument*)resolvedDoc
                 withLocalDoc: (CBLDocument*)localDoc
                    remoteDoc: (CBLDocument*)remoteDoc
                        error: (NSError**)outError
{
    CBL_LOCK(self) {
        C4Transaction t(_c4db);
        if (!t.begin())
            return convertError(t.error(), outError);
        
        if (!resolvedDoc) {
            if (localDoc.isDeleted)
                resolvedDoc = localDoc;
            
            if (remoteDoc.isDeleted)
                resolvedDoc = remoteDoc;
        }
        
        if (resolvedDoc != localDoc)
            resolvedDoc.database = self;
        
        // The remote branch has to win, so that the doc revision history matches the server's.
        CBLStringBytes winningRevID = remoteDoc.revisionID;
        CBLStringBytes losingRevID = localDoc.revisionID;
        
        alloc_slice mergedBody;
        C4RevisionFlags mergedFlags = 0;
        if (resolvedDoc != remoteDoc) {
            BOOL isDeleted = YES;
            if (resolvedDoc) {
                mergedFlags = resolvedDoc.c4Doc != nil ? resolvedDoc.c4Doc.revFlags : 0;
                
                // Unless the remote revision is being used as-is, we need a new revision:
                NSError* err = nil;
                mergedBody = [resolvedDoc encode: &err];
                if (err) {
                    createError(CBLErrorUnexpectedError, err.localizedDescription, outError);
                    return false;
                }
                
                if (!mergedBody) {
                    createError(CBLErrorUnexpectedError, kCBLErrorMessageResolvedDocContainsNull, outError);
                    return false;
                }
                isDeleted = resolvedDoc.isDeleted;
            } else
                mergedBody = [self emptyFLSliceResult];
            
            if (isDeleted)
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
        CBLLogInfo(Sync, @"Conflict resolved as doc '%@' rev %.*s",
                   localDoc.id, (int)rawDoc->revID.size, rawDoc->revID.buf);
        
        return t.commit() || convertError(t.error(), outError);
    }
}

- (FLSliceResult) emptyFLSliceResult {
    FLEncoder enc = c4db_getSharedFleeceEncoder(_c4db);
    FLEncoder_BeginDict(enc, 0);
    FLEncoder_EndDict(enc);
    auto result = FLEncoder_Finish(enc, nullptr);
    FLEncoder_Reset(enc);
    return result;
}

# pragma mark DOCUMENT EXPIRATION

- (void) scheduleDocumentExpiration: (NSTimeInterval)minimumDelay {
    [self cancelDocExpiryTimer];
    
    UInt64 nextExpiration = c4db_nextDocExpiration(_c4db);
    if (nextExpiration > 0) {
        NSDate* expDate = [NSDate dateWithTimeIntervalSince1970: (nextExpiration/msec)];
        NSTimeInterval delay = MAX(expDate.timeIntervalSinceNow, minimumDelay);
        CBLLogInfo(Database, @"Scheduling next doc expiration in %.3g sec", delay);
        _docExpiryTimer = [CBLTimer scheduleIn: _dispatchQueue after: delay block: ^{
            CBL_LOCK(self) {
                if ([self isClosed])
                    return;
                
                CBLLogInfo(Database, @"Purging expired documents...");
                C4Error c4err;
                UInt64 nPurged = c4db_purgeExpiredDocs(_c4db, &c4err);
                CBLLogInfo(Database, @"Purged %lld expired documents", nPurged);
                [self scheduleDocumentExpiration: 1.0];
            }
        }];
    } else {
        CBLLogInfo(Database, @"No pending doc expirations");
    }
}

- (void) cancelDocExpiryTimer {
    [CBLTimer cancel: _docExpiryTimer];
    _docExpiryTimer = nil;
}

/** Check and show warning if file logging is not configured. */
+ (void) checkFileLogging: (BOOL)swift {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (!CBLDatabase.log.file.config) {
            NSString* clazz = swift ? @"Database" : @"CBLDatabase";
            CBLWarn(Database, @"%@.log.file.config is nil, meaning file logging is disabled. "
                    "Log files required for product support are not being generated.", clazz);
        }
    });
}

@end
