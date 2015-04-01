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

#if __has_feature(nullability) // Xcode 6.3+
#pragma clang assume_nonnull begin
#else
#define nullable
#define __nullable
#endif


typedef NS_ENUM(unsigned, CBLAllDocsMode) {
    kCBLAllDocs,            /**< Normal behavior for all-docs query */
    kCBLIncludeDeleted,     /**< Will include rows for deleted documents */
    kCBLShowConflicts,      /**< Rows will indicate conflicting revisions */
    kCBLOnlyConflicts,      /**< Will _only_ return rows for docs in conflict */
    kCBLBySequence          /**< Order by sequence number (i.e. chronologically) */
};


/** Query options to allow out-of-date results to be returned in return for faster queries. */
typedef NS_ENUM(unsigned, CBLIndexUpdateMode) {
    kCBLUpdateIndexBefore,  /**< Always update index if needed before querying (default) */
    kCBLUpdateIndexNever,   /**< Don't update the index; results may be out of date */
    kCBLUpdateIndexAfter    /**< Update index _after_ querying (results may still be out of date) */
};


/** Represents a query of a CouchbaseLite 'view', or of a view-like resource like _all_documents. */
@interface CBLQuery : NSObject

/** The database that contains this view. */
@property (readonly) CBLDatabase* database;

/** The maximum number of rows to return. Defaults to 'unlimited' (UINT_MAX). */
@property NSUInteger limit;

/** The number of initial rows to skip. Default value is 0.
    Should only be used with small values. For efficient paging, use startKey and limit.*/
@property NSUInteger skip;

/** Should the rows be returned in descending key order? Default value is NO. */
@property BOOL descending;

/** If non-nil, the key value to start at. */
@property (copy, nullable) id startKey;

/** If non-nil, the key value to end after. */
@property (copy, nullable) id endKey;

/** If non-nil, the document ID to start at. 
    (Useful if the view contains multiple identical keys, making .startKey ambiguous.) */
@property (copy, nullable) NSString* startKeyDocID;

/** If non-nil, the document ID to end at. 
    (Useful if the view contains multiple identical keys, making .endKey ambiguous.) */
@property (copy, nullable) NSString* endKeyDocID;

/** If YES (the default) the startKey (or startKeyDocID) comparison uses ">=". Else it uses ">". */
@property BOOL inclusiveStart;

/** If YES (the default) the endKey (or endKeyDocID) comparison uses "<=". Else it uses "<". */
@property BOOL inclusiveEnd;

/** If nonzero, enables prefix matching of string or array keys.
    * A value of 1 treats the endKey itself as a prefix: if it's a string, keys in the index that
      come after the endKey, but begin with the same prefix, will be matched. (For example, if the
      endKey is "foo" then the key "foolish" in the index will be matched, but not "fong".) Or if
      the endKey is an array, any array beginning with those elements will be matched. (For
      example, if the endKey is [1], then [1, "x"] will match, but not [2].) If the key is any
      other type, there is no effect.
    * A value of 2 assumes the endKey is an array and treats its final item as a prefix, using the
      rules above. (For example, an endKey of [1, "x"] will match [1, "xtc"] but not [1, "y"].)
    * A value of 3 assumes the key is an array of arrays, etc.
    Note that if the .descending property is also set, the search order is reversed and the above
    discussion applies to the startKey, _not_ the endKey. */
@property NSUInteger prefixMatchLevel;

/** An optional array of NSSortDescriptor objects; overrides the default by-key ordering.
    Key-paths are interpreted relative to a CBLQueryRow object, so they should start with
    "value" to refer to the value, or "key" to refer to the key.
    A limited form of array indexing is supported, so you can refer to "key[1]" or "value[0]" if
    the key or value are arrays. This only works with indexes from 0 to 3. */
@property (copy, nullable) NSArray* sortDescriptors;

/** An optional predicate that filters the resulting query rows.
    If present, it's called on every row returned from the query, and if it returns NO
    the row is skipped.
    Key-paths are interpreted relative to a CBLQueryRow, so they should start with
    "value" to refer to the value, or "key" to refer to the key. */
@property (strong, nullable) NSPredicate* postFilter;

/** Determines whether or when the view index is updated. By default, the index will be updated
    if necessary before the query runs -- this guarantees up-to-date results but can cause a
    delay. The "Never" mode skips updating the index, so it's faster but can return out of date
    results. The "After" mode is a compromise that may return out of date results but if so will
    start asynchronously updating the index after the query so future results are accurate. */
@property CBLIndexUpdateMode indexUpdateMode;

/** If non-nil, the query will fetch only the rows with the given keys. */
@property (copy, nullable) NSArray* keys;

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

/** Sends the query to the server and returns an enumerator over the result rows (Synchronous).
    Note: In a CBLLiveQuery you should access the .rows property instead. */
- (nullable CBLQueryEnumerator*) run: (NSError**)outError;

/** Starts an asynchronous query. Returns immediately, then calls the onComplete block when the
    query completes, passing it the row enumerator (or an error). */
- (void) runAsync: (void (^)(CBLQueryEnumerator*, NSError*))onComplete   __attribute__((nonnull));

/** Returns a live query with the same parameters. */
- (CBLLiveQuery*) asLiveQuery;

@end


/** A CBLQuery subclass that automatically refreshes the result rows every time the database
    changes. All you need to do is use KVO to observe changes to the .rows property. */
@interface CBLLiveQuery : CBLQuery

/** The shortest interval at which the query will update, regardless of how often the
    database changes. Defaults to 0.5 sec. Increase this if the query is expensive and
    the database updates frequently, to limit CPU consumption. */
