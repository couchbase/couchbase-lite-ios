//
//  CBL_ViewStorage.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/13/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import "CBL_StorageTypes.h"
#import "CBL_Revision.h"    // defines SequenceNumber
@protocol CBL_ViewStorageDelegate, CBL_QueryRowStorage;


/** Storage for a view. Instances are created by CBL_Storage implementations, and are owned by
    CBLView instances. */
@protocol CBL_ViewStorage <NSObject>

/** The name of the view. */
@property (readonly) NSString* name;

/** The delegate (in practice, the owning CBLView itself.) */
@property (nonatomic, weak) id<CBL_ViewStorageDelegate> delegate;

/** Closes the storage. */
- (void) close;

/** Erases the view's index. */
- (void) deleteIndex;

/** Deletes the view's storage (metadata and index), removing it from the database. */
- (void) deleteView;

/** Updates the version of the view. A change in version means the delegate's map block has
    changed its semantics, so the index should be deleted. */
- (BOOL) setVersion: (NSString*)version;

/** The total number of rows in the index. */
@property (readonly) NSUInteger totalRows;

/** The last sequence number that has been indexed. */
@property (readonly) SequenceNumber lastSequenceIndexed;

/** The last sequence number that caused an actual change in the index. */
@property (readonly) SequenceNumber lastSequenceChangedAt;

/** Updates the indexes of one or more views in parallel.
    @param  views  An array of CBL_ViewStorage instances, always including the receiver.
    @return  The success/error status. */
- (CBLStatus) updateIndexes: (NSArray*)views; // array of CBL_ViewStorage

/** Queries the view without performing any reducing or grouping. */
- (CBLQueryIteratorBlock) regularQueryWithOptions: (CBLQueryOptions*)options
                                           status: (CBLStatus*)outStatus;

/** Queries the view, with reducing or grouping as per the options. */
- (CBLQueryIteratorBlock) reducedQueryWithOptions: (CBLQueryOptions*)options
                                           status: (CBLStatus*)outStatus;

/** Performs a full-text query as per the options. */
- (CBLQueryIteratorBlock) fullTextQueryWithOptions: (CBLQueryOptions*)options
                                            status: (CBLStatus*)outStatus;

- (id<CBL_QueryRowStorage>) storageForQueryRow: (CBLQueryRow*)row;

#if DEBUG
/** Just for unit tests and debugging. Returns every row in the index in order, as an NSDictionary
    with keys @"key", @"value" and @"seq". */
- (NSArray*) dump;
#endif

@end




/** Storage for a CBLQueryRow. Instantiated by a CBL_ViewStorage when it creates a CBLQueryRow. */
@protocol CBL_QueryRowStorage <NSObject>

/** Given the raw data of a row's value, returns YES if this is a non-JSON placeholder representing
    the entire document. If so, the CBLQueryRow will not parse this data but will instead fetch the
    document's body from the database and use that as its value. */
- (BOOL) rowValueIsEntireDoc: (NSData*)valueData;

/** Parses a "normal" (not entire-doc) row value into a JSON-compatible object. */
- (id) parseRowValue: (NSData*)valueData;

/** Fetches a document's body; called when the row value represents the entire document.
    @param docID  The document ID
    @param sequence  The sequence representing this revision
    @param outStatus  On failure, an error status will be stored here
    @return  The document properties, or nil on error */
- (NSDictionary*) documentPropertiesWithID: (NSString*)docID
                                  sequence: (SequenceNumber)sequence
                                    status: (CBLStatus*)outStatus;

/** Fetches the full text that was emitted for the given document.
    @param docID  The document ID
    @param sequence  The sequence representing this revision
    @param fullTextID  The opaque ID given when the CBLQueryRow was created; this is used to
                disambiguate between multiple calls to emit() made for a single document.
    @return  The full text as UTF-8 data, or nil on error. */
- (NSData*) fullTextForDocument: (NSString*)docID
                       sequence: (SequenceNumber)sequence
                     fullTextID: (UInt64)fullTextID;
@end




/** Delegate of a CBL_ViewStorage instance. CBLView implements this. */
@protocol CBL_ViewStorageDelegate <NSObject>

/** The current map block. Never nil. */
@property (readonly) CBLMapBlock mapBlock;

/** The current reduce block, or nil if there is none. */
@property (readonly) CBLReduceBlock reduceBlock;

/** The current map version string. If this changes, the storage's -setVersion: method will be
    called to notify it, so it can invalidate the index. */
@property (readonly) NSString* mapVersion;

/** The document "type" property values this view is filtered to (nil if none.) */
@property (readonly) NSString* documentType;

@end
