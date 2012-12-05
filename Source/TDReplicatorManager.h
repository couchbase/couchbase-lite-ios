//
//  TDReplicatorManager.h
//  TouchDB
//
//  Created by Jens Alfke on 2/15/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <TouchDB/TD_Database.h>
@class TD_DatabaseManager;
@protocol TDAuthorizer;


extern NSString* const kTDReplicatorDatabaseName;


/** Manages the _replicator database for persistent replications.
    It doesn't really have an API; it works on its own by monitoring the '_replicator' database, and docs in it, for changes. Applications use the regular document APIs to manage replications.
    A TD_Server owns an instance of this class. */
@interface TDReplicatorManager : NSObject
{
    TD_DatabaseManager* _dbManager;
    TD_Database* _replicatorDB;
    NSThread* _thread;
    NSMutableDictionary* _replicatorsByDocID;
    BOOL _updateInProgress;
}

- (id) initWithDatabaseManager: (TD_DatabaseManager*)dbManager;

- (void) start;
- (void) stop;

/** Examines the JSON object describing a replication and determines the local database and remote URL, and some of the other parameters. */
- (TDStatus) parseReplicatorProperties: (NSDictionary*)body
                            toDatabase: (TD_Database**)outDatabase
                                remote: (NSURL**)outRemote
                                isPush: (BOOL*)outIsPush
                          createTarget: (BOOL*)outCreateTarget
                               headers: (NSDictionary**)outHeaders
                            authorizer: (id<TDAuthorizer>*)outAuthorizer;

@end
