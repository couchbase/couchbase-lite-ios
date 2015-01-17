//
//  CBL_Storage.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/13/15.
//
//

#import "CBL_Revision.h"
#import "CBLStatus.h"
#import "CBLQuery.h"
@class CBLDatabaseChange, CBLManager;
@protocol CBL_ViewStorage;


/** Options for what metadata to include in document bodies */
typedef unsigned CBLContentOptions;
enum {
    kCBLIncludeAttachments = 1,              // adds inline bodies of attachments
    kCBLIncludeConflicts = 2,                // adds '_conflicts' property (if relevant)
    kCBLIncludeRevs = 4,                     // adds '_revisions' property
    kCBLIncludeRevsInfo = 8,                 // adds '_revs_info' property
    kCBLIncludeLocalSeq = 16,                // adds '_local_seq' property
    kCBLLeaveAttachmentsEncoded = 32,        // i.e. don't decode
    kCBLBigAttachmentsFollow = 64,           // i.e. add 'follows' key instead of data for big ones
    kCBLNoBody = 128,                        // omit regular doc body properties
    kCBLNoAttachments = 256                  // Omit the _attachments property
};


typedef BOOL (^CBLQueryRowFilter)(CBLQueryRow*);


/** Standard query options for views. */
@interface CBLQueryOptions : NSObject
{
    @public
    const struct CBLGeoRect* bbox;
    unsigned prefixMatchLevel;
    unsigned skip;
    unsigned limit;
    unsigned groupLevel;
    CBLContentOptions content;
    BOOL descending;
    BOOL includeDocs;
    BOOL updateSeq;
    BOOL localSeq;
    BOOL inclusiveStart;
    BOOL inclusiveEnd;
    BOOL reduceSpecified;
    BOOL reduce;                   // Ignore if !reduceSpecified
    BOOL group;
    BOOL fullTextSnippets;
    BOOL fullTextRanking;
    CBLIndexUpdateMode indexUpdateMode;
    CBLAllDocsMode allDocsMode;
}

@property (copy, nonatomic) id startKey;
@property (copy, nonatomic) id endKey;
@property (copy, nonatomic) NSString* startKeyDocID;
@property (copy, nonatomic) NSString* endKeyDocID;
@property (copy, nonatomic) NSArray* keys;
@property (copy, nonatomic) CBLQueryRowFilter filter;
@property (copy, nonatomic) NSString* fullTextQuery;

@end

#define kCBLQueryOptionsDefaultLimit UINT_MAX


/** Options for _changes feed (-changesSinceSequence:). */
typedef struct CBLChangesOptions {
    unsigned limit;
    CBLContentOptions contentOptions;
    BOOL includeDocs;
    BOOL includeConflicts;
    BOOL sortBySequence;
} CBLChangesOptions;

extern const CBLChangesOptions kDefaultCBLChangesOptions;


@class CBLQueryRow;
typedef CBLQueryRow* (^CBLQueryIteratorBlock)(void);
typedef CBLStatus(^CBL_StorageValidationBlock)(CBL_Revision* newRev,
                                               CBL_Revision* prev,
                                               NSString* parentRevID);


@protocol CBL_StorageDelegate;


/** Abstraction of database storage. */
@protocol CBL_Storage <NSObject>

/** Opens storage. Files will be created in the directory, which must already exist. */
- (BOOL) openInDirectory: (NSString*)directory
                readOnly: (BOOL)readOnly
                 manager: (CBLManager*)manager
                   error: (NSError**)error;
- (void) close;

@property id<CBL_StorageDelegate> delegate;

@property (nonatomic, readonly) NSString* directory;
@property (nonatomic, readonly) NSUInteger documentCount;
@property (nonatomic, readonly) SequenceNumber lastSequence;

@property (nonatomic, readonly) BOOL inTransaction;

@property unsigned maxRevTreeDepth;
@property BOOL autoCompact;
- (BOOL) compact: (NSError**)outError;

/** Executes the block within a database transaction.
    If the block returns a non-OK status, the transaction is aborted/rolled back.
    If the block returns kCBLStatusDBBusy, the block will also be retried after a short delay;
    if 10 retries all fail, the kCBLStatusDBBusy will be returned to the caller.
    Any exception raised by the block will be caught and treated as kCBLStatusException. */
- (CBLStatus) inTransaction: (CBLStatus(^)())block;

// DOCUMENTS:

- (CBL_MutableRevision*) getDocumentWithID: (NSString*)docID
                                revisionID: (NSString*)revID
                                   options: (CBLContentOptions)options
                                    status: (CBLStatus*)outStatus;

