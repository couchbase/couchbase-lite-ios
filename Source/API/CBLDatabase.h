//
//  CBLDatabase.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/17/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLView.h"
@class CBLManager, CBLDocument, CBLRevision, CBLSavedRevision, CBLView, CBLQuery, CBLReplication;
@protocol CBLValidationContext;


/** Validation block, used to approve revisions being added to the database.
    The block should call `[context reject]` or `[context rejectWithMessage:]` if the proposed
    new revision is invalid. */
typedef void (^CBLValidationBlock) (CBLRevision* newRevision,
                                   id<CBLValidationContext> context);

#define VALIDATIONBLOCK(BLOCK) ^void(CBLRevision* newRevision, id<CBLValidationContext> context)\
                                    {BLOCK}

/** Filter block, used in changes feeds and replication. */
typedef BOOL (^CBLFilterBlock) (CBLSavedRevision* revision, NSDictionary* params);

#define FILTERBLOCK(BLOCK) ^BOOL(CBLSavedRevision* revision, NSDictionary* params) {BLOCK}


/** An external object that knows how to convert source code into an executable filter. */
@protocol CBLFilterCompiler <NSObject>
- (CBLFilterBlock) compileFilterFunction: (NSString*)filterSource language: (NSString*)language;
@end


/** A CouchbaseLite database. */
@interface CBLDatabase : NSObject

/** The database's name. */
@property (readonly) NSString* name;

/** The database manager that owns this database. */
@property (readonly) CBLManager* manager;

/** The number of documents in the database. */
@property (readonly) NSUInteger documentCount;

/** The latest sequence number used.
    Every new revision is assigned a new sequence number, so this property increases monotonically
    as changes are made to the database. It can be used to check whether the database has changed
    between two points in time. */
@property (readonly) SInt64 lastSequenceNumber;

/** The URL of the database in the REST API. You can access this URL within this process,
    using NSURLConnection or other APIs that use that (such as XMLHTTPRequest inside a WebView),
    but it isn't available outside the process.
    This method is only available if you've linked with the CouchbaseLiteListener framework. */
@property (readonly) NSURL* internalURL;


#pragma mark - HOUSEKEEPING:

/** Closes a database.
    This first stops all replications, and calls -saveAllModels: to save changes to CBLModel
    objects. It returns NO if some models failed to save. */
- (BOOL) close: (NSError**)error;

/** Compacts the database file by purging non-current JSON bodies, pruning revisions older than
    the maxRevTreeDepth, deleting unused attachment files, and vacuuming the SQLite database. */
- (BOOL) compact: (NSError**)outError;

/** The maximum depth of a document's revision tree (or, max length of its revision history.)
    Revisions older than this limit will be deleted during a -compact: operation. 
    Smaller values save space, at the expense of making document conflicts somewhat more likely. */
@property NSUInteger maxRevTreeDepth;

/** Deletes the database. */
- (BOOL) deleteDatabase: (NSError**)outError;

/** Changes the database's unique IDs to new random values.
    Ordinarily you should never need to call this method; it's only made public to fix databases
    that are already affected by bug github.com/couchbase/couchbase-lite-ios/issues/145 .
    Make sure you only call this once, to fix that problem, because every call has the side effect
    of resetting all replications, making them run slow the next time. */
- (BOOL) replaceUUIDs: (NSError**)outError;


#pragma mark - DOCUMENT ACCESS:

/** Instantiates a CBLDocument object with the given ID.
    Doesn't touch the on-disk database; a document with that ID doesn't even need to exist yet.
    CBLDocuments are cached, so there will never be more than one instance (in this database)
    at a time with the same documentID. */
- (CBLDocument*) documentWithID: (NSString*)docID                       __attribute__((nonnull));

/** Instantiates a CBLDocument object with the given ID.
    Unlike -documentWithID: this method loads the document from the database, and returns nil if
    no such document exists.
    CBLDocuments are cached, so there will never be more than one instance (in this database)
    at a time with the same documentID. */
- (CBLDocument*) existingDocumentWithID: (NSString*)docID               __attribute__((nonnull));

/** Same as -documentWithID:. Enables "[]" access in Xcode 4.4+ */
- (CBLDocument*)objectForKeyedSubscript: (NSString*)key                 __attribute__((nonnull));

/** Creates a new CBLDocument object with no properties and a new (random) UUID.
    The document will be saved to the database when you call -putProperties: on it. */
- (CBLDocument*) createDocument;


#pragma mark - LOCAL DOCUMENTS:


/** Returns the contents of the local document with the given ID, or nil if none exists. */
- (NSDictionary*) existingLocalDocumentWithID: (NSString*)localDocID         __attribute__((nonnull));

/** Sets the contents of the local document with the given ID. Unlike CouchDB, no revision-ID
    checking is done; the put always succeeds. If the properties dictionary is nil, the document
    will be deleted. */
- (BOOL) putLocalDocument: (NSDictionary*)properties
                   withID: (NSString*)localDocID
                    error: (NSError**)outError                      __attribute__((nonnull(2)));

/** Deletes the local document with the given ID. */
- (BOOL) deleteLocalDocumentWithID: (NSString*)localDocID
                             error: (NSError**)outError             __attribute__((nonnull(1)));


#pragma mark - VIEWS AND OTHER CALLBACKS:

