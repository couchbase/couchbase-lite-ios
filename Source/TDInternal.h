//
//  TDInternal.h
//  TouchDB
//
//  Created by Jens Alfke on 12/8/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <TouchDB/TDDatabase.h>
#import "TDDatabase+Attachments.h"
#import "TDDatabaseManager.h"
#import "TDView.h"
#import "TDServer.h"
#import "TDRouter.h"
#import "TDReplicator.h"
#import "TDRemoteRequest.h"
#import "TDBlobStore.h"
@class TDAttachment;


@interface TDDatabase ()
@property (readwrite, copy) NSString* name;  // make it settable
@property (readonly) FMDatabase* fmdb;
@property (readonly) TDBlobStore* attachmentStore;
- (SInt64) getDocNumericID: (NSString*)docID;
- (TDRevisionList*) getAllRevisionsOfDocumentID: (NSString*)docID
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

@interface TDDatabase (Insertion_Internal)
- (NSData*) encodeDocumentJSON: (TDRevision*)rev;
- (TDStatus) validateRevision: (TDRevision*)newRev previousRevision: (TDRevision*)oldRev;
@end

@interface TDDatabase (Attachments_Internal)
- (void) rememberAttachmentWritersForDigests: (NSDictionary*)writersByDigests;
#if DEBUG
- (id) attachmentWriterForAttachment: (NSDictionary*)attachment;
#endif
- (BOOL) storeBlob: (NSData*)blob creatingKey: (TDBlobKey*)outKey;
- (TDStatus) insertAttachment: (TDAttachment*)attachment
                  forSequence: (SequenceNumber)sequence;
- (TDStatus) copyAttachmentNamed: (NSString*)name
                    fromSequence: (SequenceNumber)fromSequence
                      toSequence: (SequenceNumber)toSequence;
@end

@interface TDDatabase (Replication_Internal)
- (void) stopAndForgetReplicator: (TDReplicator*)repl;
- (NSString*) lastSequenceWithCheckpointID: (NSString*)checkpointID;
- (BOOL) setLastSequence: (NSString*)lastSequence withCheckpointID: (NSString*)checkpointID;
+ (NSString*) joinQuotedStrings: (NSArray*)strings;
@end


@interface TDView ()
- (id) initWithDatabase: (TDDatabase*)db name: (NSString*)name;
@property (readonly) int viewID;
- (NSArray*) dump;
- (void) databaseClosing;
@end


@interface TDServer ()
#if DEBUG
+ (TDServer*) createEmptyAtPath: (NSString*)path;  // for testing
+ (TDServer*) createEmptyAtTemporaryPath: (NSString*)name;  // for testing
#endif
@end


@interface TDDatabaseManager ()
@property (readonly, nonatomic) TDReplicatorManager* replicatorManager;
#if DEBUG
+ (TDDatabaseManager*) createEmptyAtPath: (NSString*)path;  // for testing
+ (TDDatabaseManager*) createEmptyAtTemporaryPath: (NSString*)name;  // for testing
#endif
@end


@interface TDRouter ()
- (id) initWithDatabaseManager: (TDDatabaseManager*)dbManager request: (NSURLRequest*)request;
@end


@interface TDReplicator ()
// protected:
@property (copy) NSString* lastSequence;
@property (readwrite, nonatomic) NSUInteger changesProcessed, changesTotal;
- (void) maybeCreateRemoteDB;
- (void) beginReplicating;
- (void) addToInbox: (TDRevision*)rev;
- (void) addRevsToInbox: (TDRevisionList*)revs;
- (void) processInbox: (TDRevisionList*)inbox;  // override this
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

- (void) reachabilityChanged: (TDReachability*)host;
- (BOOL) goOffline;
- (BOOL) goOnline;
#if DEBUG
@property (readonly) BOOL savingCheckpoint;
#endif
@end
