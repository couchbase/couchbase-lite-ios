//
//  CBLDatabase+Internal.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/19/10.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import "CBL_Revision.h"
#import "CBLStatus.h"
#import "CBLDatabase.h"
@class CBL_FMDatabase, CBLView, CBL_BlobStore, CBLDocument, CBLCache, CBLDatabase, CBLDatabaseChange, CBL_Shared;
struct CBLQueryOptions;      // declared in CBLView+Internal.h


/** NSNotification posted when one or more documents have been updated.
    The userInfo key "changes" contains an array of CBLDatabaseChange objects. */
extern NSString* const CBL_DatabaseChangesNotification;

/** NSNotification posted when a database is closing. */
extern NSString* const CBL_DatabaseWillCloseNotification;

/** NSNotification posted when a database is about to be deleted (but before it closes). */
extern NSString* const CBL_DatabaseWillBeDeletedNotification;




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


/** Options for _changes feed (-changesSinceSequence:). */
typedef struct CBLChangesOptions {
    unsigned limit;
    CBLContentOptions contentOptions;
    BOOL includeDocs;
    BOOL includeConflicts;
    BOOL sortBySequence;
} CBLChangesOptions;

extern const CBLChangesOptions kDefaultCBLChangesOptions;



// Additional instance variable and property declarations
@interface CBLDatabase ()
{
    @private
    NSString* _path;
    NSString* _name;
    CBLManager* _manager;
    CBL_FMDatabase *_fmdb;
    BOOL _readOnly;
    BOOL _isOpen;
    int _transactionLevel;
    NSThread* _thread;
    dispatch_queue_t _dispatchQueue;    // One and only one of _thread or _dispatchQueue is set
    NSCache* _docIDs;
    NSMutableDictionary* _views;
    CBL_BlobStore* _attachments;
    NSMutableDictionary* _pendingAttachmentsByDigest;
    NSMutableArray* _activeReplicators;
    NSMutableArray* _changesToNotify;
    bool _postingChangeNotifications;
    NSDate* _startTime;
#if DEBUG
    CBL_Shared* _debug_shared;
#endif
}

@property (nonatomic, readwrite, copy) NSString* name;  // make it settable
@property (nonatomic, readonly) NSString* path;
@property (nonatomic, readonly) BOOL isOpen;

- (void) postPublicChangeNotification: (NSArray*)changes; // implemented in CBLDatabase.m
- (BOOL) close;
- (BOOL) closeForDeletion;

@end



// Internal API
@interface CBLDatabase (Internal)

- (instancetype) _initWithPath: (NSString*)path
                          name: (NSString*)name
                       manager: (CBLManager*)manager
                      readOnly: (BOOL)readOnly;
+ (BOOL) deleteDatabaseFilesAtPath: (NSString*)dbPath error: (NSError**)outError;
#if DEBUG
+ (instancetype) createEmptyDBAtPath: (NSString*)path;
#endif
- (BOOL) openFMDB: (NSError**)outError;
- (BOOL) open: (NSError**)outError;
- (BOOL) closeInternal;

@property (nonatomic, readonly) CBL_FMDatabase* fmdb;
@property (nonatomic, readonly) CBL_BlobStore* attachmentStore;
@property (nonatomic, readonly) CBL_Shared* shared;

@property (nonatomic, readonly) BOOL exists;
@property (nonatomic, readonly) UInt64 totalDataSize;
@property (nonatomic, readonly) int schemaVersion;
@property (nonatomic, readonly) NSDate* startTime;

/** The status of the last SQLite call, either kCBLStatusOK on success, or some error (generally
    kCBLStatusDBBusy or kCBLStatusDBError.)
    If you already know there's been an error, you should use lastDbError instead. */
@property (readonly) CBLStatus lastDbStatus;

/** The error status of the last SQLite call: Generally kCBLStatusDBBusy or kCBLStatusDBError.
    Always returns some error code, never kCBLStatusOK! It's assumed that you're calling this
    because a CBLDatabase method failed, so you should be returning _some_ error to the caller. */
@property (readonly) CBLStatus lastDbError;

- (NSString*) infoForKey: (NSString*)key;
- (CBLStatus) setInfo: (id)info forKey: (NSString*)key;

