//
//  CBLThreadSafe.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#ifndef CBLThreadSafe_h
#define CBLThreadSafe_h

#if CBL_THREADSAFE
#if DEBUG
#define CBL_LOCK(m) assert(m); @synchronized(m)
#else
#define CBL_LOCK(m) @synchronized(m)
#endif

#define CBL_LOCK_GUARD(m) std::lock_guard<std::mutex> lock(m);
#else
#define CBL_LOCK(m)
#define CBL_LOCK_GUARD(m)
#endif

#endif /* CBLThreadSafe_h */