// Loads revision given its sequence. Assumes the given docID is valid.
- (CBL_MutableRevision*) getDocumentWithID: (NSString*)docID
                                  sequence: (SequenceNumber)sequence
                                    status: (CBLStatus*)outStatus;

- (CBLStatus) loadRevisionBody: (CBL_MutableRevision*)rev
                       options: (CBLContentOptions)options;

- (SequenceNumber) getRevisionSequence: (CBL_Revision*)rev;

- (CBL_Revision*) getParentRevision: (CBL_Revision*)rev;

/** Returns an array of CBL_Revisions in reverse chronological order,
    starting with the given revision. */
- (NSArray*) getRevisionHistory: (CBL_Revision*)rev;

/** Returns the revision history as a _revisions dictionary, as returned by the REST API's ?revs=true option. If 'ancestorRevIDs' is present, the revision history will only go back as far as any of the revision ID strings in that array. */
- (NSDictionary*) getRevisionHistoryDict: (CBL_Revision*)rev
                       startingFromAnyOf: (NSArray*)ancestorRevIDs;

/** Returns all the known revisions (or all current/conflicting revisions) of a document. */
- (CBL_RevisionList*) getAllRevisionsOfDocumentID: (NSString*)docID
                                    onlyCurrent: (BOOL)onlyCurrent;

/** Returns IDs of local revisions of the same document, that have a lower generation number.
    Does not return revisions whose bodies have been compacted away, or deletion markers.
    If 'onlyAttachments' is true, only revisions with attachments will be returned. */
- (NSArray*) getPossibleAncestorRevisionIDs: (CBL_Revision*)rev
                                      limit: (unsigned)limit
                            onlyAttachments: (BOOL)onlyAttachments;

/** Returns the most recent member of revIDs that appears in rev's ancestry. */
- (NSString*) findCommonAncestorOf: (CBL_Revision*)rev withRevIDs: (NSArray*)revIDs;

- (CBL_RevisionList*) changesSinceSequence: (SequenceNumber)lastSequence
                                   options: (const CBLChangesOptions*)options
                                    filter: (CBL_RevisionFilter)filter
                                    status: (CBLStatus*)outStatus;

- (BOOL) findMissingRevisions: (CBL_RevisionList*)revs
                       status: (CBLStatus*)outStatus;

/** Returns all attachment keys, in the form of an NSData containing a CBLBlobKey (SHA-1 digest). */
- (NSSet*) findAllAttachmentKeys: (NSError**)outError;

/** Purges specific revisions, which deletes them completely from the local database _without_ adding a "tombstone" revision. It's as though they were never there.
    @param docsToRevs  A dictionary mapping document IDs to arrays of revision IDs.
    @param outResult  On success will point to an NSDictionary with the same form as docsToRev, containing the doc/revision IDs that were actually removed. */
- (CBLStatus) purgeRevisions: (NSDictionary*)docsToRevs
                      result: (NSDictionary**)outResult;

- (CBLQueryIteratorBlock) getAllDocs: (CBLQueryOptions*)options
                              status: (CBLStatus*)outStatus;

// LOCAL DOCS / DB INFO:

- (CBL_MutableRevision*) getLocalDocumentWithID: (NSString*)docID
                                     revisionID: (NSString*)revID;
- (CBL_Revision*) putLocalRevision: (CBL_Revision*)revision
                    prevRevisionID: (NSString*)prevRevID
                          obeyMVCC: (BOOL)obeyMVCC
                            status: (CBLStatus*)outStatus;

- (NSString*) infoForKey: (NSString*)key;
- (CBLStatus) setInfo: (NSString*)info forKey: (NSString*)key;

// INSERTION:

- (CBL_Revision*) addDocID: (NSString*)inDocID
                 prevRevID: (NSString*)inPrevRevID
                properties: (NSMutableDictionary*)properties
                  deleting: (BOOL)deleting
             allowConflict: (BOOL)allowConflict
           validationBlock: (CBL_StorageValidationBlock)validationBlock
                    status: (CBLStatus*)outStatus;

- (CBLStatus) forceInsert: (CBL_Revision*)inRev
          revisionHistory: (NSArray*)history
          validationBlock: (CBL_StorageValidationBlock)validationBlock
                   source: (NSURL*)source;

// VIEWS:

- (id<CBL_ViewStorage>) viewStorageNamed: (NSString*)name
                                  create: (BOOL)create;

@property (readonly) NSArray* allViewNames;

@end




@protocol CBL_StorageDelegate <NSObject>
- (void) storageExitedTransaction: (BOOL)committed;
- (void) databaseStorageChanged: (CBLDatabaseChange*)change;
- (NSString*) generateRevIDForJSON: (NSData*)json
                           deleted: (BOOL)deleted
                         prevRevID: (NSString*)prevID;
@end
