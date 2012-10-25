//
//  TouchDatabaseManager.m
//  TouchDB
//
//  Created by Jens Alfke on 6/19/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TouchDatabaseManager.h"
#import "TouchDBPrivate.h"

#import "TDDatabase.h"
#import "TDDatabaseManager.h"
#import "TDServer.h"


@implementation TouchDatabaseManager


@synthesize tdManager=_mgr;


+ (TouchDatabaseManager*) sharedInstance {
    static TouchDatabaseManager* sInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sInstance = [[self alloc] init];
    });
    return sInstance;
}


- (id)init {
    return [self initWithDirectory: [TDDatabaseManager defaultDirectory] error: nil];
}


- (id) initWithDirectory: (NSString*)directory error: (NSError**)outError {
    self = [super init];
    if (self) {
        _mgr = [[TDDatabaseManager alloc] initWithDirectory: directory
                                                    options: &kTDDatabaseManagerDefaultOptions
                                                      error: outError];
        if (!_mgr) {
            [self release];
            return nil;
        }
        _replications = [[NSMutableArray alloc] init];
        LogTo(TouchDatabase, @"Created %@", self);
    }
    return self;
}


- (void) close {
    [_mgr close];
    setObj(&_mgr, nil);
    [_server close];
    setObj(&_server, nil);
}


- (void)dealloc
{
    [_replications release];
    [self close];
    [super dealloc];
}


- (NSString*) description {
    return $sprintf(@"%@[%@]", [self class], _mgr.directory);
}


- (TDServer*) tdServer {
    if (!_server) {
        _server = [[TDServer alloc] initWithDirectory: _mgr.directory error: nil];
        LogTo(TouchDatabase, @"%@ created %@", self, _server);
    }
    return _server;
}


- (NSArray*) allDatabaseNames {
    return _mgr.allDatabaseNames;
}


- (TouchDatabase*) databaseForDatabase: (TDDatabase*)tddb {
    TouchDatabase* touchDatabase = tddb.touchDatabase;
    if (!touchDatabase) {
        touchDatabase = [[[TouchDatabase alloc] initWithManager: self 
                                                     TDDatabase: tddb] autorelease];
        tddb.touchDatabase = touchDatabase;
    }
    return touchDatabase;
}


- (TouchDatabase*) databaseNamed: (NSString*)name {
    TDDatabase* db = [_mgr existingDatabaseNamed: name];
    if (![db open])
        return nil;
    return [self databaseForDatabase: db];
}


- (TouchDatabase*) createDatabaseNamed: (NSString*)name error: (NSError**)outError {
    TDDatabase* db = [_mgr databaseNamed: name];
    if (![db open: outError])
        return nil;
    return [self databaseForDatabase: db];
}


#pragma mark - REPLICATION:


- (NSArray*) allReplications {
    NSMutableArray* replications = [[_replications mutableCopy] autorelease];
    TouchQuery* q = [[self databaseNamed: @"_replicator"] queryAllDocuments];
    for (TouchQueryRow* row in q.rows) {
        TouchReplication* repl = [TouchReplication modelForDocument: row.document];
        if (![replications containsObject: repl])
            [replications addObject: repl];
    }
    return replications;
}


- (TouchReplication*) replicationWithDatabase: (TouchDatabase*)db
                                       remote: (NSURL*)remote
                                         pull: (BOOL)pull
                                       create: (BOOL)create
{
    for (TouchReplication* repl in self.allReplications) {
        if (repl.localDatabase == db && $equal(repl.remoteURL, remote) && repl.pull == pull)
            return repl;
    }
    if (!create)
        return nil;
    TouchReplication* repl = [[TouchReplication alloc] initWithDatabase: db
                                                                 remote: remote
                                                                   pull: pull];
    [_replications addObject: repl];
    [repl release];
    return repl;
}


- (NSArray*) createReplicationsBetween: (TouchDatabase*)database
                                   and: (NSURL*)otherDbURL
                           exclusively: (bool)exclusively
{
    TouchReplication* pull = [self replicationWithDatabase: database remote: otherDbURL
                                                      pull: YES create: YES];
    TouchReplication* push = [self replicationWithDatabase: database remote: otherDbURL
                                                      pull: NO create: YES];
    if (exclusively) {
        for (TouchReplication* repl in self.allReplications) {
            if (repl.localDatabase == database && repl != pull && repl != push) {
                [repl deleteDocument: nil];
            }
        }
    }
    return $array(pull, push);
}


@end
