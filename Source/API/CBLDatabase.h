//
//  CBLDatabase.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/17/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLView.h"
@class CBLManager, CBLDocument, CBLRevision, CBLView, CBLQuery, CBLReplication;
@protocol CBLValidationContext;


/** Validation block, used to approve revisions being added to the database. */
typedef BOOL (^CBLValidationBlock) (CBLRevision* newRevision,
                                   id<CBLValidationContext> context);

#define VALIDATIONBLOCK(BLOCK) ^BOOL(CBLRevision* newRevision, id<CBLValidationContext> context)\
                                    {BLOCK}

/** Filter block, used in changes feeds and replication. */
typedef BOOL (^CBLFilterBlock) (CBLRevision* revision, NSDictionary* params);

#define FILTERBLOCK(BLOCK) ^BOOL(CBLRevision* revision, NSDictionary* params) {BLOCK}


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

/** Compacts the database file by purging non-current revisions, deleting unused attachment files,
    and running a SQLite "VACUUM" command. */
- (BOOL) compact: (NSError**)outError;

/** Deletes the database. */
- (BOOL) deleteDatabase: (NSError**)outError;


#pragma mark - DOCUMENT ACCESS:

/** Instantiates a CBLDocument object with the given ID.
    Doesn't touch the on-disk database; a document with that ID doesn't even need to exist yet.
    CBLDocuments are cached, so there will never be more than one instance (in this database)
    at a time with the same documentID. */
- (CBLDocument*) documentWithID: (NSString*)docID                       __attribute__((nonnull));

/** Same as -documentWithID:. Enables "[]" access in Xcode 4.4+ */
- (CBLDocument*)objectForKeyedSubscript: (NSString*)key                 __attribute__((nonnull));

/** Creates a CBLDocument object with no current ID.
    The first time you PUT to that document, it will be created on the server (via a POST). */
- (CBLDocument*) untitledDocument;

/** Returns the already-instantiated cached CBLDocument with the given ID, or nil if none is yet cached. */
- (CBLDocument*) cachedDocumentWithID: (NSString*)docID                  __attribute__((nonnull));

/** Empties the cache of recently used CBLDocument objects.
    API calls will now instantiate and return new instances. */
- (void) clearDocumentCache;


#pragma mark - LOCAL DOCUMENTS:


/** Returns the contents of the local document with the given ID, or nil if none exists. */
- (NSDictionary*) getLocalDocumentWithID: (NSString*)localDocID         __attribute__((nonnull));

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
- (CBLQuery*) queryAllDocuments;

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
- (void) defineValidation: (NSString*)validationName asBlock: (CBLValidationBlock)validationBlock
                                                                     __attribute__((nonnull(1)));

/** Returns the existing document validation function (block) registered with the given name.
    Note that validations are not persistent -- you have to re-register them on every launch. */
- (CBLValidationBlock) validationNamed: (NSString*)validationName    __attribute__((nonnull));

/** Defines or clears a named filter function.
    Filters are used by push replications to choose which documents to send. */
- (void) defineFilter: (NSString*)filterName asBlock: (CBLFilterBlock)filterBlock
                                                                     __attribute__((nonnull(1)));

/** Returns the existing filter function (block) registered with the given name.
    Note that filters are not persistent -- you have to re-register them on every launch. */
- (CBLFilterBlock) filterNamed: (NSString*)filterName                   __attribute__((nonnull));

/** Registers an object that can compile source code into executable filter blocks. */
+ (void) setFilterCompiler: (id<CBLFilterCompiler>)compiler;

/** Returns the currently registered filter compiler (nil by default). */
+ (id<CBLFilterCompiler>) filterCompiler;


/** Runs the block within a transaction. If the block returns NO, the transaction is rolled back.
    Use this when performing bulk write operations like multiple inserts/updates; it saves the overhead of multiple SQLite commits, greatly improving performance. */
- (BOOL) inTransaction: (BOOL(^)(void))bloc                         __attribute__((nonnull(1)));


#pragma mark - REPLICATION:

/** Returns an array of all current CBLReplications involving this database. */
- (NSArray*) allReplications;

/** Creates a replication that will 'push' to a database at the given URL, or returns an existing
    such replication if there already is one.
    It will initially be non-persistent; set its .persistent property to YES to make it persist. */
- (CBLReplication*) pushToURL: (NSURL*)url                              __attribute__((nonnull));

/** Creates a replication that will 'pull' from a database at the given URL, or returns an existing
    such replication if there already is one.
    It will initially be non-persistent; set its .persistent property to YES to make it persist. */
- (CBLReplication*) pullFromURL: (NSURL*)url                            __attribute__((nonnull));

/** Creates a pair of replications to both pull and push to database at the given URL, or returns existing replications if there are any.
    @param otherDbURL  The URL of the remote database, or nil for none.
    @param exclusively  If YES, any previously existing replications to or from otherDbURL will be deleted.
    @return  An array whose first element is the "pull" replication and second is the "push".
    It will initially be non-persistent; set its .persistent property to YES to make it persist. */
- (NSArray*) replicateWithURL: (NSURL*)otherDbURL exclusively: (bool)exclusively;


@end




/** This notification is posted by a CBLDatabase in response to document changes.
    Only one notification is posted per runloop cycle, no matter how many documents changed.
    If a change was not made by a CBLDocument belonging to this CBLDatabase (i.e. it came
    from another process or from a "pull" replication), the notification's userInfo dictionary will
    contain an "external" key with a value of YES. */
extern NSString* const kCBLDatabaseChangeNotification;




/** The type of callback block passed to -[CBLValidationContext enumerateChanges:]. */
typedef BOOL (^CBLChangeEnumeratorBlock) (NSString* key, id oldValue, id newValue);



/** Context passed into a CBLValidationBlock. */
@protocol CBLValidationContext <NSObject>

/** The contents of the current revision of the document, or nil if this is a new document. */
@property (readonly) CBLRevision* currentRevision;

/** The type of HTTP status to report, if the validate block returns NO.
    The default value is 403 ("Forbidden"). */
@property int errorType;

/** The error message to return in the HTTP response, if the validate block returns NO.
    The default value is "invalid document". */
@property (copy) NSString* errorMessage;


#pragma mark - CONVENIENCE METHODS:

/** Returns an array of all the keys whose values are different between the current and new revisions. */
@property (readonly) NSArray* changedKeys;

/** Returns YES if only the keys given in the 'allowedKeys' array have changed; else returns NO and sets a default error message naming the offending key. */
- (BOOL) allowChangesOnlyTo: (NSArray*)allowedKeys;

/** Returns YES if none of the keys given in the 'disallowedKeys' array have changed; else returns NO and sets a default error message naming the offending key. */
- (BOOL) disallowChangesTo: (NSArray*)disallowedKeys;

/** Calls the 'enumerator' block for each key that's changed, passing both the old and new values.
    If the block returns NO, the enumeration stops and sets a default error message, and the method returns NO; else the method returns YES. */
- (BOOL) enumerateChanges: (CBLChangeEnumeratorBlock)enumerator;

@end
