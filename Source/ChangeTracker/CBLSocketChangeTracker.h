//
//  CBLSocketChangeTracker.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/2/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import "CBLChangeTracker.h"


/** CBLChangeTracker implementation that uses a raw TCP socket to read the HTTP response. */
@interface CBLSocketChangeTracker : CBLChangeTracker

@end
