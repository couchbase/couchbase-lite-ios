//
//  TDCache.m
//  TouchDB
//
//  Created by Jens Alfke on 6/17/11.
//  Copyright 2011 Couchbase, Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TDCache.h"


static const NSUInteger kDefaultRetainLimit = 50;


@implementation TDCache


- (id)init {
    return [self initWithRetainLimit: kDefaultRetainLimit];
}


- (id)initWithRetainLimit: (NSUInteger)retainLimit {
    self = [super init];
    if (self) {
#ifdef TARGET_OS_IPHONE
        // Construct a CFDictionary that doesn't retain its values:
        CFDictionaryValueCallBacks valueCB = kCFTypeDictionaryValueCallBacks;
        valueCB.retain = NULL;
        valueCB.release = NULL;
        _map = (NSMutableDictionary*)CFDictionaryCreateMutable(
                       NULL, 100, &kCFCopyStringDictionaryKeyCallBacks, &valueCB);
#else
        // Construct an NSMapTable that doesn't retain its values:
        _map = [[NSMapTable alloc] initWithKeyOptions: NSPointerFunctionsStrongMemory |
                                                       NSPointerFunctionsObjectPersonality
                                         valueOptions: NSPointerFunctionsZeroingWeakMemory |
                                                       NSPointerFunctionsObjectPersonality
                                             capacity: 100];
#endif
        if (retainLimit > 0) {
            _cache = [[NSCache alloc] init];
            _cache.countLimit = retainLimit;
        }
    }
    return self;
}


- (void)dealloc {
    for (id<TDCacheable> doc in _map.objectEnumerator)
        doc.owningCache = nil;
    [_map release];
    [_cache release];
    [super dealloc];
}


- (void) addResource: (id<TDCacheable>)resource {
    resource.owningCache = self;
    NSString* key = resource.cacheKey;
    NSAssert(!_map[key], @"Caching duplicate items for '%@': %p, now %p",
             key, _map[key], resource);
    _map[key] = resource;
    if (_cache)
        [_cache setObject: resource forKey: key];
    else
        [[resource retain] autorelease];
}


- (id<TDCacheable>) resourceWithCacheKey: (NSString*)docID {
    id<TDCacheable> doc = _map[docID];
    if (doc && _cache && ![_cache objectForKey:docID])
        [_cache setObject: doc forKey: docID];  // re-add doc to NSCache since it's recently used
    return doc;
}


- (void) forgetResource: (id<TDCacheable>)resource {
    TDCache* cache = resource.owningCache;
    if (cache) {
        NSAssert(cache == self, @"Removing object from the wrong cache");
        resource.owningCache = nil;
        [_map removeObjectForKey: resource.cacheKey];
    }
}


- (void) resourceBeingDealloced:(id<TDCacheable>)resource {
    [_map removeObjectForKey: resource.cacheKey];
}


- (NSArray*) allCachedResources {
    return _map.allValues;
}


- (void) unretainResources {
    [_cache removeAllObjects];
}


- (void) forgetAllResources {
    [_map removeAllObjects];
    [_cache removeAllObjects];
}


@end
