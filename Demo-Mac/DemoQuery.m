//
//  DemoQuery.m
//  CouchCocoa
//
//  Created by Jens Alfke on 6/1/11.
//  Copyright (c) 2011 Couchbase, Inc, Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "DemoQuery.h"
#import <CouchCocoa/CouchCocoa.h>


@interface DemoQuery ()
- (void) loadEntriesFrom: (CouchQueryEnumerator*)rows;
@end


@implementation DemoQuery


- (id) initWithQuery: (CouchQuery*)query
{
    NSParameterAssert(query);
    self = [super init];
    if (self != nil) {
        _modelClass = [CouchModel class];
        _query = [[query asLiveQuery] retain];

        _query.prefetch = YES;        // for efficiency, include docs on first load
        [_query start];

        // Observe changes to _query.rows:
        [_query addObserver: self forKeyPath: @"rows" options: 0 context: NULL];
    }
    return self;
}


- (void) dealloc
{
    [_entries release];
    [_query removeObserver: self forKeyPath: @"rows"];
    [_query release];
    [super dealloc];
}


@synthesize modelClass=_modelClass;


- (void) loadEntriesFrom: (CouchQueryEnumerator*)rows {
    NSLog(@"Reloading %lu rows from sequence #%lu...",
          (unsigned long)rows.count, (unsigned long)rows.sequenceNumber);
    NSMutableArray* entries = [NSMutableArray array];

    for (CouchQueryRow* row in rows) {
        CouchModel* item = [_modelClass modelForDocument: row.document];
        item.autosaves = YES;
        [entries addObject: item];
        // If this item isn't in the prior _entries, it's an external insertion:
        if (_entries && [_entries indexOfObjectIdenticalTo: item] == NSNotFound)
            [item markExternallyChanged];
    }

    for (CouchModel* item in _entries) {
        if ([item isNew])
            [entries addObject: item];
    }
    
    if (![entries isEqual:_entries]) {
        NSLog(@"    ...entries changed! (was %u, now %u)", 
              (unsigned)_entries.count, (unsigned)entries.count);
        [self willChangeValueForKey: @"entries"];
        [_entries release];
        _entries = [entries mutableCopy];
        [self didChangeValueForKey: @"entries"];
    }
}


- (void)observeValueForKeyPath: (NSString*)keyPath ofObject: (id)object
                        change: (NSDictionary*)change context: (void*)context 
{
    if (object == _query) {
        [self loadEntriesFrom: _query.rows];
    }
}


#pragma mark -
#pragma mark ENTRIES PROPERTY:


- (NSUInteger) countOfEntries {
    return _entries.count;
}


- (CouchModel*)objectInEntriesAtIndex: (NSUInteger)index {
    return [_entries objectAtIndex: index];
}


- (void) insertObject: (CouchModel*)object inEntriesAtIndex: (NSUInteger)index {
    [_entries insertObject: object atIndex: index];
    object.autosaves = YES;
    object.database = _query.database;
}


- (void) removeObjectFromEntriesAtIndex: (NSUInteger)index {
    CouchModel* item = [_entries objectAtIndex: index];
    item.database = nil;
    [_entries removeObjectAtIndex: index];
}


@end
