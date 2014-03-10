//
//  CBLReplication.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/22/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLDatabase;


/** Describes the current status of a replication. */
typedef enum {
    kCBLReplicationStopped, /**< The replication is finished or hit a fatal error. */
    kCBLReplicationOffline, /**< The remote host is currently unreachable. */
    kCBLReplicationIdle,    /**< Continuous replication is caught up and waiting for more changes.*/
    kCBLReplicationActive   /**< The replication is actively transferring data. */
} CBLReplicationStatus;


/** A callback block for transforming revision bodies during replication.
    See CBLReplication.propertiesTransformationBlock's documentation for details. */
typedef NSDictionary *(^CBLPropertiesTransformationBlock)(NSDictionary *);


/** A 'push' or 'pull' replication between a local and a remote database.
    Replications can be one-shot or continuous. */
@interface CBLReplication : NSObject

/** The local database being replicated to/from. */
@property (nonatomic, readonly) CBLDatabase* localDatabase;

/** The URL of the remote database. */
@property (nonatomic, readonly) NSURL* remoteURL;

/** Does the replication pull from (as opposed to push to) the target? */
@property (nonatomic, readonly) BOOL pull;


#pragma mark - OPTIONS:

/** Should the target database be created if it doesn't already exist? (Defaults to NO). */
@property (nonatomic) BOOL createTarget;

/** Should the replication operate continuously? (Defaults to NO).
    A continuous replication keeps running (with 'idle' status) after updating the target database.
    It monitors the source database and copies new revisions as soon as they're available.
    Continuous replications keep running until the app quits or they're stopped. */
@property (nonatomic) bool continuous;

/** Name of an optional filter function to run on the source server.
    Only documents for which the function returns true are replicated.
    * For a pull replication, the name looks like "designdocname/filtername".
    * For a push replication, use the name under which you registered the filter with the CBLDatabase. */
@property (nonatomic, copy) NSString* filter;

/** Parameters to pass to the filter function.
    Should map strings to strings. */
@property (nonatomic, copy) NSDictionary* filterParams;

/** List of Sync Gateway channel names to filter by; a nil value means no filtering, i.e. all
    available channels will be synced.
    Only valid for pull replications whose source database is on a Couchbase Sync Gateway server.
    (This is a convenience that just reads or changes the values of .filter and .query_params.) */
@property (nonatomic, copy) NSArray* channels;

/** Sets the documents to specify as part of the replication. */
@property (copy) NSArray *documentIDs;

/** Extra HTTP headers to send in all requests to the remote server.
    Should map strings (header names) to strings. */
@property (nonatomic, copy) NSDictionary* headers;

/** Specifies which class of network the replication will operate over.
    Default value is nil, which means replicate over all networks.
    Set to "WiFi" (or "!Cell") to replicate only over WiFi,
    or to "Cell" (or "!WiFi") to replicate only over cellular. */
@property (nonatomic, copy) NSString* network;

/** An optional JSON-compatible dictionary of extra properties for the replicator. */
@property (nonatomic, copy) NSDictionary* customProperties;


#pragma mark - AUTHENTICATION:

/** The credential (generally username+password) to use to authenticate to the remote database.
    This can either come from the URL itself (if it's of the form "http://user:pass@example.com")
    or be stored in the NSURLCredentialStore, which is a wrapper around the Keychain. */
@property (nonatomic, strong) NSURLCredential* credential;

/** OAuth parameters that the replicator should use when authenticating to the remote database.
    Keys in the dictionary should be "consumer_key", "consumer_secret", "token", "token_secret",
    and optionally "signature_method". */
@property (nonatomic, copy) NSDictionary* OAuth;

/** Email address for login with Facebook credentials.
    In addition to this, you also need to get a token from Facebook's servers,
    which you then pass to -registerFacebookToken:forEmailAddress. */
@property (nonatomic, copy) NSString* facebookEmailAddress;

/** Registers a Facebook login token that will be used on the next login to the remote server.
    This also sets facebookEmailAddress. 
    For security reasons the token is not stored in the replication document, but instead kept
    in an in-memory registry private to the Facebook authorizer. On login the token is sent to
    the server, and the server will respond with a session cookie. After that the token isn't
    needed again until the session expires. At that point you'll need to recover or regenerate
    the token and register it again. */
