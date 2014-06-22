//
//  CBLInternal.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/8/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import "CBLDatabase.h"
#import "CBLDatabase+Attachments.h"
#import "CBLDatabaseChange.h"
#import "CBLManager+Internal.h"
#import "CBLView+Internal.h"
#import "CBL_Server.h"
#import "CBL_Router.h"
#import "CBL_Replicator.h"
#import "CBLRemoteRequest.h"
#import "CBL_BlobStore.h"
@class CBL_Attachment, CBL_BlobStoreWriter, CBLDatabaseChange;


#define UU __unsafe_unretained  /* Use on method parameters to avoid retaining/releasing them */


@interface CBLDatabase (Insertion_Internal)
- (CBLStatus) validateRevision: (CBL_Revision*)newRev previousRevision: (CBL_Revision*)oldRev;
@end

@interface CBLDatabase (Attachments_Internal)
- (void) rememberAttachmentWriter: (CBL_BlobStoreWriter*)writer;
- (void) rememberAttachmentWritersForDigests: (NSDictionary*)writersByDigests;
#if DEBUG
- (id) attachmentWriterForAttachment: (NSDictionary*)attachment;
#endif
- (BOOL) storeBlob: (NSData*)blob creatingKey: (CBLBlobKey*)outKey;
- (CBLStatus) insertAttachment: (CBL_Attachment*)attachment
                  forSequence: (SequenceNumber)sequence;
- (CBLStatus) copyAttachmentNamed: (NSString*)name
                    fromSequence: (SequenceNumber)fromSequence
                      toSequence: (SequenceNumber)toSequence;
- (BOOL) inlineFollowingAttachmentsIn: (CBL_Revision*)rev error: (NSError**)outError;
@end

@interface CBLDatabase (Replication_Internal)
- (void) stopAndForgetReplicator: (CBL_Replicator*)repl;
- (NSString*) lastSequenceWithCheckpointID: (NSString*)checkpointID;
- (BOOL) setLastSequence: (NSString*)lastSequence withCheckpointID: (NSString*)checkpointID;
+ (NSString*) joinQuotedStrings: (NSArray*)strings;
@end


@interface CBL_Server ()
#if DEBUG
+ (instancetype) createEmptyAtPath: (NSString*)path;  // for testing
+ (instancetype) createEmptyAtTemporaryPath: (NSString*)name;  // for testing
#endif
@end


@interface CBLManager (Testing)
#if DEBUG
+ (instancetype) createEmptyAtPath: (NSString*)path;  // for testing
+ (instancetype) createEmptyAtTemporaryPath: (NSString*)name;  // for testing
#endif
@end


@interface CBLDatabaseChange ()
- (instancetype) initWithAddedRevision: (CBL_Revision*)addedRevision
                       winningRevision: (CBL_Revision*)winningRevision
                            inConflict: (BOOL)maybeConflict
                                source: (NSURL*)source;
/** The revision just added. Guaranteed immutable. */
@property (nonatomic, readonly) CBL_Revision* addedRevision;
/** The revision that is now the default "winning" revision of the document.
 Guaranteed immutable.*/
@property (nonatomic, readonly) CBL_Revision* winningRevision;
/** Is this a relayed notification of one from another thread, not the original? */
@property (nonatomic, readonly) bool echoed;
@end


@interface CBL_Router ()
- (instancetype) initWithDatabaseManager: (CBLManager*)dbManager request: (NSURLRequest*)request;
@end


@interface CBL_Replicator ()
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
- (void) databaseClosing;
- (void) revisionFailed;    // subclasses call this if a transfer fails
- (void) retry;

- (void) reachabilityChanged: (CBLReachability*)host;
- (BOOL) goOffline;
- (BOOL) goOnline;
- (void) setSuspended: (BOOL)suspended;
- (BOOL) checkSSLServerTrust: (SecTrustRef)trust forHost: (NSString*)host port: (UInt16)port;
#if DEBUG
@property (readonly) BOOL savingCheckpoint;
#endif
@end


#if DEBUG
// For unit tests only: Returns the URL of a named database on the test server.
// The test server defaults to <http://127.0.0.1:5984> but can be configured by setting the
// environment variable "CBL_TEST_SERVER" at runtime.
NSURL* RemoteTestDBURL(NSString* dbName);

void AddTemporaryCredential(NSURL* url, NSString* realm,
                            NSString* username, NSString* password);

void DeleteRemoteDB(NSURL* dbURL);
#endif
