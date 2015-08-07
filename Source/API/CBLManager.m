//
//  CBLManager.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/19/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLManager.h"
#import "CouchbaseLitePrivate.h"

#import "CBLDatabase.h"
#import "CBLDatabase+Attachments.h"
#import "CBLDatabase+Insertion.h"
#import "CBLDatabase+Internal.h"
#import "CBLDatabase+Replication.h"
#import "CBLManager+Internal.h"
#import "CBL_Replicator.h"
#import "CBL_Server.h"
#import "CBL_URLProtocol.h"
#import "CBLPersonaAuthorizer.h"
#import "CBLFacebookAuthorizer.h"
#import "CBLOAuth1Authorizer.h"
#import "CBL_Shared.h"
#import "CBLInternal.h"
#import "CBLMisc.h"
#import "CBLStatus.h"
#import "CBLDatabaseUpgrade.h"
#import "CBLSymmetricKey.h"
#import "MYBlockUtils.h"


#define kV1DBExtension @"cblite"    // Couchbase Lite 1.0
#define kDBExtension @"cblite2"


static const CBLManagerOptions kCBLManagerDefaultOptions;


#ifdef GNUSTEP
static double CouchbaseLiteVersionNumber = 0.7;
#else
extern double CouchbaseLiteVersionNumber; // Defined in Xcode-generated CouchbaseLite_vers.c
#endif


NSString* CBLVersion( void ) {
    if (CouchbaseLiteVersionNumber > 0)
        return $sprintf(@"%s (build %g)", CBL_VERSION_STRING, CouchbaseLiteVersionNumber);
    else
        return $sprintf(@"%s (unofficial)", CBL_VERSION_STRING);
}

#ifndef MY_DISABLE_LOGGING
static NSString* CBLFullVersionInfo( void ) {
    NSMutableString* vers = [NSMutableString stringWithFormat: @"Couchbase Lite %@", CBLVersion()];
#ifdef CBL_SOURCE_REVISION
    if (strlen(CBL_SOURCE_REVISION) > (0))
        [vers appendFormat: @"; git commit %s", CBL_SOURCE_REVISION];
#endif
    return vers;
}
#endif


@interface CBLManager ()

@property (nonatomic) NSMutableDictionary* customHTTPHeaders;

@end

@implementation CBLManager
{
    NSString* _dir;
    CBLManagerOptions _options;
    NSThread* _thread;
    dispatch_queue_t _dispatchQueue;
    NSMutableDictionary* _databases;
    NSURL* _internalURL;
    Class _replicatorClass;
    NSMutableArray* _replications;
    __weak CBL_Shared *_shared;
    id _strongShared;       // optional strong reference to _shared
}


@synthesize dispatchQueue=_dispatchQueue, directory = _dir;
@synthesize customHTTPHeaders = _customHTTPHeaders;
@synthesize storageType=_storageType, replicatorClassName=_replicatorClassName;


// http://wiki.apache.org/couchdb/HTTP_database_API#Naming_and_Addressing
#define kLegalChars @"abcdefghijklmnopqrstuvwxyz0123456789_$()+-/"
static NSCharacterSet* kIllegalNameChars;

+ (void) initialize {
    if (self == [CBLManager class]) {
        Log(@"### %@ ###", CBLFullVersionInfo());
        kIllegalNameChars = [[NSCharacterSet characterSetWithCharactersInString: kLegalChars]
                             invertedSet];
    }
}


+ (void) enableLogging: (NSString*)type {
#ifdef MY_DISABLE_LOGGING
    NSLog(@"Can't enable logging: Couchbase Lite was compiled with logging disabled");
#else
    EnableLog(YES);
    if (type != nil)
        _EnableLogTo(type, YES);
#endif
}

+ (void) redirectLogging: (void (^)(NSString* type, NSString* message))callback {
#ifndef MY_DISABLE_LOGGING
    MYLoggingCallback = callback;
#endif
}

+ (void) setWarningsRaiseExceptions: (BOOL)wre {
    gMYWarnRaisesException = wre;
}


+ (NSString*) defaultDirectory {
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                         NSUserDomainMask, YES);
    NSString* path = paths[0];
#if !TARGET_OS_IPHONE
    path = [path stringByAppendingPathComponent: [[NSBundle mainBundle] bundleIdentifier]];
