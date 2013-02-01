/*
 *  CBL_Database.h
 *  CouchbaseLite
 *
 *  Created by Jens Alfke on 6/19/10.
 *  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
 *
 */

#import "CBL_Revision.h"
#import "CBLStatus.h"
@class FMDatabase, CBL_View, CBL_BlobStore, CBLDocument, CBLCache, CBLDatabase;
struct CBLQueryOptions;      // declared in CBL_View.h


/** NSNotification posted when one or more documents have been updated.
    The userInfo key "changes" contains an array of {rev: CBL_Revision, source: NSURL,
    winner: new winning CBL_Revision, _if_ it changed (often same as rev).}*/
extern NSString* const CBL_DatabaseChangesNotification;

/** NSNotification posted when a database is closing. */
extern NSString* const CBL_DatabaseWillCloseNotification;

/** NSNotification posted when a database is about to be deleted (but before it closes). */
extern NSString* const CBL_DatabaseWillBeDeletedNotification;


/** Filter block, used in changes feeds and replication. */
typedef BOOL (^CBL_FilterBlock) (CBL_Revision* revision, NSDictionary* params);

/** An external object that knows how to map source code of some sort into executable functions. */
@protocol CBLFilterCompiler <NSObject>
- (CBL_FilterBlock) compileFilterFunction: (NSString*)filterSource language: (NSString*)language;
@end




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



/** A CouchbaseLite database. */
@interface CBL_Database : NSObject
{
    @private
    NSString* _path;
    NSString* _name;
    FMDatabase *_fmdb;
    BOOL _readOnly;
    BOOL _open;
    int _transactionLevel;
    NSThread* _thread;
    NSMutableDictionary* _views;
    NSMutableDictionary* _validations;
    NSMutableDictionary* _filters;
    CBL_BlobStore* _attachments;
    NSMutableDictionary* _pendingAttachmentsByDigest;
    NSMutableArray* _activeReplicators;
    __weak CBLDatabase* _touchDatabase;
    NSMutableArray* _changesToNotify;
}    
        
- (id) initWithPath: (NSString*)path;
- (BOOL) open: (NSError**)outError;
- (BOOL) open;
- (BOOL) close;
- (BOOL) deleteDatabase: (NSError**)outError;

+ (CBL_Database*) createEmptyDBAtPath: (NSString*)path;

/** Should the database file be opened in read-only mode? */
@property BOOL readOnly;

@property (readonly) NSString* path;
@property (readonly, copy) NSString* name;
@property (readonly) NSThread* thread;
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
    Any exception raised by the block will be caught and treated as kCBLStatusException. */
- (CBLStatus) inTransaction: (CBLStatus(^)())block;

// DOCUMENTS:

- (CBL_Revision*) getDocumentWithID: (NSString*)docID 
                       revisionID: (NSString*)revID
                          options: (CBLContentOptions)options
                           status: (CBLStatus*)outStatus;
- (CBL_Revision*) getDocumentWithID: (NSString*)docID
                       revisionID: (NSString*)revID;

- (BOOL) existsDocumentWithID: (NSString*)docID
                   revisionID: (NSString*)revID;

- (CBLStatus) loadRevisionBody: (CBL_Revision*)rev
                      options: (CBLContentOptions)options;

/** Returns an array of CBLRevs in reverse chronological order,
    starting with the given revision. */
- (NSArray*) getRevisionHistory: (CBL_Revision*)rev;

/** Returns the revision history as a _revisions dictionary, as returned by the REST API's ?revs=true option. */
- (NSDictionary*) getRevisionHistoryDict: (CBL_Revision*)rev;

/** Returns all the known revisions (or all current/conflicting revisions) of a document. */
- (CBL_RevisionList*) getAllRevisionsOfDocumentID: (NSString*)docID
                                    onlyCurrent: (BOOL)onlyCurrent;

/** Returns IDs of local revisions of the same document, that have a lower generation number.
    Does not return revisions whose bodies have been compacted away, or deletion markers. */
- (NSArray*) getPossibleAncestorRevisionIDs: (CBL_Revision*)rev
                                      limit: (unsigned)limit;

/** Returns the most recent member of revIDs that appears in rev's ancestry. */
- (NSString*) findCommonAncestorOf: (CBL_Revision*)rev withRevIDs: (NSArray*)revIDs;

// VIEWS & QUERIES:

/** Returns the value of an _all_docs query, as an array of CBL_QueryRow. */
- (NSArray*) getAllDocs: (const struct CBLQueryOptions*)options;

- (CBL_View*) viewNamed: (NSString*)name;

- (CBL_View*) existingViewNamed: (NSString*)name;

- (CBL_View*) makeAnonymousView;

/** Returns the view with the given name. If there is none, and the name is in CouchDB
    format ("designdocname/viewname"), it attempts to load the view properties from the
    design document and compile them with the CBLViewCompiler. */
- (CBL_View*) compileViewNamed: (NSString*)name status: (CBLStatus*)outStatus;

@property (readonly) NSArray* allViews;

- (CBL_RevisionList*) changesSinceSequence: (SequenceNumber)lastSequence
                                 options: (const CBLChangesOptions*)options
                                  filter: (CBL_FilterBlock)filter
                                  params: (NSDictionary*)filterParams;

/** Define or clear a named filter function. These aren't used directly by CBL_Database, but they're looked up by CBL_Router when a _changes request has a ?filter parameter. */
- (void) defineFilter: (NSString*)filterName asBlock: (CBL_FilterBlock)filterBlock;

- (CBL_FilterBlock) filterNamed: (NSString*)filterName;

- (CBL_FilterBlock) compileFilterNamed: (NSString*)filterName status: (CBLStatus*)outStatus;

+ (void) setFilterCompiler: (id<CBLFilterCompiler>)compiler;
+ (id<CBLFilterCompiler>) filterCompiler;

@end
