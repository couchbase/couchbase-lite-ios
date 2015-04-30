//
//  CBL_Replicator+Internal.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 4/30/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import "CBL_Replicator.h"
#import "CBLRemoteRequest.h"
@class CBL_RevisionList, CBLReachability;


@interface CBL_Replicator ()
- (instancetype) initWithDB: (CBLDatabase*)db
                     remote: (NSURL*)remote
                       push: (BOOL)push
                 continuous: (BOOL)continuous;
// protected:
@property (copy) NSString* lastSequence;
@property (readwrite, nonatomic) NSUInteger changesProcessed, changesTotal;
- (void) maybeCreateRemoteDB;
- (void) beginReplicating;
- (void) addToInbox: (CBL_Revision*)rev;
- (void) addRevsToInbox: (CBL_RevisionList*)revs;
- (void) processInbox: (CBL_RevisionList*)inbox;  // override this
- (BOOL) serverIsSyncGatewayVersion: (NSString*)minVersion;
@property (readonly) BOOL canSendCompressedRequests;
- (CBLRemoteJSONRequest*) sendAsyncRequest: (NSString*)method
                                     path: (NSString*)relativePath
                                     body: (id)body
                             onCompletion: (CBLRemoteRequestCompletionBlock)onCompletion;
- (void) addRemoteRequest: (CBLRemoteRequest*)request;
- (void) removeRemoteRequest: (CBLRemoteRequest*)request;
- (void) asyncTaskStarted;
- (void) asyncTasksFinished: (NSUInteger)numTasks;
- (void) stopped;
- (void) revisionFailed;    // subclasses call this if a transfer fails
- (void) retry;

- (void) reachabilityChanged: (CBLReachability*)host;
- (BOOL) goOffline;
- (BOOL) goOnline;
- (BOOL) checkSSLServerTrust: (SecTrustRef)trust forHost: (NSString*)host port: (UInt16)port;
#if DEBUG
@property (readonly) BOOL savingCheckpoint;
#endif
@end
