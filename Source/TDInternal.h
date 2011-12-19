//
//  TDInternal.h
//  TouchDB
//
//  Created by Jens Alfke on 12/8/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TDDatabase.h"
#import "TDView.h"
#import "TDServer.h"
#import "TDReplicator.h"
#import "TDRemoteRequest.h"


@interface TDDatabase ()
@property (readonly) FMDatabase* fmdb;
@property (readonly) TDBlobStore* attachmentStore;
- (TDStatus) deleteViewNamed: (NSString*)name;
- (NSString*) lastSequenceWithRemoteURL: (NSURL*)url
                                   push: (BOOL)push;
- (BOOL) setLastSequence: (NSString*)lastSequence
           withRemoteURL: (NSURL*)url
                    push: (BOOL)push;
- (void) replicatorDidStop: (TDReplicator*)repl;
@end

@interface TDDatabase (Attachments_Internal)
- (TDStatus) copyAttachmentNamed: (NSString*)name
                    fromSequence: (SequenceNumber)fromSequence
                      toSequence: (SequenceNumber)toSequence;
@end


@interface TDView ()
- (id) initWithDatabase: (TDDatabase*)db name: (NSString*)name;
@property (readonly) int viewID;
- (NSArray*) dump;
@end


@interface TDServer ()
#if DEBUG
+ (TDServer*) createEmptyAtPath: (NSString*)path;  // for testing
#endif
@end


@interface TDReplicator ()
// protected:
@property (copy) NSString* lastSequence;
@property (readwrite, nonatomic) NSUInteger changesProcessed, changesTotal;
- (void) addToInbox: (TDRevision*)rev;
- (void) processInbox: (TDRevisionList*)inbox;  // override this
- (void) sendAsyncRequest: (NSString*)method path: (NSString*)relativePath body: (id)body
             onCompletion: (TDRemoteRequestCompletionBlock)onCompletion;
- (void) asyncTaskStarted;
- (void) asyncTasksFinished: (NSUInteger)numTasks;
- (void) stopped;
@end
