//
//  CBLRestReplicator+Internal.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 4/30/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import "CBLRestReplicator.h"
#import "CBLRemoteRequest.h"
@class CBL_RevisionList, CBLReachability;
@protocol CBLAuthorizer;


@interface CBLRestReplicator ()
{
    @protected
    BOOL _running, _online, _active;
    CBL_ReplicatorSettings* _settings;
    CBLDatabase* __weak _db;
    NSString* _lastSequence;
    CBLBatcher* _batcher;
    CBLRemoteSession* _remoteSession;
#if TARGET_OS_IPHONE
    MYBackgroundMonitor *_bgMonitor;
#endif
}

@property (readwrite) id lastSequence;
@property (readwrite, nonatomic) NSUInteger changesProcessed, changesTotal;
- (void) maybeCreateRemoteDB;
- (void) beginReplicating;
- (void) addToInbox: (CBL_Revision*)rev;
- (void) addRevsToInbox: (CBL_RevisionList*)revs;
- (void) processInbox: (CBL_RevisionList*)inbox;  // override this
- (void) receivedResponseHeaders: (NSDictionary*)responseHeaders;
- (BOOL) serverIsSyncGatewayVersion: (NSString*)minVersion;
@property (readonly) BOOL canSendCompressedRequests;
- (void) stopRemoteRequests;
- (void) asyncTaskStarted;
- (void) asyncTasksFinished: (NSUInteger)numTasks;
- (void) stopped;
- (void) revisionFailed;    // subclasses call this if a transfer fails
- (void) retry;

- (void) reachabilityChanged: (CBLReachability*)host;
- (BOOL) goOffline;
- (BOOL) goOnline;
- (BOOL) checkSSLServerTrust: (SecTrustRef)trust forHost: (NSString*)host port: (UInt16)port;
@end