#endif
    return [path stringByAppendingPathComponent: @"CouchbaseLite"];
}


static CBLManager* sInstance;

+ (instancetype) sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sInstance = [[self alloc] init];
        LogTo(CBLDatabase, @"%@ is the sharedInstance", sInstance);
    });
    return sInstance;
}


- (instancetype) init {
    NSError* error;
    self = [self initWithDirectory: [[self class] defaultDirectory]
                           options: NULL
                             error: &error];
    if (self) {
        _customHTTPHeaders = [NSMutableDictionary dictionary];
    }
    return self;
}


// Initializer for main manager (not copies).
- (instancetype) initWithDirectory: (NSString*)directory
                           options: (const CBLManagerOptions*)options
                             error: (NSError**)outError
{
    if (outError) *outError = nil;
    self = [self initWithDirectory: directory
                           options: options
                            shared: [[CBL_Shared alloc] init]];
    if (self) {
        _thread = [NSThread currentThread];
        // Create the directory but don't fail if it already exists:
        NSError* error;
        NSDictionary* attributes = nil;
#if TARGET_OS_IPHONE
        // Set the iOS file protection mode of the manager's top-level directory.
        // This mode will be inherited by all files created in that directory.
        NSString* protection;
        switch (_options.fileProtection & NSDataWritingFileProtectionMask) {
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
        if (![[NSFileManager defaultManager] createDirectoryAtPath: _dir
                                       withIntermediateDirectories: YES
                                                        attributes: attributes
                                                             error: &error]) {
            if (!CBLIsFileExistsError(error)) {
                if (outError) *outError = error;
                return nil;
            }
            if (attributes) {
                if (![[NSFileManager defaultManager] setAttributes: attributes
                                                      ofItemAtPath: _dir
                                                             error: outError]) {
                    return nil;
                }
            }
        }
        [self upgradeOldDatabaseFiles];
    }
    return self;
}


// Base initializer.
- (instancetype) initWithDirectory: (NSString*)directory
                           options: (const CBLManagerOptions*)options
                            shared: (CBL_Shared*)shared
{
    self = [super init];
    if (self) {
        _dir = [directory copy];
        _options = options ? *options : kCBLManagerDefaultOptions;
        _shared = shared;
        _strongShared = _shared;
        _databases = [[NSMutableDictionary alloc] init];
        _replications = [[NSMutableArray alloc] init];
        _storageType = [[NSUserDefaults standardUserDefaults] stringForKey: @"CBLStorageType"];
        if (!_storageType)
            _storageType = @"SQLite";
        _replicatorClassName = [[NSUserDefaults standardUserDefaults]
                                                            stringForKey: @"CBLReplicatorClass"];
        if (!_replicatorClassName)
            _replicatorClassName = @"CBLRestReplicator";
        LogTo(CBLDatabase, @"Created %@", self);
    }
    return self;
}


#if DEBUG
+ (instancetype) createEmptyAtPath: (NSString*)path {
    [CBLDatabase setAutoCompact: NO]; // unit tests don't want autocompact
    [[NSFileManager defaultManager] removeItemAtPath: path error: NULL];
    NSError* error;
    CBLManager* dbm = [[self alloc] initWithDirectory: path
                                              options: NULL
                                                error: &error];
    Assert(dbm, @"Failed to create db manager at %@: %@", path, error);
    AssertEqual(dbm.directory, path);
#if MY_ENABLE_TESTS
    AfterThisTest(^{
        [dbm close];
        [[NSFileManager defaultManager] removeItemAtPath: path error: NULL];
    });
#endif
    return dbm;
}

+ (instancetype) createEmptyAtTemporaryPath: (NSString*)name {
    return [self createEmptyAtPath: [NSTemporaryDirectory() stringByAppendingPathComponent: name]];
}
#endif


- (id) copyWithZone: (NSZone*)zone {
    CBLManager *managerCopy = [[[self class] alloc] initWithDirectory: self.directory
                                                              options: &_options
                                                               shared: _shared];
    if (managerCopy) {
        managerCopy.customHTTPHeaders = [self.customHTTPHeaders copy];
        managerCopy.storageType = _storageType;
        managerCopy.replicatorClassName = _replicatorClassName;
    }
    return managerCopy;
}

- (instancetype) copy {
    return [self copyWithZone: nil];
}


- (void) close {
    Assert(self != sInstance, @"Please don't close the sharedInstance!");
    LogTo(CBLDatabase, @"CLOSING %@ ...", self);
    for (CBLDatabase* db in _databases.allValues) {
        [db _close];
    }
    [_databases removeAllObjects];
    _shared = nil;
    _strongShared = nil;
    LogTo(CBLDatabase, @"CLOSED %@", self);
}


- (void)dealloc
{
    [self close];
}


- (Class) databaseUpgradeClass {
    return NSClassFromString(@"CBLDatabaseUpgrade");
}


// Scan my dir for SQLite-based databases from Couchbase Lite 1.0 and upgrade them:
- (void) upgradeOldDatabaseFiles {
    // The CBLDatabaseUpgrade class is optional, so don't create a hard reference to it.
    // And skip the upgrade check if it's not present:
    if (![self databaseUpgradeClass]) {
        Warn(@"Upgrade skipped: Database upgrading class is not present.");
        return;
    }

    NSFileManager* fmgr = [NSFileManager defaultManager];
    NSArray* files = [fmgr contentsOfDirectoryAtPath: _dir error: NULL];
    for (NSString* filename in [files pathsMatchingExtensions: @[kV1DBExtension]]) {
        NSString* name = [self nameOfDatabaseAtPath: filename];
        NSString* oldDbPath = [_dir stringByAppendingPathComponent: filename];
        [self upgradeDatabaseNamed: name atPath: oldDbPath error: NULL];
    }
}


- (BOOL) upgradeDatabaseNamed: (NSString*)name
                       atPath: (NSString*)dbPath
                        error: (NSError**)outError {
    Class databaseUpgradeClass = [self databaseUpgradeClass];
    if (!databaseUpgradeClass) {
        // Gracefully skipping the upgrade:
        Warn(@"Upgrade skipped: Database upgrading class is not present.");
        return YES;
    }

    if (![dbPath.pathExtension isEqualToString:kV1DBExtension]) {
        // Gracefully skipping the upgrade:
        Warn(@"Upgrade skipped: Database file extension is not %@", kV1DBExtension);
        return YES;
    }

    NSLog(@"CouchbaseLite: Upgrading v1 database at %@ ...", dbPath);
    if (![name isEqualToString: @"_replicator"]) {
        // Create and open new CBLDatabase:
        NSError* error;
        CBLDatabase* db = [self _databaseNamed: name mustExist: NO error: &error];
        if (!db) {
            Warn(@"Upgrade failed: Creating new db failed: %@", error);
            if (outError)
                *outError = error;
            return NO;
        }
        if (!db.exists) {
            // Upgrade the old database into the new one:
            CBLDatabaseUpgrade* upgrader = [[databaseUpgradeClass alloc] initWithDatabase: db
                                                                               sqliteFile: dbPath];
            CBLStatus status = [upgrader import];
            if (CBLStatusIsError(status)) {
                Warn(@"Upgrade failed: status %d", status);
                [upgrader backOut];
                if (outError)
                    *outError = error;
                return NO;
            }
        }
        [db _close];
    }

    // Remove old database file and its SQLite side files:
    NSFileManager* fmgr = [NSFileManager defaultManager];
    for (NSString* suffix in @[@"", @"-wal", @"-shm"])
        [fmgr removeItemAtPath: [dbPath stringByAppendingString: suffix] error: NULL];
    NSString* oldAttachmentsPath = [[dbPath stringByDeletingPathExtension]
                                    stringByAppendingString: @" attachments"];
    [fmgr removeItemAtPath: oldAttachmentsPath error: NULL];
    NSLog(@"    ...success!");

    return YES;
}


- (NSString*) description {
    return $sprintf(@"%@[%p %@]", [self class], self, self.directory);
}


- (BOOL) excludedFromBackup {
    NSNumber* excluded;
    NSError* error;
    if (![[NSURL fileURLWithPath: _dir] getResourceValue: &excluded
                                                  forKey: NSURLIsExcludedFromBackupKey
                                                   error: &error]) {
        Warn(@"%@: -excludedFromBackup failed: %@", self, error);
    }
    return excluded.boolValue;
}

- (void) setExcludedFromBackup: (BOOL)exclude {
    NSError* error;
    if (![[NSURL fileURLWithPath: _dir] setResourceValue: @(exclude)
                                                  forKey: NSURLIsExcludedFromBackupKey
                                                   error: &error]) {
        Warn(@"%@: -setExcludedFromBackup:%d failed: %@", self, exclude, error);
    }
}


#pragma mark - BACKGROUND TASKS:


- (void) doAsync: (void (^)())block {
    if (_dispatchQueue)
        dispatch_async(_dispatchQueue, block);
    else
        MYOnThread(_thread, block);
}


- (CBL_Shared*) shared {
    CBL_Shared* shared = _shared;
    if (!shared) {
        shared = [[CBL_Shared alloc] init];
        _shared = shared;
    }
    return shared;
}


- (CBL_Server*) backgroundServer {
    CBL_Shared* shared = _shared;
    Assert(shared);
    @synchronized(shared) {
        CBL_Server* server = shared.backgroundServer;
        if (!server) {
            CBLManager* newManager = [self copy];
            if (newManager) {
                // The server's manager can't have a strong reference to the CBLShared, or it will
                // form a cycle (newManager -> strongShared -> backgroundServer -> newManager).
                newManager->_strongShared = nil;
                Class serverClass = [self.replicatorClass needsRunLoop] ? [CBL_RunLoopServer class]
                                                                        : [CBL_DispatchServer class];
                server = [[serverClass alloc] initWithManager: newManager];
                LogTo(CBLDatabase, @"%@ created %@ (with %@)", self, server, newManager);
            }
            Assert(server, @"Failed to create backgroundServer!");
            shared.backgroundServer = server;
        }
        return server;
    }
}


- (void) backgroundTellDatabaseNamed: (NSString*)dbName to: (void (^)(CBLDatabase*))block {
    [self.backgroundServer tellDatabaseNamed: dbName to: block];
}


- (NSURL*) internalURL {
    if (!_internalURL) {
        Class tdURLProtocol = NSClassFromString(@"CBL_URLProtocol");
        Assert(tdURLProtocol, @"CBL_URLProtocol class not found; link CouchbaseLiteListener.framework");
        NSURL* serverURL = [tdURLProtocol registerServer: self.backgroundServer];
        _internalURL = [tdURLProtocol HTTPURLForServerURL: serverURL];
    }
    return _internalURL;
}


#pragma mark - DATABASES (PUBLIC API):


+ (BOOL) isValidDatabaseName: (NSString*)name {
    return name.length > 0 && name.length < 240        // leave room for filename suffixes
            && [name rangeOfCharacterFromSet: kIllegalNameChars].length == 0
            && islower([name characterAtIndex: 0]);
}


- (NSArray*) allDatabaseNames {
    NSArray* files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: _dir error: NULL];
    files = [files pathsMatchingExtensions: @[kDBExtension]];
    return [files my_map: ^(NSString* filename) {
        return [self nameOfDatabaseAtPath: filename];
    }];
}


