//
//  TouchDBPrivate.h
//  TouchDB
//
//  Created by Jens Alfke on 6/19/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TouchDB.h"


@interface TouchDatabase ()
- (id) initWithTDDatabase: (TDDatabase*)tddb;
@property (readonly, nonatomic) TDDatabase* tddb;
@end


@interface TouchDocument ()
- (id)initWithDatabase: (TouchDatabase*)database
            documentID: (NSString*)docID;
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
@end
