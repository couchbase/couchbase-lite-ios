//
//  TouchDBPrivate.h
//  TouchDB
//
//  Created by Jens Alfke on 6/19/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TouchDB.h"
#import "TDCache.h"
#import "TD_Database.h"
@class TD_DatabaseChange, TD_DatabaseManager, TD_Server;


@interface TD_Database ()
@property (weak, nonatomic) TDDatabase* touchDatabase;
@end


@interface TDDatabaseManager ()
@property (readonly) TD_Server* backgroundServer;
@property (readonly) TD_DatabaseManager* tdManager;
@property (readonly) NSArray* allReplications;
- (TDReplication*) replicationWithDatabase: (TDDatabase*)db
                                       remote: (NSURL*)remote
                                         pull: (BOOL)pull
                                       create: (BOOL)create;
- (NSArray*) createReplicationsBetween: (TDDatabase*)database
                                   and: (NSURL*)otherDbURL
                           exclusively: (bool)exclusively;
@end


@interface TDDatabase ()
- (id) initWithManager: (TDDatabaseManager*)manager
            TD_Database: (TD_Database*)tddb;
@property (readonly, nonatomic) TD_Database* tddb;
@property (readonly, nonatomic) NSMutableSet* unsavedModelsMutable;
@end


@interface TDDocument () <TDCacheable>
- (id)initWithDatabase: (TDDatabase*)database
            documentID: (NSString*)docID;
- (TDRevision*) revisionFromRev: (TD_Revision*)rev;
- (void) revisionAdded: (TD_DatabaseChange*)change;
- (void) loadCurrentRevisionFrom: (TDQueryRow*)row;
- (TDRevision*) putProperties: (NSDictionary*)properties
                       prevRevID: (NSString*)prevID
                           error: (NSError**)outError;
@end


@interface TDRevisionBase ()
@property (readonly) SequenceNumber sequence;
@end


@interface TDRevision ()
- (id)initWithDocument: (TDDocument*)doc revision: (TD_Revision*)rev;
- (id)initWithTDDB: (TD_Database*)tddb revision: (TD_Revision*)rev;
@property (readonly) TD_Revision* rev;
@end


@interface TDNewRevision ()
- (id)initWithDocument: (TDDocument*)doc parent: (TDRevision*)parent;
@end


@interface TDAttachment ()
- (id) initWithRevision: (TDRevisionBase*)rev
                   name: (NSString*)name
               metadata: (NSDictionary*)metadata;
+ (NSDictionary*) installAttachmentBodies: (NSDictionary*)attachments
                             intoDatabase: (TDDatabase*)database;
@property (readwrite, copy) NSString* name;
@property (readwrite, retain) TDRevisionBase* revision;
@end


@interface TDView ()
- (id)initWithDatabase: (TDDatabase*)database view: (TD_View*)view;
@end


@interface TDQuery ()
- (id) initWithDatabase: (TDDatabase*)database view: (TD_View*)view;
- (id)initWithDatabase: (TDDatabase*)database mapBlock: (TDMapBlock)mapBlock;
@end


@interface TDReplication ()
- (id) initWithDatabase: (TDDatabase*)database
                 remote: (NSURL*)remote
                   pull: (BOOL)pull;
@end


@interface TDModel ()
@property (readonly) NSDictionary* currentProperties;
@end