- (NSArray*) allOpenDatabases {
    return _databases.allValues;
}


- (BOOL) databaseExistsNamed: (NSString*)name {
    if (_databases[name] != nil)
        return YES;
    else if (![[self class] isValidDatabaseName: name])
        return NO;
    else
        return [[NSFileManager defaultManager] fileExistsAtPath: [self pathForDatabaseNamed: name]];
}


- (CBLDatabase*) objectForKeyedSubscript:(NSString*)key {
    return [self existingDatabaseNamed: key error: NULL];
}

- (CBLDatabase*) existingDatabaseNamed: (NSString*)name error: (NSError**)outError {
    CBLDatabase* db = [self _databaseNamed: name mustExist: YES error: outError];
    if (![db open: outError])
        db = nil;
    return db;
}


- (CBLDatabase*) databaseNamed: (NSString*)name error: (NSError**)outError {
    CBLDatabase* db = [self _databaseNamed: name mustExist: NO error: outError];
    if (![db open: outError])
        db = nil;
    return db;
}


- (BOOL) registerEncryptionKey: (id)keyOrPassword
              forDatabaseNamed: (NSString*)name
{
    CBLSymmetricKey* realKey = nil;
    if (keyOrPassword) {
        if ([keyOrPassword isKindOfClass: [NSString class]]) {
            realKey = [[CBLSymmetricKey alloc] initWithPassword: keyOrPassword];
        } else {
            Assert([keyOrPassword isKindOfClass: [NSData class]]);
            realKey = [[CBLSymmetricKey alloc] initWithKeyData: keyOrPassword];
            if (!realKey)
                return NO;
        }
    }
    [self.shared setValue: realKey
                  forType: @"encryptionKey"
                     name: @""
          inDatabaseNamed: name];
    return YES;
}


