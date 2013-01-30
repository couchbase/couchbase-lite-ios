//
//  TDDatabase.h
//  TouchDB
//
//  Created by Jens Alfke on 6/17/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TDView.h"
@class TDDatabaseManager, TDDocument, TDRevision, TDView, TDQuery, TDReplication;
@protocol TDValidationContext;


/** Validation block, used to approve revisions being added to the database. */
typedef BOOL (^TDValidationBlock) (TDRevision* newRevision,
                                   id<TDValidationContext> context);

#define VALIDATIONBLOCK(BLOCK) ^BOOL(TDRevision* newRevision, id<TDValidationContext> context)\
                                    {BLOCK}

/** Filter block, used in changes feeds and replication. */
typedef BOOL (^TDFilterBlock) (TDRevision* revision, NSDictionary* params);

#define FILTERBLOCK(BLOCK) ^BOOL(TDRevision* revision, NSDictionary* params) {BLOCK}


/** A TouchDB database. */
@interface TDDatabase : NSObject

/** The database's name. */
@property (readonly) NSString* name;

/** The database manager that owns this database. */
@property (readonly) TDDatabaseManager* manager;

/** The number of documents in the database. */
@property (readonly) NSUInteger documentCount;

/** The latest sequence number used.
    Every new revision is assigned a new sequence number, so this property increases monotonically
    as changes are made to the database. It can be used to check whether the database has changed
    between two points in time. */
@property (readonly) SInt64 lastSequenceNumber;

/** The 'touchdb:' URL of the database's REST API.
    Only available if you've linked with the TouchDBListener framework. */
@property (readonly) NSURL* internalURL;


#pragma mark - HOUSEKEEPING:

/** Compacts the database file by purging non-current revisions, deleting unused attachment files,
    and running a SQLite "VACUUM" command. */
- (BOOL) compact: (NSError**)outError;

/** Deletes the database. */
- (BOOL) deleteDatabase: (NSError**)outError;


#pragma mark - DOCUMENT ACCESS:

/** Instantiates a TDDocument object with the given ID.
    Doesn't touch the on-disk database; a document with that ID doesn't even need to exist yet.
    TDDocuments are cached, so there will never be more than one instance (in this database)
    at a time with the same documentID. */
- (TDDocument*) documentWithID: (NSString*)docID;

/** Same as -documentWithID:. Enables "[]" access in Xcode 4.4+ */
- (TDDocument*)objectForKeyedSubscript: (NSString*)key;

/** Creates a TDDocument object with no current ID.
    The first time you PUT to that document, it will be created on the server (via a POST). */
- (TDDocument*) untitledDocument;

/** Returns the already-instantiated cached TDDocument with the given ID, or nil if none is yet cached. */
- (TDDocument*) cachedDocumentWithID: (NSString*)docID;

/** Empties the cache of recently used TDDocument objects.
    API calls will now instantiate and return new instances. */
- (void) clearDocumentCache;


#pragma mark - VIEWS AND OTHER CALLBACKS:

/** Returns a query that matches all documents in the database.
    This is like querying an imaginary view that emits every document's ID as a key. */
- (TDQuery*) queryAllDocuments;

/** Creates a one-shot query with the given map function. This is equivalent to creating an
    anonymous TDView and then deleting it immediately after querying it. It may be useful during
    development, but in general this is inefficient if this map will be used more than once,
    because the entire view has to be regenerated from scratch every time. */
- (TDQuery*) slowQueryWithMap: (TDMapBlock)mapBlock;

/** Returns a TDView object for the view with the given name.
    (This succeeds even if the view doesn't already exist, but the view won't be added to the database until the TDView is assigned a map function.) */
- (TDView*) viewNamed: (NSString*)name;

/** An array of all existing views. */
@property (readonly) NSArray* allViews;

/** Defines or clears a named document validation function.
    Before any change to the database, all registered validation functions are called and given a
    chance to reject it. (This includes incoming changes from a pull replication.) */
- (void) defineValidation: (NSString*)validationName asBlock: (TDValidationBlock)validationBlock;


/** Defines or clears a named filter function.
    Filters are used by push replications to choose which documents to send. */
- (void) defineFilter: (NSString*)filterName asBlock: (TDFilterBlock)filterBlock;


/** Runs the block within a transaction. If the block returns NO, the transaction is rolled back.
    Use this when performing bulk operations like multiple inserts/updates; it saves the overhead of multiple SQLite commits. */
- (BOOL) inTransaction: (BOOL(^)(void))block;


#pragma mark - REPLICATION:

/** Returns an array of all current TDReplications involving this database. */
- (NSArray*) allReplications;

/** Creates a replication that will 'push' to a database at the given URL.
    It will initially be non-persistent; set its .persistent property to YES to make it persist. */
- (TDReplication*) pushToURL: (NSURL*)url;

/** Creates a replication that will 'pull' from a database at the given URL.
    It will initially be non-persistent; set its .persistent property to YES to make it persist. */
- (TDReplication*) pullFromURL: (NSURL*)url;

/** Creates a pair of replications to both pull and push to database at the given URL.
    @param otherDbURL  The URL of the remote database.
    @param exclusively  If YES, any previously existing replications to or from otherDbURL will be deleted.
    @return  An array whose first element is the "pull" replication and second is the "push".
    It will initially be non-persistent; set its .persistent property to YES to make it persist. */
- (NSArray*) replicateWithURL: (NSURL*)otherDbURL exclusively: (bool)exclusively;


@end




/** This notification is posted by a TDDatabase in response to document changes.
    Only one notification is posted per runloop cycle, no matter how many documents changed.
    If a change was not made by a TDDocument belonging to this TDDatabase (i.e. it came
    from another process or from a "pull" replication), the notification's userInfo dictionary will
    contain an "external" key with a value of YES. */
extern NSString* const kTDDatabaseChangeNotification;




typedef BOOL (^TDChangeEnumeratorBlock) (NSString* key, id oldValue, id newValue);


/** Context passed into a TDValidationBlock. */
@protocol TDValidationContext <NSObject>

/** The contents of the current revision of the document, or nil if this is a new document. */
@property (readonly) TDRevision* currentRevision;

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
- (BOOL) enumerateChanges: (TDChangeEnumeratorBlock)enumerator;

@end
