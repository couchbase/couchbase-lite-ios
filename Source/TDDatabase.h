/*
 *  TDDatabase.h
 *  TouchDB
 *
 *  Created by Jens Alfke on 6/19/10.
 *  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
 *
 */

#import "TDRevision.h"
@class FMDatabase, TDRevision, TDRevisionList, TDView, TDBlobStore, TDReplicator;
@protocol TDValidationContext;
struct TDQueryOptions;


/** Same interpretation as HTTP status codes, esp. 200, 201, 404, 409, 500. */
typedef int TDStatus;


/** NSNotification posted when a document is updated.
    The userInfo key "rev" has a TDRevision* as its value. */
extern NSString* const TDDatabaseChangeNotification;


/** Validation block, used to approve revisions being added to the database. */
typedef BOOL (^TDValidationBlock) (TDRevision* newRevision,
                                   id<TDValidationContext> context);

/** Filter block, used in changes feeds and replication. */
typedef BOOL (^TDFilterBlock) (TDRevision* revision);



/** Options for _changes feed (-changesSinceSequence:). */
typedef struct TDChangesOptions {
    unsigned limit;
    BOOL includeDocs;
    BOOL includeConflicts;
    BOOL sortBySequence;
} TDChangesOptions;

extern const TDChangesOptions kDefaultTDChangesOptions;



/** A TouchDB database. */
@interface TDDatabase : NSObject
{
    @private
    NSString* _path;
    NSString* _name;
    FMDatabase *_fmdb;
    BOOL _open;
    NSInteger _transactionLevel;
    NSMutableDictionary* _views;
    NSMutableArray* _validations;
    NSMutableDictionary* _filters;
    TDBlobStore* _attachments;
    NSMutableArray* _activeReplicators;
}    
        
- (id) initWithPath: (NSString*)path;
- (BOOL) open;
- (BOOL) close;
- (BOOL) deleteDatabase: (NSError**)outError;

+ (TDDatabase*) createEmptyDBAtPath: (NSString*)path;

@property (readonly) NSString* path;
@property (readonly, copy) NSString* name;
@property (readonly) BOOL exists;

/** Begins a database transaction. Transactions can nest. Every -beginTransaction must be balanced by a later -endTransaction:. */
- (BOOL) beginTransaction;

/** Commits or aborts (rolls back) a transaction.
    @param commit  If YES, commits; if NO, aborts and rolls back, undoing all changes made since the matching -beginTransaction call, *including* any committed nested transactions. */
- (BOOL) endTransaction: (BOOL)commit;

/** Compacts the database storage by removing the bodies and attachments of obsolete revisions. */
- (TDStatus) compact;

// DOCUMENTS:

@property (readonly) NSUInteger documentCount;
@property (readonly) SequenceNumber lastSequence;

- (TDRevision*) getDocumentWithID: (NSString*)docID 
                       revisionID: (NSString*)revID
                  withAttachments: (BOOL)withAttachments;
- (BOOL) existsDocumentWithID: (NSString*)docID
                   revisionID: (NSString*)revID;
- (TDStatus) loadRevisionBody: (TDRevision*)rev
              withAttachments: (BOOL)andAttachments;

/** Returns an array of TDRevs in reverse chronological order,
    starting with the given revision. */
- (NSArray*) getRevisionHistory: (TDRevision*)rev;

/** Returns all the known revisions (or all current/conflicting revisions) of a document. */
- (TDRevisionList*) getAllRevisionsOfDocumentID: (NSString*)docID
                                    onlyCurrent: (BOOL)onlyCurrent;

// VIEWS & QUERIES:

- (NSDictionary*) getAllDocs: (const struct TDQueryOptions*)options;
- (NSDictionary*) getDocsWithIDs: (NSArray*)docIDs options: (const struct TDQueryOptions*)options;

- (TDView*) viewNamed: (NSString*)name;
- (TDView*) existingViewNamed: (NSString*)name;
@property (readonly) NSArray* allViews;