#if !TARGET_OS_IPHONE
- (BOOL) encryptDatabaseNamed: (NSString*)name {
    NSString* dir = self.directory.stringByAbbreviatingWithTildeInPath;
    NSString* itemName = $sprintf(@"%@ database in %@", name, dir);
    NSError* error;
    CBLSymmetricKey* key = [[CBLSymmetricKey alloc] initWithKeychainItemNamed: itemName
                                                                        error: &error];
    if (!key) {
        if (error.code == errSecItemNotFound) {
            key = [CBLSymmetricKey new];
            if (![key saveKeychainItemNamed: itemName])
                return NO;
        } else {
            return NO;
        }
    }
    [self.shared setValue: key
                  forType: @"encryptionKey"
                     name: @""
          inDatabaseNamed: name];
    return YES;
}
#endif


- (BOOL) closeDatabaseNamed: (NSString*)name error: (NSError**)error {
    CBLDatabase* db = _databases[name];
    if (db) {
        if (![db close: error])
            return NO;
    }
    
    CBL_Shared* shared = _shared;
    if (shared.backgroundServer) {
        return [[shared.backgroundServer waitForDatabaseNamed: name to: ^id(CBLDatabase* bgdb) {
            BOOL result = [bgdb close: error];
            return @(result);
        }] boolValue];
    }
    return YES;
}


