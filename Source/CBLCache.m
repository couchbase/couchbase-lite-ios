//
//  CBLCache.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/17/11.
//  Copyright (c) 2011-2015 Couchbase, Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLCache.h"


static const NSUInteger kDefaultRetainLimit = 50;


@implementation CBLCache
{
    @private
    NSMapTable* _map;           // Weak mapping, docID-->Document
    NSMutableArray* _recents;   // Retains recently-used documents (least recently used first)
    NSUInteger _retainLimit;    // Max number of docs to retain
}


- (instancetype) init {
    return [self initWithRetainLimit: kDefaultRetainLimit];
}


- (instancetype) initWithRetainLimit: (NSUInteger)retainLimit {
    self = [super init];
    if (self) {
        // Construct an NSMapTable with weak references to values, which automatically removes
        // key/value pairs when a value is dealloced.
        _map = [[NSMapTable alloc] initWithKeyOptions: NSMapTableStrongMemory
                                         valueOptions: NSMapTableWeakMemory
                                             capacity: 100];
        if (retainLimit > 0) {
            _retainLimit = retainLimit;
            _recents = [[NSMutableArray alloc] initWithCapacity: retainLimit];
        }
    }
    return self;
}


- (void) addResource: (id<CBLCacheable>)resource {
    NSString* key = resource.cacheKey;
    NSAssert(![_map objectForKey: key], @"Caching duplicate items for '%@': %p, now %p",
             key, [_map objectForKey: key], resource);
    [_map setObject: resource forKey: key];
    if (_recents) {
        if (_recents.count == _retainLimit)
            [_recents removeObjectAtIndex: 0];    // remove least recently used
        [_recents addObject: resource];
    }
}


- (id<CBLCacheable>) resourceWithCacheKey: (NSString*)docID {
    id<CBLCacheable> doc = [_map objectForKey: docID];
    if (doc && _recents.count > 1) {
        // Move doc to the front of the list since it's been accessed:
        // (Yes, this is O(n), but it's very fast: just a scan for pointer equality).
        NSUInteger index = [_recents indexOfObjectIdenticalTo: doc];
        if (index != NSNotFound && index != _recents.count - 1) {
            [_recents removeObjectAtIndex: index];
            [_recents addObject: doc];
        }
    }
    return doc;
}

- (id<CBLCacheable>) resourceWithCacheKeyDontRecache: (NSString*)docID {
    return [_map objectForKey: docID];
}


- (void) forgetResource: (id<CBLCacheable>)resource {
    [_map removeObjectForKey: resource.cacheKey];
}


- (void) unretainResources {
    [_recents removeAllObjects];
}


- (void) forgetAllResources {
    [_map removeAllObjects];
    [_recents removeAllObjects];
}


@end
