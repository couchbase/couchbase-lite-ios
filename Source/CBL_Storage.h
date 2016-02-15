//
//  CBL_Storage.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/13/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import "CBL_Revision.h"
#import "CBL_StorageTypes.h"
@class CBLDatabaseChange, CBLManager, CBLSymmetricKey, MYAction;
@protocol CBL_ViewStorage;
@protocol CBL_StorageDelegate;


/** Abstraction of database storage. Every CBLDatabase has an instance of this,
    and acts as that instance's delegate. */
@protocol CBL_Storage <NSObject>

// INITIALIZATION AND CONFIGURATION:

/** Preflight to see if a database file exists in this directory. Called _before_ -open! */
+ (BOOL) databaseExistsIn: (NSString*)directory;

/** Opens storage. Files will be created in the directory, which must already exist.
    @param directory  The existing directory to put data files into. The implementation may
        create as many files as it wants here. There will be a subdirectory called "attachments"
        which contains attachments; don't mess with that.
    @param readOnly  If this is YES, the database is opened read-only and any attempt to modify
        it must return an error.
    @param manager  The owning CBLManager; this is provided so the storage can examine its
        properties.
    @param error  On failure, store an NSError here if it's non-NULL.
    @return  YES on success, NO on failure. */
- (BOOL) openInDirectory: (NSString*)directory
                readOnly: (BOOL)readOnly
                 manager: (CBLManager*)manager
                   error: (NSError**)error;

/** Closes storage before it's deallocated. */
- (void) close;

/** The delegate object, which in practice is the CBLDatabase. */
@property id<CBL_StorageDelegate> delegate;

/** The maximum depth a document's revision tree should grow to; beyond that, it should be pruned.
    This will be set soon after the -openInDirectory call. */
@property unsigned maxRevTreeDepth;

/** Whether the database storage should automatically (periodically) be compacted.
    This will be set soon after the -openInDirectory call. */
@property BOOL autoCompact;


// DATABASE ATTRIBUTES & OPERATIONS:

/** Stores an arbitrary string under an arbitrary key, persistently. */
- (CBLStatus) setInfo: (NSString*)info forKey: (NSString*)key;

/** Returns the value assigned to the given key by -setInfo:forKey:. */
- (NSString*) infoForKey: (NSString*)key;

/** The number of (undeleted) documents in the database. */
@property (nonatomic, readonly) NSUInteger documentCount;

/** The last sequence number allocated to a revision. */
@property (nonatomic, readonly) SequenceNumber lastSequence;

/** Is a transaction active? */
@property (nonatomic, readonly) BOOL inTransaction;

/** Explicitly compacts document storage. */
- (BOOL) compact: (NSError**)outError;

/** Executes the block within a database transaction.
    If the block returns a non-OK status, the transaction is aborted/rolled back.
    If the block returns kCBLStatusDBBusy, the block will also be retried after a short delay;
    if 10 retries all fail, the kCBLStatusDBBusy will be returned to the caller.
    Any exception raised by the block will be caught and treated as kCBLStatusException. */
- (CBLStatus) inTransaction: (CBLStatus(^)())block;


// DOCUMENTS:

/** Retrieves a document revision by ID.
    @param docID  The document ID
    @param revID  The revision ID; may be nil, meaning "the current revision".
    @param withBody  If NO, revision's body won't be loaded
    @param outStatus  If returning nil, store a CBLStatus error value here.
    @return  The revision, or nil if not found. */
- (CBL_MutableRevision*) getDocumentWithID: (NSString*)docID
                                revisionID: (NSString*)revID
                                  withBody: (BOOL)withBody
                                    status: (CBLStatus*)outStatus;

/** Loads the body of a revision.
    On entry, rev.docID and rev.revID will be valid.
    On success, rev.body and rev.sequence will be valid. */
- (CBLStatus) loadRevisionBody: (CBL_MutableRevision*)rev;

/** Looks up the sequence number of a revision.
    Will only be called on revisions whose .sequence property is not already set.
    Does not need to set the revision's .sequence property; the caller will take care of that. */
- (SequenceNumber) getRevisionSequence: (CBL_Revision*)rev;

/** Retrieves the parent revision of a revision, or returns nil if there is no parent. */
- (CBL_Revision*) getParentRevision: (CBL_Revision*)rev;

/** Returns an array of CBL_Revisions giving the revision history in reverse order, starting from
    `rev` and going back to any of the revision IDs in `ancestorRevIDs` (or all the way back if
    that array is empty or nil.) */
