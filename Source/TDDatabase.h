/*
 *  TDDatabase.h
 *  TouchDB
 *
 *  Created by Jens Alfke on 6/19/10.
 *  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
 *
 */

#import "TDRevision.h"
@class FMDatabase, TDRevision, TDRevisionList, TDView, TDContentStore;

struct TDQueryOptions;


/** Same interpretation as HTTP status codes, esp. 200, 201, 404, 409, 500. */
typedef int TDStatus;


/** NSNotification posted when a document is updated.
    The userInfo key "rev" has a TDRevision* as its value. */
extern NSString* const TDDatabaseChangeNotification;


/** A TouchDB database. */
@interface TDDatabase : NSObject
{
    @private
    NSString* _path;
    FMDatabase *_fmdb;
    BOOL _open;
    NSInteger _transactionLevel;
    BOOL _transactionFailed;
    NSMutableDictionary* _views;
    TDContentStore* _attachments;
}    
        
- (id) initWithPath: (NSString*)path;
- (BOOL) open;
#if SQLITE_VERSION_NUMBER >= 3005000
- (BOOL) openWithFlags:(int)flags;
#endif
- (BOOL) close;

+ (TDDatabase*) createEmptyDBAtPath: (NSString*)path;

@property (readonly) NSString* path;
@property (readonly) NSString* name;
@property (readonly) BOOL exists;
@property (readonly) int error;

- (void) beginTransaction;
- (void) endTransaction;
@property BOOL transactionFailed;

- (TDStatus) compact;
- (NSInteger) garbageCollectAttachments;

// DOCUMENTS:

+ (BOOL) isValidDocumentID: (NSString*)str;
- (NSString*) generateDocumentID;

@property (readonly) NSUInteger documentCount;
@property (readonly) SequenceNumber lastSequence;

- (TDRevision*) getDocumentWithID: (NSString*)docID;
- (TDRevision*) getDocumentWithID: (NSString*)docID revisionID: (NSString*)revID;
- (TDStatus) loadRevisionBody: (TDRevision*)rev;

/** Returns an array of TDRevs in reverse chronological order,
    starting with the given revision. */
- (NSArray*) getRevisionHistory: (TDRevision*)rev;
- (TDRevisionList*) getAllRevisionsOfDocumentID: (NSString*)docID;

- (TDRevision*) putRevision: (TDRevision*)revision
         prevRevisionID: (NSString*)revID
                 status: (TDStatus*)outStatus;
- (TDStatus) forceInsert: (TDRevision*)rev
            revisionHistory: (NSArray*)history;

- (BOOL) insertAttachment: (NSData*)contents
              forSequence: (SequenceNumber)sequence
                    named: (NSString*)filename;
- (NSData*) getAttachmentForSequence: (SequenceNumber)sequence
                               named: (NSString*)filename
                              status: (TDStatus*)outStatus;

- (NSArray*) changesSinceSequence: (int)lastSequence
                          options: (const struct TDQueryOptions*)options;

// VIEWS & QUERIES:

- (NSDictionary*) getAllDocs: (const struct TDQueryOptions*)options;

- (TDView*) viewNamed: (NSString*)name;
@property (readonly) NSArray* allViews;

// FOR REPLICATION:

- (BOOL) findMissingRevisions: (TDRevisionList*)revs;

@end
