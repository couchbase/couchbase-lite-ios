//
//  TouchReplication.m
//  TouchDB
//
//  Created by Jens Alfke on 6/22/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TouchReplication.h"
#import "TouchDB.h"

#import "TDPusher.h"
#import "TDDatabase+Replication.h"
#import "TDDatabaseManager.h"
#import "TDServer.h"


@interface TouchReplication ()
@property (nonatomic, readwrite) BOOL running;
@property (nonatomic, readwrite, copy) NSString* status;
@property (nonatomic, readwrite) unsigned completed, total;
@property (nonatomic, readwrite, retain) NSError* error;
@property (nonatomic, readwrite) TouchReplicationMode mode;
@end


@implementation TouchReplication


- (id) initWithServer: (TDServer*)server
             database: (TouchDatabase*)database
               remote: (NSURL*)remote
{
    NSParameterAssert(remote);
    self = [super init];
    if (self) {
        _server = [server retain];
        _database = [database retain];
        _remote = [remote retain];
        // Give the caller a chance to customize parameters like .filter before calling -start,
        // but make sure -start will be run even if the caller doesn't call it.
        [self performSelector: @selector(start) withObject: nil afterDelay: 0.0];
    }
    return self;
}


- (void)dealloc {
    Log(@"%@: dealloc", self);
    [_server release];
    [_remote release];
    [_database release];
    [_status release];
    [_error release];
    [_filter release];
    [_filterParams release];
    [_options release];
    [_headers release];
    [_oauth release];
    [super dealloc];
}


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%@ %@]",
                self.class, (_pull ? @"from" : @"to"), _remote];
}


@synthesize pull=_pull, createTarget=_createTarget, continuous=_continuous,
            filter=_filter, filterParams=_filterParams, options=_options, headers=_headers,
            OAuth=_oauth, localDatabase=_database;


- (void) start {
    if (_replicator)
        return;
    
    [_server tellDatabaseManager:^(TDDatabaseManager* dbmgr) {
        // This runs on the server thread:
        TDDatabase* db = [dbmgr databaseNamed: _database.name];
        TDReplicator* repl = [db replicatorWithRemoteURL: _remote push: !_pull continuous: _continuous];
        if (!repl)
            return;
        repl.filterName = _filter;
        repl.filterParameters = _filterParams;
        repl.options = _options;
        repl.requestHeaders = _headers;
        if (!_pull)
            ((TDPusher*)repl).createTarget = _createTarget;
        [repl start];
        
        _replicator = [repl retain];
        [repl addObserver: self forKeyPath: @"running" options: 0 context: NULL];
        [repl addObserver: self forKeyPath: @"active" options: 0 context: NULL];
        [repl addObserver: self forKeyPath: @"changesProcessed" options: 0 context: NULL];
        [repl addObserver: self forKeyPath: @"changesTotal" options: 0 context: NULL];
    }];
}


- (void) stopped {
    self.status = nil;
    if (_taskID) {
        [_taskID release];
        _taskID = nil;
        [self autorelease]; // balances [self retain] when successfully started
    }
    self.running = NO;
    self.mode = kTouchReplicationStopped;
}


- (void) stop {
    if (_replicator) {
        
    }
}


@synthesize running = _running, status=_status, completed=_completed, total=_total, error = _error;
@synthesize mode=_mode, remoteURL = _remote;




@end