- (NSArray*) getRevisionHistory: (CBL_Revision*)rev
                   backToRevIDs: (NSSet*)ancestorRevIDs;

/** Returns all the known revisions (or all current/conflicting revisions) of a document.
    @param docID  The document ID
    @param onlyCurrent  If YES, only leaf revisions (whether or not deleted) should be returned.
    @return  An array of all available revisions of the document. */
- (CBL_RevisionList*) getAllRevisionsOfDocumentID: (NSString*)docID
                                      onlyCurrent: (BOOL)onlyCurrent;

/** Returns IDs of local revisions of the same document, that have a lower generation number.
    Does not return revisions whose bodies have been compacted away, or deletion markers.
    If 'onlyAttachments' is true, only revisions with attachments will be returned. */
- (NSArray*) getPossibleAncestorRevisionIDs: (CBL_Revision*)rev
                                      limit: (unsigned)limit
                            onlyAttachments: (BOOL)onlyAttachments;

/** Returns the most recent member of revIDs that appears in rev's ancestry.
    In other words: Look at the revID properties of rev, its parent, grandparent, etc.
    As soon as you find a revID that's in the revIDs array, stop and return that revID.
    If no match is found, return nil. */
- (NSString*) findCommonAncestorOf: (CBL_Revision*)rev withRevIDs: (NSArray*)revIDs;

/** Looks for each given revision in the local database, and removes each one found from the list.
    On return, therefore, `revs` will contain only the revisions that don't exist locally. */
- (BOOL) findMissingRevisions: (CBL_RevisionList*)revs
                       status: (CBLStatus*)outStatus;

/** Returns the keys (unique IDs) of all attachments referred to by existing un-compacted
    Each revision key is an NSData object containing a CBLBlobKey (raw SHA-1 digest) derived from
    the "digest" property of the attachment's metadata. */
- (NSSet*) findAllAttachmentKeys: (NSError**)outError;

/** Iterates over all documents in the database, according to the given query options. */
- (CBLQueryEnumerator*) getAllDocs: (CBLQueryOptions*)options
                            status: (CBLStatus*)outStatus;

/** Returns all database changes with sequences greater than `lastSequence`.
    @param  lastSequence  The sequence number to start _after_
    @param  options  Options for ordering, document content, etc.
    @param  filter  If non-nil, will be called on every revision, and those for which it returns NO
                    will be skipped.
    @param  outStatus  On nil return, will be set to an error status.
    @return  The list of CBL_Revisions. */
- (CBL_RevisionList*) changesSinceSequence: (SequenceNumber)lastSequence
                                   options: (const CBLChangesOptions*)options
                                    filter: (CBL_RevisionFilter)filter
                                    status: (CBLStatus*)outStatus;

// INSERTION / DELETION:

/** Creates a new revision of a document.
    On success, before returning the new CBL_Revision, the implementation will also call the
    delegate's -databaseStorageChanged: method to give it more details about the change.
    @param docID  The document ID, or nil if an ID should be generated at random.
    @param prevRevID  The parent revision ID, or nil if creating a new document.
    @param properties  The new revision's properties. (Metadata other than "_attachments" ignored.)
    @param deleting  YES if this revision is a deletion.
    @param allowConflict  YES if this operation is allowed to create a conflict; otherwise a 409
                status will be returned if the parent revision is not a leaf.
    @param validationBlock  If non-nil, this block will be called before the revision is added.
                It's given the parent revision, with its properties if available, and can reject
                the operation by returning an error status.
    @param status  On return a status will be stored here. Note that on success, the
                status should be 201 for a created revision but 200 for a deletion.
    @param outError  On return, an error indicating a reason of the failure
    @return  The new revision, with its revID and sequence filled in, or nil on error. */
- (CBL_Revision*) addDocID: (NSString*)docID
                 prevRevID: (NSString*)prevRevID
                properties: (NSMutableDictionary*)properties
                  deleting: (BOOL)deleting
             allowConflict: (BOOL)allowConflict
           validationBlock: (CBL_StorageValidationBlock)validationBlock
                    status: (CBLStatus*)status
                     error: (NSError**)outError;

