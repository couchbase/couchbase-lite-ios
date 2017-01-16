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


@implementation CBLDatabaseOptions


- (instancetype) copyWithZone:(NSZone *)zone {
    CBLDatabaseOptions* o = [[self.class alloc] init];
    o.directory = self.directory;
    o.encryptionKey = self.encryptionKey;
    o.readOnly = self.readOnly;
    return o;
}


+ (instancetype) defaultOptions {
    return [[CBLDatabaseOptions alloc] init];
}


@end


@implementation CBLDatabase {
    NSString* _name;
    CBLDatabaseOptions* _options;
    C4Database* _c4db;
    NSMapTable<NSString*, CBLDocument*>* _documents;
    NSMutableSet<CBLDocument*>* _unsavedDocuments;
}


@synthesize c4db=_c4db;


static const C4DatabaseConfig kDBConfig = {
    .flags = (kC4DB_Create | kC4DB_AutoCompact | kC4DB_Bundled | kC4DB_SharedKeys),
    .storageEngine = kC4SQLiteStorageEngine,
    .versioning = kC4RevisionTrees,
};


static void logCallback(C4LogDomain domain, C4LogLevel level, C4Slice message) {
    static const char* klevelNames[5] = {"Debug", "Verbose", "Info", "WARNING", "ERROR"};
    NSLog(@"CouchbaseLite %s %s: %.*s", c4log_getDomainName(domain), klevelNames[level],
          (int)message.size, (char*)message.buf);
}


+ (void) initialize {
    if (self == [CBLDatabase class]) {
        c4log_register(kC4LogWarning, &logCallback);
    }
}


- (instancetype) initWithName: (NSString*)name
                        error: (NSError**)outError {
    return [self initWithName: name
                      options: [CBLDatabaseOptions defaultOptions]
                        error: outError];
}


- (instancetype) initWithName: (NSString*)name
                      options: (CBLDatabaseOptions*)options
                        error: (NSError**)outError {
    _name = name;
    _options = [options copy];
    if (![self open: outError])
        return nil;
    return self;
}


- (BOOL) open: (NSError**)outError {
    if (_c4db)
        return YES;
    
    if (![self setupDirectory: _options.directory
               fileProtection: _options.fileProtection
                        error: outError])
        return NO;
    
    NSString* path = databasePath(_name, _options.directory);    
    CBLStringBytes bPath = CBLStringBytes(path);
    
    C4DatabaseConfig config = kDBConfig;
    if (_options.readOnly)
        config.flags = config.flags | kC4DB_ReadOnly;
    if (_options.encryptionKey != nil) {
        CBLSymmetricKey* key = [[CBLSymmetricKey alloc]
                                initWithKeyOrPassword: _options.encryptionKey];
        config.encryptionKey = symmetricKey2C4Key(key);
    }
    
    C4Error err;
    _c4db = c4db_open(bPath, &config, &err);
    if (!_c4db)
        return convertError(err, outError);
    
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
    
    dir = directory(dir);
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
    c4db_free(_c4db);
}


- (BOOL) close: (NSError**)outError {
    if (!_c4db)
        return YES;
    
    if (_unsavedDocuments.count > 0)
        CBLWarn(Default, @"Closing database with %lu unsaved docs",
                (unsigned long)_unsavedDocuments.count);
    
    _documents = nil;
    _unsavedDocuments = nil;
    
    C4Error err;
    if (!c4db_close(_c4db, &err))
        return convertError(err, outError);
    
    c4db_free(_c4db);
    _c4db = nullptr;
    
    return YES;
}


- (BOOL) changeEncryptionKey: (nullable id)key error: (NSError**)outError {
    // TODO:
    return NO;
}


- (BOOL) deleteDatabase: (NSError**)outError {
    C4Error err;
    if (!c4db_delete(_c4db, &err))
        return convertError(err, outError);
    _c4db = nullptr;
    return true;
}


+ (BOOL) deleteDatabase: (NSString*)name
            inDirectory: (nullable NSString*)directory
                  error: (NSError**)outError {
    NSString* path = databasePath(name, directory);
    CBLStringBytes bPath = CBLStringBytes(path);
    C4Error err;
    return c4db_deleteAtPath(bPath, &kDBConfig, &err) || convertError(err, outError);
}


+ (BOOL) databaseExists: (NSString*)name
            inDirectory: (nullable NSString*)directory {
    NSString* path = databasePath(name, directory);
    return [[NSFileManager defaultManager] fileExistsAtPath: path];
}


- (bool) inBatch: (NSError**)outError do: (BOOL (^)())block {
    C4Transaction transaction(_c4db);
    if (outError)
        *outError = nil;
    
    if (!transaction.begin())
        return convertError(transaction.error(), outError);
    
    if (!block())
        return false;
    
    if (!transaction.commit())
        return convertError(transaction.error(), outError);
    return true;
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


#pragma mark - INTERNAL


- (void) document: (CBLDocument*)doc hasUnsavedChanges: (bool)unsaved {
    if (unsaved)
        [_unsavedDocuments addObject: doc];
    else
        [_unsavedDocuments removeObject: doc];
}


- (NSString*) path {
    C4SliceResult str = c4db_getPath(_c4db);
    NSString* path = [NSFileManager.defaultManager
                      stringWithFileSystemRepresentation: (const char*)str.buf
                      length: str.size];
    c4slice_free(str);
    return path;
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


static NSString* directory(NSString* directory) {
    return directory != nil ? directory : defaultDirectory();
}


static NSString* databasePath(NSString* name, NSString* dir) {
    NSString* path = [directory(dir) stringByAppendingPathComponent: name];
    return path.stringByStandardizingPath;
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


- (nullable CBLQuery*) createQuery: (nullable id)query
                             error: (NSError**)outError
{
    return [self createQueryWhere: query orderBy: nil error: outError];
}


- (nullable CBLQuery*) createQueryWhere: (nullable id)where
                                orderBy: (nullable NSArray*)sortDescriptors
                                  error: (NSError**)outError
{
    return [[CBLQuery alloc] initWithDatabase: self
                                        where: where
                                      orderBy: sortDescriptors
                                        error: outError];
}


- (bool) createIndexOn: (NSString*)propertyPath
                 error: (NSError**)outError
{
    return [self createIndexOn: propertyPath type: kCBLValueIndex options: NULL error: outError];
}


- (bool) createIndexOn: (NSString*)propertyPath
                  type: (CBLIndexType)type
               options: (const CBLIndexOptions*)options
                 error: (NSError**)outError
{
    static_assert(sizeof(CBLIndexOptions) == sizeof(C4IndexOptions), "Index options incompatible");
    CBLStringBytes propertyBytes(propertyPath);
    C4Error c4err;
    return c4db_createIndex(_c4db, propertyBytes,
                            (C4IndexType)type,
                            (const C4IndexOptions*)options,
                            &c4err)
                || convertError(c4err, outError);
}


- (bool) deleteIndexOn: (NSString*)propertyPath
                  type: (CBLIndexType)type
{
    CBLStringBytes propertyBytes(propertyPath);
    return c4db_deleteIndex(_c4db, propertyBytes, (C4IndexType)type, NULL);
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
