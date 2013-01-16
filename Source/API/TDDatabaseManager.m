//
//  TDDatabaseManager.m
//  TouchDB
//
//  Created by Jens Alfke on 6/19/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDDatabaseManager.h"
#import "TouchDBPrivate.h"

#import "TD_Database.h"
#import "TD_DatabaseManager.h"
#import "TD_Server.h"
#import "TDURLProtocol.h"
#import "TDInternal.h"


@implementation TDDatabaseManager
{
    TDDatabaseManagerOptions _options;
    TD_DatabaseManager* _mgr;
    TD_Server* _server;
    NSURL* _internalURL;
    NSMutableArray* _replications;
}


@synthesize tdManager=_mgr;


+ (TDDatabaseManager*) sharedInstance {
    static TDDatabaseManager* sInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sInstance = [[self alloc] init];
    });
    return sInstance;
}


- (id)init {
    NSError* error;
    self = [self initWithDirectory: [TD_DatabaseManager defaultDirectory]
                           options: NULL
                             error: &error];
    if (!self)
        Warn(@"Failed to create TDDatabaseManager: %@", error);
    return self;
}


- (id) initWithDirectory: (NSString*)directory
                 options: (const TDDatabaseManagerOptions*)options
                   error: (NSError**)outError {
    self = [super init];
    if (self) {
        if (options)
            _options = *options;

        TD_DatabaseManagerOptions tdOptions = {
            .readOnly = _options.readOnly,
            .noReplicator = _options.noReplicator
        };
        _mgr = [[TD_DatabaseManager alloc] initWithDirectory: directory
                                                    options: &tdOptions
                                                      error: outError];
        if (!_mgr) {
            return nil;
        }
        [_mgr replicatorManager];
        _replications = [[NSMutableArray alloc] init];
        LogTo(TDDatabase, @"Created %@", self);
    }
    return self;
}


- (id) copyWithZone: (NSZone*)zone {
    TDDatabaseManagerOptions options = _options;
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


- (TD_Server*) backgroundServer {
    if (!_server) {
        TD_DatabaseManagerOptions tdOptions = {
            .readOnly = _options.readOnly,
            .noReplicator = true
        };
        _server = [[TD_Server alloc] initWithDirectory: _mgr.directory
                                               options: &tdOptions
                                                 error: nil];
        LogTo(TDDatabase, @"%@ created %@", self, _server);
    }
    return _server;
}


- (NSURL*) internalURL {
    if (!_internalURL) {
        if (!self.backgroundServer)
            return nil;
        Class tdURLProtocol = NSClassFromString(@"TDURLProtocol");
        Assert(tdURLProtocol, @"TDURLProtocol class not found; link TouchDBListener.framework");
        _internalURL = [tdURLProtocol registerServer: _server];
    }
    return _internalURL;
}


- (NSArray*) allDatabaseNames {
    return _mgr.allDatabaseNames;
}


- (TDDatabase*) databaseForDatabase: (TD_Database*)tddb {
    TDDatabase* touchDatabase = tddb.touchDatabase;
    if (!touchDatabase) {
        touchDatabase = [[TDDatabase alloc] initWithManager: self
                                                    TD_Database: tddb];
        tddb.touchDatabase = touchDatabase;
    }
    return touchDatabase;
}


- (TDDatabase*) databaseNamed: (NSString*)name {
    TD_Database* db = [_mgr existingDatabaseNamed: name];
    if (![db open])
        return nil;
    return [self databaseForDatabase: db];
}

- (TDDatabase*) objectForKeyedSubscript:(NSString*)key {
    return [self databaseNamed: key];
}

- (TDDatabase*) createDatabaseNamed: (NSString*)name error: (NSError**)outError {
    TD_Database* db = [_mgr databaseNamed: name];
    if (![db open: outError])
        return nil;
    return [self databaseForDatabase: db];
}


#pragma mark - REPLICATION:


- (NSArray*) allReplications {
    NSMutableArray* replications = [_replications mutableCopy];
    TDQuery* q = [[self databaseNamed: @"_replicator"] queryAllDocuments];
    for (TDQueryRow* row in q.rows) {
        TDReplication* repl = [TDReplication modelForDocument: row.document];
        if (![replications containsObject: repl])
            [replications addObject: repl];
    }
    return replications;
}


- (TDReplication*) replicationWithDatabase: (TDDatabase*)db
                                       remote: (NSURL*)remote
                                         pull: (BOOL)pull
                                       create: (BOOL)create
{
    for (TDReplication* repl in self.allReplications) {
        if (repl.localDatabase == db && $equal(repl.remoteURL, remote) && repl.pull == pull)
            return repl;
    }
    if (!create)
        return nil;
    TDReplication* repl = [[TDReplication alloc] initWithDatabase: db
                                                           remote: remote
                                                             pull: pull];
    [_replications addObject: repl];
    return repl;
}


- (NSArray*) createReplicationsBetween: (TDDatabase*)database
                                   and: (NSURL*)otherDbURL
                           exclusively: (bool)exclusively
{
    TDReplication* pull = nil, *push = nil;
    if (otherDbURL) {
        pull = [self replicationWithDatabase: database remote: otherDbURL
                                                          pull: YES create: YES];
        push = [self replicationWithDatabase: database remote: otherDbURL
                                                          pull: NO create: YES];
        if (!pull || !push)
            return nil;
    }
    if (exclusively) {
        for (TDReplication* repl in self.allReplications) {
            if (repl.localDatabase == database && repl != pull && repl != push) {
                [repl deleteDocument: nil];
            }
        }
    }
    return otherDbURL ? $array(pull, push) : nil;
}


@end
