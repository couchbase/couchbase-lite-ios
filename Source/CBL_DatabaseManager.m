//
//  CBL_DatabaseManager.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/22/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBL_DatabaseManager.h"
#import "CBL_Database.h"
#import "CBLOAuth1Authorizer.h"
#import "CBLBrowserIDAuthorizer.h"
#import "CBL_Pusher.h"
#import "CBL_ReplicatorManager.h"
#import "CBLInternal.h"
#import "CBLMisc.h"


const CBL_DatabaseManagerOptions kCBL_DatabaseManagerDefaultOptions;


@implementation CBL_DatabaseManager


#define kDBExtension @"touchdb" // For backward compatibility reasons we're not changing this

// http://wiki.apache.org/couchdb/HTTP_database_API#Naming_and_Addressing
#define kLegalChars @"abcdefghijklmnopqrstuvwxyz0123456789_$()+-/"
static NSCharacterSet* kIllegalNameChars;

+ (void) initialize {
    if (self == [CBL_DatabaseManager class]) {
        kIllegalNameChars = [[NSCharacterSet characterSetWithCharactersInString: kLegalChars]
                                        invertedSet];
    }
}


#if DEBUG
+ (CBL_DatabaseManager*) createEmptyAtPath: (NSString*)path {
    [[NSFileManager defaultManager] removeItemAtPath: path error: NULL];
    NSError* error;
    CBL_DatabaseManager* dbm = [[self alloc] initWithDirectory: path
                                                     options: NULL
                                                       error: &error];
    Assert(dbm, @"Failed to create db manager at %@: %@", path, error);
    AssertEqual(dbm.directory, path);
    return dbm;
}

+ (CBL_DatabaseManager*) createEmptyAtTemporaryPath: (NSString*)name {
    return [self createEmptyAtPath: [NSTemporaryDirectory() stringByAppendingPathComponent: name]];
}
#endif


+ (NSString*) defaultDirectory {
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                         NSUserDomainMask, YES);
    NSString* path = paths[0];
#if !TARGET_OS_IPHONE
    path = [path stringByAppendingPathComponent: [[NSBundle mainBundle] bundleIdentifier]];
#endif
    return [path stringByAppendingPathComponent: @"CouchbaseLite"];
}


- (id) initWithDirectory: (NSString*)dirPath
                 options: (const CBL_DatabaseManagerOptions*)options
                   error: (NSError**)outError
{
    if (outError) *outError = nil;
    self = [super init];
    if (self) {
        _dir = [dirPath copy];
        _databases = [[NSMutableDictionary alloc] init];
        _options = options ? *options : kCBL_DatabaseManagerDefaultOptions;
        
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
    }
    return self;
}


- (void)dealloc {
    LogTo(CBL_Server, @"DEALLOC %@", self);
    [self close];
}


@synthesize directory = _dir;


#pragma mark - DATABASES:


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


- (CBL_Database*) databaseNamed: (NSString*)name create: (BOOL)create {
    if (_options.readOnly)
        create = NO;
    CBL_Database* db = _databases[name];
    if (!db) {
        NSString* path = [self pathForName: name];
        if (!path)
            return nil;
        db = [[CBL_Database alloc] initWithPath: path];
        db.readOnly = _options.readOnly;
        if (!create && !db.exists) {
            return nil;
        }
        db.name = name;
        _databases[name] = db;
    }
    return db;
}


- (CBL_Database*) databaseNamed: (NSString*)name {
    return [self databaseNamed: name create: YES];
}


- (CBL_Database*) existingDatabaseNamed: (NSString*)name {
    CBL_Database* db = [self databaseNamed: name create: NO];
    if (db && ![db open])
        db = nil;
    return db;
}


- (BOOL) deleteDatabase: (CBL_Database*)db error: (NSError**)outError {
    if (![db deleteDatabase: outError])
        return NO;
    [_databases removeObjectForKey: db.name];
    return YES;
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


- (void) close {
    LogTo(CBL_Server, @"CLOSING %@ ...", self);
    [_replicatorManager stop];
    _replicatorManager = nil;
    for (CBL_Database* db in _databases.allValues) {
        [db close];
    }
    [_databases removeAllObjects];
    LogTo(CBL_Server, @"CLOSED %@", self);
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
    if ([CBL_DatabaseManager isValidDatabaseName: source]) {
        if (outDatabase)
            db = [self existingDatabaseNamed: source];
        remoteDict = targetDict;
        *outIsPush = YES;
    } else {
        if (![CBL_DatabaseManager isValidDatabaseName: target])
            return kCBLStatusBadID;
        remoteDict = sourceDict;
        if (outDatabase) {
            if (*outCreateTarget) {
                db = [self databaseNamed: target];
                if (![db open])
                    return kCBLStatusDBError;
            } else {
                db = [self existingDatabaseNamed: target];
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
    if (!_replicatorManager && !_options.noReplicator) {
        LogTo(CBL_Server, @"Starting replicator manager for %@", self);
        _replicatorManager = [[CBL_ReplicatorManager alloc] initWithDatabaseManager: self];
        [_replicatorManager start];
    }
    return _replicatorManager;
}


@end




#pragma mark - TESTS
#if DEBUG

TestCase(CBL_DatabaseManager) {
    RequireTestCase(CBL_Database);
    CBL_DatabaseManager* dbm = [CBL_DatabaseManager createEmptyAtTemporaryPath: @"CBL_DatabaseManagerTest"];
    CBL_Database* db = [dbm databaseNamed: @"foo"];
    CAssert(db != nil);
    CAssertEqual(db.name, @"foo");
    CAssertEqual(db.path.stringByDeletingLastPathComponent, dbm.directory);
    CAssert(!db.exists);
    
    CAssertEq([dbm databaseNamed: @"foo"], db);
    
    CAssertEqual(dbm.allDatabaseNames, @[]);    // because foo doesn't exist yet
    
    CAssert([db open]);
    CAssert(db.exists);
    CAssertEqual(dbm.allDatabaseNames, @[@"foo"]);    // because foo doesn't exist yet
}

#endif
