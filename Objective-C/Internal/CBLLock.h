//
//  CBLLock.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 11/22/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//


#pragma once

#if CBL_THREADSAFE
    #if DEBUG
        #define CBL_LOCK(m) assert(m); @synchronized(m)
    #else
        #define CBL_LOCK(m) @synchronized(m)
    #endif
#endif
