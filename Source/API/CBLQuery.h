//
//  CBLQuery.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/18/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class CBLDatabase, CBLDocument;
@class CBLLiveQuery, CBLQueryEnumerator, CBLQueryRow;


typedef enum {
    kCBLAllDocs,            /**< Normal behavior for all-docs query */
    kCBLIncludeDeleted,     /**< Will include rows for deleted documents */
    kCBLShowConflicts,      /**< Rows will indicate conflicting revisions */
    kCBLOnlyConflicts       /**< Will _only_ return rows for docs in conflict */
} CBLAllDocsMode;


/** Options for CBLQuery.updateIndex property, to allow out-of-date results to be returned. */
typedef enum {
    kCBLUpdateIndexBefore,  /**< Always update index if needed before querying (default) */
    kCBLUpdateIndexNever,   /**< Don't update the index; results may be out of date */
    kCBLUpdateIndexAfter    /**< Update index after querying (results may still be out of date) */
} CBLUpdateIndexMode;


/** Represents a query of a CouchbaseLite 'view', or of a view-like resource like _all_documents. */
@interface CBLQuery : NSObject

/** The database that contains this view. */
@property (readonly) CBLDatabase* database;

/** The maximum number of rows to return. Default value is 0, meaning 'unlimited'. */
@property NSUInteger limit;

/** The number of initial rows to skip. Default value is 0.
    Should only be used with small values. For efficient paging, use startKey and limit.*/
@property NSUInteger skip;

/** Should the rows be returned in descending key order? Default value is NO. */
@property BOOL descending;

/** If non-nil, the key value to start at. */
@property (copy) id startKey;

/** If non-nil, the key value to end after. */
@property (copy) id endKey;

/** If non-nil, the document ID to start at. 
    (Useful if the view contains multiple identical keys, making .startKey ambiguous.) */
@property (copy) NSString* startKeyDocID;

/** If non-nil, the document ID to end at. 
    (Useful if the view contains multiple identical keys, making .endKey ambiguous.) */
@property (copy) NSString* endKeyDocID;

/** Determines whether or when the view index is updated. By default, the index will be updated
    if necessary before the query runs -- this guarantees up-to-date results but can cause a
    delay. The "Never" mode skips updating the index, so it's faster but can return out of date
    results. The "After" mode is a compromise that may return out of date results but if so will
    start asynchronously updating the index after the query so future results are accurate. */
@property CBLUpdateIndexMode updateIndex;

/** If non-nil, the query will fetch only the rows with the given keys. */
@property (copy) NSArray* keys;

/** If set to YES, disables use of the reduce function.
    (Equivalent to setting "?reduce=false" in the REST API.) */
@property BOOL mapOnly;

/** If non-zero, enables grouping of results, in views that have reduce functions. */
@property NSUInteger groupLevel;

/** If set to YES, the results will include the entire document contents of the associated rows.
    These can be accessed via CBLQueryRow's -documentProperties property.
    This slows down the query, but can be a good optimization if you know you'll need the entire
    contents of each document. */
@property BOOL prefetch;

/** Changes the behavior of a query created by -queryAllDocuments.
    * In mode kCBLAllDocs (the default), the query simply returns all non-deleted documents.
    * In mode kCBLIncludeDeleted, it also returns deleted documents.
    * In mode kCBLShowConflicts, the .conflictingRevisions property of each row will return the
      conflicting revisions, if any, of that document.
    * In mode kCBLOnlyConflicts, _only_ documents in conflict will be returned.
      (This mode is especially useful for use with a CBLLiveQuery, so you can be notified of
      conflicts as they happen, i.e. when they're pulled in by a replication.) */
@property CBLAllDocsMode allDocsMode;

/** Sends the query to the server and returns an enumerator over the result rows (Synchronous). */
- (CBLQueryEnumerator*) rows: (NSError**)outError;

/** Starts an asynchronous query. Returns immediately, then calls the onComplete block when the
    query completes, passing it the row enumerator.
    If the query fails, the block will receive a non-nil enumerator but its .error property will
    be set to a value reflecting the error. The originating CBLQuery's .error property will NOT
    change. */
- (void) runAsync: (void (^)(CBLQueryEnumerator*, NSError*))onComplete   __attribute__((nonnull));

/** Returns a live query with the same parameters. */
- (CBLLiveQuery*) asLiveQuery;



#ifdef CBL_DEPRECATED
@property BOOL includeDeleted __attribute__((deprecated("use allDocsMode instead")));
@property CBLUpdateIndexMode stale __attribute__((deprecated("renamed staleness")));
- (CBLQueryEnumerator*) rows __attribute__((deprecated("renamed rows:")));
- (CBLQueryEnumerator*) rowsIfChanged __attribute__((deprecated("use CBLQueryEnumerator.stale")));
@property (readonly) NSError* error __attribute__((deprecated("use rows: which returns an error")));
#endif
@end


