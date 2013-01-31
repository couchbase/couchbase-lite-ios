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
@class CBL_DatabaseChange, CBL_DatabaseManager, CBL_Server;


@interface CBL_Database ()
@property (weak, nonatomic) CBLDatabase* touchDatabase;
@end


@interface CBLManager ()
@property (readonly) CBL_Server* backgroundServer;
@property (readonly) CBL_DatabaseManager* tdManager;
@property (readonly) NSArray* allReplications;
- (CBLReplication*) replicationWithDatabase: (CBLDatabase*)db
                                       remote: (NSURL*)remote
                                         pull: (BOOL)pull
                                       create: (BOOL)create;
- (NSArray*) createReplicationsBetween: (CBLDatabase*)database
                                   and: (NSURL*)otherDbURL
                           exclusively: (bool)exclusively;
@end


@interface CBLDatabase ()
- (id) initWithManager: (CBLManager*)manager
            CBL_Database: (CBL_Database*)tddb;
@property (readonly, nonatomic) CBL_Database* tddb;
@property (readonly, nonatomic) NSMutableSet* unsavedModelsMutable;
@end


@interface CBLDocument () <CBLCacheable>
- (id)initWithDatabase: (CBLDatabase*)database
            documentID: (NSString*)docID;
- (CBLRevision*) revisionFromRev: (CBL_Revision*)rev;
- (void) revisionAdded: (CBL_DatabaseChange*)change;
- (void) loadCurrentRevisionFrom: (CBLQueryRow*)row;
- (CBLRevision*) putProperties: (NSDictionary*)properties
                       prevRevID: (NSString*)prevID
                           error: (NSError**)outError;
@end


@interface CBLRevisionBase ()
@property (readonly) SequenceNumber sequence;
@end


@interface CBLRevision ()
- (id)initWithDocument: (CBLDocument*)doc revision: (CBL_Revision*)rev;
- (id)initWithCBLDB: (CBL_Database*)tddb revision: (CBL_Revision*)rev;
@property (readonly) CBL_Revision* rev;
@end


@interface CBLNewRevision ()
- (id)initWithDocument: (CBLDocument*)doc parent: (CBLRevision*)parent;
@end


@interface CBLAttachment ()
- (id) initWithRevision: (CBLRevisionBase*)rev
                   name: (NSString*)name
               metadata: (NSDictionary*)metadata;
+ (NSDictionary*) installAttachmentBodies: (NSDictionary*)attachments
                             intoDatabase: (CBLDatabase*)database;
@property (readwrite, copy) NSString* name;
@property (readwrite, retain) CBLRevisionBase* revision;
@end


@interface CBLView ()
- (id)initWithDatabase: (CBLDatabase*)database view: (CBL_View*)view;
@end


@interface CBLQuery ()
- (id) initWithDatabase: (CBLDatabase*)database view: (CBL_View*)view;
- (id)initWithDatabase: (CBLDatabase*)database mapBlock: (CBLMapBlock)mapBlock;
@end


@interface CBLReplication ()
- (id) initWithDatabase: (CBLDatabase*)database
                 remote: (NSURL*)remote
                   pull: (BOOL)pull;
@end


@interface CBLModel ()
@property (readonly) NSDictionary* currentProperties;
@end
