//
//  CouchbaseLitePrivate.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/19/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import <CouchbaseLite/CouchbaseLite.h>
#import <CouchbaseLite/CBLReplication+Transformation.h>
@class CBL_Server, CBL_BlobStoreWriter;


@interface CBLManager ()
#if DEBUG // for unit tests only
+ (instancetype) createEmptyAtPath: (NSString*)path;  // for testing
+ (instancetype) createEmptyAtTemporaryPath: (NSString*)name;  // for testing
- (CBLDatabase*) createEmptyDatabaseNamed: (NSString*)name error: (NSError**)outError;
#endif
+ (void) setWarningsRaiseExceptions: (BOOL)wre;
@end


@interface CBLDatabase ()
- (instancetype) initWithDir: (NSString*)dir
                        name: (NSString*)name
                     manager: (CBLManager*)manager
                    readOnly: (BOOL)readOnly;
@property (readonly, nonatomic) NSMutableSet* unsavedModelsMutable;
- (void) removeDocumentFromCache: (CBLDocument*)document;
- (void) doAsyncAfterDelay: (NSTimeInterval)delay block: (void (^)())block;
- (BOOL) waitFor: (BOOL (^)())block;
- (void) addReplication: (CBLReplication*)repl;
- (void) forgetReplication: (CBLReplication*)repl;
- (void) _clearDocumentCache;
- (void) _pruneDocumentCache;
- (CBLDocument*) _cachedDocumentWithID: (NSString*)docID;
@end

@interface CBLDatabase (Private)
@property (nonatomic, readonly) NSString* privateUUID;
@property (nonatomic, readonly) NSString* publicUUID;
- (NSString*) lastSequenceWithCheckpointID: (NSString*)checkpointID;
- (BOOL) setLastSequence: (NSString*)lastSequence withCheckpointID: (NSString*)checkpointID;
- (BOOL) hasAttachmentWithDigest: (NSString*)digest;
- (uint64_t) lengthOfAttachmentWithDigest: (NSString*)digest;
- (NSData*) contentOfAttachmentWithDigest: (NSString*)digest;
- (NSInputStream*) contentStreamOfAttachmentWithDigest: (NSString*)digest;
- (CBL_BlobStoreWriter*) attachmentWriter;
- (void) rememberAttachmentWritersForDigests: (NSDictionary*)blobsByDigests;
- (NSArray*) getPossibleAncestorsOfDocID: (NSString*)docID
                                   revID: (NSString*)revID
                                   limit: (NSUInteger)limit;
- (BOOL) forceInsertRevisionWithJSON: (NSData*)json
                     revisionHistory: (NSArray*)history
                              source: (NSURL*)source
                               error: (NSError**)outError;
@end


@interface CBLDatabaseChange ()
@property (readonly) UInt64 sequenceNumber;
@property (readonly) BOOL isDeletion;
/** The revID of the default "winning" revision, or nil if it did not change. */
@property (nonatomic, readonly) NSString* winningRevisionID;
/** The revision that is now the default "winning" revision of the document, or nil if not known
    Guaranteed immutable.*/
/** Is this a relayed notification of one from another thread, not the original? */
@property (nonatomic, readonly) bool echoed;
/** Discards the body of the revision to save memory. */
- (void) reduceMemoryUsage;
@end


@interface CBLDocument ()
- (CBLSavedRevision*) putProperties: (NSDictionary*)properties
                     prevRevID: (NSString*)prevID
                 allowConflict: (BOOL)allowConflict
                         error: (NSError**)outError;
- (NSArray*) getPossibleAncestorsOfRevisionID: (NSString*)revID
                                        limit: (NSUInteger)limit;
@end


@interface CBLRevision ()
@property (readonly) SInt64 sequence;
@property (readonly) NSDictionary* attachmentMetadata;
@end


@interface CBLSavedRevision ()
@property (readonly) BOOL propertiesAreLoaded;
@property (readonly) NSData* JSONData;
- (NSArray*) getRevisionHistoryBackToRevisionIDs: (NSArray*)ancestorIDs
                                           error: (NSError**)outError;
@end


@interface CBLAttachment ()
+ (NSDictionary*) installAttachmentBodies: (NSDictionary*)attachments
                             intoDatabase: (CBLDatabase*)database   __attribute__((nonnull(2)));
@property (readwrite, copy) NSString* name;
@property (readwrite, retain) CBLRevision* revision;
@end


@interface CBLReplication ()
@property (nonatomic, readonly) NSDictionary* properties;
@end


@interface CBLModelFactory ()
- (CBLQueryBuilder*) queryBuilderForClass: (Class)klass
                                 property: (NSString*)property;
- (void) setQueryBuilder: (CBLQueryBuilder*)builder
                forClass: (Class)klass
                property: (NSString*)property;
@end


@interface CBLQuery ()
@property (nonatomic, strong) BOOL (^filterBlock)(CBLQueryRow*);
@end