/** A CBLQuery subclass that automatically refreshes the result rows every time the database changes.
    All you need to do is use KVO to observe changes to the .rows property. */
@interface CBLLiveQuery : CBLQuery

/** Starts observing database changes. The .rows property will now update automatically. (You 
    usually don't need to call this yourself, since accessing or observing the .rows property will
    call -start for you.) */
- (void) start;

/** Stops observing database changes. Calling -start or .rows will restart it. */
- (void) stop;

/** In CBLLiveQuery the -rows accessor is now a non-blocking property that can be observed using KVO. Its value will be nil until the initial query finishes. */
@property (readonly, retain) CBLQueryEnumerator* rows;

/** Blocks until the intial async query finishes. 
    After this call either .rows or .error will be non-nil. */
- (BOOL) waitForRows;

/** If non-nil, the error of the last execution of the query.
    If nil, the last execution of the query was successful. */
@property (readonly) NSError* lastError;

@end


/** Enumerator on a CBLQuery's result rows.
    The objects returned are instances of CBLQueryRow. */
@interface CBLQueryEnumerator : NSEnumerator <NSCopying>

/** The number of rows returned in this enumerator */
@property (readonly) NSUInteger count;

/** The database's current sequenceNumber at the time the view was generated. */
@property (readonly) UInt64 sequenceNumber;

/** YES if the database has changed since the view was generated. */
@property (readonly) BOOL stale;

/** The next result row. This is the same as -nextObject but with a checked return type. */
- (CBLQueryRow*) nextRow;

/** Random access to a row in the result */
- (CBLQueryRow*) rowAtIndex: (NSUInteger)index;

/** Resets the enumeration so the next call to -nextObject or -nextRow will return the first row. */
- (void) reset;

@end


/** A result row from a CouchbaseLite view query.
    Full-text and geo queries return subclasses -- see CBLFullTextQueryRow and CBLGeoQueryRow. */
@interface CBLQueryRow : NSObject

/** The row's key: this is the first parameter passed to the emit() call that generated the row. */
@property (readonly) id key;

/** The row's value: this is the second parameter passed to the emit() call that generated the row. */
@property (readonly) id value;

/** The ID of the document described by this view row.
    This is not necessarily the same as the document that caused this row to be emitted; see the discussion of the .sourceDocumentID property for details. */
@property (readonly) NSString* documentID;

/** The ID of the document that caused this view row to be emitted.
    This is the value of the "id" property of the JSON view row.
    It will be the same as the .documentID property, unless the map function caused a related document to be linked by adding an "_id" key to the emitted value; in this case .documentID will refer to the linked document, while sourceDocumentID always refers to the original document.
    In a reduced or grouped query the value will be nil, since the rows don't correspond to
    individual documents. */
@property (readonly) NSString* sourceDocumentID;

/** The revision ID of the document this row was mapped from. */
@property (readonly) NSString* documentRevision;

@property (readonly) CBLDatabase* database;

/** The document this row was mapped from.
    This will be nil if a grouping was enabled in the query, because then the result rows don't correspond to individual documents. */
@property (readonly) CBLDocument* document;

/** The properties of the document this row was mapped from.
    To get this, you must have set the .prefetch property on the query; else this will be nil.
    (You can still get the document properties via the .document property, of course. But it
    takes a separate call to the database. So if you're doing it for every row, using
    .prefetch and .documentProperties is faster.) */
@property (readonly) NSDictionary* documentProperties;

/** If this row's key is an array, returns the item at that index in the array.
    If the key is not an array, index=0 will return the key itself.
    If the index is out of range, returns nil. */
- (id) keyAtIndex: (NSUInteger)index;

/** Convenience for use in keypaths. Returns the key at the given index. */
@property (readonly) id key0, key1, key2, key3;

/** The database sequence number of the associated doc/revision. */
@property (readonly) UInt64 sequenceNumber;

/** Returns all conflicting revisions of the document, as an array of CBLRevision, or nil if the
    document is not in conflict.
    The first object in the array will be the default "winning" revision that shadows the others.
    This is only valid in an allDocuments query whose allDocsMode is set to kCBLShowConflicts
    or kCBLOnlyConflicts; otherwise it returns nil. */
@property (readonly) NSArray* conflictingRevisions;

#ifdef CBL_DEPRECATED
@property (readonly) UInt64 localSequence __attribute__((deprecated("renamed sequenceNumber")));
#endif
@end
