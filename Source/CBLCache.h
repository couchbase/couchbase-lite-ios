//
//  CBLCache.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/17/11.
//  Copyright 2011-2013 Couchbase, Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import <Foundation/Foundation.h>
@protocol CBLCacheable;


// CBLCache doesn't need hand-holding from its CBLCacheable objects if NSMapTable is available
// and supports weak references. (iOS 6, Mac OS X 10.8.)
#if ! __has_feature(objc_arc)
#  define CBLCACHE_IS_SMART 0
#elif defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
#  define CBLCACHE_IS_SMART (__IPHONE_OS_VERSION_MIN_REQUIRED >= 60000)
#elif defined(TARGET_OS_MAC)
#  define CBLCACHE_IS_SMART (__MAC_OS_X_VERSION_MIN_REQUIRED >= 1080)
#else
#  define CBLCACHE_IS_SMART 0
#endif


/** An in-memory object cache.
    It keeps track of all added objects as long as anything else has retained them,
    and it keeps a certain number of recently-accessed objects with no external references.
    It's intended for use by a parent resource, to cache its children.
 
    Important:
    * Every object added must have a unique and fixed .cacheKey value.
    * If ARC is not enabled, an object can belong to only one CBLCache at a time. */
@interface CBLCache : NSObject
{
    @private
#if CBLCACHE_IS_SMART
    NSMapTable* _map;
#else
    NSMutableDictionary* _map;
#endif
    NSCache* _cache;
}

- (instancetype) init;
- (instancetype) initWithRetainLimit: (NSUInteger)retainLimit;

/** Adds a resource to the cache.
    Does nothing if the resource is already in the cache.
    An exception is raised if the resource is already in a different cache. */
- (void) addResource: (id<CBLCacheable>)resource;

/** Looks up a resource given its -cacheKey property. */
- (id<CBLCacheable>) resourceWithCacheKey: (NSString*)cacheKey;

/** Removes a resource from the cache.
    Does nothing if the resource is not cached.
    An exception is raised if the resource is already in a different cache. */
- (void) forgetResource: (id<CBLCacheable>)resource;

/** Removes all resources from the cache. */
- (void) forgetAllResources;

/** Removes retained references to objects.
    All objects that don't have anything else retaining them will be removed from the cache. */
- (void) unretainResources;

#if ! CBLCACHE_IS_SMART
/** A CBLCacheable implementation MUST call this at the start of its -dealloc method! */
- (void) resourceBeingDealloced:(id<CBLCacheable>)resource;
#endif

@end


@protocol CBLCacheable <NSObject>

#if ! CBLCACHE_IS_SMART
@property (weak) CBLCache* owningCache;
#endif
@property (readonly) NSString* cacheKey;

@end
