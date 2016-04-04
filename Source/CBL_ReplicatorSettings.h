//
//  CBL_ReplicatorSettings.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/3/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import "CBLDatabase.h"
#import "CBLStatus.h"
@class CBL_Revision, CBLReachability;
@protocol CBLAuthorizer;


typedef CBL_Revision* (^RevisionBodyTransformationBlock)(CBL_Revision*);


/** Replicator settings/configuration. This is created and set up by CBLReplication or the REST
    router, and passed to the actual replicator implementation. */
@interface CBL_ReplicatorSettings : NSObject

- (instancetype) initWithRemote: (NSURL*)remote
                           push: (BOOL)push;

@property (readonly) NSURL* remote;
@property (readonly) BOOL isPush;
@property BOOL continuous;
@property BOOL createTarget;
@property (copy) NSString* filterName;
@property (copy) CBLFilterBlock filterBlock;
@property (copy) NSDictionary* filterParameters;
@property (copy) NSArray *docIDs;
@property BOOL downloadAttachments;
@property (copy) NSDictionary* options;

/** Optional dictionary of headers to be added to all requests to remote servers. */
@property (copy) NSDictionary* requestHeaders;

@property (strong) id<CBLAuthorizer> authorizer;

/** Hook for transforming document body, e.g., encryption and decryption during replication */
@property (strong, nonatomic) RevisionBodyTransformationBlock revisionBodyTransformationBlock;


// Methods below are conveniences for the replicator implementation to call:


/** The value to use for the User-Agent HTTP header. */
+ (NSString*) userAgentHeader;

- (NSString*) remoteCheckpointDocIDForLocalUUID: (NSString*)localUUID;

/** Timeout interval for HTTP requests sent by this replicator.
    (Derived from options key "connection_timeout", in milliseconds.) */
@property (readonly) NSTimeInterval requestTimeout;

/** How often a continuous pull replicator should poll the server.
    Zero means it should not poll but should keep the connection open.
    (Derived from options key "poll", in milliseconds.) */
@property (readonly) NSTimeInterval pollInterval;

@property (readonly) BOOL canUseCellNetwork;

/** Returns YES if the reachability flags indicate the host is reachable according to the settings'
    "network" option (see below). */
- (BOOL) isHostReachable: (CBLReachability*)reachability;

@property (readonly) BOOL trustReachability;

/** Checks whether to trust the SSL server, using the options value "pinnedCert". */
- (BOOL) checkSSLServerTrust: (SecTrustRef)trust
                     forHost: (NSString*)host
                        port: (UInt16)port;

/** Applies the revisionBodyTransformationBlock to the given revision, returning the result. */
- (CBL_Revision*) transformRevision: (CBL_Revision*)rev;

- (BOOL) compilePushFilterForDatabase: (CBLDatabase*)db
                               status: (CBLStatus*)outStatus;

@end


// Supported keys in the .options dictionary:
#define kCBLReplicatorOption_Reset @"reset"
#define kCBLReplicatorOption_Timeout @"connection_timeout"  // CouchDB specifies this name
#define kCBLReplicatorOption_Heartbeat @"heartbeat"         // NSNumber, in ms
#define kCBLReplicatorOption_PollInterval @"poll"           // NSNumber, in ms
#define kCBLReplicatorOption_Network @"network"             // "WiFi" or "Cell"
#define kCBLReplicatorOption_UseWebSocket @"websocket"      // Boolean; default is YES
#define kCBLReplicatorOption_PinnedCert @"pinnedCert"       // NSData or (hex) NSString
#define kCBLReplicatorOption_RemoteUUID @"remoteUUID"       // NSString
#define kCBLReplicatorOption_PurgePushed @"purgePushed"     // Boolean; default is NO
#define kCBLReplicatorOption_AllNew @"allNew"               // Boolean; default is NO

// Boolean; default is YES. Setting this option will have no effect and result to always 'trust' if
// the kCBLReplicatorOption_Network option is also set.
#define kCBLReplicatorOption_TrustReachability @"trust_reachability"