- (TDRevisionList*) changesSinceSequence: (SequenceNumber)lastSequence
                                 options: (const TDChangesOptions*)options
                                  filter: (TDFilterBlock)filter;

/** Define a named filter function. These aren't used directly by TDDatabase, but they're looked up by TDRouter when a _changes request has a ?filter parameter. */
- (void) defineFilter: (NSString*)filterName asBlock: (TDFilterBlock)filterBlock;
- (TDFilterBlock) filterNamed: (NSString*)filterName;

@end



@interface TDDatabase (Insertion)

+ (BOOL) isValidDocumentID: (NSString*)str;
+ (NSString*) generateDocumentID;

/** Stores a new (or initial) revision of a document. This is what's invoked by a PUT or POST. As with those, the previous revision ID must be supplied when necessary and the call will fail if it doesn't match.
    @param revision  The revision to add. If the docID is nil, a new UUID will be assigned. Its revID must be nil. It must have a JSON body.
    @param prevRevID  The ID of the revision to replace (same as the "?rev=" parameter to a PUT), or nil if this is a new document.
    @param status  On return, an HTTP status code indicating success or failure.
    @return  A new TDRevision with the docID, revID and sequence filled in (but no body). */
- (TDRevision*) putRevision: (TDRevision*)revision
             prevRevisionID: (NSString*)prevRevID
                     status: (TDStatus*)outStatus;

/** Inserts an already-existing revision replicated from a remote database. It must already have a revision ID. This may create a conflict! The revision's history must be given; ancestor revision IDs that don't already exist locally will create phantom revisions with no content. */
- (TDStatus) forceInsert: (TDRevision*)rev
         revisionHistory: (NSArray*)history
                  source: (NSURL*)source;

/** Parses the _revisions dict from a document into an array of revision ID strings */
+ (NSArray*) parseCouchDBRevisionHistory: (NSDictionary*)docProperties;

- (void) addValidation: (TDValidationBlock)validationBlock;

@end



@interface TDDatabase (Attachments)

/** Given a newly-added revision, adds the necessary attachment rows to the database and stores inline attachments into the blob store. */
- (TDStatus) processAttachmentsForRevision: (TDRevision*)rev
                        withParentSequence: (SequenceNumber)parentSequence;

/** Inserts a single new attachment for a revision. */
- (BOOL) insertAttachment: (NSData*)contents
              forSequence: (SequenceNumber)sequence
                    named: (NSString*)filename
                     type: (NSString*)contentType
                   revpos: (unsigned)revpos;

/** Constructs an "_attachments" dictionary for a revision, to be inserted in its JSON body. */
- (NSDictionary*) getAttachmentDictForSequence: (SequenceNumber)sequence
                                   withContent: (BOOL)withContent;

/** Returns the content and MIME type of an attachment */
- (NSData*) getAttachmentForSequence: (SequenceNumber)sequence
                               named: (NSString*)filename
                                type: (NSString**)outType
                              status: (TDStatus*)outStatus;

/** Deletes obsolete attachments from the database and blob store. */
- (TDStatus) garbageCollectAttachments;

@end



@interface TDDatabase (Replication)
@property (readonly) NSArray* activeReplicators;

- (TDReplicator*) activeReplicatorWithRemoteURL: (NSURL*)remote
                                           push: (BOOL)push;
- (TDReplicator*) replicateWithRemoteURL: (NSURL*)remote
                                    push: (BOOL)push
                              continuous: (BOOL)continuous;

- (BOOL) findMissingRevisions: (TDRevisionList*)revs;
@end






/** Context passed into a TDValidationBlock. */
@protocol TDValidationContext <NSObject>
/** The contents of the current revision of the document, or nil if this is a new document. */
@property (readonly) TDRevision* currentRevision;

/** The type of HTTP status to report, if the validate block returns NO.
    The default value is 403 ("Forbidden"). */
@property TDStatus errorType;

/** The error message to return in the HTTP response, if the validate block returns NO.
    The default value is "invalid document". */
@property (copy) NSString* errorMessage;
@end
