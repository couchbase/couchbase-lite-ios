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
#import "CBL_DatabaseManager.h"
#import "CBL_Server.h"
#import "CBL_URLProtocol.h"
#import "CBLInternal.h"


@implementation CBLManager
{
    CBLManagerOptions _options;
    CBL_DatabaseManager* _mgr;
    CBL_Server* _server;
    NSURL* _internalURL;
    NSMutableArray* _replications;
}


@synthesize tdManager=_mgr;


+ (CBLManager*) sharedInstance {
    static CBLManager* sInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sInstance = [[self alloc] init];
    });
    return sInstance;
}


- (id)init {
    NSError* error;
    self = [self initWithDirectory: [CBL_DatabaseManager defaultDirectory]
                           options: NULL
                             error: &error];
    if (!self)
        Warn(@"Failed to create CBLManager: %@", error);
    return self;
}


- (id) initWithDirectory: (NSString*)directory
                 options: (const CBLManagerOptions*)options
                   error: (NSError**)outError {
    self = [super init];
    if (self) {
        if (options)
            _options = *options;

        CBL_DatabaseManagerOptions tdOptions = {
            .readOnly = _options.readOnly,
            .noReplicator = _options.noReplicator
        };
        _mgr = [[CBL_DatabaseManager alloc] initWithDirectory: directory
                                                    options: &tdOptions
                                                      error: outError];
        if (!_mgr) {
            return nil;
        }
        [_mgr replicatorManager];
        _replications = [[NSMutableArray alloc] init];
        LogTo(CBLDatabase, @"Created %@", self);
    }
    return self;
}


- (id) copyWithZone: (NSZone*)zone {
    CBLManagerOptions options = _options;
    options.noReplicator = true;        // Don't want to run multiple replicator tasks
    return [[[self class] alloc] initWithDirectory: _mgr.directory options: &options error: NULL];
}


- (void) close {
    [_mgr close];
    _mgr = nil;
    [_server close];
    _server = nil;
}


- (void)dealloc
{
    [self close];
}


- (NSString*) description {
    return $sprintf(@"%@[%@]", [self class], _mgr.directory);
}


- (CBL_Server*) backgroundServer {
    if (!_server) {
        CBL_DatabaseManagerOptions tdOptions = {
            .readOnly = _options.readOnly,
            .noReplicator = true
        };
        _server = [[CBL_Server alloc] initWithDirectory: _mgr.directory
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
        _internalURL = [tdURLProtocol registerServer: _server];
    }
    return _internalURL;
}


- (NSArray*) allDatabaseNames {
    return _mgr.allDatabaseNames;
}


- (CBLDatabase*) databaseForDatabase: (CBL_Database*)tddb {
    CBLDatabase* touchDatabase = tddb.touchDatabase;
    if (!touchDatabase) {
        touchDatabase = [[CBLDatabase alloc] initWithManager: self
                                                    CBL_Database: tddb];
        tddb.touchDatabase = touchDatabase;
    }
    return touchDatabase;
}


- (CBLDatabase*) databaseNamed: (NSString*)name {
    CBL_Database* db = [_mgr existingDatabaseNamed: name];
    if (![db open])
        return nil;
    return [self databaseForDatabase: db];
}

- (CBLDatabase*) objectForKeyedSubscript:(NSString*)key {
    return [self databaseNamed: key];
}

- (CBLDatabase*) createDatabaseNamed: (NSString*)name error: (NSError**)outError {
    CBL_Database* db = [_mgr databaseNamed: name];
    if (![db open: outError])
        return nil;
    return [self databaseForDatabase: db];
}


#pragma mark - REPLICATION:


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
