//
//  TD_DatabaseManager.m
//  TouchDB
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

#import "TD_DatabaseManager.h"
#import "TD_Database.h"
#import "TDOAuth1Authorizer.h"
#import "TDBrowserIDAuthorizer.h"
#import "TDPusher.h"
#import "TDReplicatorManager.h"
#import "TDInternal.h"
#import "TDMisc.h"


const TD_DatabaseManagerOptions kTD_DatabaseManagerDefaultOptions;


@implementation TD_DatabaseManager


#define kDBExtension @"touchdb"

// http://wiki.apache.org/couchdb/HTTP_database_API#Naming_and_Addressing
#define kLegalChars @"abcdefghijklmnopqrstuvwxyz0123456789_$()+-/"
static NSCharacterSet* kIllegalNameChars;

+ (void) initialize {
    if (self == [TD_DatabaseManager class]) {
        kIllegalNameChars = [[NSCharacterSet characterSetWithCharactersInString: kLegalChars]
                                        invertedSet];
    }
}


#if DEBUG
+ (TD_DatabaseManager*) createEmptyAtPath: (NSString*)path {
    [[NSFileManager defaultManager] removeItemAtPath: path error: NULL];
    NSError* error;
    TD_DatabaseManager* dbm = [[self alloc] initWithDirectory: path
                                                     options: NULL
                                                       error: &error];
    Assert(dbm, @"Failed to create db manager at %@: %@", path, error);
    AssertEqual(dbm.directory, path);
    return dbm;
}

+ (TD_DatabaseManager*) createEmptyAtTemporaryPath: (NSString*)name {
    return [self createEmptyAtPath: [NSTemporaryDirectory() stringByAppendingPathComponent: name]];
}
#endif


- (id) initWithDirectory: (NSString*)dirPath
                 options: (const TD_DatabaseManagerOptions*)options
                   error: (NSError**)outError
{
    if (outError) *outError = nil;
    self = [super init];
    if (self) {
        _dir = [dirPath copy];
        _databases = [[NSMutableDictionary alloc] init];
        _options = options ? *options : kTD_DatabaseManagerDefaultOptions;
        
        // Create the directory but don't fail if it already exists:
        NSError* error;
        if (![[NSFileManager defaultManager] createDirectoryAtPath: _dir
                                       withIntermediateDirectories: NO
                                                        attributes: nil
                                                             error: &error]) {
            if (!TDIsFileExistsError(error)) {
                if (outError) *outError = error;
                return nil;
            }
        }
    }
    return self;
}


- (void)dealloc {
    LogTo(TD_Server, @"DEALLOC %@", self);
    [self close];
}


@synthesize directory = _dir;


#pragma mark - DATABASES:


+ (BOOL) isValidDatabaseName: (NSString*)name {
    if (name.length > 0 && [name rangeOfCharacterFromSet: kIllegalNameChars].length == 0
                        && islower([name characterAtIndex: 0]))
        return YES;
    return $equal(name, kTDReplicatorDatabaseName);
}


- (NSString*) pathForName: (NSString*)name {
    if (![[self class] isValidDatabaseName: name])
        return nil;
    name = [name stringByReplacingOccurrencesOfString: @"/" withString: @":"];
    return [_dir stringByAppendingPathComponent:[name stringByAppendingPathExtension:kDBExtension]];
}


- (TD_Database*) databaseNamed: (NSString*)name create: (BOOL)create {
    if (_options.readOnly)
        create = NO;
    TD_Database* db = _databases[name];
    if (!db) {
        NSString* path = [self pathForName: name];
        if (!path)
            return nil;
        db = [[TD_Database alloc] initWithPath: path];
        db.readOnly = _options.readOnly;
        if (!create && !db.exists) {
            return nil;
        }
        db.name = name;
        _databases[name] = db;
    }
    return db;
}


- (TD_Database*) databaseNamed: (NSString*)name {
    return [self databaseNamed: name create: YES];
}


- (TD_Database*) existingDatabaseNamed: (NSString*)name {
    TD_Database* db = [self databaseNamed: name create: NO];
    if (db && ![db open])
        db = nil;
    return db;
}


