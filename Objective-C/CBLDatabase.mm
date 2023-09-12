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
#import "CBLLog+Admin.h"
#import "CBLLog+Internal.h"
#import "CBLMisc.h"
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

static NSString* kBlobTypeProperty = @kC4ObjectTypeProperty;
static NSString* kBlobDigestProperty = @kC4BlobDigestProperty;
static NSString* kBlobDataProperty = @kC4BlobDataProperty;
static NSString* kBlobLengthProperty = @"length";
static NSString* kBlobContentTypeProperty = @"content_type";

// this variable defines the state of database
typedef enum {
    kCBLDatabaseStateClosed = 0,
    kCBLDatabaseStateClosing,
    kCBLDatabaseStateOpened,
} CBLDatabaseState;

@implementation CBLDatabase {
    NSString* _name;
    CBLDatabaseConfiguration* _config;
    
    C4DatabaseObserver* _dbObs;

// TODO: Remove https://issues.couchbase.com/browse/CBL-3206
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CBLChangeNotifier<CBLDatabaseChange*>* _dbChangeNotifier;
#pragma clang diagnostic pop

    NSMutableDictionary<NSString*,CBLDocumentChangeNotifier*>* _docChangeNotifiers;
    
    BOOL _shellMode;
    dispatch_source_t _docExpiryTimer;
    
    NSMutableSet<id<CBLStoppable>>* _activeStoppables;
    
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
    .flags = (kC4DB_Create | kC4DB_AutoCompact),
};

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
        
        NSString* qName = $sprintf(@"Database <%@: %@>", self, name);
        _dispatchQueue = dispatch_queue_create(qName.UTF8String, DISPATCH_QUEUE_SERIAL);
        
        qName = $sprintf(@"Database-Query <%@: %@>", self, name);
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
        [self freeC4Observer];
        [self freeC4DB];
    }
}

- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%@]", self.class, _name];
}

- (NSString*) fullDescription {
    return [NSString stringWithFormat: @"%p %@[%@] c4db=%p", self, self.class, _name, _c4db];
}

- (NSString*) path {
    CBL_LOCK(_mutex) {
        return _c4db != nullptr ? sliceResult2FilesystemPath(c4db_getPath(_c4db)) : nil;
    }
}

- (uint64_t) count {
    return [self defaultCollection: nil].count;
}

- (CBLDatabaseConfiguration*) config {
    return _config;
}

#pragma mark - GET EXISTING DOCUMENT

- (nullable CBLDocument*) documentWithID: (NSString*)documentID {
    return [self withDefaultCollectionForObjectAndError: nil block: ^id(CBLCollection* collection, NSError** err) {
        return [[self defaultCollectionOrThrow] documentWithID: documentID error: err];
    }];
}

#pragma mark - SUBSCRIPTION

- (CBLDocumentFragment*) objectForKeyedSubscript: (NSString*)documentID {
    id result = [self withDefaultCollectionForObjectAndError: nil block: ^id(CBLCollection* collection, NSError** err) {
        return [collection objectForKeyedSubscript: documentID];
    }];
    assert(result != nil);
    return result;
}

#pragma mark - SAVE

- (BOOL) saveDocument: (CBLMutableDocument*)document error:(NSError**)error {
    return [self saveDocument: document
           concurrencyControl: kCBLConcurrencyControlLastWriteWins
                        error: error];
}

- (BOOL) saveDocument: (CBLMutableDocument*)document
   concurrencyControl: (CBLConcurrencyControl)concurrencyControl
                error: (NSError**)error {
    return [self withDefaultCollectionAndError: error block: ^BOOL(CBLCollection* collection, NSError** err) {
        return [collection saveDocument: document concurrencyControl: concurrencyControl error: err];
    }];
}

- (BOOL) saveDocument: (CBLMutableDocument*)document
      conflictHandler: (BOOL (^)(CBLMutableDocument*, CBLDocument* nullable))conflictHandler
                error: (NSError**)error {
    return [self withDefaultCollectionAndError: error block: ^BOOL(CBLCollection* collection, NSError** err) {
        return [collection saveDocument: document conflictHandler: conflictHandler error: err];
    }];
}

