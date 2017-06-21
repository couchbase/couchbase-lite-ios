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
#define CBL_LOCK(m) @synchronized(m)
#else
#define CBL_LOCK(m) 
#endif

#endif /* CBLThreadSafe_h */
