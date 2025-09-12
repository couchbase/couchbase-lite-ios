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

#import "CBLChangeListenerToken.h"
#import "CBLCollection+Internal.h"
#import "CBLCoreBridge.h"
#import "CBLData.h"
#import "CBLDatabase.h"
#import "CBLDatabase+Internal.h"
#import "CBLDocumentChangeNotifier.h"
#import "CBLDocumentFragment.h"
#import "CBLDocument+Internal.h"
#import "CBLErrorMessage.h"
#import "CBLIndexConfiguration+Internal.h"
#import "CBLIndexSpec.h"
#import "CBLIndex+Internal.h"
#import "CBLLogSinks+Internal.h"
#import "CBLMisc.h"
#import "CBLPrecondition.h"
#import "CBLQuery+Internal.h"
#import "CBLQuery+N1QL.h"
#import "CBLScope+Internal.h"
#import "CBLStatus.h"
#import "CBLStringBytes.h"
#import "CBLVersion.h"
#import "Foundation+CBL.h"
#import "c4BlobStore.h"
#import "c4Observer.h"
#import "fleece/Fleece.hh"

#ifdef COUCHBASE_ENTERPRISE
#import "CBLDatabase+EncryptionInternal.h"
#endif

using namespace fleece;
using namespace cbl;

#define kDBExtension @"cblite2"

#ifdef COUCHBASE_ENTERPRISE
#define kVectorSearchExtIdentifier @"com.couchbase.vectorSearchExtension"
#endif

static NSString* kBlobTypeProperty = @kC4ObjectTypeProperty;
static NSString* kBlobDigestProperty = @kC4BlobDigestProperty;
static NSString* kBlobDataProperty = @kC4BlobDataProperty;
static NSString* kBlobLengthProperty = @"length";
static NSString* kBlobContentTypeProperty = @"content_type";

// This variable defines the state of database
typedef enum {
    kCBLDatabaseStateClosed = 0,
    kCBLDatabaseStateClosing,
    kCBLDatabaseStateOpened,
} CBLDatabaseState;

@implementation CBLDatabase {
    NSString* _name;
    CBLDatabaseConfiguration* _config;
    
    BOOL _shellMode;
    dispatch_source_t _docExpiryTimer;
    
    NSMutableSet<id<CBLDatabaseService>>* _activeServices;
    
    NSCondition* _closeCondition;
    
    CBLDatabaseState _state;
    
    CBLCollection* _defaultCollection;
    
    // this object will be retained and used to lock from outside classes.
    id _mutex;
}

@synthesize name=_name;
@synthesize dispatchQueue=_dispatchQueue;
@synthesize queryQueue=_queryQueue;
@synthesize c4db=_c4db, sharedKeys=_sharedKeys;

static const C4DatabaseConfig2 kDBConfig = {
    .flags = (kC4DB_Create | kC4DB_AutoCompact | kC4DB_VersionVectors),
};

/** 
 Static Initializer called when CBL library is loaded.
 @note: App may not configure its logging yet when this initialize() method is called. So if possible, any operations that may log are better
 to be done in CBLInit()which is called only once when the first CBLDatabase is created
 */
+ (void) initialize {
    if (self == [CBLDatabase class]) {
        NSLog(@"%@", [CBLVersion userAgent]);
        // Initialize logging
        CBLAssertNotNil(CBLLogSinks.self);
    }
}

/** Called when the first CBLDatabase object is created. */
+ (void) CBLInit {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [self checkFileLogging];
    });
}

/** Check and show warning if file logging is not configured. */
+ (void) checkFileLogging {
    if (!CBLLogSinks.file) {
        CBLWarn(Database, @"File logging is disabled. Log files required for product support are not being generated.");
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
        // Perform only once when the first CBLDatabase object is created:
        [[self class] CBLInit];
        
        _name = name;
        _config = [[CBLDatabaseConfiguration alloc] initWithConfig: config readonly: YES];
        if (![self open: outError])
            return nil;
        
        NSString* qName = $sprintf(@"Database <%p: %@>", self, self);
        _dispatchQueue = dispatch_queue_create(qName.UTF8String, DISPATCH_QUEUE_SERIAL);
        
        qName = $sprintf(@"Database::Query <%p: %@>", self, self);
        _queryQueue = dispatch_queue_create(qName.UTF8String, DISPATCH_QUEUE_SERIAL);
        
        _state = kCBLDatabaseStateOpened;
        
        _mutex = [NSObject new];
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
        
        _state = kCBLDatabaseStateOpened;
    }
    return self;
}

