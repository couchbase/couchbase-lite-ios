//
//  CBLReplication.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/22/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import "CBLModel.h"
@class CBLDatabase;


/** Describes the current status of a replication. */
typedef enum {
    kCBLReplicationStopped, /**< The replication is finished or hit a fatal error. */
    kCBLReplicationOffline, /**< The remote host is currently unreachable. */
    kCBLReplicationIdle,    /**< Continuous replication is caught up and waiting for more changes.*/
    kCBLReplicationActive   /**< The replication is actively transferring data. */
} CBLReplicationMode;


/** A 'push' or 'pull' replication between a local and a remote database.
    Replications can be one-shot, continuous or persistent.
    CBLReplication is a model class representing a document in the _replicator database, but unless saved an instance has only a temporary existence. Saving it makes it persistent. */
@interface CBLReplication : CBLModel

/** Creates a new pull replication. It is non-persistent, unless you immediately set its
    .persistent property.
    It's more common to call -[CBLDatabase pullFromURL:] instead, as that will return an existing
    replication if possible. But if you intentionally want to create multiple replications
    from the same source database (e.g. with different filters), use this.
    Note: The replication won't start until you call -start. */
- (instancetype) initPullFromSourceURL: (NSURL*)source toDatabase: (CBLDatabase*)database
                                                                        __attribute__((nonnull));

/** Creates a new push replication. It is non-persistent, unless you immediately set its
    .persistent property.
    It's more common to call -[CBLDatabase pushToURL:] instead, as that will return an existing
    replication if possible. But if you intentionally want to create multiple replications
     to the same source database (e.g. with different filters), use this.
     Note: The replication won't start until you call -start. */
- (instancetype) initPushFromDatabase: (CBLDatabase*)database toTargetURL: (NSURL*)target
                                                                        __attribute__((nonnull));

/** The local database being replicated to/from. */
@property (nonatomic, readonly) CBLDatabase* localDatabase;

/** The URL of the remote database. */
@property (nonatomic, readonly) NSURL* remoteURL;

/** Does the replication pull from (as opposed to push to) the target? */
@property (nonatomic, readonly) BOOL pull;


#pragma mark - OPTIONS:

/** Is this replication remembered persistently in the _replicator database?
    Persistent continuous replications will automatically restart on the next launch
    or (on iOS) when the app returns to the foreground. */
@property BOOL persistent;

/** Should the target database be created if it doesn't already exist? (Defaults to NO). */
@property (nonatomic) BOOL createTarget;

/** Should the replication operate continuously, copying changes as soon as the source database is modified? (Defaults to NO). */
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


#pragma mark - AUTHENTICATION:

/** The credential (generally username+password) to use to authenticate to the remote database.
    This can either come from the URL itself (if it's of the form "http://user:pass@example.com")
    or be stored in the NSURLCredentialStore, which is a wrapper around the Keychain. */
@property (nonatomic, strong) NSURLCredential* credential;

/** OAuth parameters that the replicator should use when authenticating to the remote database.
    Keys in the dictionary should be "consumer_key", "consumer_secret", "token", "token_secret",
    and optionally "signature_method". */
@property (nonatomic, copy) NSDictionary* OAuth;

/** Email address for login with Facebook credentials. This is stored persistently in
    the replication document, but it's not sufficient for login (you also need to get a
    token from Facebook's servers, which you then pass to -registerFacebookToken:forEmailAddress.)*/
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

/** Email address for remote login with Persona (aka BrowserID). This is stored persistently in
    the replication document, but it's not sufficient for login (you also need to go through the
    Persona protocol to get a signed assertion, which you then pass to the
    -registerPersonaAssertion: method.)*/
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
    You can monitor its progress by observing the kCBLReplicationChangeNotification it sends,
    or by using KVO to observe its .running, .mode, .error, .total and .completed properties. */
- (void) start;

/** Stops replication, asynchronously. */
- (void) stop;

/** Restarts a completed or failed replication. */
- (void) restart;

/** The replication's current state, one of {stopped, offline, idle, active}. */
@property (nonatomic, readonly) CBLReplicationMode mode;

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
@property (nonatomic, readonly, retain) NSError* error;
@property (nonatomic, readonly) unsigned completed __attribute__((deprecated("renamed completedChangesCount")));
@property (nonatomic, readonly) unsigned total __attribute__((deprecated("renamed changesCount")));
#endif
@end


/** This notification is posted by a CBLReplication when any of these properties change:
    {mode, running, error, completed, total}. It's often more convenient to observe this
    notification rather than observing each property individually. */
extern NSString* const kCBLReplicationChangeNotification;
