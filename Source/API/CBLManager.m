//
//  CBLManager.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/19/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "CBLManager.h"
#import "CouchbaseLitePrivate.h"

#import "CBL_Database.h"
#import "CBL_Database+Attachments.h"
#import "CBLManager+Internal.h"
#import "CBL_Pusher.h"
#import "CBL_ReplicatorManager.h"
#import "CBL_Server.h"
#import "CBL_URLProtocol.h"
#import "CBLBrowserIDAuthorizer.h"
#import "CBLOAuth1Authorizer.h"
#import "CBLInternal.h"
#import "CBLMisc.h"
#import "CBLStatus.h"


#define kDBExtension @"touchdb" // For backward compatibility reasons we're not changing this


static const CBLManagerOptions kCBLManagerDefaultOptions;


@implementation CBLManager
{
    NSString* _dir;
    CBLManagerOptions _options;
    NSMutableDictionary* _databases;
    CBL_ReplicatorManager* _replicatorManager;
    CBL_Server* _server;
    NSURL* _internalURL;
    NSMutableArray* _replications;
}


// http://wiki.apache.org/couchdb/HTTP_database_API#Naming_and_Addressing
#define kLegalChars @"abcdefghijklmnopqrstuvwxyz0123456789_$()+-/"
static NSCharacterSet* kIllegalNameChars;