- (instancetype) copyWithZone: (NSZone*)zone {
    return [[[self class] alloc] initWithName: _name config: _config error: nil];
}

- (void) dealloc {
    if (!_shellMode) {
        CBL_LOCK(_mutex) {
            [self freeC4DB];
        }
    }
}

- (NSString*) description {
    return [NSString stringWithFormat: @"%@@%p[name=%@]", self.class, self, _name];
}

- (NSString*) path {
    CBL_LOCK(_mutex) {
        return _c4db != nullptr ? sliceResult2FilesystemPath(c4db_getPath(_c4db)) : nil;
    }
}

- (CBLDatabaseConfiguration*) config {
    return _config;
}

#pragma mark - Blob Save/Get

- (BOOL) saveBlob: (CBLBlob*)blob error: (NSError**)error {
    return [blob installInDatabase: self error: error];
}

- (CBLBlob*) getBlob: (NSDictionary*)properties {
    if (![CBLBlob isBlob: properties])
        [NSException raise: NSInvalidArgumentException
                    format: @"%@", kCBLErrorMessageInvalidBlob];
    C4BlobKey expectedKey;
    CBLStringBytes key(properties[kCBLBlobDigestProperty]);
    if (!c4blob_keyFromString(key, &expectedKey))
        return nil;
    
    C4Error err;
    C4BlobStore* store = c4db_getBlobStore(_c4db, &err);
    
    int64_t size = c4blob_getSize(store, expectedKey);
    if (size == -1)
        return nil;
    
    if (properties[kCBLBlobLengthProperty]) {
        NSInteger num = asNumber(properties[kCBLBlobLengthProperty]).unsignedLongLongValue;
        Assert(num == size, @"Given length property and retrieved blob length mismatch");
    } else {
        // if length property is missing, will include it
        NSMutableDictionary* dict = [properties mutableCopy];
        dict[kCBLBlobLengthProperty] = @(size);
        properties = [dict copy];
    }
    
    return [[CBLBlob alloc] initWithDatabase: self properties: properties];
}

#pragma mark - BATCH OPERATION

