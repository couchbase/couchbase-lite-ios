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
- (void) addReplication: (CBLReplication*)repl;
- (void) forgetReplication: (CBLReplication*)repl;
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
- (void) _setParentRevisionID: (NSString*)parentRevID;
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
@property (nonatomic, readonly) NSDictionary* properties;

/** Optional callback for transforming document bodies during replication; can be used to encrypt documents stored on the remote server, for example.
    In a push replication, the block is called with document properties from the local database, and the transformed properties are what will be uploaded to the server.
    In a pull replication, the block is called with document properties downloaded from the server, and the transformed properties are what will be stored in the local database.
    The block takes an NSDictionary containing the document's properties (including the "_id" and "_rev" metadata), and returns a dictionary of transformed properties. It may return the input dictionary if it has no changes to make.
    The transformation MUST preserve the values of any keys whose names begin with an underscore ("_")!
    The block will be called on the background replicator thread, NOT on the CBLReplication's thread, so it shouldn't directly access any Couchbase Lite objects. */
@property (strong) CBLPropertiesTransformationBlock propertiesTransformationBlock;
@end