/** Inserts an already-existing revision (with its revID), plus its ancestry, into a document.
    This is called by the pull replicator to add the revisions received from the server.
    On success, the implementation will also call the
    delegate's -databaseStorageChanged: method to give it more details about the change.
    @param inRev  The revision to insert. Its revID will be non-nil.
    @param history  The revIDs of the revision and its ancestors, in reverse chronological order.
                    The first item will be equal to inRev.revID.
    @param validationBlock  If non-nil, this block will be called before the revision is added.
                It's given the parent revision, with its properties if available, and can reject
                the operation by returning an error status.
    @param source  The URL of the remote database this was pulled from, or nil if it's local.
                (This will be used to create the CBLDatabaseChange object sent to the delegate.)
    @param outError  On return, an error indicating a reason of the failure.
    @return  Status code; 200 on success, otherwise an error. */
- (CBLStatus) forceInsert: (CBL_Revision*)inRev
          revisionHistory: (NSArray*)history
          validationBlock: (CBL_StorageValidationBlock)validationBlock
                   source: (NSURL*)source
                    error: (NSError**)outError;

/** Purges specific revisions, which deletes them completely from the local database _without_ adding a "tombstone" revision. It's as though they were never there.
    @param docsToRevs  A dictionary mapping document IDs to arrays of revision IDs.
                        The magic revision ID "*" means "all revisions", indicating that the
                        document should be removed entirely from the database.
    @param outResult  On success will point to an NSDictionary with the same form as docsToRev, containing the doc/revision IDs that were actually removed. */
- (CBLStatus) purgeRevisions: (NSDictionary*)docsToRevs
                      result: (NSDictionary**)outResult;


// VIEWS:

/** Instantiates storage for a view.
    @param name  The name of the view
    @param create  If YES, the view should be created; otherwise it must already exist
    @return  Storage for the view, or nil if create=NO and it doesn't exist. */
- (id<CBL_ViewStorage>) viewStorageNamed: (NSString*)name
                                  create: (BOOL)create;

/** Returns the names of all existing views in the database. */
@property (readonly) NSArray* allViewNames;


// LOCAL DOCS:

/** Returns the contents of a local document. Note that local documents do not have revision
    histories, so only the current revision exists.
    @param docID  The document ID, which will begin with "_local/"
    @param revID  The revision ID, or nil to return the current revision.
    @return  A revision containing the body of the document, or nil if not found. */
- (CBL_MutableRevision*) getLocalDocumentWithID: (NSString*)docID
                                     revisionID: (NSString*)revID;

/** Creates / updates / deletes a local document.
    @param revision  The new revision to save. Its docID must be set but the revID is ignored.
                    If its .deleted property is YES, it's a deletion.
    @param prevRevID  The revision ID to replace
    @param obeyMVCC  If YES, the prevRevID must match the document's current revID (or nil if the
                    document doesn't exist) or a 409 error is returned. If NO, the prevRevID is
                    ignored and the operation always succeeds.
    @param outStatus  On return the status is always stored here (201 on creation, 200 on deletion,
                    else an error.)
    @return  The new revision, with revID filled in, or nil on error. */
- (CBL_Revision*) putLocalRevision: (CBL_Revision*)revision
                    prevRevisionID: (NSString*)prevRevID
                          obeyMVCC: (BOOL)obeyMVCC
                            status: (CBLStatus*)outStatus;

@optional

/** Low-memory warning; free up resources if possible. */
- (void) lowMemoryWarning;

/** Registers the encryption key of the database file. Must be called before opening the db. */
- (void) setEncryptionKey: (CBLSymmetricKey*)key;

/** Called when the delegate changes its encryptionKey property. The storage should rewrite its
    files using the new key (which may be nil, meaning no encryption.) */
- (MYAction*) actionToChangeEncryptionKey: (CBLSymmetricKey*)newKey;

@end




/** Delegate of a CBL_Storage instance. CBLDatabase implements this. */
@protocol CBL_StorageDelegate <NSObject>

/** Called whenever the outermost transaction completes.
    @param committed  YES on commit, NO if the transaction was aborted. */
- (void) storageExitedTransaction: (BOOL)committed;

/** Called whenever a revision is added to the database (but not for local docs or for purges.) */
- (void) databaseStorageChanged: (CBLDatabaseChange*)change;

/** Generates a revision ID for a new revision.
    @param json  The canonical JSON of the revision (with metadata properties removed.)
    @param deleted  YES if this revision is a deletion
    @param prevID  The parent's revision ID, or nil if this is a new document. */
- (NSString*) generateRevIDForJSON: (NSData*)json
                           deleted: (BOOL)deleted
                         prevRevID: (NSString*)prevID;
@end
