//
//  TDInternal.h
//  TouchDB
//
//  Created by Jens Alfke on 12/8/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TDDatabase.h"
#import "TDDatabase+Attachments.h"
#import "TDView.h"
#import "TDServer.h"
#import "TDReplicator.h"
#import "TDRemoteRequest.h"


extern NSString* const kTDAttachmentBlobKeyProperty;

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
                                           sequence: (SequenceNumber)sequence
                                            options: (TDContentOptions)options;
@end

@interface TDDatabase (Insertion_Internal)
- (NSData*) encodeDocumentJSON: (TDRevision*)rev;
- (TDStatus) validateRevision: (TDRevision*)newRev previousRevision: (TDRevision*)oldRev;
@end

@interface TDDatabase (Attachments_Internal)
- (void) rememberAttachmentWritersForDigests: (NSDictionary*)writersByDigests;
- (NSData*) keyForAttachment: (NSData*)contents;
- (TDStatus) insertAttachmentWithKey: (NSData*)keyData
                         forSequence: (SequenceNumber)sequence
                               named: (NSString*)name
                                type: (NSString*)contentType
                            encoding: (TDAttachmentEncoding)encoding
                              length: (UInt64)length
                       encodedLength: (UInt64)encodedLength
                              revpos: (unsigned)revpos;
- (TDStatus) copyAttachmentNamed: (NSString*)name
                    fromSequence: (SequenceNumber)fromSequence
                      toSequence: (SequenceNumber)toSequence;
@end

@interface TDDatabase (Replication_Internal)
- (NSString*) lastSequenceWithRemoteURL: (NSURL*)url
                                   push: (BOOL)push;
- (BOOL) setLastSequence: (NSString*)lastSequence
           withRemoteURL: (NSURL*)url
                    push: (BOOL)push;
+ (NSString*) joinQuotedStrings: (NSArray*)strings;
@end


@interface TDView ()
- (id) initWithDatabase: (TDDatabase*)db name: (NSString*)name;
@property (readonly) int viewID;
- (NSArray*) dump;
- (void) databaseClosing;
@end


@interface TDServer ()
@property (readonly, nonatomic) TDReplicatorManager* replicatorManager;
#if DEBUG
+ (TDServer*) createEmptyAtPath: (NSString*)path;  // for testing
+ (TDServer*) createEmptyAtTemporaryPath: (NSString*)name;  // for testing
#endif
@end


@interface TDReplicator ()
// protected:
@property (copy) NSString* lastSequence;
@property (readwrite, nonatomic) NSUInteger changesProcessed, changesTotal;
- (void) maybeCreateRemoteDB;
- (void) beginReplicating;
- (void) addToInbox: (TDRevision*)rev;
- (void) processInbox: (TDRevisionList*)inbox;  // override this
- (void) sendAsyncRequest: (NSString*)method path: (NSString*)relativePath body: (id)body
             onCompletion: (TDRemoteRequestCompletionBlock)onCompletion;
- (void) asyncTaskStarted;
- (void) asyncTasksFinished: (NSUInteger)numTasks;
- (void) stopped;
- (void) databaseClosing;

- (void) reachabilityChanged: (TDReachability*)host;
- (BOOL) goOffline;
- (BOOL) goOnline;
@end