- (BOOL) registerFacebookToken: (NSString*)token
               forEmailAddress: (NSString*)email                        __attribute__((nonnull));

/** The base URL of the remote server, for use as the "origin" parameter when requesting Persona or
    Facebook authentication. */
@property (readonly) NSURL* personaOrigin;

/** Email address for remote login with Persona (aka BrowserID).
    In addition to this, you also need to go through the Persona protocol to get a signed assertion,
    which you then pass to the -registerPersonaAssertion: method.)*/
@property (nonatomic, copy) NSString* personaEmailAddress;

/** Registers a Persona 'assertion' (ID verification) string that will be used on the next login to the remote server. This also sets personaEmailAddress.
    Note: An assertion is a type of certificate and typically has a very short lifespan (like, a
    few minutes.) For this reason it's not stored in the replication document, but instead kept
    in an in-memory registry private to the Persona authorizer. You should initiate a replication
    immediately after registering the assertion, so that the replicator engine can use it to
    authenticate before it expires. After that, the replicator will have a login session cookie
    that should last significantly longer before needing to be renewed. */
- (BOOL) registerPersonaAssertion: (NSString*)assertion               __attribute__((nonnull));

/** Adds additional SSL root certificates to be trusted by the replicator, or entirely overrides the
    OS's default list of trusted root certs.
    @param certs  An array of SecCertificateRefs of root certs that should be trusted. Most often
        these will be self-signed certs, but they might also be the roots of nonstandard CAs.
    @param onlyThese  If NO, the given certs are appended to the system's built-in list of trusted
        root certs; if YES, it replaces them (so *only* the given certs will be trusted.) */
+ (void) setAnchorCerts: (NSArray*)certs onlyThese: (BOOL)onlyThese;


#pragma mark - STATUS:

/** Starts the replication, asynchronously.
    Has no effect if the replication is already running.
    You can monitor its progress by observing the kCBLReplicationChangeNotification it sends,
    or by using KVO to observe its .running, .status, .error, .total and .completed properties. */
- (void) start;

/** Stops replication, asynchronously.
    Has no effect if the replication is not running. */
- (void) stop;

/** Restarts a running replication.
    Has no effect if the replication is not running. */
- (void) restart;

/** The replication's current state, one of {stopped, offline, idle, active}. */
@property (nonatomic, readonly) CBLReplicationStatus status;

/** YES while the replication is running, NO if it's stopped.
    Note that a continuous replication never actually stops; it only goes idle waiting for new
    data to appear. */
@property (nonatomic, readonly) BOOL running;

/** The error status of the replication, or nil if there have not been any errors since it started. */
@property (nonatomic, readonly, retain) NSError* lastError;

/** The number of completed changes processed, if the task is active, else 0 (observable). */
@property (nonatomic, readonly) unsigned completedChangesCount;

/** The total number of changes to be processed, if the task is active, else 0 (observable). */
@property (nonatomic, readonly) unsigned changesCount;


#ifdef CBL_DEPRECATED
@property (nonatomic) bool create_target __attribute__((deprecated("renamed createTarget")));
@property (nonatomic, copy) NSDictionary* query_params __attribute__((deprecated("renamed filterParams")));
@property (copy) NSArray *doc_ids __attribute__((deprecated("renamed documentIDs")));
@property (nonatomic, readonly) CBLReplicationStatus mode __attribute__((deprecated("renamed status")));
@property (nonatomic, readonly, retain) NSError* error __attribute__((deprecated("renamed lastError")));
@property (nonatomic, readonly) unsigned completed __attribute__((deprecated("renamed completedChangesCount")));
@property (nonatomic, readonly) unsigned total __attribute__((deprecated("renamed changesCount")));
#endif
@end


/** This notification is posted by a CBLReplication when any of these properties change:
    {status, running, error, completed, total}. It's often more convenient to observe this
    notification rather than observing each property individually. */
extern NSString* const kCBLReplicationChangeNotification;


#ifdef CBL_DEPRECATED
typedef CBLReplicationStatus CBLReplicationMode __attribute__((deprecated("renamed CBLReplicationStatus")));
#endif
