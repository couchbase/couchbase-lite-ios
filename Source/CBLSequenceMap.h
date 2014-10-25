//
//  CBLSequenceMap.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/21/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import "CBL_Revision.h"


/** A data structure representing a type of array that allows object values to be added to the end, and removed in arbitrary order; it's used by the replicator to keep track of which revisions have been transferred and what sequences to checkpoint. */
@interface CBLSequenceMap : NSObject
{
    NSMutableIndexSet* _sequences;  // Sequence numbers currently in the map
    NSUInteger _lastSequence;       // last generated sequence
    NSMutableArray* _values;        // values of remaining sequences
    NSUInteger _firstValueSequence; // sequence # of first item in _values
}

- (instancetype) init;

/** Adds a value to the map, assigning it a sequence number and returning it.
    Sequence numbers start at 1 and increment from there. */
- (SequenceNumber) addValue: (id)value;

/** Removes a sequence and its associated value. */
- (void) removeSequence: (SequenceNumber)sequence;

@property (readonly) BOOL isEmpty;
@property (readonly) NSUInteger count;

/** Returns the maximum consecutively-removed sequence number.
    This is one less than the minimum remaining sequence number. */
- (SequenceNumber) checkpointedSequence;

/** Returns the value associated with the checkpointedSequence. */
- (id) checkpointedValue;

@end
