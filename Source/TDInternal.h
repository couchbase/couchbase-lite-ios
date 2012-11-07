//
//  TDInternal.h
//  TouchDB
//
//  Created by Jens Alfke on 12/8/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <TouchDB/TD_Database.h>
#import "TD_Database+Attachments.h"
#import "TD_DatabaseManager.h"
#import "TD_View.h"
#import "TD_Server.h"
#import "TDRouter.h"
#import "TDReplicator.h"
#import "TDRemoteRequest.h"
#import "TDBlobStore.h"
@class TD_Attachment;


@interface TD_Database ()
@property (readwrite, copy) NSString* name;  // make it settable
@property (readonly) FMDatabase* fmdb;
@property (readonly) TDBlobStore* attachmentStore;
- (SInt64) getDocNumericID: (NSString*)docID;
- (TD_RevisionList*) getAllRevisionsOfDocumentID: (NSString*)docID
                                      numericID: (SInt64)docNumericID
                                    onlyCurrent: (BOOL)onlyCurrent;
- (TDStatus) deleteViewNamed: (NSString*)name;
- (NSMutableDictionary*) documentPropertiesFromJSON: (NSData*)json
                                              docID: (NSString*)docID
                                              revID: (NSString*)revID
                                            deleted: (BOOL)deleted
                                           sequence: (SequenceNumber)sequence
                                            options: (TDContentOptions)options;
- (NSString*) winningRevIDOfDocNumericID: (SInt64)docNumericID
                               isDeleted: (BOOL*)outIsDeleted;
@end

@interface TD_Database (Insertion_Internal)
- (NSData*) encodeDocumentJSON: (TD_Revision*)rev;
- (TDStatus) validateRevision: (TD_Revision*)newRev previousRevision: (TD_Revision*)oldRev;
@end

@interface TD_Database (Attachments_Internal)
- (void) rememberAttachmentWritersForDigests: (NSDictionary*)writersByDigests;
#if DEBUG
- (id) attachmentWriterForAttachment: (NSDictionary*)attachment;
#endif
- (BOOL) storeBlob: (NSData*)blob creatingKey: (TDBlobKey*)outKey;
- (TDStatus) insertAttachment: (TD_Attachment*)attachment
                  forSequence: (SequenceNumber)sequence;
- (TDStatus) copyAttachmentNamed: (NSString*)name
                    fromSequence: (SequenceNumber)fromSequence
                      toSequence: (SequenceNumber)toSequence;
- (BOOL) inlineFollowingAttachmentsIn: (TD_Revision*)rev error: (NSError**)outError;
@end

@interface TD_Database (Replication_Internal)
- (void) stopAndForgetReplicator: (TDReplicator*)repl;
- (NSString*) lastSequenceWithCheckpointID: (NSString*)checkpointID;
- (BOOL) setLastSequence: (NSString*)lastSequence withCheckpointID: (NSString*)checkpointID;
+ (NSString*) joinQuotedStrings: (NSArray*)strings;
@end


@interface TD_View ()
- (id) initWithDatabase: (TD_Database*)db name: (NSString*)name;
@property (readonly) int viewID;
- (NSArray*) dump;
- (void) databaseClosing;
@end


@interface TD_Server ()
#if DEBUG
+ (TD_Server*) createEmptyAtPath: (NSString*)path;  // for testing
+ (TD_Server*) createEmptyAtTemporaryPath: (NSString*)name;  // for testing
#endif
@end


@interface TD_DatabaseManager ()
@property (readonly, nonatomic) TDReplicatorManager* replicatorManager;
#if DEBUG
+ (TD_DatabaseManager*) createEmptyAtPath: (NSString*)path;  // for testing
+ (TD_DatabaseManager*) createEmptyAtTemporaryPath: (NSString*)name;  // for testing
#endif
@end


@interface TDRouter ()
- (id) initWithDatabaseManager: (TD_DatabaseManager*)dbManager request: (NSURLRequest*)request;
@end


@interface TDReplicator ()
// protected:
@property (copy) NSString* lastSequence;
@property (readwrite, nonatomic) NSUInteger changesProcessed, changesTotal;
- (void) maybeCreateRemoteDB;
- (void) beginReplicating;
- (void) addToInbox: (TD_Revision*)rev;
- (void) addRevsToInbox: (TD_RevisionList*)revs;
- (void) processInbox: (TD_RevisionList*)inbox;  // override this
- (TDRemoteJSONRequest*) sendAsyncRequest: (NSString*)method
                                     path: (NSString*)relativePath
                                     body: (id)body
                             onCompletion: (TDRemoteRequestCompletionBlock)onCompletion;
- (void) addRemoteRequest: (TDRemoteRequest*)request;
- (void) removeRemoteRequest: (TDRemoteRequest*)request;
- (void) asyncTaskStarted;
- (void) asyncTasksFinished: (NSUInteger)numTasks;
- (void) stopped;
- (void) databaseClosing;
- (void) revisionFailed;    // subclasses call this if a transfer fails
- (void) retry;

- (void) reachabilityChanged: (TDReachability*)host;
- (BOOL) goOffline;
- (BOOL) goOnline;
#if DEBUG
@property (readonly) BOOL savingCheckpoint;
#endif
@end
