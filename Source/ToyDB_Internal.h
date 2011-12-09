//
//  ToyDB_Internal.h
//  ToyCouch
//
//  Created by Jens Alfke on 12/8/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "ToyDB.h"
#import "ToyView.h"


@interface ToyDB ()
@property (readonly) FMDatabase* fmdb;
- (ToyDBStatus) deleteViewNamed: (NSString*)name;
@end


@interface ToyView ()
- (id) initWithDatabase: (ToyDB*)db name: (NSString*)name;
@property (readonly) int viewID;
@end
