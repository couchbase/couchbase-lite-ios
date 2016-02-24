//
//  CBLSyncConnection_Internal.h
//  Couchbase Lite
//
//  Created by Jens Alfke on 4/27/15.
//  Copyright (c) 2015 Couchbase. All rights reserved.
//

#import "CBLSyncConnection.h"
#import "CouchbaseLite.h"
#import "CouchbaseLitePrivate.h"
#import "CBLMisc.h"
#import "CBL_BlobStore.h"
#import "BLIPRequest.h"
#import "BLIPResponse.h"
#import "CollectionUtils.h"


UsingLogDomain(Sync);


// Enables using a second CBLDatabase, on a separate dispatch queue, for insertions.
// When used with ForestDB this provides greater parallelism since inserts will not block
// the regular _dbQueue. It won't help with SQLite though, because writes block reads.
#define PARALLEL_INSERTS 0

#if PARALLEL_INSERTS
#  define kInsertBatchInterval 1.0            // How long to wait to insert revs
#  define kMaxRevsToInsert 10000              // Max # of revs to insert into db in one transaction
#else
#  define kInsertBatchInterval 0.5
#  define kMaxRevsToInsert 100
#endif

#define kMaxPossibleAncestorsToSend 20

#define kMinLengthToCompress 100            // Minimum length JSON body that's worth compressing

#define kDefaultChangeBatchSize 200         // # of changes to send in one message
#define kMaxChangeMessagesInFlight 4        // How many changes messages can be active at once
#define kChangeMessagesAreUrgent YES        // Are change messages sent at high priority?

#define kProgressUpdateInterval 0.25        // How often to update self.progress


// Define this to track & log how much time is spent doing work on the database queue
//#define TIME_DB_QUEUE


@interface CBLSyncConnection ()
{
    CBLDatabase* _db;                           // The database
    dispatch_queue_t _dbQueue;                  // Dispatch queue to call the database on
    dispatch_queue_t _syncQueue;                // Dispatch queue most of this object runs on
    BLIPConnection* _connection;                // The BLIP connection to the peer
    NSURL* _peerURL;                            // The URL of the peer
    BOOL _connected;                            // Has _connection connected?
    SyncState _state;                           // Current state
    dispatch_block_t _updateStateSoon;          // Call this to update .state property RSN
    NSProgress *_pullProgress, *_pushProgress;   // Synthesized as public properties

    BOOL _pushing;                              // Should I actively push revisions?
    BOOL _pulling;                              // Should I actively pull revisions?
    BOOL _pushContinuousChanges;                // Is push continuous?
    BOOL _pullContinuousChanges;                // Is pull continuous?
    BOOL _pullCatchingUp;                       // Has the pull yet to catch up to latest sequence?

    id _remoteCheckpointSequence;               // Last-received remote sequence (pull)
    uint64_t _localCheckpointSequence;          // Last-sent local sequence (push)
    BOOL _lastSequenceChanged;                  // Has a last-sequence changed since checkpointed?
    BOOL _savingCheckpoint;                     // Is a checkpoint currently being saved?
    BOOL _overdueForSave;                       // Did checkpoint change again during a save?
    BOOL _closeAfterSave;                       // If set, close connection when save finishes
    NSString* _remoteCheckpointRevID;           // _rev of remote checkpoint doc

    NSInteger _changesBatchSize;                // Number of changes to send/receive in one message
    NSUInteger _changeListsInFlight;            // Number of change msgs sent but not yet acked
    NSUInteger _awaitingRevs;                   // Number of revisions requested but not received

    NSMutableArray* _revsToInsert;              // Incoming revisions to be inserted into the db
    NSUInteger _insertingRevs;                  // Number of revs received but not inserted yet

    CBLFilterBlock _pushFilter;                 // Filter for outgoing revisions
    NSDictionary* _pushFilterParams;            // ...and parameters for it
    NSString* _pullFilterName;                  // Name of remote filter for incoming revisions
    NSDictionary* _pullFilterParams;            // ...and parameters for it

    CBLDatabase* _insertDB;                     // DB used for insertion (maybe same as _db)
    dispatch_queue_t _insertDBQueue;            // Dispatch queue used for insertion

#ifdef TIME_DB_QUEUE
    CFAbsoluteTime _dbQueueTime;
    NSTimeInterval _dbQueueTotalIdleTime, _dbQueueTotalBusyTime;
    NSTimeInterval _dbQueueTotalInsertTime;
#endif
}

@property (readwrite) SyncState state;
@property (readwrite) NSError* error;
@property (readwrite, copy) NSArray *nestedPullProgress, *nestedPushProgress;

- (void) updateState;
- (void) updateState: (SyncState)state;
- (BOOL) gotError: (BLIPResponse*)response;

- (void) onSyncQueue: (void(^)())block;
- (void) onDatabaseQueue: (void(^)())block;

- (NSProgress*) addAttachmentProgressWithName: (NSString*)name
                                       length: (uint64_t)length
                                      pulling: (BOOL)pulling;
- (void) removeAttachmentProgress: (NSProgress*)attProgress
                          pulling: (BOOL)pulling;

- (BOOL) accessCheckForRequest: (BLIPRequest*)request;

@end


@interface CBLSyncConnection (Checkpoints)
- (void) getCheckpoint;
- (BOOL) updateCheckpoint;
- (void) noteLastSequenceChanged;
- (void) noteLocalSequenceIDPushed: (id)sequenceID;
@end


@interface CBLSyncConnection (Push)
- (void) sendChangesSince: (uint64_t)since;
@end


@interface CBLSyncConnection (Pull)
- (void) requestChangesSince: (id)sinceSequence
                 inBatchesOf: (NSUInteger)batchSize
                  continuous: (BOOL)continuous;
@end
