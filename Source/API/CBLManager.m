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
#import "CBL_Pusher.h"
#import "CBL_Server.h"
#import "CBL_URLProtocol.h"
#import "CBLPersonaAuthorizer.h"
#import "CBLFacebookAuthorizer.h"
#import "CBLOAuth1Authorizer.h"
#import "CBL_Shared.h"
#import "CBLInternal.h"
#import "CBLMisc.h"
#import "CBLStatus.h"
#import "MYBlockUtils.h"


#define kOldDBExtension @"touchdb" // Used before CBL beta 1
#define kDBExtension @"cblite"


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

static NSString* CBLFullVersionInfo( void ) {
    NSMutableString* vers = [NSMutableString stringWithFormat: @"Couchbase Lite %@", CBLVersion()];
#ifdef CBL_SOURCE_REVISION
    if (strlen(CBL_SOURCE_REVISION) > (0))
        [vers appendFormat: @"; git commit %s", CBL_SOURCE_REVISION];
#endif
    return vers;
}


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
    NSMutableArray* _replications;
    __weak CBL_Shared *_shared;
    id _strongShared;       // optional strong reference to _shared
}


@synthesize dispatchQueue=_dispatchQueue, directory = _dir;
@synthesize customHTTPHeaders = _customHTTPHeaders;


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
    EnableLog(YES);
    if (type != nil)
        _EnableLogTo(type, YES);
}

+ (void) redirectLogging: (void (^)(NSString* type, NSString* message))callback {
    MYLoggingCallback = callback;
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
    if (!self)
        Warn(@"Failed to create CBLManager: %@", error);
    
    _customHTTPHeaders = [NSMutableDictionary dictionary];
    
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
        if (![[NSFileManager defaultManager] createDirectoryAtPath: _dir
                                       withIntermediateDirectories: YES
                                                        attributes: nil
                                                             error: &error]) {
            if (!CBLIsFileExistsError(error)) {
                if (outError) *outError = error;
                return nil;
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
        LogTo(CBLDatabase, @"Created %@", self);
    }
    return self;
}


#if DEBUG
+ (instancetype) createEmptyAtPath: (NSString*)path {
    [[NSFileManager defaultManager] removeItemAtPath: path error: NULL];
    NSError* error;
    CBLManager* dbm = [[self alloc] initWithDirectory: path
                                              options: NULL
                                                error: &error];
    Assert(dbm, @"Failed to create db manager at %@: %@", path, error);
    AssertEqual(dbm.directory, path);
    AfterThisTest(^{
        [dbm close];
        [[NSFileManager defaultManager] removeItemAtPath: path error: NULL];
    });
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
    
    managerCopy.customHTTPHeaders = [self.customHTTPHeaders copy];
    
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


// Scan my dir for older ".touchdb" databases & rename them to ".cblite"
- (void) upgradeOldDatabaseFiles {
    NSFileManager* fmgr = [NSFileManager defaultManager];
    NSArray* files = [fmgr contentsOfDirectoryAtPath: _dir error: NULL];
    for (NSString* filename in [files pathsMatchingExtensions: @[kOldDBExtension]]) {
        NSString* oldPath = [_dir stringByAppendingPathComponent: filename];
        NSString* newPath = [oldPath.stringByDeletingPathExtension
                                            stringByAppendingPathExtension: kDBExtension];
        Log(@"Renaming old database file %@", oldPath);
        for (NSString* suffix in @[@"", @"-wal", @"-shm"]) {
            NSError* error;
            BOOL ok = [[NSFileManager defaultManager]
                    moveItemAtPath: [oldPath stringByAppendingString: suffix]
                            toPath: [newPath stringByAppendingString: suffix]
                             error: &error];
            if (!ok)
                Warn(@"Couldn't move %@: %@", oldPath, error);
        }
    }
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


#if TARGET_OS_IPHONE
- (NSDataWritingOptions) fileProtection {
    return _options.fileProtection & NSDataWritingFileProtectionMask;
}
#endif


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
                server = [[CBL_Server alloc] initWithManager: newManager];
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
    return [files my_map: ^(id filename) {
        return [[filename stringByDeletingPathExtension]
                stringByReplacingOccurrencesOfString: @":" withString: @"/"];
    }];
}


- (NSArray*) allOpenDatabases {
    return _databases.allValues;
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
    NSString* dstAttachmentsPath = db.attachmentStorePath;
    NSFileManager* fmgr = [NSFileManager defaultManager];
    return [fmgr copyItemAtPath: databasePath toPath: db.path error: outError] &&
            CBLRemoveFileIfExists(dstAttachmentsPath, outError) &&
            (!attachmentsPath || [fmgr copyItemAtPath: attachmentsPath
                                               toPath: dstAttachmentsPath
                                                error: outError]) &&
            [db open: outError] &&
            [db replaceUUIDs: outError];
}


@end




@implementation CBLManager (Internal)


- (NSString*) pathForDatabaseNamed: (NSString*)name {
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
            if (outError)
                *outError = CBLStatusToNSError(kCBLStatusBadID, nil);
            return nil;
        }
        db = [[CBLDatabase alloc] initWithPath: [self pathForDatabaseNamed: name]
                                          name: name
                                       manager: self
                                      readOnly: _options.readOnly];
        if (mustExist && !db.exists) {
            if (outError)
                *outError = CBLStatusToNSError(kCBLStatusNotFound, nil);
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
                return kCBLStatusServerError;   // Listener/router framework not installed
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
                db = [self _databaseNamed: target mustExist: NO error: NULL];
                if (![db open: NULL])
                    return kCBLStatusDBError;
            } else {
                db = self[target];
            }
        }
    } else {
        return kCBLStatusBadID;
    }

    NSURL* remote = [NSURL URLWithString: remoteDict[@"url"]];
    if (![@[@"http", @"https", @"cbl"] containsObject: remote.scheme.lowercaseString])
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


