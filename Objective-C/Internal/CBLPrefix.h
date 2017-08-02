//
//  CBLPrefix.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/5/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#ifdef __OBJC__

#import <Foundation/Foundation.h>

#import "Fleece.h"
#import "CBLLog.h"

#ifdef __cplusplus
extern "C" {
#endif

#ifndef CBL_THREADSAFE
#define CBL_THREADSAFE 1
#endif
    
#import "CBLThreadSafe.h"
#import "CollectionUtils.h"
#import "Test.h"

#ifdef __cplusplus
}
#endif

#endif // __OBJC__