#if DEBUG
- (CBLDatabase*) createEmptyDatabaseNamed: (NSString*)name error: (NSError**)outError {
    CBLDatabase* db = _databases[name];
    if (db) {
        if (![db deleteDatabase: outError])
            return nil;
    } else {
        AssertEq([_shared countForOpenedDatabase: name], 0u);
        if (![CBLDatabase deleteDatabaseFilesAtPath: [self pathForDatabaseNamed: name]
                                              error: outError])
            return nil;
    }
    return [self databaseNamed: name error: outError];
}
#endif


- (BOOL) replaceDatabaseNamed: (NSString*)databaseName
             withDatabaseFile: (NSString*)databasePath
              withAttachments: (NSString*)attachmentsPath
                        error: (NSError**)outError
{
    CBLDatabase* db = [self _databaseNamed: databaseName mustExist: NO error: outError];
    if (!db)
        return NO;
    Assert(!db.isOpen, @"Already-open database cannot be replaced");

    NSFileManager *fmgr = [NSFileManager defaultManager];
    BOOL isDbPathDir;
    if (![fmgr fileExistsAtPath: databasePath isDirectory: &isDbPathDir]) {
        Warn(@"Database file doesn't exist at path : %@", databasePath);
        return NO;
    }

    if (isDbPathDir) {
        Warn(@"Database file is a directory. "
              "Use -replaceDatabaseNamed:withDatabaseDir:error: instead.");
        CBLStatusToOutNSError(kCBLStatusBadParam, outError);
        return NO;
    }

    NSString* dstDbPath = [[db.dir stringByDeletingPathExtension]
                            stringByAppendingPathExtension: kV1DBExtension];
    NSString* dstAttsPath = [[dstDbPath stringByDeletingPathExtension]
                                    stringByAppendingString: @" attachments"];

    return CBLRemoveFileIfExists(dstDbPath, outError) &&
        CBLRemoveFileIfExists([dstDbPath stringByAppendingString: @"-wal"], outError) &&
        CBLRemoveFileIfExists([dstDbPath stringByAppendingString: @"-shm"], outError) &&
        CBLRemoveFileIfExists(dstAttsPath, outError) &&
        CBLCopyFileIfExists(databasePath, dstDbPath, outError) &&
        CBLCopyFileIfExists([databasePath stringByAppendingString: @"-wal"],
                            [dstDbPath stringByAppendingString: @"-wal"], outError) &&
        CBLCopyFileIfExists([databasePath stringByAppendingString: @"-shm"],
                            [dstDbPath stringByAppendingString: @"-shm"], outError) &&
        (!attachmentsPath || CBLCopyFileIfExists(attachmentsPath, dstAttsPath, outError)) &&
        (isDbPathDir || [self upgradeDatabaseNamed: databaseName atPath: dstDbPath error: NULL]) &&
        [db open: outError] &&
        [db saveLocalUUIDInLocalCheckpointDocument: outError] &&
        [db replaceUUIDs: outError];
}