@property (nonatomic, readonly) NSString* privateUUID;
@property (nonatomic, readonly) NSString* publicUUID;

/** Executes the block within a database transaction.
    If the block returns a non-OK status, the transaction is aborted/rolled back.
    If the block returns kCBLStatusDBBusy, the block will also be retried after a short delay;
    if 10 retries all fail, the kCBLStatusDBBusy will be returned to the caller.
    Any exception raised by the block will be caught and treated as kCBLStatusException. */
- (CBLStatus) _inTransaction: (CBLStatus(^)())block;

- (void) notifyChange: (CBLDatabaseChange*)change;

// DOCUMENTS:

- (CBL_Revision*) getDocumentWithID: (NSString*)docID 
                       revisionID: (NSString*)revID
                          options: (CBLContentOptions)options
                           status: (CBLStatus*)outStatus;
- (CBL_Revision*) getDocumentWithID: (NSString*)docID
                       revisionID: (NSString*)revID;

- (BOOL) existsDocumentWithID: (NSString*)docID
                   revisionID: (NSString*)revID;

- (CBLStatus) loadRevisionBody: (CBL_MutableRevision*)rev
                       options: (CBLContentOptions)options;
- (CBL_Revision*) revisionByLoadingBody: (CBL_Revision*)rev
                                options: (CBLContentOptions)options
                                 status: (CBLStatus*)outStatus;

- (SInt64) getDocNumericID: (NSString*)docID;
- (SequenceNumber) getSequenceOfDocument: (SInt64)docNumericID
                                revision: (NSString*)revID
                             onlyCurrent: (BOOL)onlyCurrent;
- (CBL_RevisionList*) getAllRevisionsOfDocumentID: (NSString*)docID
                                      numericID: (SInt64)docNumericID
                                    onlyCurrent: (BOOL)onlyCurrent;
- (NSMutableDictionary*) documentPropertiesFromJSON: (NSData*)json
                                              docID: (NSString*)docID
                                              revID: (NSString*)revID
                                            deleted: (BOOL)deleted
                                           sequence: (SequenceNumber)sequence
                                            options: (CBLContentOptions)options;
- (NSString*) winningRevIDOfDocNumericID: (SInt64)docNumericID
                               isDeleted: (BOOL*)outIsDeleted
                              isConflict: (BOOL*)outIsConflict;

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
    Does not return revisions whose bodies have been compacted away, or deletion markers. */
- (NSArray*) getPossibleAncestorRevisionIDs: (CBL_Revision*)rev
                                      limit: (unsigned)limit
                              hasAttachment: (BOOL*)outHasAttachment;

/** Returns the most recent member of revIDs that appears in rev's ancestry. */
- (NSString*) findCommonAncestorOf: (CBL_Revision*)rev withRevIDs: (NSArray*)revIDs;

// VIEWS & QUERIES:

/** An array of all existing views. */
@property (readonly) NSArray* allViews;

- (CBLStatus) deleteViewNamed: (NSString*)name;

/** Returns the value of an _all_docs query, as an array of CBLQueryRow. */
- (NSArray*) getAllDocs: (const struct CBLQueryOptions*)options;

- (CBLView*) makeAnonymousView;

/** Returns the view with the given name. If there is none, and the name is in CouchDB
    format ("designdocname/viewname"), it attempts to load the view properties from the
    design document and compile them with the CBLViewCompiler. */
- (CBLView*) compileViewNamed: (NSString*)name status: (CBLStatus*)outStatus;

- (NSString*) _indexedTextWithID: (UInt64)fullTextID;

//@property (readonly) NSArray* allViews;

- (CBL_RevisionList*) changesSinceSequence: (SequenceNumber)lastSequence
                                 options: (const CBLChangesOptions*)options
                                  filter: (CBLFilterBlock)filter
                                  params: (NSDictionary*)filterParams;

- (CBLFilterBlock) compileFilterNamed: (NSString*)filterName status: (CBLStatus*)outStatus;

- (BOOL) runFilter: (CBLFilterBlock)filter
            params: (NSDictionary*)filterParams
        onRevision: (CBL_Revision*)rev;

@end
