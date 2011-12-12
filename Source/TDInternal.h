//
//  TDInternal.h
//  TouchDB
//
//  Created by Jens Alfke on 12/8/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TDDatabase.h"
#import "TDView.h"
#import "TDServer.h"


@interface TDDatabase ()
@property (readonly) FMDatabase* fmdb;
@property (readonly) TDContentStore* attachmentStore;
- (TDStatus) deleteViewNamed: (NSString*)name;
@end


@interface TDView ()
- (id) initWithDatabase: (TDDatabase*)db name: (NSString*)name;
@property (readonly) int viewID;
- (NSArray*) dump;
@end


@interface TDServer ()
#if DEBUG
+ (TDServer*) createEmptyAtPath: (NSString*)path;  // for testing
#endif
@end