- (BOOL) replaceDatabaseNamed: (NSString*)databaseName
             withDatabaseDir: (NSString*)databaseDir
                        error: (NSError**)outError
{
    CBLDatabase* db = [self _databaseNamed: databaseName mustExist: NO error: outError];
    if (!db)
        return NO;
    Assert(!db.isOpen, @"Already-open database cannot be replaced");

    NSFileManager *fmgr = [NSFileManager defaultManager];
    BOOL isDbPathDir;
    if (![fmgr fileExistsAtPath: databaseDir isDirectory: &isDbPathDir]) {
        Warn(@"Database file doesn't exist at path : %@", databaseDir);
        CBLStatusToOutNSError(kCBLStatusNotFound, outError);
        return NO;
    }

    if (!isDbPathDir) {
        Warn(@"Database file is not a directory. "
              "Use -replaceDatabaseNamed:withDatabaseFilewithAttachments:error: instead.");
        CBLStatusToOutNSError(kCBLStatusBadParam, outError);
        return NO;
    }

    return CBLRemoveFileIfExists(db.dir, outError) &&
            [fmgr copyItemAtPath: databaseDir toPath: db.dir error: outError] &&
            [db open: outError] &&
            [db saveLocalUUIDInLocalCheckpointDocument: outError] &&
            [db replaceUUIDs: outError];
}


- (NSString*) nameOfDatabaseAtPath: (NSString*)path {
    NSString* name = path.lastPathComponent.stringByDeletingPathExtension;
    return [name stringByReplacingOccurrencesOfString: @":" withString: @"/"];
}


- (NSString*) pathForDatabaseNamed: (NSString*)name {
    name = [[name stringByReplacingOccurrencesOfString: @"/" withString: @":"]
            stringByAppendingPathExtension: kDBExtension];
    return [_dir stringByAppendingPathComponent: name];
}


- (NSString*) pathForV1DatabaseNamed: (NSString*)name {
    name = [[name stringByReplacingOccurrencesOfString: @"/" withString: @":"]
            stringByAppendingPathExtension: kDBExtension];
    return [_dir stringByAppendingPathComponent: name];
}


// Instantiates a database but doesn't open the file yet.
- (CBLDatabase*) _databaseNamed: (NSString*)name
                      mustExist: (BOOL)mustExist
                          error: (NSError**)outError
{
    if (_options.readOnly)
        mustExist = YES;
    CBLDatabase* db = _databases[name];
    if (!db) {
        if (![[self class] isValidDatabaseName: name]) {
            CBLStatusToOutNSError(kCBLStatusBadID, outError);
            return nil;
        }
        db = [[CBLDatabase alloc] initWithDir: [self pathForDatabaseNamed: name]
                                         name: name
                                      manager: self
                                     readOnly: _options.readOnly];
        if (mustExist && !db.exists) {
            CBLStatusToOutNSError(kCBLStatusNotFound, outError);
            return nil;
        }
        _databases[name] = db;
        [_shared openedDatabase: name];
    }
    return db;
}


// Called when a database is being closed
- (void) _forgetDatabase: (CBLDatabase*)db {
    NSString* name = db.name;
    [_replications my_removeMatching: ^int(CBLReplication* repl) {
        return [repl localDatabase] == db;
    }];
    [_databases removeObjectForKey: name];
    [_shared closedDatabase: name];
}


#pragma mark - REPLICATION:


// Replication 'source' or 'target' property may be a string or a dictionary. Normalize to dict form
static NSDictionary* parseSourceOrTarget(NSDictionary* properties, NSString* key) {
    id value = properties[key];
    if ([value isKindOfClass: [NSDictionary class]])
        return value;
    else if ([value isKindOfClass: [NSString class]])
        return $dict({@"url", value});
    else
        return nil;
}