- (BOOL) inBatch: (NSError**)outError usingBlockWithError: (void (NS_NOESCAPE ^)(NSError**))block {
    [CBLPrecondition assertNotNil: block name: @"block"];
    
    CBL_LOCK(_mutex) {
        if (![self mustBeOpen: outError])
            return false;
        
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
    
    return YES;
}

- (BOOL) inBatch: (NSError**)outError usingBlock: (void (NS_NOESCAPE ^)())block {
    [CBLPrecondition assertNotNil: block name: @"block"];
    
    return [self inBatch: outError usingBlockWithError: ^(NSError **) { block(); }];
}

- (BOOL) maybeBatch: (NSError**)outError usingBlockWithError: (BOOL (NS_NOESCAPE ^)(NSError**))block {
    [CBLPrecondition assertNotNil: block name: @"block"];
    
    CBL_LOCK(_mutex) {
        if (![self mustBeOpen: outError])
            return false;
        
        C4Transaction transaction(_c4db);
        if (outError)
            *outError = nil;
        
        if (!transaction.begin())
            return convertError(transaction.error(), outError);
        
        NSError* err = nil;
        BOOL result = block(&err);
        if (err) {
            // if swift throws an error, `err` will be populated
            transaction.abort();
            return createError(CBLErrorUnexpectedError,
                               [NSString stringWithFormat: @"%@", err.localizedDescription],
                               outError);
        }
        if (!result) {
            // If the closure returns false, abort transaction
            transaction.abort();
            return false;
        }
        
        if (!transaction.commit())
            return convertError(transaction.error(), outError);
    }
    
    return YES;
}

#pragma mark - DATABASE MAINTENANCE

- (BOOL) close: (NSError**)outError {
    NSArray* activeServices = nil;
    
    CBL_LOCK(_mutex) {
        if ([self isClosed]) {
            return YES;
        }
        
        if (_state == kCBLDatabaseStateClosing) {
            CBLLogInfo(Database, @"%@: Database at path %@ is already closing, ignoring request",
                       self, self.path);
            return NO;
        }
        
        CBLLogInfo(Database, @"%@: Closing database at path %@", self, self.path);
        
        if (!_closeCondition) {
            _closeCondition = [[NSCondition alloc] init];
        }
        
        activeServices = [_activeServices allObjects];
    }
    
    // Stop services outside of lock to avoid deadlocks:
    for (id<CBLDatabaseService> service in activeServices) {
        [service stop];
    }
    
    // Wait until all services report they’re done:
    [_closeCondition lock];
    while (![self isReadyToClose]) {
        [_closeCondition wait];
    }
    [_closeCondition unlock];
    
    CBL_LOCK(_mutex) {
        // Close database:
        C4Error err;
        if (!c4db_close(_c4db, &err)) {
            NSError* error = nil;
            convertError(err, &error);
            if (outError) {
                *outError = error;
            }
            
            CBLWarnError(Database, @"%@: Failed to close database at path %@, error %@",
                         self, self.path, error);
            
            // Reset state:
            _state = kCBLDatabaseStateOpened;
            return NO;
        }
          
        // Success, free and set closed state
        [self freeC4DB];
        return YES;
    }
}

- (BOOL) isReadyToClose {
    CBL_LOCK(_mutex) {
        return _activeServices.count == 0;
    }
}

- (BOOL) delete: (NSError**)outError {
    CBL_LOCK(_mutex) {
        if (![self mustBeOpen: outError]) {
            return NO;
        }
    }
    
    if (![self close: outError]) {
        return NO;
    }
    
    return [self.class deleteDatabase: self.name
                          inDirectory: self.config.directory
                                error: outError];
}

- (BOOL) performMaintenance: (CBLMaintenanceType)type error: (NSError**)outError {
    CBL_LOCK(_mutex) {
        if (![self mustBeOpen: outError]) {
            return NO;
        }
        
        C4Error err;
        if (!c4db_maintenance(_c4db, (C4MaintenanceType)type, &err)) {
            return convertError(err, outError);
        }
        
        return YES;
    }
}

+ (BOOL) deleteDatabase: (NSString*)name
            inDirectory: (nullable NSString*)directory
                  error: (NSError**)outError {
    [CBLPrecondition assertNotNil: name name: @"name"];
    
    C4Error err;
    CBLStringBytes n(name);
    CBLStringBytes dir(directory ?: defaultDirectory());
    return c4db_deleteNamed(n, dir, &err) || err.code==0 || convertError(err, outError);
}

+ (BOOL) databaseExists: (NSString*)name
            inDirectory: (nullable NSString*)directory
{
    [CBLPrecondition assertNotNil: name name: @"name"];
    
    NSString* path = databasePath(name, directory ?: defaultDirectory());
    return [[NSFileManager defaultManager] fileExistsAtPath: path];
}

+ (BOOL) copyFromPath: (NSString*)path
           toDatabase: (NSString*)name
           withConfig: (nullable CBLDatabaseConfiguration*)config
                error: (NSError**)outError
{
    [CBLPrecondition assertNotNil: path name: @"path"];
    [CBLPrecondition assertNotNil: name name: @"name"];
    
    NSString* dir = config.directory ?: defaultDirectory();
    if (!setupDatabaseDirectory(dir, outError))
        return NO;
    
    C4Error err;
    slice fromPath(path.fileSystemRepresentation);
    CBLStringBytes destinationName(name);
    C4DatabaseConfig2 c4Config = c4DatabaseConfig2(config ?: [CBLDatabaseConfiguration new]);
    CBLStringBytes d(config != nil ? config.directory : CBLDatabaseConfiguration.defaultDirectory);
    c4Config.parentDirectory = d;
    
    if (!(c4db_copyNamed(fromPath, destinationName, &c4Config, &err) || err.code==0 || convertError(err, outError))) {
        NSString* toPathStr = databasePath(name, dir);
        NSError* removeError;
        if (![[NSFileManager defaultManager] removeItemAtPath: toPathStr error: &removeError])
            CBLWarn(Database, @"Error when deleting the copied database dir: %@", removeError);
        return NO;
    }
    return YES;
}

#pragma mark - Query

- (nullable CBLQuery*) createQuery: (NSString*)query error: (NSError**)error {
    return [[CBLQuery alloc] initWithDatabase: self expressions: query error: error];
}

#pragma mark - Scope

- (nullable CBLScope*) defaultScope: (NSError**)error {
    CBL_LOCK(_mutex) {
        if (![self mustBeOpen: error])
            return nil;
        
        return [[CBLScope alloc] initWithDB: self name: kCBLDefaultScopeName cached: NO];
    }
}

- (nullable NSArray*) scopes: (NSError**)error {
    CBL_LOCK(_mutex) {
        if (![self mustBeOpen: error])
            return nil;
        
        C4Error c4err = {};
        FLMutableArray list = c4db_scopeNames(_c4db, &c4err);
        if (c4err.code != 0) {
            CBLWarn(Database, @"%@ Failed to get scope names (%d/%d)",
                    self, c4err.domain, c4err.code);
            convertError(c4err, error);
            FLArray_Release(list);
            return nil;
        }
        
        NSUInteger count = FLArray_Count(list);
        NSMutableArray* scopes = [NSMutableArray arrayWithCapacity: count];
        for (uint i = 0; i < count; i++) {
            NSString* name = FLValue_GetNSObject(FLArray_Get(list, i), nullptr);
            
            NSError* err = nil;
            CBLScope* s = [self scopeWithName: name error: &err];
            if (!s) {
                CBLWarn(Database, @"%@ Failed to get scope: %@ error: %@", self, name, err);
                if (error)
                    *error = err;
                FLArray_Release(list);
                return nil;
            }
            
            [scopes addObject: s];
        }
        FLArray_Release(list);
        
        return [NSArray arrayWithArray: scopes];
    }
}

- (nullable CBLScope*) scopeWithName: (NSString*)name error: (NSError**)error {
    NSString* scopeName = name ?: kCBLDefaultScopeName;
    
    CBL_LOCK(_mutex) {
        if (![self mustBeOpen: error])
            return nil;
        
        CBLStringBytes sname(scopeName);
        BOOL exists = c4db_hasScope(_c4db, sname);
        if (!exists) {
            return nil;
        }
        
        return [[CBLScope alloc] initWithDB: self name: scopeName cached: NO];
    }
}

#pragma mark - Collections

- (nullable CBLCollection*) defaultCollection: (NSError**)error {
    CBL_LOCK(_mutex) {
        if (![self mustBeOpen: error])
            return nil;
        
        if (!_defaultCollection) {
            C4Error c4error {};
            C4Collection* c4col = c4db_getDefaultCollection(_c4db, &c4error);
            if (!c4col) {
                if (c4error.code != 0) {
                    CBLWarn(Database, @"%@ : Error getting the default collection: %d/%d",
                            self, c4error.domain, c4error.code);
                    convertError(c4error, error);
                }
                return nil;
            }
            _defaultCollection = [[CBLCollection alloc] initWithDB: self c4collection: c4col cached: YES];
        }
        return _defaultCollection;
    }
}

- (nullable  NSArray*) collections: (nullable NSString*)scope error: (NSError**)error {
    NSString * scopeName = scope ?: kCBLDefaultScopeName;
    CBLStringBytes sName(scopeName);
    CBL_LOCK(_mutex) {
        if (![self mustBeOpen: error])
            return nil;
        
        C4Error c4err = {};
        FLMutableArray list = c4db_collectionNames(_c4db, sName, &c4err);
        if (c4err.code != 0) {
            CBLWarn(Database, @"%@ Failed to get collection names: %@ (%d/%d)",
                    self, scopeName, c4err.domain, c4err.code);
            convertError(c4err, error);
            FLArray_Release(list);
            return nil;
        }
        
        // TODO: check direct convertion of list to NSArray or each item to NSString is faster?
        NSUInteger count = FLArray_Count(list);
        NSMutableArray* collections = [NSMutableArray arrayWithCapacity: count];
        for (uint i = 0; i < count; i++) {
            NSString* name = FLValue_GetNSObject(FLArray_Get(list, i), nullptr);
            
            NSError* err = nil;
            CBLCollection* c = [self collectionWithName: name scope: scopeName error: &err];
            if (!c) {
                CBLWarn(Database, @"%@ Failed to get collection: %@.%@ error: %@",
                        self, scopeName, name, err);
                if (error)
                    *error = err;
                FLArray_Release(list);
                return nil;
            }
            
            [collections addObject: c];
        }
        FLArray_Release(list);
        
        return [NSArray arrayWithArray: collections];
    }
}

- (nullable CBLCollection*) createCollectionWithName: (NSString*)name
                                               scope: (nullable NSString*)scopeName
                                               error: (NSError**)error {
    scopeName = scopeName ?: kCBLDefaultScopeName;
    CBLStringBytes cName(name);
    CBLStringBytes sName(scopeName);
    C4CollectionSpec spec = { .name = cName, .scope = sName };
    
    C4Collection* c4collection;
    CBL_LOCK(_mutex) {
        if (![self mustBeOpen: error])
            return nil;
        
        C4Error c4err = {};
        c4collection = c4db_createCollection(_c4db, spec, &c4err);
        if (!c4collection) {
            CBLWarn(Database, @"%@ Failed to create collection: %@.%@ (%d/%d)",
                    self, scopeName, name, c4err.domain, c4err.code);
            convertError(c4err, error);
            return nil;
        }
        CBLLogVerbose(Database, @"%@: Created collection %@.%@ (c4col=%p)", self, scopeName, name, c4collection);
        return [[CBLCollection alloc] initWithDB: self c4collection: c4collection cached: NO];
    }
}

- (nullable CBLCollection*) collectionWithName: (NSString*)name
                                         scope: (nullable NSString*)scope
                                         error: (NSError**)error {
    NSString* scopeName = scope ?: kCBLDefaultScopeName;
    CBLStringBytes cName(name);
    CBLStringBytes sName(scopeName);
    C4CollectionSpec spec = { .name = cName, .scope = sName };
    
    CBL_LOCK(_mutex) {
        if (![self mustBeOpen: error])
            return nil;
        
        C4Error c4err = {};
        C4Collection* c4col = c4db_getCollection(_c4db, spec, &c4err);
        if (!c4col) {
            if (!(c4err.code == kC4ErrorNotFound && c4err.domain == LiteCoreDomain)) {
                CBLWarn(Database, @"%@: Failed to get collection %@.%@ (%d/%d)",
                        self, scopeName, name, c4err.domain, c4err.code);
                convertError(c4err, error);
            }
            return nil;
        }
        return [[CBLCollection alloc] initWithDB: self c4collection: c4col cached: NO];
    }
}

- (BOOL) deleteCollectionWithName: (NSString*)name
                            scope: (nullable NSString*)scope
                            error: (NSError**)error {
    NSString* scopeName = scope ?: kCBLDefaultScopeName;
    CBLStringBytes cName(name);
    CBLStringBytes sName(scopeName);
    C4CollectionSpec spec = { .name = cName, .scope = sName };
    CBL_LOCK(_mutex) {
        if (![self mustBeOpen: error])
            return NO;
        
        CBLLogVerbose(Database, @"%@: Deleting collection %@.%@", self, scopeName, name);
        C4Error c4err = {};
        return c4db_deleteCollection(_c4db, spec, &c4err) || convertError(c4err, error);
    }
}

#pragma mark - INTERNAL

// Must be called inside self lock
- (void) mustBeOpen {
    if ([self isClosed])
        [NSException raise: NSInternalInconsistencyException
                    format: @"%@", kCBLErrorMessageDBClosedOrCollectionDeleted];
}

- (BOOL) mustBeOpen: (NSError**)outError {
    return ![self isClosed] || convertError({LiteCoreDomain, kC4ErrorNotOpen}, outError);
}

- (void) mustBeOpenLocked {
    CBL_LOCK(_mutex) {
        [self mustBeOpen];
    }
}

// Must be called inside self lock
- (void) mustBeOpenAndNotClosing {
    if (_state < kCBLDatabaseStateOpened)
        [NSException raise: NSInternalInconsistencyException
                    format: @"%@", kCBLErrorMessageDBClosedOrCollectionDeleted];
}

// Must be called inside self lock
- (BOOL) isClosed {
    if (_state == kCBLDatabaseStateClosed) {
        Assert(_c4db == nullptr);
        return YES;
    } else {
        Assert(_c4db != nullptr);
        return NO;
    }
}

- (BOOL) isClosedLocked {
    CBL_LOCK(_mutex) {
        return [self isClosed];
    }
}

- (C4SliceResult) getPublicUUID: (NSError**)outError {
    CBL_LOCK(_mutex) {
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
    CBL_LOCK(_mutex) {
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

- (NSString*) getCookies: (NSURL*)url error: (NSError**)error {
    CBL_LOCK(_mutex) {
        if (![self mustBeOpen: error])
            return nil;
        
        C4Error err = {};
        CBLStringBytes schemeSlice(url.scheme);
        CBLStringBytes hostSlice(url.host);
        CBLStringBytes pathSlice(url.path.stringByDeletingLastPathComponent);
        C4Address addr = {
            .scheme = schemeSlice,
            .hostname = hostSlice,
            .port = url.port.unsignedShortValue,
            .path = pathSlice,
        };
        
        C4SliceResult cookies = c4db_getCookies(_c4db, addr, &err);
        if (err.code != 0) {
            CBLWarn(WebSocket, @"Error while getting cookies %d/%d", err.domain, err.code);
            convertError(err, error);
            return nil;
        }
        
        if (!cookies.buf) {
            CBLLogVerbose(WebSocket, @"No cookies");
            return nil;
        }
        
        return sliceResult2string(cookies);
    }
}

- (BOOL) saveCookie: (NSString*)cookie
                url: (NSURL*)url
 acceptParentDomain: (BOOL)acceptParentDomain
              error: (NSError**)error {
    CBL_LOCK(_mutex) {
        C4Error err = {};
        CBLStringBytes header(cookie);
        CBLStringBytes host(url.host);
        CBLStringBytes path(url.path.stringByDeletingLastPathComponent);
        if (!c4db_setCookie(_c4db, header, host, path, acceptParentDomain, &err)) {
            CBLWarnError(WebSocket, @"Cannot save cookie %d/%d", err.domain, err.code);
            convertError(err, error);
            return NO;
        }
        return YES;
    }
}

- (id) mutex {
    return _mutex;
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
    CBLLogInfo(Database, @"%@: Opening database at path %@", self, path);
    
    C4DatabaseConfig2 c4config = c4DatabaseConfig2(_config);
    CBLStringBytes d(_config.directory);
    c4config.parentDirectory = d;
    
    C4Error err;
    CBLStringBytes n(_name);
    _c4db = c4db_openNamed(n, &c4config, &err);
    if (!_c4db)
        return convertError(err, outError);
    
    CBLLogVerbose(Database, @"%@: Openned database (c4db=%p) successfully at path %@", self, _c4db, path);
    
    _sharedKeys = c4db_getFLSharedKeys(_c4db);
        
    _state = kCBLDatabaseStateOpened;
    
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

    if (config.fullSync)
        c4config.flags |= kC4DB_DiskSyncFull;
    if (!config.mmapEnabled)
        c4config.flags |= kC4DB_MmapDisabled;
    
#ifdef COUCHBASE_ENTERPRISE
    if (config.encryptionKey)
        c4config.encryptionKey = [CBLDatabase c4EncryptionKey: config.encryptionKey];
#endif
    return c4config;
}

- (void) freeC4DB {
    if (!_c4db) {
        return;
    }
    
    c4db_release(_c4db);
    _c4db = nil;
    
    _defaultCollection = nil;
    _state = kCBLDatabaseStateClosed;
}

- (void) safeBlock:(void (^)())block {
    CBL_LOCK(_mutex) {
        block();
    }
}

#pragma mark - Database Services

- (void) registerActiveService: (id<CBLDatabaseService>)service {
    CBL_LOCK(_mutex) {
        [self mustBeOpenAndNotClosing];
        
        if (!_activeServices)
            _activeServices = [NSMutableSet new];
        
        [_activeServices addObject: service];
    }
}

- (void) unregisterActiveService: (id<CBLDatabaseService>)service {
    CBL_LOCK(_mutex) {
        [_activeServices removeObject: service];
        if (_activeServices.count == 0) {
            [_closeCondition lock];
            [_closeCondition broadcast];
            [_closeCondition unlock];
        }
    }
}

- (uint64_t) activeServiceCount {
    CBL_LOCK(_mutex) {
        return _activeServices.count;
    }
}

#pragma mark - Private for test

- (const C4DatabaseConfig2*) getC4DBConfig {
    return c4db_getConfig2(_c4db);
}

@end
