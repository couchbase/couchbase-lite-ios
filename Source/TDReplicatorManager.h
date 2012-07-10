//
//  TDReplicatorManager.h
//  TouchDB
//
//  Created by Jens Alfke on 2/15/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <TouchDB/TDDatabase.h>
@class TDDatabaseManager;
@protocol TDAuthorizer;


extern NSString* const kTDReplicatorDatabaseName;


/** Manages the _replicator database for persistent replications.
    It doesn't really have an API; it works on its own by monitoring the '_replicator' database, and docs in it, for changes. Applications use the regular document APIs to manage replications.
    A TDServer owns an instance of this class. */
@interface TDReplicatorManager : NSObject
{
    TDDatabaseManager* _dbManager;
    TDDatabase* _replicatorDB;
    NSThread* _thread;
    NSMutableDictionary* _replicatorsByDocID;
    BOOL _updateInProgress;
}

- (id) initWithDatabaseManager: (TDDatabaseManager*)dbManager;

- (void) start;
- (void) stop;

/** Examines the JSON object describing a replication and determines the local database and remote URL, and some of the other parameters. */
- (TDStatus) parseReplicatorProperties: (NSDictionary*)body
                            toDatabase: (TDDatabase**)outDatabase
                                remote: (NSURL**)outRemote
                                isPush: (BOOL*)outIsPush
                          createTarget: (BOOL*)outCreateTarget
                               headers: (NSDictionary**)outHeaders
                            authorizer: (id<TDAuthorizer>*)outAuthorizer;

@end