- (CBLStatus) parseReplicatorProperties: (NSDictionary*)properties
                            toDatabase: (CBLDatabase**)outDatabase   // may be NULL
                                remote: (NSURL**)outRemote          // may be NULL
                                isPush: (BOOL*)outIsPush
                          createTarget: (BOOL*)outCreateTarget
                               headers: (NSDictionary**)outHeaders
                            authorizer: (id<CBLAuthorizer>*)outAuthorizer
{
    // http://wiki.apache.org/couchdb/Replication
    NSDictionary* sourceDict = parseSourceOrTarget(properties, @"source");
    NSDictionary* targetDict = parseSourceOrTarget(properties, @"target");
    NSString* source = sourceDict[@"url"];
    NSString* target = targetDict[@"url"];
    if (!source || !target)
        return kCBLStatusBadRequest;

    *outCreateTarget = [$castIf(NSNumber, properties[@"create_target"]) boolValue];
    *outIsPush = NO;
    CBLDatabase* db = nil;
    NSDictionary* remoteDict = nil;
    BOOL targetIsLocal = [CBLManager isValidDatabaseName: target];
    if ([CBLManager isValidDatabaseName: source]) {
        // Push replication:
        if (targetIsLocal) {
            // This is a local-to-local replication. Turn the remote into a full URL to keep the
            // replicator happy:
            if (!NSClassFromString(@"CBL_URLProtocol"))
                return kCBLStatusServerError;  // Listener/router framework not installed
            NSError* error;
            CBLDatabase* targetDb;
            if (*outCreateTarget)
                targetDb = [self databaseNamed: target error: &error];
            else
                targetDb = [self existingDatabaseNamed: target error: &error];
            if (!targetDb)
                return CBLStatusFromNSError(error, kCBLStatusBadRequest);
            NSURL* targetURL = targetDb.internalURL;
            if (!targetURL)
                return kCBLStatusServerError;
            NSMutableDictionary* nuTarget = [targetDict mutableCopy];
            nuTarget[@"url"] = targetURL.absoluteString;
            targetDict = nuTarget;
        }
        remoteDict = targetDict;
        if (outDatabase)
            db = self[source];
        *outIsPush = YES;
    } else if (targetIsLocal) {
        // Pull replication:
        remoteDict = sourceDict;
        if (outDatabase) {
            if (*outCreateTarget) {
                NSError* error;
                db = [self _databaseNamed: target mustExist: NO error: &error];
                if (![db open: &error])
                    return CBLStatusFromNSError(error, kCBLStatusDBError);
            } else {
                db = self[target];
            }
        }
    } else {
        return kCBLStatusBadID;
    }

    NSURL* remote = [NSURL URLWithString: remoteDict[@"url"]];
    if (![@[@"http", @"https", @"cbl", @"ws", @"wss"] containsObject: remote.scheme.lowercaseString])
        return kCBLStatusBadRequest;
    if (outDatabase) {
        *outDatabase = db;
        if (!db)
            return kCBLStatusNotFound;
    }
    if (outRemote)
        *outRemote = remote;
    if (outHeaders)
        *outHeaders = $castIf(NSDictionary, remoteDict[@"headers"]);
    
    if (outAuthorizer) {
        *outAuthorizer = nil;
        NSDictionary* auth = $castIf(NSDictionary, remoteDict[@"auth"]);
        if (auth) {
            NSDictionary* oauth = $castIf(NSDictionary, auth[@"oauth"]);
            NSDictionary* persona = $castIf(NSDictionary, auth[@"persona"]);
            NSDictionary* facebook = $castIf(NSDictionary, auth[@"facebook"]);
            if (oauth) {
                NSString* consumerKey = $castIf(NSString, oauth[@"consumer_key"]);
                NSString* consumerSec = $castIf(NSString, oauth[@"consumer_secret"]);
                NSString* token = $castIf(NSString, oauth[@"token"]);
                NSString* tokenSec = $castIf(NSString, oauth[@"token_secret"]);
                NSString* sigMethod = $castIf(NSString, oauth[@"signature_method"]);
                *outAuthorizer = [[CBLOAuth1Authorizer alloc] initWithConsumerKey: consumerKey
                                                                   consumerSecret: consumerSec
                                                                            token: token
                                                                      tokenSecret: tokenSec
                                                                  signatureMethod: sigMethod];
            } else if (persona) {
                NSString* email = $castIf(NSString, persona[@"email"]);
                *outAuthorizer = [[CBLPersonaAuthorizer alloc] initWithEmailAddress: email];
            } else if (facebook) {
                NSString* email = $castIf(NSString, facebook[@"email"]);
                *outAuthorizer = [[CBLFacebookAuthorizer alloc] initWithEmailAddress: email];
            }
            if (!*outAuthorizer)
                Warn(@"Invalid authorizer settings: %@", auth);
        }
    }

    // Can't specify both a filter and doc IDs
    if (properties[@"filter"] && properties[@"doc_ids"])
        return kCBLStatusBadRequest;
    
    return kCBLStatusOK;
}


