//
//  CBLInternal.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/8/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import "CouchbaseLite.h"
#import "CouchbaseLitePrivate.h"
#import "CBLDatabase+Attachments.h"
#import "CBLManager+Internal.h"
#import "CBLView+Internal.h"
#import "CBL_Revision.h"
#import "CBL_Server.h"
#import "CBL_BlobStore.h"
#import "CBLCache.h"
@class CBL_Attachment, CBL_BlobStoreWriter, CBLDatabaseChange;


// In a method/function implementation (not declaration), declaring an object parameter as
// __unsafe_unretained avoids the implicit retain at the start of the function and releasse at
// the end. In a performance-sensitive function, those can be significant overhead. Of course this
// should never be used if the object might be released during the function.
#define UU __unsafe_unretained


@interface CBLDatabase (Insertion_Internal)
- (CBLStatus) validateRevision: (CBL_Revision*)newRev previousRevision: (CBL_Revision*)oldRev
                         error: (NSError **)outError;
@end


@interface CBL_Server ()
#if DEBUG
+ (instancetype) createEmptyAtPath: (NSString*)path;  // for testing
+ (instancetype) createEmptyAtTemporaryPath: (NSString*)name;  // for testing
#endif
@end


@interface CBLManager ()
@property (readonly) CBL_Server* backgroundServer;
@end


@interface CBLDocument () <CBLCacheable>
- (instancetype) initWithDatabase: (CBLDatabase*)database
                       documentID: (NSString*)docID
                           exists: (BOOL)exists                     __attribute__((nonnull));
- (CBLSavedRevision*) revisionFromRev: (CBL_Revision*)rev;
- (void) revisionAdded: (CBLDatabaseChange*)change
                notify: (BOOL)notify                                __attribute__((nonnull));
- (void) forgetCurrentRevision;
- (void) loadCurrentRevisionFrom: (CBLQueryRow*)row                 __attribute__((nonnull));
@end


@interface CBLDatabaseChange ()
- (instancetype) initWithAddedRevision: (CBL_Revision*)addedRevision
                     winningRevisionID: (NSString*)winningRevisionID
                            inConflict: (BOOL)maybeConflict
                                source: (NSURL*)source;
/** The revision just added. Guaranteed immutable. */
@property (nonatomic, readonly) CBL_Revision* addedRevision;
@property (nonatomic, readonly) CBL_Revision* winningRevisionIfKnown;
@end


@interface CBLSavedRevision ()
- (instancetype) initWithDocument: (CBLDocument*)doc
                         revision: (CBL_Revision*)rev               __attribute__((nonnull(2)));
- (instancetype) initWithDatabase: (CBLDatabase*)tddb
                         revision: (CBL_Revision*)rev               __attribute__((nonnull));
- (instancetype) initForValidationWithDatabase: (CBLDatabase*)db
                                      revision: (CBL_Revision*)rev
                              parentRevisionID: (NSString*)parentRevID __attribute__((nonnull));
@property (readonly) CBL_Revision* rev;
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


@interface CBLQueryEnumerator ()
+ (NSSortDescriptor*) asNSSortDescriptor: (id)descOrStr; // Converts NSString to NSSortDescriptor
@end


@protocol CBL_QueryRowStorage;

@interface CBLQueryRow ()
- (instancetype) initWithDocID: (NSString*)docID
                      sequence: (SequenceNumber)sequence
                           key: (id)key
                         value: (id)value
                   docRevision: (CBL_Revision*)docRevision;
@property (readonly, nonatomic) id<CBL_QueryRowStorage> storage;
@property (readonly, nonatomic) CBL_Revision* documentRevision;
@end


@interface CBLFullTextQueryRow ()
- (instancetype) initWithDocID: (NSString*)docID
                      sequence: (SequenceNumber)sequence
                    fullTextID: (UInt64)fullTextID
                         value: (id)value;
@property (copy) NSString* snippet;
@property float relevance;
- (void) addTerm: (NSUInteger)term atRange: (NSRange)range;
- (BOOL) containsAllTerms: (NSUInteger)termCount;
@end


@interface CBLGeoQueryRow ()
- (instancetype) initWithDocID: (NSString*)docID
                      sequence: (SequenceNumber)sequence
                   boundingBox: (CBLGeoRect)bbox
                   geoJSONData: (NSData*)geoJSONData
                         value: (NSData*)valueData
                   docRevision: (CBL_Revision*)docRevision;
@end

NSString* CBLKeyPathForQueryRow(NSString* keyPath); // for testing


@interface CBLReplication ()
{
    CBLPropertiesTransformationBlock _propertiesTransformationBlock;
}
- (instancetype) initWithDatabase: (CBLDatabase*)database
                           remote: (NSURL*)remote
                             pull: (BOOL)pull                       __attribute__((nonnull));
@end