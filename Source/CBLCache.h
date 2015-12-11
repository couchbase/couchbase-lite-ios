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


/** An in-memory object cache.
    It keeps track of all added objects as long as anything else has retained them,
    and it keeps a certain number of recently-accessed objects with no external references.
    It's intended for use by a parent resource, to cache its children.
 
    Important: Every object added must have a unique and fixed .cacheKey value. */
@interface CBLCache : NSObject

- (instancetype) init;
- (instancetype) initWithRetainLimit: (NSUInteger)retainLimit;

/** Adds a resource to the cache.
    Does nothing if the resource is already in the cache.
    An exception is raised if the resource is already in a different cache. */
- (void) addResource: (id<CBLCacheable>)resource;

/** Looks up a resource given its -cacheKey property. */
- (id<CBLCacheable>) resourceWithCacheKey: (NSString*)cacheKey;

 /** Same as -resourceWithCacheKey but does not mark the resource as being recently-used. */
- (id<CBLCacheable>) resourceWithCacheKeyDontRecache: (NSString*)cacheKey;

/** Removes a resource from the cache.
    Does nothing if the resource is not cached.
    An exception is raised if the resource is already in a different cache. */
- (void) forgetResource: (id<CBLCacheable>)resource;

/** Removes all resources from the cache. */
- (void) forgetAllResources;

/** Removes retained references to objects.
    All objects that don't have anything else retaining them will be removed from the cache. */
- (void) unretainResources;

@end


@protocol CBLCacheable <NSObject>

@property (readonly) NSString* cacheKey;

@end
