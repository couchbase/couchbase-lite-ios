//
//  CBLSyncListener.h
//  Couchbase Lite
//
//  Created by Jens Alfke on 4/3/15.
//  Copyright (c) 2015 Couchbase. All rights reserved.
//

#import "CBLListener.h"


/** Listener/server for new replication protocol. */
@interface CBLSyncListener : CBLListener

@property (readonly) NSUInteger connectionCount;

@end
