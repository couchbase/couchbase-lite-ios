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
#import "TDInternal.h"


@implementation TDDatabaseManager


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
    return [self initWithDirectory: [TD_DatabaseManager defaultDirectory]
                           options: NULL
                             error: nil];
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


#if 0
- (TD_Server*) tdServer {
    if (!_server) {
        TDDatabaseManagerOptions tdOptions = {
            .readOnly = _options.readOnly,
            .noReplicator = _options.noReplicator
        };
        _server = [[TD_Server alloc] initWithDirectory: _mgr.directory
                                              options: &tdOptions
                                                error: nil];
        LogTo(TDDatabase, @"%@ created %@", self, _server);
    }
    return _server;
}
#endif


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
    TDReplication* pull = [self replicationWithDatabase: database remote: otherDbURL
                                                      pull: YES create: YES];
    TDReplication* push = [self replicationWithDatabase: database remote: otherDbURL
                                                      pull: NO create: YES];
    if (exclusively) {
        for (TDReplication* repl in self.allReplications) {
            if (repl.localDatabase == database && repl != pull && repl != push) {
                [repl deleteDocument: nil];
            }
        }
    }
    return $array(pull, push);
}


@end