/** Returns a query that matches all documents in the database.
    This is like querying an imaginary view that emits every document's ID as a key. */
- (CBLQuery*) createAllDocumentsQuery;

/** Creates a one-shot query with the given map function. This is equivalent to creating an
    anonymous CBLView and then deleting it immediately after querying it. It may be useful during
    development, but in general this is inefficient if this map will be used more than once,
    because the entire view has to be regenerated from scratch every time. */
- (CBLQuery*) slowQueryWithMap: (CBLMapBlock)mapBlock                    __attribute__((nonnull));

/** Returns a CBLView object for the view with the given name.
    (This succeeds even if the view doesn't already exist, but the view won't be added to the database until the CBLView is assigned a map function.) */
- (CBLView*) viewNamed: (NSString*)name                                  __attribute__((nonnull));

/** Returns the existing CBLView with the given name, or nil if none. */
- (CBLView*) existingViewNamed: (NSString*)name                         __attribute__((nonnull));

/** Defines or clears a named document validation function.
    Before any change to the database, all registered validation functions are called and given a
    chance to reject it. (This includes incoming changes from a pull replication.) */
- (void) setValidationNamed: (NSString*)validationName asBlock: (CBLValidationBlock)validationBlock
                                                                     __attribute__((nonnull(1)));

/** Returns the existing document validation function (block) registered with the given name.
    Note that validations are not persistent -- you have to re-register them on every launch. */
- (CBLValidationBlock) validationNamed: (NSString*)validationName    __attribute__((nonnull));

/** Defines or clears a named filter function.
    Filters are used by push replications to choose which documents to send. */
- (void) setFilterNamed: (NSString*)filterName asBlock: (CBLFilterBlock)filterBlock
                                                                     __attribute__((nonnull(1)));

/** Returns the existing filter function (block) registered with the given name.
    Note that filters are not persistent -- you have to re-register them on every launch. */
- (CBLFilterBlock) filterNamed: (NSString*)filterName                   __attribute__((nonnull));

/** Registers an object that can compile source code into executable filter blocks. */
+ (void) setFilterCompiler: (id<CBLFilterCompiler>)compiler;

/** Returns the currently registered filter compiler (nil by default). */
+ (id<CBLFilterCompiler>) filterCompiler;


#pragma mark - TRANSACTIONS / THREADING:

/** Runs the block within a transaction. If the block returns NO, the transaction is rolled back.
    Use this when performing bulk write operations like multiple inserts/updates; it saves the 
    overhead of multiple SQLite commits, greatly improving performance. */
- (BOOL) inTransaction: (BOOL(^)(void))block                        __attribute__((nonnull(1)));

/** Runs the block asynchronously on the database's dispatch queue or thread.
    Unlike the rest of the API, this can be called from any thread, and provides a limited form
    of multithreaded access to Couchbase Lite. */
- (void) doAsync: (void (^)())block                                 __attribute__((nonnull(1)));

/** Runs the block _synchronously_ on the database's dispatch queue or thread: this method does
    not return until after the block has completed.
    Unlike the rest of the API, this can _only_ be called from other threads/queues:  If you call it
    from the same thread or dispatch queue that the database runs on, **it will deadlock!** */
- (void) doSync: (void (^)())block                                 __attribute__((nonnull(1)));


#pragma mark - REPLICATION:

/** Returns an array of all current, running CBLReplications involving this database. */
- (NSArray*) allReplications;

/** Creates a replication that will 'push' this database to a remote database at the given URL.
    This always creates a new replication, even if there is already one to the given URL.
    You must call -start on the replication to start it. */
- (CBLReplication*) createPushReplication: (NSURL*)url;

/** Creates a replication that will 'pull' from a remote database at the given URL to this database.
    This always creates a new replication, even if there is already one from the given URL.
    You must call -start on the replication to start it. */
- (CBLReplication*) createPullReplication: (NSURL*)url;


@end




/** This notification is posted by a CBLDatabase in response to document changes.
    The notification's userInfo dictionary's "changes" key contains an NSArray of
    CBLDatabaseChange objects that describe the revisions that were added. */
extern NSString* const kCBLDatabaseChangeNotification;




/** The type of callback block passed to -[CBLValidationContext enumerateChanges:]. */
typedef BOOL (^CBLChangeEnumeratorBlock) (NSString* key, id oldValue, id newValue);



/** Context passed into a CBLValidationBlock. */
@protocol CBLValidationContext <NSObject>

/** The contents of the current revision of the document, or nil if this is a new document. */
@property (readonly) CBLSavedRevision* currentRevision;

/** Rejects the proposed new revision. */
- (void) reject;

/** Rejects the proposed new revision. Any resulting error will contain the provided message;
    for example, if the change came from an external HTTP request, the message will be in the
    response status line. The default message is "invalid document". */
- (void) rejectWithMessage: (NSString*)message;


#pragma mark - CONVENIENCE METHODS:

/** Returns an array of all the keys whose values are different between the current and new revisions. */
@property (readonly) NSArray* changedKeys;

/** Calls the 'enumerator' block for each key that's changed, passing both the old and new values.
    If the block returns NO, the enumeration stops and rejects the revision, and the method returns
    NO; else the method returns YES. */
- (BOOL) validateChanges: (CBLChangeEnumeratorBlock)enumerator;

@end
