/*
 *  TD_Database.h
 *  TouchDB
 *
 *  Created by Jens Alfke on 6/19/10.
 *  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
 *
 */

#import <TouchDB/TD_Revision.h>
#import <TouchDB/TDStatus.h>
@class FMDatabase, TD_View, TDBlobStore;
struct TDQueryOptions;      // declared in TD_View.h


/** NSNotification posted when a document is updated.
    UserInfo keys: @"rev": the new TD_Revision, @"source": NSURL of remote db pulled from,
    @"winner": new winning TD_Revision, _if_ it changed (often same as rev). */
extern NSString* const TD_DatabaseChangeNotification;

/** NSNotification posted when a database is closing. */
extern NSString* const TD_DatabaseWillCloseNotification;

/** NSNotification posted when a database is about to be deleted (but before it closes). */
extern NSString* const TD_DatabaseWillBeDeletedNotification;


/** Filter block, used in changes feeds and replication. */
typedef BOOL (^TD_FilterBlock) (TD_Revision* revision, NSDictionary* params);


/** Options for what metadata to include in document bodies */
typedef unsigned TDContentOptions;
enum {
    kTDIncludeAttachments = 1,              // adds inline bodies of attachments
    kTDIncludeConflicts = 2,                // adds '_conflicts' property (if relevant)
    kTDIncludeRevs = 4,                     // adds '_revisions' property
    kTDIncludeRevsInfo = 8,                 // adds '_revs_info' property
    kTDIncludeLocalSeq = 16,                // adds '_local_seq' property
    kTDLeaveAttachmentsEncoded = 32,        // i.e. don't decode
    kTDBigAttachmentsFollow = 64,           // i.e. add 'follows' key instead of data for big ones
    kTDNoBody = 128,                        // omit regular doc body properties
};


/** Options for _changes feed (-changesSinceSequence:). */
typedef struct TDChangesOptions {
    unsigned limit;
    TDContentOptions contentOptions;
    BOOL includeDocs;
    BOOL includeConflicts;
    BOOL sortBySequence;
} TDChangesOptions;

extern const TDChangesOptions kDefaultTDChangesOptions;



/** A TouchDB database. */
@interface TD_Database : NSObject
{
    @private
    NSString* _path;
    NSString* _name;
    FMDatabase *_fmdb;
    BOOL _readOnly;
    BOOL _open;
    int _transactionLevel;
    NSMutableDictionary* _views;
    NSMutableDictionary* _validations;
    NSMutableDictionary* _filters;
    TDBlobStore* _attachments;
    NSMutableDictionary* _pendingAttachmentsByDigest;
    NSMutableArray* _activeReplicators;
}    
        
- (id) initWithPath: (NSString*)path;
- (BOOL) open;
- (BOOL) close;
- (BOOL) deleteDatabase: (NSError**)outError;

+ (TD_Database*) createEmptyDBAtPath: (NSString*)path;

/** Should the database file be opened in read-only mode? */
@property BOOL readOnly;

/** Replaces the database with a copy of another database.
    This is primarily used to install a canned database on first launch of an app, in which case you should first check .exists to avoid replacing the database if it exists already. The canned database would have been copied into your app bundle at build time.
    @param databasePath  Path of the database file that should replace this one.
    @param attachmentsPath  Path of the associated attachments directory, or nil if there are no attachments.
    @param error  If an error occurs, it will be stored into this parameter on return.
    @return  YES if the database was copied, NO if an error occurred. */
- (BOOL) replaceWithDatabaseFile: (NSString*)databasePath
                 withAttachments: (NSString*)attachmentsPath
                           error: (NSError**)outError;

@property (readonly) NSString* path;
@property (readonly, copy) NSString* name;
@property (readonly) BOOL exists;
@property (readonly) UInt64 totalDataSize;

@property (readonly) NSUInteger documentCount;
@property (readonly) SequenceNumber lastSequence;
@property (readonly) NSString* privateUUID;
@property (readonly) NSString* publicUUID;

/** Begins a database transaction. Transactions can nest. Every -beginTransaction must be balanced by a later -endTransaction:. */
- (BOOL) beginTransaction;

/** Commits or aborts (rolls back) a transaction.
    @param commit  If YES, commits; if NO, aborts and rolls back, undoing all changes made since the matching -beginTransaction call, *including* any committed nested transactions. */
- (BOOL) endTransaction: (BOOL)commit;

/** Executes the block within a database transaction.
    If the block returns a non-OK status, the transaction is aborted/rolled back.
    Any exception raised by the block will be caught and treated as kTDStatusException. */
- (TDStatus) inTransaction: (TDStatus(^)())block;

// DOCUMENTS:

- (TD_Revision*) getDocumentWithID: (NSString*)docID 
                       revisionID: (NSString*)revID
                          options: (TDContentOptions)options
                           status: (TDStatus*)outStatus;
- (TD_Revision*) getDocumentWithID: (NSString*)docID
                       revisionID: (NSString*)revID;

- (BOOL) existsDocumentWithID: (NSString*)docID
                   revisionID: (NSString*)revID;

- (TDStatus) loadRevisionBody: (TD_Revision*)rev
                      options: (TDContentOptions)options;

/** Returns an array of TDRevs in reverse chronological order,
    starting with the given revision. */
- (NSArray*) getRevisionHistory: (TD_Revision*)rev;

/** Returns the revision history as a _revisions dictionary, as returned by the REST API's ?revs=true option. */
- (NSDictionary*) getRevisionHistoryDict: (TD_Revision*)rev;

/** Returns all the known revisions (or all current/conflicting revisions) of a document. */
- (TD_RevisionList*) getAllRevisionsOfDocumentID: (NSString*)docID
                                    onlyCurrent: (BOOL)onlyCurrent;

/** Returns IDs of local revisions of the same document, that have a lower generation number.
    Does not return revisions whose bodies have been compacted away, or deletion markers. */
- (NSArray*) getPossibleAncestorRevisionIDs: (TD_Revision*)rev
                                      limit: (unsigned)limit;

/** Returns the most recent member of revIDs that appears in rev's ancestry. */
- (NSString*) findCommonAncestorOf: (TD_Revision*)rev withRevIDs: (NSArray*)revIDs;

// VIEWS & QUERIES:

- (NSDictionary*) getAllDocs: (const struct TDQueryOptions*)options;

- (NSDictionary*) getDocsWithIDs: (NSArray*)docIDs
                         options: (const struct TDQueryOptions*)options;

- (TD_View*) viewNamed: (NSString*)name;

- (TD_View*) existingViewNamed: (NSString*)name;

/** Returns the view with the given name. If there is none, and the name is in CouchDB
    format ("designdocname/viewname"), it attempts to load the view properties from the
    design document and compile them with the TDViewCompiler. */
- (TD_View*) compileViewNamed: (NSString*)name status: (TDStatus*)outStatus;

@property (readonly) NSArray* allViews;

- (TD_RevisionList*) changesSinceSequence: (SequenceNumber)lastSequence
                                 options: (const TDChangesOptions*)options
                                  filter: (TD_FilterBlock)filter
                                  params: (NSDictionary*)filterParams;

/** Define or clear a named filter function. These aren't used directly by TD_Database, but they're looked up by TDRouter when a _changes request has a ?filter parameter. */
- (void) defineFilter: (NSString*)filterName asBlock: (TD_FilterBlock)filterBlock;

- (TD_FilterBlock) filterNamed: (NSString*)filterName;

@end
