//
//  CBLReplication.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/22/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLDatabase;
@protocol CBLAuthenticator;


/** Describes the current status of a replication. */
typedef NS_ENUM(unsigned, CBLReplicationStatus) {
    kCBLReplicationStopped, /**< The replication is finished or hit a fatal error. */
    kCBLReplicationOffline, /**< The remote host is currently unreachable. */
    kCBLReplicationIdle,    /**< Continuous replication is caught up and waiting for more changes.*/
    kCBLReplicationActive   /**< The replication is actively transferring data. */
} ;


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

/** An object that knows how to authenticate with a remote server.
    CBLAuthenticator is an opaque protocol; instances can be created by calling the factory methods
    of the class of the same name. */
@property id<CBLAuthenticator> authenticator;

/** The credential (generally username+password) to use to authenticate to the remote database.
    This can either come from the URL itself (if it's of the form "http://user:pass@example.com")
    or be stored in the NSURLCredentialStore, which is a wrapper around the Keychain. */
@property (nonatomic, strong) NSURLCredential* credential;

/** OAuth parameters that the replicator should use when authenticating to the remote database.
    Keys in the dictionary should be "consumer_key", "consumer_secret", "token", "token_secret",
    and optionally "signature_method". */
@property (nonatomic, copy) NSDictionary* OAuth;

/** The base URL of the remote server, for use as the "origin" parameter when requesting Persona or
    Facebook authentication. */
@property (readonly) NSURL* personaOrigin;

/** Adds a cookie to the shared NSHTTPCookieStorage that will be sent to the remote server. This
    is useful if you've obtained a session cookie through some external means and need to tell the
    replicator to send it for authentication purposes.
    This method constructs an NSHTTPCookie from the given parameters, as well as the remote server
    URL's host, port and path.
    If you already have an NSHTTPCookie object for the remote server, you can simply add it to the
    sharedHTTPCookieStorage yourself. 
    If you have a "Set-Cookie:" response header, you can use NSHTTPCookie's class methods to parse
    it to a cookie object, then add it to the sharedHTTPCookieStorage. */
- (void) setCookieNamed: (NSString*)name
              withValue: (NSString*)value
                   path: (NSString*)path
         expirationDate: (NSDate*)expirationDate
                 secure: (BOOL)secure;

/** Deletes the named cookie from the shared NSHTTPCookieStorage for the remote server's URL. */
-(void)deleteCookieNamed:(NSString *)name;

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

/** Suspends/resumes a replication.
    On iOS a replication will suspend itself when the app goes into the background, and resume
    when the app is re-activated. If your app receives a push notification while suspended and needs
    to run the replication to download new data, your handler should set suspended to NO to resume
    replication, and then set the property back to YES when it's done. */
@property BOOL suspended;

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
@property (nonatomic, copy) NSString* facebookEmailAddress
    __attribute__((deprecated("set authenticator property instead")));
- (BOOL) registerFacebookToken: (NSString*)token forEmailAddress: (NSString*)email
    __attribute__((deprecated("set authenticator property instead")));
- (BOOL) registerPersonaAssertion: (NSString*)assertion
    __attribute__((deprecated("set authenticator property instead")));
@property (nonatomic, copy) NSString* personaEmailAddress
    __attribute__((deprecated("set authenticator property instead")));
#endif

@end


/** This notification is posted by a CBLReplication when any of these properties change:
    {status, running, error, completed, total}. It's often more convenient to observe this
    notification rather than observing each property individually. */
extern NSString* const kCBLReplicationChangeNotification;
