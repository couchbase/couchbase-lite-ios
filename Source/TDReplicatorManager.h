//
//  TDReplicatorManager.h
//  TouchDB
//
//  Created by Jens Alfke on 2/15/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDDatabase.h"
@class TDServer;


extern NSString* const kTDReplicatorDatabaseName;


/** Manages the _replicator database for persistent replications. */
@interface TDReplicatorManager : NSObject
{
    TDServer* _server;
    TDDatabase* _replicatorDB;
    NSMutableDictionary* _replicatorsByDocID;
    BOOL _updateInProgress;
}

- (id) initWithServer: (TDServer*)server;

- (TDStatus) parseReplicatorProperties: (NSDictionary*)body
                            toDatabase: (TDDatabase**)outDatabase
                                remote: (NSURL**)outRemote
                                isPush: (BOOL*)outIsPush
                          createTarget: (BOOL*)outCreateTarget;

@end
