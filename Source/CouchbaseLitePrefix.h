//
//  CouchbaseLitePrefix.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/7/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#ifdef __OBJC__

#ifdef GNUSTEP
#import "CBLGNUstep.h"
#endif

#import <Foundation/Foundation.h>

#import "CBLJSON.h"

#import "CollectionUtils.h"
#import "Logging.h"
#import "Test.h"

#endif // __OBJC__


// Configuration for the sqlite3-unicodesn library:
#define SQLITE_ENABLE_FTS4 
#define SQLITE_ENABLE_FTS4_UNICODE61
