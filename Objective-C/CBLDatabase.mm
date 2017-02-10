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
#import "CBLInternal.h"
#import "CBLDocument.h"
#import "CBLQuery+Internal.h"
#import "CBLCoreBridge.h"
#import "CBLStringBytes.h"
#import "CBLMisc.h"
#import "CBLSharedKeys.hh"
#import "c4BlobStore.h"
#import "c4Observer.h"

#ifdef __cplusplus
extern "C" {
#endif

#import "MYBlockUtils.h"
#import "ExceptionUtils.h"

#ifdef __cplusplus
}
#endif


NSString* const kCBLDatabaseChangeNotification = @"CBLDatabaseChangeNotification";
NSString* const kCBLDatabaseChangesUserInfoKey = @"CBLDatbaseChangesUserInfoKey";
NSString* const kCBLDatabaseLastSequenceUserInfoKey = @"CBLDatabaseLastSequenceUserInfoKey";
NSString* const kCBLDatabaseIsExternalUserInfoKey = @"CBLDatabaseIsExternalUserInfoKey";


#define kDBExtension @"cblite2"


@implementation CBLDatabaseOptions


@synthesize directory=_directory, fileProtection=_fileProtection, encryptionKey=_encryptionKey;
@synthesize readOnly=_readOnly, dispatchQueue=_dispatchQueue;


- (instancetype) copyWithZone:(NSZone *)zone {
    CBLDatabaseOptions* o = [[self.class alloc] init];
    o.directory = self.directory;
    o.encryptionKey = self.encryptionKey;
    o.readOnly = self.readOnly;
    o.dispatchQueue = self.dispatchQueue;
    return o;
}


+ (instancetype) defaultOptions {
    return [[CBLDatabaseOptions alloc] init];
}


@end


@implementation CBLDatabase {
    NSString* _name;
    CBLDatabaseOptions* _options;
    NSThread* _thread;
    C4DatabaseObserver* _obs;
    NSMapTable<NSString*, CBLDocument*>* _documents;
    NSMutableSet<CBLDocument*>* _unsavedDocuments;
    CBLQuery* _allDocsQuery;
}


@synthesize name=_name, c4db=_c4db, sharedKeys=_sharedKeys, conflictResolver = _conflictResolver;


static const C4DatabaseConfig kDBConfig = {
    .flags = (kC4DB_Create | kC4DB_AutoCompact | kC4DB_Bundled | kC4DB_SharedKeys),
    .storageEngine = kC4SQLiteStorageEngine,
    .versioning = kC4RevisionTrees,
};


static void dbObserverCallback(C4DatabaseObserver* obs, void* context) {
    CBLDatabase *db = (__bridge CBLDatabase *)context;
    [db doAsync: ^{
        [db postDatabaseChanged];
    }];
}


static NSArray* CBL_RunloopModes;

+ (void) initialize {
    if (self == [CBLDatabase class]) {
        CBLLog_Init();
        CBL_RunloopModes = @[NSRunLoopCommonModes];
    }
}


- (instancetype) initWithName: (NSString*)name
                        error: (NSError**)outError {
    return [self initWithName: name
                      options: [CBLDatabaseOptions defaultOptions]
                        error: outError];
}


- (instancetype) initWithName: (NSString*)name
                      options: (nullable CBLDatabaseOptions*)options
                        error: (NSError**)outError {
    self = [super init];
    if (self) {
        _thread = [NSThread currentThread];
        _name = name;
        _options = options != nil? [options copy] : [CBLDatabaseOptions defaultOptions];
        if (![self open: outError])
            return nil;
    }
    return self;
}


- (BOOL) open: (NSError**)outError {
    if (_c4db)
        return YES;
    
    NSString* dir = _options.directory ?: defaultDirectory();
    if (![self setupDirectory: dir
               fileProtection: _options.fileProtection
                        error: outError])
        return NO;
    
    NSString* path = databasePath(_name, dir);
    CBLStringBytes bPath(path);
    
    C4DatabaseConfig config = kDBConfig;
    if (_options.readOnly)
        config.flags = config.flags | kC4DB_ReadOnly;
    if (_options.encryptionKey != nil) {
        CBLSymmetricKey* key = [[CBLSymmetricKey alloc]
                                initWithKeyOrPassword: _options.encryptionKey];
        config.encryptionKey = symmetricKey2C4Key(key);
    }

    CBLLog(Database, @"Opening %@ at path %@", self, path);
    C4Error err;
    _c4db = c4db_open(bPath, &config, &err);
    if (!_c4db)
        return convertError(err, outError);

    _sharedKeys = cbl::SharedKeys(_c4db);
    _obs = c4dbobs_create(_c4db, dbObserverCallback, (__bridge void *)self);
    _documents = [NSMapTable strongToWeakObjectsMapTable];
    _unsavedDocuments = [NSMutableSet setWithCapacity: 100];
    
    return YES;
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


- (instancetype) copyWithZone: (NSZone*)zone {
    return [[[self class] alloc] initWithName: _name options: _options error: nil];
}


- (void) dealloc {
    c4dbobs_free(_obs);
    c4db_free(_c4db);
}


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%@]", self.class, _name];
}


