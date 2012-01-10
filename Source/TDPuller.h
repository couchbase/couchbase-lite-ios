//
//  TDPuller.h
//  TouchDB
//
//  Created by Jens Alfke on 12/2/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TDReplicator.h"
#import "TDRevision.h"
@class TDChangeTracker;


/** Replicator that pulls from a remote CouchDB. */
@interface TDPuller : TDReplicator
{
    @private
    TDChangeTracker* _changeTracker;
    unsigned _nextFakeSequence;
    unsigned _maxInsertedFakeSequence;
    NSMutableArray* _revsToPull;
    NSUInteger _httpConnectionCount;
    TDBatcher* _revsToInsert;
    NSString* _filterName;
    NSDictionary* _filterParameters;
}

@property (copy) NSString* filterName;
@property (copy) NSDictionary* filterParameters;

@end



/** A revision received from a remote server during a pull. Tracks the opaque remote sequence ID. */
@interface TDPulledRevision : TDRevision
{
@private
    NSString* _remoteSequenceID;
}

@property (copy) NSString* remoteSequenceID;

@end