- (BOOL) deleteDocument: (CBLDocument*)document error: (NSError**)error {
    return [self deleteDocument: document
             concurrencyControl: kCBLConcurrencyControlLastWriteWins
                          error: error];
}

- (BOOL) deleteDocument: (CBLDocument*)document
     concurrencyControl: (CBLConcurrencyControl)concurrencyControl
                  error: (NSError**)error {
    return [self withDefaultCollectionAndError: error block: ^BOOL(CBLCollection* collection, NSError** err) {
        return [collection deleteDocument: document concurrencyControl: concurrencyControl error: err];
    }];
}

- (BOOL) purgeDocument: (CBLDocument*)document error: (NSError**)error {
    return [self withDefaultCollectionAndError: error block: ^BOOL(CBLCollection* collection, NSError** err) {
        return [collection purgeDocument: document error: err];
    }];
}

- (BOOL) purgeDocumentWithID: (NSString*)documentID error: (NSError**)error {
    return [self withDefaultCollectionAndError: error block: ^BOOL(CBLCollection* collection, NSError** err) {
        return [collection purgeDocumentWithID: documentID error: err];
    }];
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
    CBLAssertNotNil(block);
    
    CBL_LOCK(_mutex) {
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
    
    CBL_LOCK(_mutex) {
        if ([self isClosed])
            return YES;
        
        CBLLogInfo(Database, @"Closing %@ at path %@", self, self.path);
        
        if (_state != kCBLDatabaseStateClosing) {
            _state = kCBLDatabaseStateClosing;
            
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
    
    CBL_LOCK(_mutex) {
        if ([self isClosed])
            return YES;
        
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
        
        return success;
    }
}

- (BOOL) isReadyToClose {
    CBL_LOCK(_mutex) {
        return _activeStoppables.count == 0;
    }
}

- (BOOL) delete: (NSError**)outError {
    CBL_LOCK(_mutex) {
        [self mustBeOpen];
    }
    
    if (![self close: outError])
        return false;
    
    return [self.class deleteDatabase: self.name
                          inDirectory: self.config.directory
                                error: outError];
}

- (BOOL) performMaintenance: (CBLMaintenanceType)type error: (NSError**)outError {
    CBL_LOCK(_mutex) {
        [self mustBeOpen];
        
        C4Error err;
        if (!c4db_maintenance(_c4db, (C4MaintenanceType)type, &err))
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

#pragma mark - Logging

+ (CBLLog*) log {
    return [CBLLog sharedInstance];
}

#pragma mark - DOCUMENT CHANGES

- (id<CBLListenerToken>) addChangeListener: (void (^)(CBLDatabaseChange*))listener {
    return [self addChangeListenerWithQueue: nil listener: listener];
}

- (id<CBLListenerToken>) addChangeListenerWithQueue: (nullable dispatch_queue_t)queue
                                           listener: (void (^)(CBLDatabaseChange*))listener {
    return [[self defaultCollectionOrThrow] addChangeListener:^(CBLCollectionChange *change) {
        CBLDatabaseChange* dbChange = [[CBLDatabaseChange alloc] initWithDatabase: change.collection.db
                                                                      documentIDs: change.documentIDs
                                                                       isExternal: change.isExternal];
        listener(dbChange);
    }];
}

- (id<CBLListenerToken>) addDocumentChangeListenerWithID: (NSString*)id
                                                listener: (void (^)(CBLDocumentChange*))listener
{
    return [self addDocumentChangeListenerWithID: id queue: nil listener: listener];
}

- (id<CBLListenerToken>) addDocumentChangeListenerWithID: (NSString*)identifier
                                                   queue: (nullable dispatch_queue_t)queue
                                                listener: (void (^)(CBLDocumentChange*))listener {
    return [[self defaultCollectionOrThrow] addDocumentChangeListenerWithID: identifier
                                                                      queue: queue
                                                                   listener: listener];
}

- (void) removeChangeListenerWithToken: (id<CBLListenerToken>)token {
    return [[self defaultCollectionOrThrow] removeToken: token];
}

#pragma mark - Index:

- (NSArray<NSString*>*) indexes {
    id result = [self withDefaultCollectionForObjectAndError: nil block: ^id(CBLCollection* collection, NSError** err) {
        return [collection indexes: err];
    }];
    assert(result != nil);
    return result;
}

- (BOOL) createIndex: (CBLIndex*)index withName: (NSString*)name error: (NSError**)error {
    return [self withDefaultCollectionAndError: error block: ^BOOL(CBLCollection* collection, NSError** err) {
        return [collection createIndex: index name: name error: err];
    }];
}

- (BOOL) createIndexWithConfig: (CBLIndexConfiguration*)config
                          name: (NSString*)name error: (NSError**)error {
    return [self createIndex: name withConfig: config error: error];
}

- (BOOL) createIndex: (NSString*)name withConfig: (id<CBLIndexSpec>)config error: (NSError**)error {
    return [self withDefaultCollectionAndError: error block: ^BOOL(CBLCollection* collection, NSError** err) {
        return [collection createIndexWithName: name config: config error: err];
    }];
}

- (BOOL) deleteIndexForName: (NSString*)name error: (NSError**)error {
    return [self withDefaultCollectionAndError: error block: ^BOOL(CBLCollection* collection, NSError** err) {
        return [collection deleteIndexWithName: name error: err];
    }];
}

#pragma mark - DOCUMENT EXPIRATION

- (BOOL) setDocumentExpirationWithID: (NSString*)documentID
                          expiration: (nullable NSDate*)date
                               error: (NSError**)error {
    return [self withDefaultCollectionAndError: error block: ^BOOL(CBLCollection* collection, NSError** err) {
        return [collection setDocumentExpirationWithID: documentID expiration: date error: err];
    }];
}

- (nullable NSDate*) getDocumentExpirationWithID: (NSString*)documentID {
    return [self withDefaultCollectionForObjectAndError: nil block: ^id(CBLCollection* collection, NSError** err) {
        return [collection getDocumentExpirationWithID: documentID error: err];
    }];
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
        
        return [[CBLScope alloc] initWithDB: self name: kCBLDefaultScopeName];
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
        
        return [[CBLScope alloc] initWithDB: self name: scopeName];
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
                }
                convertError(c4error, error);
                return nil;
            }
            _defaultCollection = [[CBLCollection alloc] initWithDB: self c4collection: c4col];
            return _defaultCollection; // Bypass checking if collection is valid
        }
        
        // When we allow to delete the default collection, the default collection
        // may become invalid here.
        if (![_defaultCollection checkIsValid: error]) {
            return nil;
        }
        return _defaultCollection;
    }
}

- (CBLCollection*) defaultCollectionOrThrow {
    CBL_LOCK(_mutex) {
        NSError* error;
        CBLCollection* col = [self defaultCollection: &error];
        if (!col) {
            throwIfNotOpenError(error);
            
            // Not expect to happen but if it does, log a warning error before raising the exception:
            CBLWarn(Database, @"%@ Failed to get default collection with error: %@", self, error);
            [NSException raise: NSInternalInconsistencyException format: @"Unable to get the default collection"];
        }
        return col;
    }
}

- (BOOL) withDefaultCollectionAndError: (NSError**)error block: (BOOL (^)(CBLCollection*, NSError**))block {
    NSError* outError = nil;
    BOOL result = block([self defaultCollectionOrThrow], &outError);
    if (!result) {
        throwIfNotOpenError(outError);
        if (error) *error = outError;
    }
    return result;
}

- (nullable id) withDefaultCollectionForObjectAndError: (NSError**)error
                                                 block: (id _Nullable (^)(CBLCollection*, NSError**))block
{
    NSError* outError = nil;
    id result = block([self defaultCollectionOrThrow], &outError);
    if (!result) {
        throwIfNotOpenError(outError);
        if (error) *error = outError;
    }
    return result;
}

static void throwNotOpen() {
    [NSException raise: NSInternalInconsistencyException
                format: @"The database was closed, or the default collection was deleted."];
}

static void throwIfNotOpenError(NSError* error) {
    if (error && error.domain == CBLErrorDomain && error.code == CBLErrorNotOpen) {
        throwNotOpen();
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
        CBLLogVerbose(Database, @"%@ Created c4collection[%@.%@] c4col=%p",
                      self.fullDescription, scopeName, name, c4collection);
        
        return [[CBLCollection alloc] initWithDB: self c4collection: c4collection];
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
            if (c4err.code != 0) {
                CBLWarn(Database, @"%@ Failed to get collection: %@.%@ (%d/%d)",
                        self, scopeName, name, c4err.domain, c4err.code);
                convertError(c4err, error);
            }
            return nil;
        }
        return [[CBLCollection alloc] initWithDB: self c4collection: c4col];
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
        
        CBLLogVerbose(Database, @"%@ Deleting c4collection[%@.%@]", self.fullDescription, scopeName, name);
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

- (BOOL) saveCookie: (NSString*)cookie url: (NSURL*)url acceptParentDomain: (BOOL)acceptParentDomain {
    CBL_LOCK(_mutex) {
        C4Error err = {};
        CBLStringBytes header(cookie);
        CBLStringBytes host(url.host);
        CBLStringBytes path(url.path.stringByDeletingLastPathComponent);
        if (!c4db_setCookie(_c4db, header, host, path, acceptParentDomain, &err)) {
            CBLWarnError(WebSocket, @"Cannot save cookie %d/%d", err.domain, err.code);
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
    CBLLogInfo(Database, @"Opening %@ at path %@", self, path);
    
    C4DatabaseConfig2 c4config = c4DatabaseConfig2(_config);
    CBLStringBytes d(_config.directory);
    c4config.parentDirectory = d;
    
    C4Error err;
    CBLStringBytes n(_name);
    _c4db = c4db_openNamed(n, &c4config, &err);
    if (!_c4db)
        return convertError(err, outError);
    
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

#ifdef COUCHBASE_ENTERPRISE
    if (config.encryptionKey)
        c4config.encryptionKey = [CBLDatabase c4EncryptionKey: config.encryptionKey];
#endif
    return c4config;
}

#pragma mark delegate(CBLRemovableListenerToken)

- (void) removeToken: (id)token {
    [[self defaultCollectionOrThrow] removeToken: token];
}

- (void) postDatabaseChanged {
    CBL_LOCK(_mutex) {
        if (!_dbObs || !_c4db)
            return;
        
        const uint32_t kMaxChanges = 100u;
        C4DatabaseChange changes[kMaxChanges];
        bool external = false;
        C4CollectionObservation obs = {};
        NSMutableArray* docIDs = [NSMutableArray new];
        do {
            // Read changes in batches of kMaxChanges:
            obs = c4dbobs_getChanges(_dbObs, changes, kMaxChanges);
            if (obs.numChanges == 0 || external != obs.external || docIDs.count > 1000) {
                if(docIDs.count > 0) {
// TODO: Remove https://issues.couchbase.com/browse/CBL-3206
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

                    [_dbChangeNotifier postChange:
                        [[CBLDatabaseChange alloc] initWithDatabase: self
                                                        documentIDs: docIDs
                                                         isExternal: external]];
#pragma clang diagnostic pop
                    docIDs = [NSMutableArray new];
                }
            }
            
            external = obs.external;
            for(uint32_t i = 0; i < obs.numChanges; i++) {
                NSString *docID =slice2string(changes[i].docID);
                [docIDs addObject: docID];
            }
            c4dbobs_releaseChanges(changes, obs.numChanges);
        } while(obs.numChanges > 0);
    }
}

- (void) removeDocumentChangeListenerWithToken: (CBLChangeListenerToken*)token {
    CBL_LOCK(_mutex) {
        NSString* documentID = (NSString*)token.context;
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
    
    _state = kCBLDatabaseStateClosed;
    _defaultCollection = nil;
}

- (void) safeBlock:(void (^)())block {
    CBL_LOCK(_mutex) {
        block();
    }
}

#pragma mark - Stoppable

- (void) addActiveStoppable: (id<CBLStoppable>)stoppable {
    CBL_LOCK(_mutex) {
        [self mustBeOpenAndNotClosing];
        
        if (!_activeStoppables)
            _activeStoppables = [NSMutableSet new];
        
        [_activeStoppables addObject: stoppable];
    }
}

- (void) removeActiveStoppable: (id<CBLStoppable>)stoppable {
    CBL_LOCK(_mutex) {
        [_activeStoppables removeObject: stoppable];
        
        if (_activeStoppables.count == 0)
            [_closeCondition broadcast];
    }
}

- (uint64_t) activeStoppableCount {
    CBL_LOCK(_mutex) {
        return _activeStoppables.count;
    }
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
