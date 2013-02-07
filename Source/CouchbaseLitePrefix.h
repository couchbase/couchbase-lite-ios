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

#define MERGE_DATABASE 1
#if MERGE_DATABASE
#define CBL_Database CBLDatabase
#endif

#import "CBLJSON.h"

#import "CollectionUtils.h"
#import "Logging.h"
#import "Test.h"

#endif
