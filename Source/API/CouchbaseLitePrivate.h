//
//  CouchbaseLitePrivate.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/19/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import "CouchbaseLite.h"
#import "CBLCache.h"
#import "CBLDatabase.h"
#import "CBL_Revision.h"
#import "CBLGeometry.h"
@class CBLDatabaseChange, CBL_Revision, CBLManager, CBL_Server;


@interface CBLManager ()
@property (readonly) CBL_Server* backgroundServer;
@property (readonly) NSArray* allReplications;
- (CBLReplication*) replicationWithDatabase: (CBLDatabase*)db
                                     remote: (NSURL*)remote
                                       pull: (BOOL)pull
                                     create: (BOOL)create
                                      start: (BOOL)start            __attribute__((nonnull));
- (NSArray*) createReplicationsBetween: (CBLDatabase*)database
                                   and: (NSURL*)otherDbURL
                           exclusively: (BOOL)exclusively
                                 start: (BOOL)start                 __attribute__((nonnull(1)));
- (void) deletePersistentReplicationsFor: (CBLDatabase*)db;
#if DEBUG // for unit tests only
- (CBLDatabase*) createEmptyDatabaseNamed: (NSString*)name error: (NSError**)outError;
#endif

@end


@interface CBLDatabase ()
- (instancetype) initWithPath: (NSString*)path
                         name: (NSString*)name
                      manager: (CBLManager*)manager
                     readOnly: (BOOL)readOnly;
@property (readonly, nonatomic) NSMutableSet* unsavedModelsMutable;
- (void) removeDocumentFromCache: (CBLDocument*)document;
- (void) doAsyncAfterDelay: (NSTimeInterval)delay block: (void (^)())block;
#if DEBUG // for testing
- (CBLDocument*) _cachedDocumentWithID: (NSString*)docID;
- (void) _clearDocumentCache;
#endif
@end


@interface CBLDocument () <CBLCacheable>
- (instancetype) initWithDatabase: (CBLDatabase*)database
                       documentID: (NSString*)docID                 __attribute__((nonnull));
- (CBLSavedRevision*) revisionFromRev: (CBL_Revision*)rev;
- (void) revisionAdded: (CBLDatabaseChange*)change                 __attribute__((nonnull));
- (void) loadCurrentRevisionFrom: (CBLQueryRow*)row                 __attribute__((nonnull));
- (CBLSavedRevision*) putProperties: (NSDictionary*)properties
                     prevRevID: (NSString*)prevID
                 allowConflict: (BOOL)allowConflict
                         error: (NSError**)outError;
@end


@interface CBLRevision ()
@property (readonly) SequenceNumber sequence;
@end


@interface CBLSavedRevision ()
- (instancetype) initWithDocument: (CBLDocument*)doc
                         revision: (CBL_Revision*)rev               __attribute__((nonnull(2)));
- (instancetype) initWithDatabase: (CBLDatabase*)tddb
                         revision: (CBL_Revision*)rev               __attribute__((nonnull));
@property (readonly) CBL_Revision* rev;
@property (readonly) BOOL propertiesAreLoaded;
@end


@interface CBLUnsavedRevision ()
- (instancetype) initWithDocument: (CBLDocument*)doc
                           parent: (CBLSavedRevision*)parent             __attribute__((nonnull(1)));
@end


@interface CBLAttachment ()
- (instancetype) _initWithContentType: (NSString*)contentType
                                 body: (id)body                          __attribute__((nonnull));
- (instancetype) initWithRevision: (CBLRevision*)rev
                             name: (NSString*)name
                         metadata: (NSDictionary*)metadata          __attribute__((nonnull));
+ (NSDictionary*) installAttachmentBodies: (NSDictionary*)attachments
                             intoDatabase: (CBLDatabase*)database   __attribute__((nonnull(2)));
@property (readwrite, copy) NSString* name;
@property (readwrite, retain) CBLRevision* revision;
@end


@interface CBLQuery ()
{
    NSString* _fullTextQuery;
    BOOL _fullTextSnippets, _fullTextRanking;
    CBLGeoRect _boundingBox;
    BOOL _isGeoQuery;
}
- (instancetype) initWithDatabase: (CBLDatabase*)database
                             view: (CBLView*)view                  __attribute__((nonnull(1)));
- (instancetype) initWithDatabase: (CBLDatabase*)database
                         mapBlock: (CBLMapBlock)mapBlock            __attribute__((nonnull));
@end


@interface CBLQueryRow ()
- (instancetype) initWithDocID: (NSString*)docID
                      sequence: (SequenceNumber)sequence
                           key: (id)key
                         value: (id)value
                 docProperties: (NSDictionary*)docProperties;
@property (readonly, nonatomic) NSDictionary* asJSONDictionary;
@end

@interface CBLFullTextQueryRow ()
- (instancetype) initWithDocID: (NSString*)docID
                      sequence: (SequenceNumber)sequence
                    fullTextID: (UInt64)fullTextID
                  matchOffsets: (NSString*)matchOffsets
                         value: (id)value;
@property (nonatomic) NSString* snippet;
@end

@interface CBLGeoQueryRow ()
- (instancetype) initWithDocID: (NSString*)docID
                      sequence: (SequenceNumber)sequence
                   boundingBox: (CBLGeoRect)bbox
                   geoJSONData: (NSData*)geoJSONData
                         value: (NSData*)valueData
                 docProperties: (NSDictionary*)docProperties;
@end


@interface CBLReplication ()
- (instancetype) initWithDatabase: (CBLDatabase*)database
                           remote: (NSURL*)remote
                             pull: (BOOL)pull                       __attribute__((nonnull));
@end
