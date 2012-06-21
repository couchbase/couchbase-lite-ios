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
@end


@interface TouchView ()
- (id)initWithDatabase: (TouchDatabase*)database view: (TDView*)view;
@end


@interface TouchQuery ()
- (id) initWithDatabase: (TouchDatabase*)database view: (TDView*)view;
@end
