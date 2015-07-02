//
//  CBLSyncListener.h
//  Couchbase Lite
//
//  Created by Jens Alfke on 4/3/15.
//  Copyright (c) 2015 Couchbase. All rights reserved.
//

#import "BLIPPocketSocketListener.h"

@class CBLDatabase;


@interface CBLSyncListener : BLIPPocketSocketListener

- (instancetype) initWithDatabase: (CBLDatabase*)db
                             path: (NSString*)path;

@end
