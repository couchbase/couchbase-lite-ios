//
//  CBL_ViewStorage.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/13/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import "CBL_StorageTypes.h"
#import "CBL_Revision.h"    // defines SequenceNumber
#import "CBLStatus.h"
@protocol CBL_ViewStorageDelegate, CBL_QueryRowStorage;


UsingLogDomain(View);
UsingLogDomain(Query);


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

/** Queries the view. */
- (CBLQueryEnumerator*) queryWithOptions: (CBLQueryOptions*)options
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
