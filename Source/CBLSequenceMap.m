//
//  CBLSequenceMap.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/21/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLSequenceMap.h"


@implementation CBLSequenceMap


- (instancetype) init
{
    self = [super init];
    if (self) {
        _sequences = [[NSMutableIndexSet alloc] init];
        _values = [[NSMutableArray alloc] initWithCapacity: 100];
        _firstValueSequence = 1;
    }
    return self;
}




- (SequenceNumber) addValue: (id)value {
    [_sequences addIndex: ++_lastSequence];
    [_values addObject: value];
    return _lastSequence;
}


- (void) removeSequence: (SequenceNumber)sequence {
    Assert(sequence > 0 && sequence <= (SequenceNumber)_lastSequence,
           @"Invalid sequence %lld (latest is %u)", sequence, _lastSequence);
    [_sequences removeIndex: (NSUInteger) sequence];
}


- (BOOL) isEmpty {
    return _sequences.firstIndex == NSNotFound;
}


- (SequenceNumber) checkpointedSequence {
    NSUInteger sequence = _sequences.firstIndex;
    sequence = (sequence == NSNotFound) ? _lastSequence : sequence-1;
    
    if (sequence > _firstValueSequence) {
        // Garbage-collect inaccessible values:
        NSUInteger numToRemove = sequence - _firstValueSequence;
        [_values removeObjectsInRange: NSMakeRange(0, numToRemove)];
        _firstValueSequence += numToRemove;
    }
    return sequence;
}


- (id) checkpointedValue {
    NSInteger index = (NSInteger)([self checkpointedSequence] - _firstValueSequence);
    return (index >= 0) ? _values[index] : nil;
}


@end



TestCase(CBLSequenceMap) {
    CBLSequenceMap* map = [[CBLSequenceMap alloc] init];
    CAssertEq(map.checkpointedSequence, 0);
    CAssertEqual(map.checkpointedValue, nil);
    CAssert(map.isEmpty);
    
    CAssertEq([map addValue: @"one"], 1);
    CAssertEq(map.checkpointedSequence, 0);
    CAssertEqual(map.checkpointedValue, nil);
    CAssert(!map.isEmpty);
    
    CAssertEq([map addValue: @"two"], 2);
    CAssertEq(map.checkpointedSequence, 0);
    CAssertEqual(map.checkpointedValue, nil);
    
    CAssertEq([map addValue: @"three"], 3);
    CAssertEq(map.checkpointedSequence, 0);
    CAssertEqual(map.checkpointedValue, nil);
    
    [map removeSequence: 2];
    CAssertEq(map.checkpointedSequence, 0);
    CAssertEqual(map.checkpointedValue, nil);
    
    [map removeSequence: 1];
    CAssertEq(map.checkpointedSequence, 2);
    CAssertEqual(map.checkpointedValue, @"two");
    
    CAssertEq([map addValue: @"four"], 4);
    CAssertEq(map.checkpointedSequence, 2);
    CAssertEqual(map.checkpointedValue, @"two");
    
    [map removeSequence: 3];
    CAssertEq(map.checkpointedSequence, 3);
    CAssertEqual(map.checkpointedValue, @"three");
    
    [map removeSequence: 4];
    CAssertEq(map.checkpointedSequence, 4);
    CAssertEqual(map.checkpointedValue, @"four");
    CAssert(map.isEmpty);
}