- (CBL_Replicator*) replicatorWithProperties: (NSDictionary*)properties
                                      status: (CBLStatus*)outStatus
{
    // An unfortunate limitation:
    Assert(_dispatchQueue==NULL || _dispatchQueue==dispatch_get_main_queue(),
           @"CBLReplicators need a thread not a dispatch queue");
    
    // Extract the parameters from the JSON request body:
    // http://wiki.apache.org/couchdb/Replication
    CBLDatabase* db;
    NSURL* remote;
    BOOL push, createTarget;
    NSDictionary* headers;
    id<CBLAuthorizer> authorizer;

    CBLStatus status = [self parseReplicatorProperties: properties
                                            toDatabase: &db remote: &remote
                                                isPush: &push
                                          createTarget: &createTarget
                                               headers: &headers
                                            authorizer: &authorizer];
    if (CBLStatusIsError(status)) {
        if (outStatus)
            *outStatus = status;
        return nil;
    }

    BOOL continuous = [$castIf(NSNumber, properties[@"continuous"]) boolValue];

    CBL_Replicator* repl = [[CBL_Replicator alloc] initWithDB: db
                                                       remote: remote
                                                         push: push
                                                   continuous: continuous];
    if (!repl) {
        if (outStatus)
            *outStatus = kCBLStatusServerError;
        return nil;
    }

    repl.filterName = $castIf(NSString, properties[@"filter"]);
    repl.filterParameters = $castIf(NSDictionary, properties[@"query_params"]);
    repl.docIDs = $castIf(NSArray, properties[@"doc_ids"]);
    repl.options = properties;
    repl.requestHeaders = headers;
    repl.authorizer = authorizer;
    if (push)
        ((CBL_Pusher*)repl).createTarget = createTarget;

    // If this is a duplicate, reuse an existing replicator:
    CBL_Replicator* existing = [db activeReplicatorLike: repl];
    if (existing)
        repl = existing;

    if (outStatus)
        *outStatus = kCBLStatusOK;
    return repl;
}


@end




#pragma mark - TESTS
#if DEBUG

TestCase(CBLManager) {
    RequireTestCase(CBLDatabase);

    for (NSString* name in @[@"f", @"foo123", @"foo/($12)", @"f+-_00/"])
        CAssert([CBLManager isValidDatabaseName: name]);
    NSMutableString* longName = [@"long" mutableCopy];
    while (longName.length < 240)
        [longName appendString: @"!"];
    for (NSString* name in @[@"", @"0", @"123foo", @"Foo", @"/etc/passwd", @"foo ", @"_foo", longName])
        CAssert(![CBLManager isValidDatabaseName: name], @"Db name '%@' should not be valid", name);

    CBLManager* dbm = [CBLManager createEmptyAtTemporaryPath: @"CBLManagerTest"];
    CAssertEqual(dbm.allDatabaseNames, @[]);
    CBLDatabase* db = [dbm existingDatabaseNamed: @"foo" error: NULL];
    CAssert(db == nil);
    
    db = [dbm databaseNamed: @"foo" error: NULL];
    CAssert(db != nil);
    CAssertEqual(db.name, @"foo");
    CAssertEqual(db.path.stringByDeletingLastPathComponent, dbm.directory);
    CAssert(db.exists);
    CAssertEqual(dbm.allDatabaseNames, @[@"foo"]);

    CAssertEq([dbm existingDatabaseNamed: @"foo" error: NULL], db);
    [dbm close];
}

TestCase(CBLManager_Close) {
    RequireTestCase(CBLManager);

    CBLManager* mgrMain = [CBLManager createEmptyAtTemporaryPath: @"CBLManagerTest"];

    CBLManager* mgr1 = [mgrMain copy];
    CBLDatabase* db = [mgr1 databaseNamed: @"test_db" error: NULL];
    CAssert(db);
    
    CBLManager* mgr2 = [mgrMain copy];
    db = [mgr2 databaseNamed: @"test_db" error: NULL];
    CAssert(db);
    
    [mgr1 close];
    NSInteger count = [mgrMain.shared countForOpenedDatabase: @"test_db"];
    CAssertEq(count, 1);
    
    [mgr2 close];
    count = [mgrMain.shared countForOpenedDatabase: @"test_db"];
    CAssertEq(count, 0);
    
    [mgrMain close];
}

#endif
