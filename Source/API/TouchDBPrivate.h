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
@property (weak, nonatomic) TouchDatabase* touchDatabase;
@end


@interface TouchDatabaseManager ()
#if 0
@property (readonly) TD_Server* tdServer;
#endif
@property (readonly) TD_DatabaseManager* tdManager;
- (TouchReplication*) replicationWithDatabase: (TouchDatabase*)db
                                       remote: (NSURL*)remote
                                         pull: (BOOL)pull
                                       create: (BOOL)create;
- (NSArray*) createReplicationsBetween: (TouchDatabase*)database
and: (NSURL*)otherDbURL
exclusively: (bool)exclusively;
@end


@interface TouchDatabase ()
- (id) initWithManager: (TouchDatabaseManager*)manager
            TD_Database: (TD_Database*)tddb;
@property (readonly, nonatomic) TD_Database* tddb;
@end


@interface TouchDocument ()
- (id)initWithDatabase: (TouchDatabase*)database
            documentID: (NSString*)docID;
- (TouchRevision*) revisionFromRev: (TD_Revision*)rev;
- (void) revisionAdded: (TD_Revision*)rev source: (NSURL*)source;
- (void) loadCurrentRevisionFrom: (TouchQueryRow*)row;
- (TouchRevision*) putProperties: (NSDictionary*)properties
                       prevRevID: (NSString*)prevID
                           error: (NSError**)outError;
@end


@interface TouchRevision ()
- (id)initWithDocument: (TouchDocument*)doc revision: (TD_Revision*)rev;
@property (readonly) TD_Revision* rev;
@property (readonly) SequenceNumber sequence;
@end


@interface TouchAttachment ()
- (id) initWithRevision: (TouchRevision*)rev
                   name: (NSString*)name
               metadata: (NSDictionary*)metadata;
+ (NSDictionary*) installAttachmentBodies: (NSDictionary*)attachments
                             intoDatabase: (TouchDatabase*)database;
@property (readwrite, copy) NSString* name;
@end


@interface TouchView ()
- (id)initWithDatabase: (TouchDatabase*)database view: (TD_View*)view;
@end


@interface TouchQuery ()
- (id) initWithDatabase: (TouchDatabase*)database view: (TD_View*)view;
- (id)initWithDatabase: (TouchDatabase*)database mapBlock: (TDMapBlock)mapBlock;
@end


@interface TouchReplication ()
- (id) initWithDatabase: (TouchDatabase*)database
                 remote: (NSURL*)remote
                   pull: (BOOL)pull;
@end


@interface TouchModel ()
@property (readonly) NSDictionary* currentProperties;
@end