- (BOOL) deleteDatabaseNamed: (NSString*)name {
    TD_Database* db = [self databaseNamed: name];
    if (!db)
        return NO;
    [db deleteDatabase: NULL];
    [_databases removeObjectForKey: name];
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
    LogTo(TD_Server, @"CLOSING %@ ...", self);
    [_replicatorManager stop];
    _replicatorManager = nil;
    for (TD_Database* db in _databases.allValues) {
        [db close];
    }
    [_databases removeAllObjects];
    LogTo(TD_Server, @"CLOSED %@", self);
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


- (TDStatus) parseReplicatorProperties: (NSDictionary*)properties
                            toDatabase: (TD_Database**)outDatabase   // may be NULL
                                remote: (NSURL**)outRemote          // may be NULL
                                isPush: (BOOL*)outIsPush
                          createTarget: (BOOL*)outCreateTarget
                               headers: (NSDictionary**)outHeaders
                            authorizer: (id<TDAuthorizer>*)outAuthorizer
{
    // http://wiki.apache.org/couchdb/Replication
    NSDictionary* sourceDict = parseSourceOrTarget(properties, @"source");
    NSDictionary* targetDict = parseSourceOrTarget(properties, @"target");
    NSString* source = sourceDict[@"url"];
    NSString* target = targetDict[@"url"];
    if (!source || !target)
        return kTDStatusBadRequest;

    *outCreateTarget = [$castIf(NSNumber, properties[@"create_target"]) boolValue];
    *outIsPush = NO;
    TD_Database* db = nil;
    NSDictionary* remoteDict = nil;
    if ([TD_DatabaseManager isValidDatabaseName: source]) {
        if (outDatabase)
            db = [self existingDatabaseNamed: source];
        remoteDict = targetDict;
        *outIsPush = YES;
    } else {
        if (![TD_DatabaseManager isValidDatabaseName: target])
            return kTDStatusBadID;
        remoteDict = sourceDict;
        if (outDatabase) {
            if (*outCreateTarget) {
                db = [self databaseNamed: target];
                if (![db open])
                    return kTDStatusDBError;
            } else {
                db = [self existingDatabaseNamed: target];
            }
        }
    }
    NSURL* remote = [NSURL URLWithString: remoteDict[@"url"]];
    if (![@[@"http", @"https", @"touchdb"] containsObject: remote.scheme.lowercaseString])
        return kTDStatusBadRequest;
    if (outDatabase) {
        *outDatabase = db;
        if (!db)
            return kTDStatusNotFound;
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
                *outAuthorizer = [[TDOAuth1Authorizer alloc] initWithConsumerKey: consumerKey
                                                                   consumerSecret: consumerSec
                                                                            token: token
                                                                      tokenSecret: tokenSec
                                                                  signatureMethod: sigMethod];
            } else {
                NSDictionary* browserid = $castIf(NSDictionary, auth[@"browserid"]);
                if (browserid) {
                    NSString* assertion = $castIf(NSString, browserid[@"assertion"]);
                    *outAuthorizer = [[TDBrowserIDAuthorizer alloc] initWithAssertion: assertion];
                }
            }
            if (!*outAuthorizer)
                return kTDStatusBadRequest;
        }
    }
    
    return kTDStatusOK;
}


- (TDStatus) validateReplicatorProperties: (NSDictionary*)properties {
    BOOL push, createTarget;
    return [self parseReplicatorProperties: properties toDatabase: NULL
                                    remote: NULL isPush: &push createTarget: &createTarget
                                   headers: NULL
                                authorizer: NULL];
}


- (TDReplicator*) replicatorWithProperties: (NSDictionary*)properties
                                    status: (TDStatus*)outStatus
{
    // Extract the parameters from the JSON request body:
    // http://wiki.apache.org/couchdb/Replication
    TD_Database* db;
    NSURL* remote;
    BOOL push, createTarget;
    NSDictionary* headers;
    id<TDAuthorizer> authorizer;

    TDStatus status = [self parseReplicatorProperties: properties
                                           toDatabase: &db remote: &remote
                                               isPush: &push
                                         createTarget: &createTarget
                                              headers: &headers
                                           authorizer: &authorizer];
    if (TDStatusIsError(status)) {
        if (outStatus)
            *outStatus = status;
        return nil;
    }

    BOOL continuous = [$castIf(NSNumber, properties[@"continuous"]) boolValue];

    TDReplicator* repl = [[TDReplicator alloc] initWithDB: db
                                                   remote: remote
                                                     push: push
                                               continuous: continuous];
    if (!repl) {
        if (outStatus)
            *outStatus = kTDStatusServerError;
        return nil;
    }
    
    repl.filterName = $castIf(NSString, properties[@"filter"]);
    repl.filterParameters = $castIf(NSDictionary, properties[@"query_params"]);
    repl.options = properties;
    repl.requestHeaders = headers;
    repl.authorizer = authorizer;
    if (push)
        ((TDPusher*)repl).createTarget = createTarget;
    
    if (outStatus)
        *outStatus = kTDStatusOK;
    return repl;
}


- (TDReplicatorManager*) replicatorManager {
    if (!_replicatorManager && !_options.noReplicator) {
        LogTo(TD_Server, @"Starting replicator manager for %@", self);
        _replicatorManager = [[TDReplicatorManager alloc] initWithDatabaseManager: self];
        [_replicatorManager start];
    }
    return _replicatorManager;
}


@end




#pragma mark - TESTS
#if DEBUG

TestCase(TD_DatabaseManager) {
    RequireTestCase(TD_Database);
    TD_DatabaseManager* dbm = [TD_DatabaseManager createEmptyAtTemporaryPath: @"TD_DatabaseManagerTest"];
    TD_Database* db = [dbm databaseNamed: @"foo"];
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