+ (void) initialize {
    if (self == [CBLManager class]) {
        kIllegalNameChars = [[NSCharacterSet characterSetWithCharactersInString: kLegalChars]
                             invertedSet];
    }
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


+ (instancetype) sharedInstance {
    static CBLManager* sInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sInstance = [[self alloc] init];
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
    return self;
}


- (instancetype) initWithDirectory: (NSString*)directory
                           options: (const CBLManagerOptions*)options
                             error: (NSError**)outError
{
    if (outError) *outError = nil;
    self = [super init];
    if (self) {
        _dir = [directory copy];
        _databases = [[NSMutableDictionary alloc] init];
        _options = options ? *options : kCBLManagerDefaultOptions;

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

        _replications = [[NSMutableArray alloc] init];

        if (!_options.noReplicator) {
            LogTo(CBLDatabase, @"Starting replicator manager for %@", self);
            _replicatorManager = [[CBL_ReplicatorManager alloc] initWithDatabaseManager: self];
            [_replicatorManager start];
        }
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
    return dbm;
}

+ (instancetype) createEmptyAtTemporaryPath: (NSString*)name {
    return [self createEmptyAtPath: [NSTemporaryDirectory() stringByAppendingPathComponent: name]];
}
#endif


- (id) copyWithZone: (NSZone*)zone {
    CBLManagerOptions options = _options;
    options.noReplicator = true;        // Don't want to run multiple replicator tasks
    return [[[self class] alloc] initWithDirectory: self.directory options: &options error: NULL];
}


- (void) close {
    LogTo(CBLDatabase, @"CLOSING %@ ...", self);
    [_server close];
    _server = nil;
    [_replicatorManager stop];
    _replicatorManager = nil;
    for (CBL_Database* db in _databases.allValues) {
        [db close];
    }
    [_databases removeAllObjects];
    LogTo(CBLDatabase, @"CLOSED %@", self);
}


- (void)dealloc
{
    [self close];
}


@synthesize directory = _dir;


- (NSString*) description {
    return $sprintf(@"%@[%@]", [self class], self.directory);
}


- (CBL_Server*) backgroundServer {
    if (!_server) {
        CBLManagerOptions tdOptions = {
            .readOnly = _options.readOnly,
            .noReplicator = true
        };
        _server = [[CBL_Server alloc] initWithDirectory: self.directory
                                                options: &tdOptions
                                                  error: nil];
        LogTo(CBLDatabase, @"%@ created %@", self, _server);
    }
    return _server;
}


- (NSURL*) internalURL {
    if (!_internalURL) {
        if (!self.backgroundServer)
            return nil;
        Class tdURLProtocol = NSClassFromString(@"CBL_URLProtocol");
        Assert(tdURLProtocol, @"CBL_URLProtocol class not found; link CouchbaseLiteListener.framework");
        _internalURL = [tdURLProtocol HTTPURLForServerURL: [tdURLProtocol registerServer: _server]];
    }
    return _internalURL;
}


#pragma mark - DATABASES (PUBLIC API):


+ (BOOL) isValidDatabaseName: (NSString*)name {
    if (name.length > 0 && [name rangeOfCharacterFromSet: kIllegalNameChars].length == 0
        && islower([name characterAtIndex: 0]))
        return YES;
    return $equal(name, kCBL_ReplicatorDatabaseName);
}


- (NSString*) pathForName: (NSString*)name {
    if (![[self class] isValidDatabaseName: name])
        return nil;
    name = [name stringByReplacingOccurrencesOfString: @"/" withString: @":"];
    return [_dir stringByAppendingPathComponent:[name stringByAppendingPathExtension:kDBExtension]];
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


- (CBLDatabase*) databaseNamed: (NSString*)name {
    return [self _existingDatabaseNamed: name];
}

- (CBLDatabase*) objectForKeyedSubscript:(NSString*)key {
    return [self databaseNamed: key];
}

- (CBLDatabase*) createDatabaseNamed: (NSString*)name error: (NSError**)outError {
    CBL_Database* db = [self _databaseNamed: name];
    if (![db open: outError])
        return nil;
    return db;
}


- (BOOL) replaceDatabaseNamed: (NSString*)databaseName
             withDatabaseFile: (NSString*)databasePath
              withAttachments: (NSString*)attachmentsPath
                        error: (NSError**)outError
{
    CBL_Database* db = [self _databaseNamed: databaseName];
    if (!db) {
        if (outError)
            *outError = CBLStatusToNSError(kCBLStatusBadID, nil);
        return NO;
    }
    Assert(!db.open, @"Already-open database cannot be replaced");
    NSString* dstAttachmentsPath = db.attachmentStorePath;
    NSFileManager* fmgr = [NSFileManager defaultManager];
    return [fmgr copyItemAtPath: databasePath toPath: db.path error: outError] &&
    CBLRemoveFileIfExists(dstAttachmentsPath, outError) &&
    (!attachmentsPath || [fmgr copyItemAtPath: attachmentsPath
                                       toPath: dstAttachmentsPath
                                        error: outError]);

}


#pragma mark - REPLICATIONs (PUBLIC API):


- (NSArray*) allReplications {
    NSMutableArray* replications = [_replications mutableCopy];
    CBLQuery* q = [[self databaseNamed: @"_replicator"] queryAllDocuments];
    for (CBLQueryRow* row in q.rows) {
        CBLReplication* repl = [CBLReplication modelForDocument: row.document];
        if (![replications containsObject: repl])
            [replications addObject: repl];
    }
    return replications;
}


- (CBLReplication*) replicationWithDatabase: (CBLDatabase*)db
                                       remote: (NSURL*)remote
                                         pull: (BOOL)pull
                                       create: (BOOL)create
{
    for (CBLReplication* repl in self.allReplications) {
        if (repl.localDatabase == db && $equal(repl.remoteURL, remote) && repl.pull == pull)
            return repl;
    }
    if (!create)
        return nil;
    CBLReplication* repl = [[CBLReplication alloc] initWithDatabase: db
                                                           remote: remote
                                                             pull: pull];
    [_replications addObject: repl];
    return repl;
}


- (NSArray*) createReplicationsBetween: (CBLDatabase*)database
                                   and: (NSURL*)otherDbURL
                           exclusively: (bool)exclusively
{
    CBLReplication* pull = nil, *push = nil;
    if (otherDbURL) {
        pull = [self replicationWithDatabase: database remote: otherDbURL
                                                          pull: YES create: YES];
        push = [self replicationWithDatabase: database remote: otherDbURL
                                                          pull: NO create: YES];
        if (!pull || !push)
            return nil;
    }
    if (exclusively) {
        for (CBLReplication* repl in self.allReplications) {
            if (repl.localDatabase == database && repl != pull && repl != push) {
                [repl deleteDocument: nil];
            }
        }
    }
    return otherDbURL ? $array(pull, push) : nil;
}


@end




@implementation CBLManager (Internal)


- (CBL_Database*) _databaseNamed: (NSString*)name create: (BOOL)create {
    if (_options.readOnly)
        create = NO;
    CBL_Database* db = _databases[name];
    if (!db) {
        NSString* path = [self pathForName: name];
        if (!path)
            return nil;
        db = [[CBL_Database alloc] initWithPath: path
                                           name: name
                                        manager: self
                                       readOnly: _options.readOnly];
        if (!create && !db.exists) {
            return nil;
        }
        _databases[name] = db;
    }
    return db;
}


- (CBL_Database*) _databaseNamed: (NSString*)name {
    return [self _databaseNamed: name create: YES];
}


- (CBL_Database*) _existingDatabaseNamed: (NSString*)name {
    CBL_Database* db = [self _databaseNamed: name create: NO];
    if (db && ![db open: nil])
        db = nil;
    return db;
}


- (void) _forgetDatabase: (CBL_Database*)db {
    [_databases removeObjectForKey: db.name];
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
                            toDatabase: (CBL_Database**)outDatabase   // may be NULL
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
    CBL_Database* db = nil;
    NSDictionary* remoteDict = nil;
    if ([CBLManager isValidDatabaseName: source]) {
        if (outDatabase)
            db = [self _existingDatabaseNamed: source];
        remoteDict = targetDict;
        *outIsPush = YES;
    } else {
        if (![CBLManager isValidDatabaseName: target])
            return kCBLStatusBadID;
        remoteDict = sourceDict;
        if (outDatabase) {
            if (*outCreateTarget) {
                db = [self _databaseNamed: target];
                if (![db open: nil])
                    return kCBLStatusDBError;
            } else {
                db = [self _existingDatabaseNamed: target];
            }
        }
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
            } else {
                NSDictionary* browserid = $castIf(NSDictionary, auth[@"browserid"]);
                if (browserid) {
                    NSString* email = $castIf(NSString, browserid[@"email"]);
                    *outAuthorizer = [[CBLBrowserIDAuthorizer alloc] initWithEmailAddress: email];
                }
            }
            if (!*outAuthorizer)
                Warn(@"Invalid authorizer settings: %@", auth);
        }
    }
    
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
    // Extract the parameters from the JSON request body:
    // http://wiki.apache.org/couchdb/Replication
    CBL_Database* db;
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
    repl.options = properties;
    repl.requestHeaders = headers;
    repl.authorizer = authorizer;
    if (push)
        ((CBL_Pusher*)repl).createTarget = createTarget;

    if (outStatus)
        *outStatus = kCBLStatusOK;
    return repl;
}


- (CBL_ReplicatorManager*) replicatorManager {
    return _replicatorManager;
}


@end




#pragma mark - TESTS
#if DEBUG

TestCase(CBLManager) {
    RequireTestCase(CBL_Database);
    CBLManager* dbm = [CBLManager createEmptyAtTemporaryPath: @"CBLManagerTest"];
    CBL_Database* db = [dbm _databaseNamed: @"foo"];
    CAssert(db != nil);
    CAssertEqual(db.name, @"foo");
    CAssertEqual(db.path.stringByDeletingLastPathComponent, dbm.directory);
    CAssert(!db.exists);
    
    CAssertEq([dbm _databaseNamed: @"foo"], db);
    
    CAssertEqual(dbm.allDatabaseNames, @[]);    // because foo doesn't exist yet
    
    CAssert([db open: nil]);
    CAssert(db.exists);
    CAssertEqual(dbm.allDatabaseNames, @[@"foo"]);    // because foo doesn't exist yet
}

#endif