@property (nonatomic) NSTimeInterval updateInterval;

/** Starts observing database changes. The .rows property will now update automatically. (You 
    usually don't need to call this yourself, since accessing or observing the .rows property will
    call -start for you.) */
- (void) start;

/** Stops observing database changes. Calling -start or .rows will restart it. */
- (void) stop;

/** The current query results; this updates as the database changes, and can be observed using KVO.
    Its value will be nil until the initial asynchronous query finishes. */
@property (readonly, strong, nullable) CBLQueryEnumerator* rows;

/** Blocks until the intial asynchronous query finishes.
    After this call either .rows or .lastError will be non-nil. */
- (BOOL) waitForRows;

/** If non-nil, the error of the last execution of the query.
    If nil, the last execution of the query was successful. */
@property (readonly, nullable) NSError* lastError;

/** Call this method to notify that the query parameters have been changed, the CBLLiveQuery object
    should re-run the query. */
- (void) queryOptionsChanged;

@end


/** Enumerator on a CBLQuery's result rows.
    The objects returned are instances of CBLQueryRow. */
@interface CBLQueryEnumerator : NSEnumerator <NSCopying, NSFastEnumeration>

/** The number of rows returned in this enumerator */
@property (readonly) NSUInteger count;

/** The database's current sequenceNumber at the time the view was generated. */
@property (readonly) UInt64 sequenceNumber;

/** YES if the database has changed since the view was generated. */
@property (readonly) BOOL stale;

/** The next result row. This is the same as -nextObject but with a checked return type. */
- (nullable CBLQueryRow*) nextRow;

/** Random access to a row in the result */
- (CBLQueryRow*) rowAtIndex: (NSUInteger)index;

/** Resets the enumeration so the next call to -nextObject or -nextRow will return the first row. */
- (void) reset;

/** Re-sorts the rows based on the given sort descriptors.
    This operation requires that all rows be loaded into memory, so you can't have previously
    called -nextObject, -nextRow or for...in on this enumerator. (But it's fine to use them
    _after_ calling this method.)
    You can call this method multiple times with different sort descriptors, but the effects
    on any in-progress enumeration are undefined.
    The items in the array can be NSSortDescriptors or simply NSStrings. An NSString will be
    treated as an NSSortDescriptor with the string as the keyPath; prefix with a "-" for descending
    sort.
    Key-paths are interpreted relative to a CBLQueryRow, so they should start with
    "value" to refer to the value, or "key" to refer to the key.
    A limited form of array indexing is supported, so you can refer to "key[1]" or "value[0]" if
    the key or value are arrays. This only works with indexes from 0 to 3. */
- (void) sortUsingDescriptors: (NSArray*)sortDescriptors;

@end


/** A result row from a CouchbaseLite view query.
    Full-text and geo queries return subclasses -- see CBLFullTextQueryRow and CBLGeoQueryRow. */
@interface CBLQueryRow : NSObject

/** The row's key: this is the first parameter passed to the emit() call that generated the row. */
@property (readonly) id key;

/** The row's value: this is the second parameter passed to the emit() call that generated the
    row. */
@property (readonly, nullable) id value;

/** The ID of the document described by this view row.
    This is not necessarily the same as the document that caused this row to be emitted; see the
    discussion of the .sourceDocumentID property for details. */
@property (readonly, nullable) NSString* documentID;

/** The ID of the document that caused this view row to be emitted.
    This is the value of the "id" property of the JSON view row.
    It will be the same as the .documentID property, unless the map function caused a related
    document to be linked by adding an "_id" key to the emitted value; in this case .documentID
    will refer to the linked document, while sourceDocumentID always refers to the original 
    document.
    In a reduced or grouped query the value will be nil, since the rows don't correspond to
    individual documents. */
@property (readonly, nullable) NSString* sourceDocumentID;

/** The revision ID of the document this row was mapped from. */
@property (readonly) NSString* documentRevisionID;

@property (readonly) CBLDatabase* database;

/** The document this row was mapped from.
    This will be nil if a grouping was enabled in the query, because then the result rows don't
    correspond to individual documents. */
@property (readonly, nullable) CBLDocument* document;

/** The properties of the document this row was mapped from.
    To get this, you must have set the .prefetch property on the query; else this will be nil.
    (You can still get the document properties via the .document property, of course. But it
    takes a separate call to the database. So if you're doing it for every row, using
    .prefetch and .documentProperties is faster.) */
@property (readonly, nullable) NSDictionary* documentProperties;

/** If this row's key is an array, returns the item at that index in the array.
    If the key is not an array, index=0 will return the key itself.
    If the index is out of range, returns nil. */
- (nullable id) keyAtIndex: (NSUInteger)index;

/** Convenience for use in keypaths. Returns the key at the given index. */
//@property (readonly, nullable) id key0, key1, key2, key3;
@property (readonly, nullable) id key0;
@property (readonly, nullable) id key1;
@property (readonly, nullable) id key2;
@property (readonly, nullable) id key3;

/** The database sequence number of the associated doc/revision. */
@property (readonly) UInt64 sequenceNumber;

/** Returns all conflicting revisions of the document, as an array of CBLRevision, or nil if the
    document is not in conflict.
    The first object in the array will be the default "winning" revision that shadows the others.
    This is only valid in an allDocuments query whose allDocsMode is set to kCBLShowConflicts
    or kCBLOnlyConflicts; otherwise it returns nil. */
@property (readonly, nullable) NSArray* conflictingRevisions;

@end


#if __has_feature(nullability)
#pragma clang assume_nonnull end
#endif
