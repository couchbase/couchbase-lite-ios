//
//  CBLQueryEnumerator.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/11/15.
//  Copyright (c) 2012-2015 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLQuery.h"
#import "CBLInternal.h"
#import "CBLView+Internal.h"
#import "CBL_StorageTypes.h"


#define kEnumerationBufferSize 16


@implementation CBLQueryEnumerator
{
    CBLDatabase* _database;
    CBLView* _view; // nil if this is an all-docs query
    NSArray* _rows;
    NSUInteger _nextRow;
    UInt64 _sequenceNumber;
    CBLQueryIteratorBlock _iterator;
    BOOL _usingIterator;
    id __unsafe_unretained _enumerationBuffer[kEnumerationBufferSize];
}


@synthesize sequenceNumber=_sequenceNumber;


- (instancetype) initWithDatabase: (CBLDatabase*)database
                             view: (CBLView*)view
                   sequenceNumber: (SequenceNumber)sequenceNumber
                         iterator: (CBLQueryIteratorBlock)iterator
{
    NSParameterAssert(database);
    self = [super init];
    if (self ) {
        _database = database;
        _view = view;
        _sequenceNumber = sequenceNumber;
        _iterator = iterator;
    }
    return self;
}

- (instancetype) initWithDatabase: (CBLDatabase*)database
                             view: (CBLView*)view
                   sequenceNumber: (SequenceNumber)sequenceNumber
                             rows: (NSArray*)rows
{
    NSParameterAssert(database);
    self = [super init];
    if (self ) {
        _database = database;
        _view = view;
        _sequenceNumber = sequenceNumber;
        _rows = rows;
    }
    return self;
}

- (id) copyWithZone: (NSZone*)zone {
    return [[[self class] alloc] initWithDatabase: _database
                                             view: _view
                                   sequenceNumber: _sequenceNumber
                                             rows: self.allObjects];
}

- (void) dealloc {
    [self clearEnumBuffer];
}


- (BOOL) isEqual:(id)object {
    if (object == self)
        return YES;
    if (![object isKindOfClass: [CBLQueryEnumerator class]])
        return NO;
    return [[object allObjects] isEqual: self.allObjects];
}


- (BOOL) stale {
    // Check whether the result-set's sequence number is up to date with either the db or the view:
    SequenceNumber dbSequence = _database.lastSequenceNumber;
    if ((SequenceNumber)_sequenceNumber == dbSequence)
        return NO;
    if (_view && _view.lastSequenceIndexed == dbSequence
        && _view.lastSequenceChangedAt == (SequenceNumber)_sequenceNumber)
        return NO;
    return YES;
}


- (void) sortUsingDescriptors: (NSArray*)sortDescriptors {
    // First make the key-paths relative to each row's value unless they start from a root key:
    sortDescriptors = [sortDescriptors my_map: ^id(id descOrString) {
        NSSortDescriptor* desc = [[self class] asNSSortDescriptor: descOrString];
        NSString* keyPath = desc.key;
        NSString* newKeyPath = CBLKeyPathForQueryRow(keyPath);
        Assert(newKeyPath, @"Invalid CBLQueryRow key path \"%@\"", keyPath);
        if (newKeyPath == keyPath)
            return desc;
        else if (desc.comparator)
            return [[NSSortDescriptor alloc] initWithKey: newKeyPath
                                               ascending: desc.ascending
                                              comparator: desc.comparator];
        else
            return [[NSSortDescriptor alloc] initWithKey: newKeyPath
                                               ascending: desc.ascending
                                                selector: desc.selector];
    }];

    // Now the sorting is trivial:
    _rows = [self.allObjects sortedArrayUsingDescriptors: sortDescriptors];
}

- (void) sortUsingDescriptors: (NSArray*)sortDescriptors
                         skip: (NSUInteger)skip
                        limit: (NSUInteger)limit
{
    [self sortUsingDescriptors: sortDescriptors];
    NSUInteger n = _rows.count;
    if (skip >= n) {
        _rows = @[];
    } else if (skip > 0 || limit < n) {
        limit = MIN(limit, n - skip);
        _rows = [_rows subarrayWithRange: NSMakeRange(skip, limit)];
    }
}


- (CBLQueryRow*) nextRow {
    if (_rows) {
        // Using array:
        if (_nextRow >= _rows.count)
            return nil;
        return [self rowAtIndex:_nextRow++];

    } else {
        // Using iterator:
        _usingIterator = YES;
        if (!_iterator)
            return nil;
        CBLQueryRow* row = _iterator();
        if (row)
            row.database = _database;
        else
            _iterator = nil;
        return row;
    }
}


- (id) nextObject {
    return [self nextRow];
}


- (NSArray*) allObjects {
    if (!_rows) {
        Assert(!_usingIterator, @"Enumerator is not at start");
        _rows = [super allObjects];
        _usingIterator = NO;
    }
    return _rows;
}


- (NSUInteger) count {
    return self.allObjects.count;
}


- (CBLQueryRow*) rowAtIndex: (NSUInteger)index {
    return self.allObjects[index];
}


- (void) reset {
    Assert(!_usingIterator, @"Sorry, the enumerator did not save up its rows so it cannot be "
           "reset. Call -allObjects first thing to make the enumerator resettable.");
    _nextRow = 0;
}


// fast-enumeration support
- (NSUInteger) countByEnumeratingWithState: (NSFastEnumerationState*)state
                                   objects: (id __unsafe_unretained[])stackbuf
                                     count: (NSUInteger)stackbufLength
{
    if (state->state == 0) {
        state->state = 1;
        state->mutationsPtr = &state->extra[0]; // boilerplate for when we don't track mutations
        _nextRow = 0; // restart in case we're iterating over _rows
    }
    [self clearEnumBuffer];
    NSUInteger i;
    for (i = 0; i < stackbufLength; i++) {
        CBLQueryRow* row = [self nextRow];
        _enumerationBuffer[i] = row;
        if (!row)
            break;
        CFRetain((__bridge CFTypeRef)row);  // balanced by CFRelease in -clearEnumBuffer
    }
    state->itemsPtr = _enumerationBuffer;
    return i;
}

- (void) clearEnumBuffer {
    for (NSUInteger i = 0; i < kEnumerationBufferSize && _enumerationBuffer[i]; i++) {
        CFRelease((__bridge CFTypeRef)_enumerationBuffer[i]);
        _enumerationBuffer[i] = NULL;
    }
}


+ (NSSortDescriptor*) asNSSortDescriptor: (id)desc {
    if ([desc isKindOfClass: [NSString class]]) {
        BOOL ascending = ![desc hasPrefix: @"-"];
        if (!ascending)
            desc = [desc substringFromIndex: 1];
        desc = [NSSortDescriptor sortDescriptorWithKey: desc ascending: ascending];
    }
    return desc;
}


@end
