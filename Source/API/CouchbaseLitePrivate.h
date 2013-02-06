//
//  CouchbaseLitePrivate.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/19/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "CouchbaseLite.h"
#import "CBLCache.h"
#import "CBL_Database.h"
@class CBL_DatabaseChange, CBLManager, CBL_Server;


@interface CBLManager ()
@property (readonly) CBL_Server* backgroundServer;
@property (readonly) NSArray* allReplications;
- (CBLReplication*) replicationWithDatabase: (CBLDatabase*)db
                                       remote: (NSURL*)remote
                                         pull: (BOOL)pull
                                       create: (BOOL)create         __attribute__((nonnull));
- (NSArray*) createReplicationsBetween: (CBLDatabase*)database
                                   and: (NSURL*)otherDbURL
                           exclusively: (bool)exclusively           __attribute__((nonnull(1)));
@end


@interface CBLDatabase ()
- (instancetype) initWithManager: (CBLManager*)manager
                    CBL_Database: (CBL_Database*)tddb               __attribute__((nonnull));
@property (readonly, nonatomic) CBL_Database* tddb;
@property (readonly, nonatomic) NSMutableSet* unsavedModelsMutable;
- (void) removeDocumentFromCache: (CBLDocument*)document;
@end


@interface CBLDocument () <CBLCacheable>
- (instancetype) initWithDatabase: (CBLDatabase*)database
                       documentID: (NSString*)docID                 __attribute__((nonnull));
- (CBLRevision*) revisionFromRev: (CBL_Revision*)rev;
- (void) revisionAdded: (CBL_DatabaseChange*)change                 __attribute__((nonnull));
- (void) loadCurrentRevisionFrom: (CBLQueryRow*)row                 __attribute__((nonnull));
- (CBLRevision*) putProperties: (NSDictionary*)properties
                       prevRevID: (NSString*)prevID
                           error: (NSError**)outError;
@end


@interface CBLRevisionBase ()
@property (readonly) SequenceNumber sequence;
@end


@interface CBLRevision ()
- (instancetype) initWithDocument: (CBLDocument*)doc
                         revision: (CBL_Revision*)rev               __attribute__((nonnull(2)));
- (instancetype) initWithCBLDB: (CBL_Database*)tddb
                      revision: (CBL_Revision*)rev                  __attribute__((nonnull));
@property (readonly) CBL_Revision* rev;
@end


@interface CBLNewRevision ()
- (instancetype) initWithDocument: (CBLDocument*)doc
                           parent: (CBLRevision*)parent             __attribute__((nonnull(1)));
@end


@interface CBLAttachment ()
- (instancetype) initWithRevision: (CBLRevisionBase*)rev
                             name: (NSString*)name
                         metadata: (NSDictionary*)metadata          __attribute__((nonnull));
+ (NSDictionary*) installAttachmentBodies: (NSDictionary*)attachments
                             intoDatabase: (CBLDatabase*)database   __attribute__((nonnull(2)));
@property (readwrite, copy) NSString* name;
@property (readwrite, retain) CBLRevisionBase* revision;
@end


@interface CBLQuery ()
- (instancetype) initWithDatabase: (CBLDatabase*)database
                             view: (CBLView*)view                  __attribute__((nonnull(1)));
- (instancetype) initWithDatabase: (CBLDatabase*)database
                         mapBlock: (CBLMapBlock)mapBlock            __attribute__((nonnull));
@end


@interface CBLReplication ()
- (instancetype) initWithDatabase: (CBLDatabase*)database
                           remote: (NSURL*)remote
                             pull: (BOOL)pull                       __attribute__((nonnull));
@end


@interface CBLModel ()
@property (readonly) NSDictionary* currentProperties;
@end