- (CBLStatus) validateReplicatorProperties: (NSDictionary*)properties {
    BOOL push, createTarget;
    return [self parseReplicatorProperties: properties toDatabase: NULL
                                    remote: NULL isPush: &push createTarget: &createTarget
                                   headers: NULL
                                authorizer: NULL];
}


- (Class) replicatorClass {
    if (!_replicatorClass) {
        _replicatorClass = NSClassFromString(_replicatorClassName);
        Assert(_replicatorClass, @"CBLManager.replicatorClassName is '%@' but no such class found",
               _replicatorClassName);
        Assert([_replicatorClass conformsToProtocol: @protocol(CBL_Replicator)],
               @"CBLManager.replicatorClassName is '%@' but class doesn't implement CBL_Replicator",
               _replicatorClassName);
    }
    return _replicatorClass;
}


- (id<CBL_Replicator>) replicatorWithProperties: (NSDictionary*)properties
                                         status: (CBLStatus*)outStatus
{
    // Extract the parameters from the JSON request body:
    // http://wiki.apache.org/couchdb/Replication
    CBLDatabase* db;
    CBLStatus status;
    CBL_ReplicatorSettings* settings = [self replicatorSettingsWithProperties: properties
                                                                   toDatabase: &db
                                                                       status: &status];
    if (CBLStatusIsError(status)) {
        if (outStatus)
            *outStatus = status;
        return nil;
    }

    id<CBL_Replicator> repl = [[self.replicatorClass alloc] initWithDB: db settings: settings];
    if (!repl) {
        if (outStatus)
            *outStatus = kCBLStatusServerError;
        return nil;
    }

    // If this is a duplicate, reuse an existing replicator:
    id<CBL_Replicator> existing = [db activeReplicatorLike: repl];
    if (existing)
        repl = existing;

    if (outStatus)
        *outStatus = kCBLStatusOK;
    return repl;
}


- (CBL_ReplicatorSettings*) replicatorSettingsWithProperties: (NSDictionary*)properties
                                                  toDatabase: (CBLDatabase**)outDatabase
                                                      status: (CBLStatus*)outStatus {
    // Extract the parameters from the JSON request body:
    // http://wiki.apache.org/couchdb/Replication
    NSURL* remote;
    BOOL push, createTarget;
    NSDictionary* headers;
    id<CBLAuthorizer> authorizer;
    CBLDatabase* database;

    CBLStatus status = [self parseReplicatorProperties: properties
                                            toDatabase: &database
                                                remote: &remote
                                                isPush: &push
                                          createTarget: &createTarget
                                               headers: &headers
                                            authorizer: &authorizer];
    if (outStatus)
        *outStatus = status;

    if (CBLStatusIsError(status))
        return nil;

    NSString* filterName = $castIf(NSString, properties[@"filter"]);
    NSArray* docIDs = $castIf(NSArray, properties[@"doc_ids"]);

    CBL_ReplicatorSettings* settings = [[CBL_ReplicatorSettings alloc] initWithRemote: remote
                                                                                 push: push];
    settings.continuous = [$castIf(NSNumber, properties[@"continuous"]) boolValue];
    settings.filterName = filterName;
    settings.filterParameters = $castIf(NSDictionary, properties[@"query_params"]);
    settings.docIDs = docIDs;
    settings.options = properties;
    settings.requestHeaders = headers;
    settings.authorizer = authorizer;
    settings.createTarget = push && createTarget;

    if (![settings compilePushFilterForDatabase: database status: outStatus])
        return nil;

    if (outDatabase)
        *outDatabase = database;

    return settings;
}


@end
