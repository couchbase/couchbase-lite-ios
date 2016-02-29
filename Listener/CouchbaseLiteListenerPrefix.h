//
//  CouchbaseLiteListenerPrefix.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/24/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

#import "CouchbaseLitePrefix.h"

// Workaround for GCDAsyncSocket also defining a LogVerbose macro:
#undef LogVerbose
