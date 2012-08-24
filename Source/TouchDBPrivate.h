//
//  TouchDBPrivate.h
//  TouchDB
//
//  Created by Jens Alfke on 6/19/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TouchDB.h"
@class TDServer;


@interface TDDatabase ()
@property (assign, nonatomic) TouchDatabase* touchDatabase;
@end


@interface TouchDatabaseManager ()
@property (readonly) TDServer* tdServer;
@property (readonly) TDDatabaseManager* tdManager;
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
            TDDatabase: (TDDatabase*)tddb;
@property (readonly, nonatomic) TDDatabase* tddb;
@end


@interface TouchDocument ()
- (id)initWithDatabase: (TouchDatabase*)database
            documentID: (NSString*)docID;
- (TouchRevision*) revisionFromRev: (TDRevision*)rev;
- (void) revisionAdded: (TDRevision*)rev source: (NSURL*)source;
- (void) loadCurrentRevisionFrom: (TouchQueryRow*)row;
- (TouchRevision*) putProperties: (NSDictionary*)properties
                       prevRevID: (NSString*)prevID
                           error: (NSError**)outError;
@end


@interface TouchRevision ()
- (id)initWithDocument: (TouchDocument*)doc revision: (TDRevision*)rev;
@property (readonly) TDRevision* rev;
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
- (id)initWithDatabase: (TouchDatabase*)database view: (TDView*)view;
@end


@interface TouchQuery ()
- (id) initWithDatabase: (TouchDatabase*)database view: (TDView*)view;
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