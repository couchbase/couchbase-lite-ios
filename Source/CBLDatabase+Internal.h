//
//  CBLDatabase+Internal.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/19/10.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import "CBL_Storage.h"
#import "CBLDatabase.h"
@class CBLQueryOptions, CBLView, CBLQueryRow, CBL_BlobStore, CBLDocument, CBLCache, CBLDatabase,
       CBLDatabaseChange, CBL_Shared, CBLModelFactory, CBLDatabaseOptions;


UsingLogDomain(Database);


// Default value for maxRevTreeDepth, the max rev depth to preserve in a prune operation
#define kDefaultMaxRevs 20

/** NSNotification posted when one or more documents have been updated.
    The userInfo key "changes" contains an array of CBLDatabaseChange objects. */
extern NSString* const CBL_DatabaseChangesNotification;

/** NSNotification posted when a database is closing. */
extern NSString* const CBL_DatabaseWillCloseNotification;

/** NSNotification posted when a database is about to be deleted (but before it closes). */
extern NSString* const CBL_DatabaseWillBeDeletedNotification;


/** A private runloop mode for waiting on. */
extern NSString* const CBL_PrivateRunloopMode;

/** Runloop modes that events/blocks will be scheduled to run in. Includes CBL_PrivateRunloopMode. */
extern NSArray* CBL_RunloopModes;


// Additional instance variable and property declarations
@interface CBLDatabase ()
{
    @private
    NSString* _dir;
    NSString* _name;
    CBLManager* _manager;
    id<CBL_Storage> _storage;
    BOOL _readOnly;
    BOOL _isOpen;
    NSThread* _thread;
    dispatch_queue_t _dispatchQueue;    // One and only one of _thread or _dispatchQueue is set
    NSMutableDictionary* _views;
    CBL_BlobStore* _attachments;
    NSMutableDictionary* _pendingAttachmentsByDigest;
    NSMutableArray* _activeReplicators;
    NSMutableArray* _changesToNotify;
    bool _postingChangeNotifications;
    NSDate* _startTime;
    CBLModelFactory* _modelFactory;
    NSMutableSet* _unsavedModelsMutable;   // All CBLModels that have unsaved changes
#if DEBUG
    CBL_Shared* _debug_shared;
#endif
}

@property (nonatomic, readwrite, copy) NSString* name;  // make it settable
@property (nonatomic, readonly) NSString* dir;
@property (nonatomic, readonly) BOOL isOpen;

- (void) postPublicChangeNotification: (NSArray*)changes; // implemented in CBLDatabase.m

@end



// Internal API
@interface CBLDatabase (Internal) <CBL_StorageDelegate>

- (instancetype) _initWithDir: (NSString*)dirPath
                         name: (NSString*)name
                      manager: (CBLManager*)manager
                     readOnly: (BOOL)readOnly;
+ (BOOL) deleteDatabaseFilesAtPath: (NSString*)dbPath error: (NSError**)outError;

#if DEBUG
+ (instancetype) createEmptyDBAtPath: (NSString*)path;
#endif
- (BOOL) open: (NSError**)outError;
- (BOOL) openWithOptions: (CBLDatabaseOptions*)options error: (NSError**)outError;
- (void) _close; // closes without saving CBLModels.

+ (void) setAutoCompact: (BOOL)autoCompact;

@property (nonatomic, readonly) id<CBL_Storage> storage;
@property (nonatomic, readonly) CBL_BlobStore* attachmentStore;
@property (nonatomic, readonly) CBL_Shared* shared;

@property (nonatomic, readonly) BOOL exists;
@property (nonatomic, readonly) UInt64 totalDataSize;
@property (nonatomic, readonly) NSDate* startTime;

@property (nonatomic, readonly) NSString* privateUUID;
@property (nonatomic, readonly) NSString* publicUUID;


// DOCUMENTS:

- (CBL_Revision*) getDocumentWithID: (NSString*)docID
                         revisionID: (NSString*)revID
                           withBody: (BOOL)withBody
                             status: (CBLStatus*)outStatus;
#if DEBUG // convenience method for tests
- (CBL_Revision*) getDocumentWithID: (NSString*)docID
                         revisionID: (NSString*)revID;
#endif

- (CBLStatus) loadRevisionBody: (CBL_MutableRevision*)rev;
- (CBL_Revision*) revisionByLoadingBody: (CBL_Revision*)rev
                                 status: (CBLStatus*)outStatus;
- (SequenceNumber) getRevisionSequence: (CBL_Revision*)rev;

// HISTORY:

- (NSArray*) getRevisionHistory: (CBL_Revision*)rev
                   backToRevIDs: (NSArray*)ancestorRevIDs;
+ (NSDictionary*) makeRevisionHistoryDict: (NSArray*)history;

// VIEWS & QUERIES:

/** An array of all existing views. */
@property (readonly) NSArray* allViews;

- (void) forgetViewNamed: (NSString*)name;

/** Returns the value of an _all_docs query, as an enumerator of CBLQueryRow. */
- (CBLQueryEnumerator*) getAllDocs: (CBLQueryOptions*)options
                            status: (CBLStatus*)outStatus;

- (CBLView*) makeAnonymousView;

- (id) getDesignDocFunction: (NSString*)fnName
                        key: (NSString*)key
                   language: (NSString**)outLanguage;

//@property (readonly) NSArray* allViews;

- (CBL_RevisionList*) changesSinceSequence: (SequenceNumber)lastSequence
                                   options: (const CBLChangesOptions*)options
                                    filter: (CBLFilterBlock)filter
                                    params: (NSDictionary*)filterParams
                                    status: (CBLStatus*)outStatus;

- (CBLFilterBlock) compileFilterNamed: (NSString*)filterName status: (CBLStatus*)outStatus;

- (BOOL) runFilter: (CBLFilterBlock)filter
            params: (NSDictionary*)filterParams
        onRevision: (CBL_Revision*)rev;

/** Post an NSNotification. handles if the database is running on a separate dispatch_thread
 (issue #364). */
- (void) postNotification: (NSNotification*)notification;

@end
