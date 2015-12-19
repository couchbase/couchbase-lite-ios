//
//  CBLReplication.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/22/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import "CBLBase.h"
@class CBLDatabase, CBLDocument;
@protocol CBLAuthenticator;

NS_ASSUME_NONNULL_BEGIN

/** Describes the current status of a replication. */
typedef NS_ENUM(unsigned, CBLReplicationStatus) {
    kCBLReplicationStopped, /**< The replication is finished or hit a fatal error. */
    kCBLReplicationOffline, /**< The remote host is currently unreachable. */
    kCBLReplicationIdle,    /**< Continuous replication is caught up and waiting for more changes.*/
    kCBLReplicationActive   /**< The replication is actively transferring data. */
} ;


/** Callback for notifying progress downloading an attachment.
    `bytesRead` is the number of bytes received so far and `contentLength` is the total number of
    bytes to read. The download is complete when bytesRead == contentLength. If an error occurs,
    `error` will be non-nil. */
typedef void (^CBLAttachmentProgressBlock)(uint64_t bytesRead,
                                           uint64_t contentLength,
                                           NSError* error);


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
@property (nonatomic, copy, nullable) NSString* filter;

/** Parameters to pass to the filter function.
    Should map strings to strings. */
@property (nonatomic, copy, nullable) CBLJSONDict* filterParams;

/** List of Sync Gateway channel names to filter by; a nil value means no filtering, i.e. all
    available channels will be synced.
    Only valid for pull replications whose source database is on a Couchbase Sync Gateway server.
    (This is a convenience that just reads or changes the values of .filter and .query_params.) */
@property (nonatomic, copy, nullable) CBLArrayOf(NSString*)* channels;

/** Sets the documents to specify as part of the replication. */
@property (copy, nullable) CBLArrayOf(NSString*) *documentIDs;

/** Should attachments be downloaded automatically along with documents?
    Defaults to YES; if you set it to NO you can later download individual attachments by calling
    -downloadAttachment:. */
@property (nonatomic) BOOL downloadsAttachments;

/** Extra HTTP headers to send in all requests to the remote server.
    Should map strings (header names) to strings. */
@property (nonatomic, copy, nullable) CBLDictOf(NSString*, NSString*)* headers;

/** Specifies which class of network the replication will operate over.
    Default value is nil, which means replicate over all networks.
    Set to "WiFi" (or "!Cell") to replicate only over WiFi,
    or to "Cell" (or "!WiFi") to replicate only over cellular. */
@property (nonatomic, copy, nullable) NSString* network;

/** An optional JSON-compatible dictionary of extra properties for the replicator. */
@property (nonatomic, copy, nullable) CBLJSONDict* customProperties;


#pragma mark - AUTHENTICATION:

/** An object that knows how to authenticate with a remote server.
    CBLAuthenticator is an opaque protocol; instances can be created by calling the factory methods
    of the class of the same name. */
@property (nonatomic, strong, nullable) id<CBLAuthenticator> authenticator;

/** The credential (generally username+password) to use to authenticate to the remote database.
    This can either come from the URL itself (if it's of the form "http://user:pass@example.com")
    or be stored in the NSURLCredentialStorage, which is a wrapper around the Keychain. */
@property (nonatomic, strong, nullable) NSURLCredential* credential;

/** OAuth parameters that the replicator should use when authenticating to the remote database.
    Keys in the dictionary should be "consumer_key", "consumer_secret", "token", "token_secret",
    and optionally "signature_method". */
@property (nonatomic, copy, nullable) CBLJSONDict* OAuth;

/** The base URL of the remote server, for use as the "origin" parameter when requesting Persona or
    Facebook authentication. */
@property (readonly, nullable) NSURL* personaOrigin;

/** Registers an HTTP cookie that will be sent to the remote server along with the replication's
    HTTP requests. This is useful if you've obtained a session cookie through some external means.
    The cookie will be saved persistently until its `expirationDate` passes; or if that date is
    nil, the cookie will only be associated with this replication object.
 
    The parameters have the same meanings as in the NSHTTPCookie API. If the `path` is nil, the
    path of this replication's URL is used.

    The replicator does _not_ use the standard shared NSHTTPCookieStorage, so registering a cookie
    through that will have no effect. This is because each replication has independent
    authentication and may need to send different cookies. */
- (void) setCookieNamed: (NSString*)name
              withValue: (NSString*)value
                   path: (nullable NSString*)path
         expirationDate: (nullable NSDate*)expirationDate
                 secure: (BOOL)secure;

/** Deletes the named cookie from this replication's cookie storage. */
- (void) deleteCookieNamed: (NSString *)name;

/** Adds additional SSL root certificates to be trusted by the replicator, or entirely overrides the
    OS's default list of trusted root certs.
    @param certs  An array of SecCertificateRefs of root certs that should be trusted. Most often
        these will be self-signed certs, but they might also be the roots of nonstandard CAs.
    @param onlyThese  If NO, the given certs are appended to the system's built-in list of trusted
        root certs; if YES, it replaces them (so *only* the given certs will be trusted.) */
+ (void) setAnchorCerts: (nullable NSArray*)certs onlyThese: (BOOL)onlyThese;

/** The server's SSL certificate. This will be NULL until the first HTTPS response is received
    from the server. */
@property (readonly, nullable) SecCertificateRef serverCertificate;

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
@property (nonatomic, readonly, strong, nullable) NSError* lastError;

/** The number of completed changes processed, if the task is active, else 0 (observable). */
@property (nonatomic, readonly) unsigned completedChangesCount;

/** The total number of changes to be processed, if the task is active, else 0 (observable). */
@property (nonatomic, readonly) unsigned changesCount;

#pragma mark - PENDING DOCUMENTS (PUSH ONLY):

/** The IDs of documents that have local changes that have not yet been pushed to the server
    by this replication. This only considers documents that this replication would push: documents
    that aren't matched by its filter or documentIDs (if any) are ignored.
    If the replication hasn't started yet, or if it's encountered an error, or if it's not a push
    replication at all, the value of this property is nil. */
@property (readonly, nullable) NSSet* pendingDocumentIDs;

/** Returns YES if a document has local changes that this replication will push to its server, but
    hasn't yet. This only considers documents that this replication would push: it returns NO for
    a document that isn't matched by its filter or documentIDs, even if that document has local
    changes. */
- (BOOL) isDocumentPending: (CBLDocument*)doc;

#pragma mark - ATTACHMENT DOWNLOADING (PULL ONLY)

/** Starts an asynchronous download of an attachment that was skipped in a pull replication.
    @param attachment  The attachment to download.
    @return  An NSProgress object that will be updated to report the progress of the download.
        You can use Key-Value Observing to observe its fractionCompleted property.
        (Note: observer callbacks will be issued on a background thread!)
        You can cancel the download by calling its -cancel method. */
- (NSProgress*) downloadAttachment: (CBLAttachment*)attachment;


- (instancetype) init NS_UNAVAILABLE;

@end


/** This notification is posted by a CBLReplication when any of these properties change:
    {status, running, error, completed, total}. It's often more convenient to observe this
    notification rather than observing each property individually. */
extern NSString* const kCBLReplicationChangeNotification;

/** NSProgress userInfo key used to report an NSError when an attachment download fails. */
extern NSString* const kCBLProgressErrorKey;


NS_ASSUME_NONNULL_END
