//
//  CBL_Replicator.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/6/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class CBLDatabase, CBL_Revision, CBL_RevisionList, CBLBatcher, CBLReachability, CBLCookieStorage;
@protocol CBLAuthorizer;

typedef CBL_Revision* (^RevisionBodyTransformationBlock)(CBL_Revision*);

/** Posted when changesProcessed or changesTotal changes. */
extern NSString* CBL_ReplicatorProgressChangedNotification;

/** Posted when replicator stops running. */
extern NSString* CBL_ReplicatorStoppedNotification;


/** Abstract base class for push or pull replications. */
@interface CBL_Replicator : NSObject
{
    @protected
    CBLDatabase* __weak _db;
    NSURL* _remote;
    BOOL _continuous;
    NSString* _filterName;
    NSDictionary* _filterParameters;
    NSArray* _docIDs;
    NSString* _lastSequence;
    CBLBatcher* _batcher;
    id<CBLAuthorizer> _authorizer;
    NSDictionary* _options;
    NSDictionary* _requestHeaders;
    NSString* _serverType;
    CBLCookieStorage* _cookieStorage;
#if TARGET_OS_IPHONE
    NSUInteger /*UIBackgroundTaskIdentifier*/ _bgTask;
#endif
}

+ (NSString *)progressChangedNotification;
+ (NSString *)stoppedNotification;

/** Adds to (or replaces) the system list of trusted root certs. */
+ (void) setAnchorCerts: (NSArray*)certs onlyThese: (BOOL)onlyThese;

- (instancetype) initWithDB: (CBLDatabase*)db
                     remote: (NSURL*)remote
                       push: (BOOL)push
                 continuous: (BOOL)continuous;

@property (weak, readonly) CBLDatabase* db;
@property (readonly) NSURL* remote;
@property (readonly) BOOL isPush;
@property (readonly) BOOL continuous;
@property (readonly) CBLCookieStorage* cookieStorage;
@property (copy) NSString* filterName;
@property (copy) NSDictionary* filterParameters;
@property (copy) NSArray *docIDs;
@property (copy) NSDictionary* options;

/** Optional dictionary of headers to be added to all requests to remote servers. */
@property (copy) NSDictionary* requestHeaders;

@property (strong) id<CBLAuthorizer> authorizer;

/** Do these two replicators have identical settings? */
- (bool) hasSameSettingsAs: (CBL_Replicator*)other;

/** Starts the replicator.
    Replicators run asynchronously so nothing will happen until later.
    A replicator can only be started once; don't reuse it after it stops. */
- (void) start;

/** Request to stop the replicator.
    Any pending asynchronous operations will be canceled.
    CBL_ReplicatorStoppedNotification will be posted when it finally stops. */
- (void) stop;

/** Setting suspended to YES pauses the replicator. */
@property (nonatomic) BOOL suspended;

/** Is the replicator running? (Observable) */
@property (readonly, nonatomic) BOOL running;

/** Is the replicator able to connect to the remote host? */
@property (readonly, nonatomic) BOOL online;

/** Is the replicator actively sending/receiving revisions? (Observable) */
@property (readonly, nonatomic) BOOL active;

/** Latest error encountered while replicating.
    This is set to nil when starting. It may also be set to nil by the client if desired.
    Not all errors are fatal; if .running is still true, the replicator will retry. */
@property (strong, nonatomic) NSError* error;

/** A unique-per-process string identifying this replicator instance. */
@property (copy, nonatomic) NSString* sessionID;

/** Number of changes (docs or other metadata) transferred so far. */
@property (readonly, nonatomic) NSUInteger changesProcessed;

/** Approximate total number of changes to transfer.
    This is only an estimate and its value will change during replication. It starts at zero and returns to zero when replication stops. */
@property (readonly, nonatomic) NSUInteger changesTotal;

/** JSON-compatible dictionary of task info, as seen in _active_tasks REST API */
@property (readonly) NSDictionary* activeTaskInfo;

/** Timeout interval for HTTP requests sent by this replicator.
    (Derived from options key "connection_timeout", in milliseconds.) */
@property (readonly) NSTimeInterval requestTimeout;

/** Hook for transforming document body, e.g., encryption and decryption during replication */
@property (strong, nonatomic) RevisionBodyTransformationBlock revisionBodyTransformationBlock;

- (CBL_Revision *) transformRevision:(CBL_Revision *)rev;

@property (readonly) SecCertificateRef serverCert;

@end


// Supported keys in the .options dictionary:
#define kCBLReplicatorOption_Reset @"reset"
#define kCBLReplicatorOption_Timeout @"connection_timeout"  // CouchDB specifies this name
#define kCBLReplicatorOption_Heartbeat @"heartbeat"         // NSNumber, in ms
#define kCBLReplicatorOption_PollInterval @"poll"           // NSNumber, in ms
#define kCBLReplicatorOption_Network @"network"             // "WiFi" or "Cell"
#define kCBLReplicatorOption_UseWebSocket @"websocket"      // Boolean; default is YES
#define kCBLReplicatorOption_PinnedCert @"pinnedCert"       // NSData or (hex) NSString
