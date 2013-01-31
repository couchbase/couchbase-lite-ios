//
//  CBLReplication.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/22/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "CBLModel.h"
@class CBLDatabase;


typedef enum {
    kCBLReplicationStopped,
    kCBLReplicationOffline,
    kCBLReplicationIdle,
    kCBLReplicationActive
} CBLReplicationMode;


/** A 'push' or 'pull' replication between a local and a remote database.
    Replications can be one-shot, continuous or persistent.
    CBLReplication is a model class representing a document in the _replicator database, but unless saved an instance has only a temporary existence. Saving it makes it persistent. */
@interface CBLReplication : CBLModel

/** The local database being replicated to/from. */
@property (nonatomic, readonly) CBLDatabase* localDatabase;

/** The URL of the remote database. */
@property (nonatomic, readonly) NSURL* remoteURL;

/** Does the replication pull from (as opposed to push to) the target? */
@property (nonatomic, readonly) bool pull;


#pragma mark - OPTIONS:

/** Is this replication remembered persistently in the _replicator database?
    Persistent continuous replications will automatically restart on the next launch
    or (on iOS) when the app returns to the foreground. */
@property bool persistent;

/** Should the target database be created if it doesn't already exist? (Defaults to NO). */
@property (nonatomic) bool create_target;

/** Should the replication operate continuously, copying changes as soon as the source database is modified? (Defaults to NO). */
@property (nonatomic) bool continuous;

/** Path of an optional filter function to run on the source server.
    Only documents for which the function returns true are replicated.
    The path looks like "designdocname/filtername". */
@property (nonatomic, copy) NSString* filter;

/** Parameters to pass to the filter function.
    Should map strings to strings. */
@property (nonatomic, copy) NSDictionary* query_params;

/** Sets the documents to specify as part of the replication. */
@property (copy) NSArray *doc_ids;

/** Extra HTTP headers to send in all requests to the remote server.
    Should map strings (header names) to strings. */
@property (nonatomic, copy) NSDictionary* headers;


#pragma mark - AUTHENTICATION:

/** The credential (generally username+password) to use to authenticate to the remote database.
    This can either come from the URL itself (if it's of the form "http://user:pass@example.com")
    or be stored in the NSURLCredentialStore, which is a wrapper around the Keychain. */
@property NSURLCredential* credential;

/** OAuth parameters that the replicator should use when authenticating to the remote database.
    Keys in the dictionary should be "consumer_key", "consumer_secret", "token", "token_secret",
    and optionally "signature_method". */
@property (nonatomic, copy) NSDictionary* OAuth;

/** The base URL of the remote server, for use as the "origin" parameter when requesting BrowserID authentication. */
@property (readonly) NSURL* browserIDOrigin;

/** Email address for remote login with BrowserID (aka Persona). This is stored persistently in
    the replication document, but it's not sufficient for login (you also need to go through the
    BrowserID protocol to get a signed assertion, which you then pass to the
    -registerBrowserIDAssertion: method.)*/
@property (nonatomic, copy) NSString* browserIDEmailAddress;

/** Registers a BrowserID 'assertion' (ID verification) string that will be used on the next login to the remote server. This also sets browserIDEmailAddress.
    Note: An assertion is a type of certificate and typically has a very short lifespan (like, a
    few minutes.) For this reason it's not stored in the replication document, but instead kept
    in an in-memory registry private to the BrowserID authorizer. You should initiate a replication
    immediately after registering the assertion, so that the replicator engine can use it to
    authenticate before it expires. After that, the replicator will have a login session cookie
    that should last significantly longer before needing to be renewed. */
- (bool) registerBrowserIDAssertion: (NSString*)assertion;


#pragma mark - STATUS:

/** Starts the replication, asynchronously. */
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
@property (nonatomic, readonly) bool running;

/** The error status of the replication, or nil if there have not been any errors since it started. */
@property (nonatomic, readonly, retain) NSError* error;

/** The number of completed changes processed, if the task is active, else 0 (observable). */
@property (nonatomic, readonly) unsigned completed;

/** The total number of changes to be processed, if the task is active, else 0 (observable). */
@property (nonatomic, readonly) unsigned total;


@end


/** This notification is posted by a CBLReplication when any of these properties change:
    {mode, running, error, completed, total}. It's often more convenient to observe this
    notification rather than observing each property individually. */
extern NSString* const kCBLReplicationChangeNotification;
