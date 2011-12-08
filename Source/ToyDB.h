/*
 *  ToyDB.h
 *  ToyCouch
 *
 *  Created by Jens Alfke on 6/19/10.
 *  Copyright 2010 Jens Alfke. All rights reserved.
 *
 */

#import "ToyRev.h"
@class FMDatabase, ToyRev, ToyRevList;


/** Same interpretation as HTTP status codes, esp. 200, 201, 404, 409, 500. */
typedef int ToyDBStatus;


extern NSString* const ToyDBChangeNotification;


typedef struct {
    NSString* startKey;
    NSString* endKey;
    int skip;
    int limit;
    BOOL descending;
    BOOL includeDocs;
    BOOL updateSeq;
} ToyDBQueryOptions;

extern const ToyDBQueryOptions kDefaultToyDBQueryOptions;


/** A ToyCouch database. Acts primarily as a container for named tables (CLCaches). */
@interface ToyDB : NSObject
{
    @private
    NSString* _path;
    FMDatabase *_fmdb;
    BOOL _open;
    NSInteger _transactionLevel;
    BOOL _transactionFailed;
}    
        
- (id) initWithPath: (NSString*)path;
- (BOOL) open;
#if SQLITE_VERSION_NUMBER >= 3005000
- (BOOL) openWithFlags:(int)flags;
#endif
- (BOOL) close;

@property (readonly) NSString* path;
@property (readonly) NSString* name;
@property (readonly) BOOL exists;
@property (readonly) int error;

- (void) beginTransaction;
- (void) endTransaction;
@property BOOL transactionFailed;

- (ToyDBStatus) compact;

// DOCUMENTS:

+ (BOOL) isValidDocumentID: (NSString*)str;
- (NSString*) generateDocumentID;

@property (readonly) NSUInteger documentCount;
@property (readonly) SequenceNumber lastSequence;

- (ToyRev*) getDocumentWithID: (NSString*)docID;
- (ToyRev*) getDocumentWithID: (NSString*)docID revisionID: (NSString*)revID;
- (ToyDBStatus) loadRevisionBody: (ToyRev*)rev;

/** Returns an array of ToyRevs in reverse chronological order,
    starting with the given revision. */
- (NSArray*) getRevisionHistory: (ToyRev*)rev;
- (ToyRevList*) getAllRevisionsOfDocumentID: (NSString*)docID;

- (ToyRev*) putRevision: (ToyRev*)revision
         prevRevisionID: (NSString*)revID
                 status: (ToyDBStatus*)outStatus;
- (ToyDBStatus) forceInsert: (ToyRev*)rev
            revisionHistory: (NSArray*)history;

- (NSArray*) changesSinceSequence: (int)lastSequence
                          options: (const ToyDBQueryOptions*)options;

// QUERIES:

- (NSDictionary*) getAllDocs: (const ToyDBQueryOptions*)options;

// FOR REPLICATION:

- (BOOL) findMissingRevisions: (ToyRevList*)toyRevs;

@end
