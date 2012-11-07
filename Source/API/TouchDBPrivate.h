//
//  TouchDBPrivate.h
//  TouchDB
//
//  Created by Jens Alfke on 6/19/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TouchDB.h"
@class TD_Server;


@interface TD_Database ()
@property (weak, nonatomic) TDDatabase* touchDatabase;
@end


@interface TDDatabaseManager ()
#if 0
@property (readonly) TD_Server* tdServer;
#endif
@property (readonly) TD_DatabaseManager* tdManager;
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
@end


@interface TDDocument ()
- (id)initWithDatabase: (TDDatabase*)database
            documentID: (NSString*)docID;
- (TDRevision*) revisionFromRev: (TD_Revision*)rev;
- (void) revisionAdded: (TD_Revision*)rev source: (NSURL*)source;
- (void) loadCurrentRevisionFrom: (TDQueryRow*)row;
- (TDRevision*) putProperties: (NSDictionary*)properties
                       prevRevID: (NSString*)prevID
                           error: (NSError**)outError;
@end


@interface TDRevision ()
- (id)initWithDocument: (TDDocument*)doc revision: (TD_Revision*)rev;
@property (readonly) TD_Revision* rev;
@property (readonly) SequenceNumber sequence;
@end


@interface TDAttachment ()
- (id) initWithRevision: (TDRevision*)rev
                   name: (NSString*)name
               metadata: (NSDictionary*)metadata;
+ (NSDictionary*) installAttachmentBodies: (NSDictionary*)attachments
                             intoDatabase: (TDDatabase*)database;
@property (readwrite, copy) NSString* name;
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