- (NSString*) path {
    return _c4db != nullptr ? sliceResult2FilesystemPath(c4db_getPath(_c4db)) : nil;
}


- (BOOL) close: (NSError**)outError {
    if (!_c4db)
        return YES;
    
    CBLLog(Database, @"Closing %@ at path %@", self, self.path);
    if (_unsavedDocuments.count > 0)
        CBLWarn(Database, @"Closing %@ with %lu unsaved docs, such as %@",
                self, (unsigned long)_unsavedDocuments.count, _unsavedDocuments.anyObject);
    
    _documents = nil;
    _unsavedDocuments = nil;
    
    C4Error err;
    if (!c4db_close(_c4db, &err))
        return convertError(err, outError);
    
    c4db_free(_c4db);
    c4dbobs_free(_obs);
    _c4db = nullptr;
    _obs = nullptr;

    return YES;
}


- (BOOL) mustBeOpen: (NSError**)outError {
    return _c4db != nullptr || convertError({LiteCoreDomain, kC4ErrorNotOpen}, outError);
}


- (BOOL) changeEncryptionKey: (nullable id)key error: (NSError**)outError {
    // TODO:
    return NO;
}


- (BOOL) deleteDatabase: (NSError**)outError {
    C4Error err;
    if (!c4db_delete(_c4db, &err))
        return convertError(err, outError);
    c4db_free(_c4db);
    _c4db = nullptr;
    c4dbobs_free(_obs);
    _obs = nullptr;
    return YES;
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


- (BOOL) inBatch: (NSError**)outError do: (void (^)())block {
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


- (CBLDocument*) document {
    return [self documentWithID: [self generateDocID]];
}


- (CBLDocument*) documentWithID: (NSString*)docID {
    return [self documentWithID: docID mustExist: NO error: nil];
}


- (CBLDocument*) objectForKeyedSubscript: (NSString*)docID {
    return [self documentWithID: docID mustExist: NO error: nil];
}


- (BOOL) documentExists: (NSString*)docID {
    id doc = [self documentWithID: docID mustExist: YES error: nil];
    return doc != nil;
}


static void catchInBlock(void (^block)(), NSString* method) {
    @try { block(); } catchAndReport([NSString stringWithFormat:@"-[CBLDatabase %@]", method]);
}


- (void) doAsync: (void (^)())block {
    block = ^{
        if ([self mustBeOpen: nil])
            catchInBlock(block, @"doAsync:");
    };
    
    if (_options.dispatchQueue)
        dispatch_async(_options.dispatchQueue, block);
    else
        MYOnThreadInModes(_thread, CBL_RunloopModes, NO, block);
}


- (void) doSync: (void (^)())block {
    if (_options.dispatchQueue)
        dispatch_sync(_options.dispatchQueue, ^{catchInBlock(block, @"doSync:");});
    else
        MYOnThreadInModes(_thread, CBL_RunloopModes, YES, ^{catchInBlock(block, @"doSync:");});
}


#pragma mark - INTERNAL


- (void) document: (CBLDocument*)doc hasUnsavedChanges: (bool)unsaved {
    if (unsaved)
        [_unsavedDocuments addObject: doc];
    else
        [_unsavedDocuments removeObject: doc];
}


#pragma mark - PRIVATE


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


static NSString* databasePath(NSString* name, NSString* dir) {
    name = [[name stringByReplacingOccurrencesOfString: @"/" withString: @":"]
            stringByAppendingPathExtension: kDBExtension];
    NSString* path = [dir stringByAppendingPathComponent: name];
    return path.stringByStandardizingPath;
}


- (void) postDatabaseChanged {
    if (!_obs || !_c4db || c4db_isInTransaction(_c4db))
        return;

    const uint32_t kMaxChanges = 100u;
    C4Slice c4docIDs[kMaxChanges];
    C4SequenceNumber lastSequence;
    bool external = false;
    uint32_t changes = 0u;
    NSMutableArray* docIDs = [NSMutableArray new];
    do {
        // Read changes in batches of kMaxChanges:
        bool newExternal;
        changes = c4dbobs_getChanges(_obs, c4docIDs, kMaxChanges, &lastSequence, &newExternal);
        if(changes == 0 || external != newExternal || docIDs.count > 1000) {
            if(docIDs.count > 0) {
                // Only notify if there are actually changes to send
                NSDictionary *userInfo = @{kCBLDatabaseChangesUserInfoKey: docIDs,
                                           kCBLDatabaseLastSequenceUserInfoKey: @(lastSequence),
                                           kCBLDatabaseIsExternalUserInfoKey: @(external)};
                NSNotification* n = [NSNotification notificationWithName: kCBLDatabaseChangeNotification
                                                                  object: self
                                                                userInfo: userInfo];
                [[NSNotificationCenter defaultCenter] postNotification: n];
                docIDs = [NSMutableArray new];
            }
        }

        external = newExternal;
        for(uint32_t i = 0; i < changes; i++) {
            NSString *docID =slice2string(c4docIDs[i]);
            [docIDs addObject:docID];
            if(external) {
                [[_documents objectForKey:docID] changedExternally];
            }
        }
    } while(changes > 0);
}


- (C4BlobStore*) getBlobStore: (NSError**)outError {
    if (![self mustBeOpen: outError])
        return nil;
    C4Error err;
    C4BlobStore *blobStore = c4db_getBlobStore(_c4db, &err);
    if (!blobStore)
        convertError(err, outError);
    return blobStore;
}


#pragma mark - PRIVATE: DOCUMENT


- (NSString*) generateDocID {
    return CBLCreateUUID();
}


- (CBLDocument*) documentWithID: (NSString*)docID
                     mustExist: (bool)mustExist
                         error: (NSError**)outError
{
    CBLDocument *doc = [_documents objectForKey: docID];
    if (!doc) {
        doc = [[CBLDocument alloc] initWithDatabase: self docID: docID
                                          mustExist: mustExist
                                              error: outError];
        if (!doc)
            return nil;
        [_documents setObject: doc forKey: docID];
    } else {
        if (mustExist && !doc.exists) {
            // Don't return a pre-instantiated CBLDocument if it doesn't exist
            convertError(C4Error{LiteCoreDomain, kC4ErrorNotFound},  outError);
            return nil;
        }
    }
    return doc;
}


#pragma mark - QUERIES:


- (NSEnumerator<CBLDocument*>*) allDocuments {
    if (!_allDocsQuery) {
        _allDocsQuery = [[CBLQuery alloc] initWithDatabase: self];
        _allDocsQuery.orderBy = @[@"_id"];
    }
    auto e = [_allDocsQuery allDocuments: nullptr];
    Assert(e, @"allDocuments failed?!");
    return e;
}


- (CBLQuery*) createQueryWhere: (nullable id)where {
    auto query = [[CBLQuery alloc] initWithDatabase: self];
    query.where = where;
    return query;
}


- (BOOL) createIndexOn: (NSArray<NSExpression*>*)expressions
                 error: (NSError**)outError
{
    return [self createIndexOn: expressions type: kCBLValueIndex options: NULL error: outError];
}


- (BOOL) createIndexOn: (NSArray*)expressions
                  type: (CBLIndexType)type
               options: (const CBLIndexOptions*)options
                 error: (NSError**)outError
{
    static_assert(sizeof(CBLIndexOptions) == sizeof(C4IndexOptions), "Index options incompatible");
    NSData* json = [CBLQuery encodeExpressionsToJSON: expressions error: outError];
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
    NSData* json = [CBLQuery encodeExpressionsToJSON: expressions error: outError];
    if (!json)
        return NO;
    C4Error c4err;
    return c4db_deleteIndex(_c4db, {json.bytes, json.length}, (C4IndexType)type, &c4err)
            || convertError(c4err, outError);
}


@end

// TODO:
// * Close all other database handles when deleting the database
//   and changing the encryption key
// * Database Change Notification in save and when inBatch.
// * Encryption key and rekey
//     * [MacOS] Support encryption key from the Keychain
// * Error Domain: Should LiteCore error domain transfer to CouchbaseLite?
// *. Live Object and Change from external
//
