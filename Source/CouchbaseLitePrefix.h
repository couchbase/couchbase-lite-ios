//
//  CouchbaseLitePrefix.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/7/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#ifdef __OBJC__

#ifdef GNUSTEP
#import "CBLGNUstep.h"
#endif

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

#import "CBLJSON.h"

#import "CollectionUtils.h"
#import "Logging.h"
#import "Test.h"

#ifdef __cplusplus
}
#endif

#endif // __OBJC__
