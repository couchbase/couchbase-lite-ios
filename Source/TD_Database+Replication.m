//
//  TD_Database+Replication.m
//  TouchDB
//
//  Created by Jens Alfke on 12/27/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TD_Database+Replication.h"
#import "TDInternal.h"
#import "TDPuller.h"
#import "MYBlockUtils.h"

#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"


#define kActiveReplicatorCleanupDelay 10.0


@implementation TD_Database (Replication)


- (NSArray*) activeReplicators {
    return _activeReplicators;
}

- (TDReplicator*) activeReplicatorWithRemoteURL: (NSURL*)remote
                                           push: (BOOL)push {
    TDReplicator* repl;
    for (repl in _activeReplicators) {
        if ($equal(repl.remote, remote) && repl.isPush == push && repl.running)
            return repl;
    }
    return nil;
}

- (TDReplicator*) replicatorWithRemoteURL: (NSURL*)remote
                                     push: (BOOL)push
                               continuous: (BOOL)continuous {
    TDReplicator* repl = [self activeReplicatorWithRemoteURL: remote push: push];
    if (repl)
        return repl;
    repl = [[TDReplicator alloc] initWithDB: self
                                     remote: remote 
                                       push: push
                                 continuous: continuous];
    if (!repl)
        return nil;
    if (!_activeReplicators) {
        _activeReplicators = [[NSMutableArray alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(replicatorDidStop:)
                                                     name: TDReplicatorStoppedNotification
                                                   object: nil];
    }
    [_activeReplicators addObject: repl];
    return repl;
}


- (void) stopAndForgetReplicator: (TDReplicator*)repl {
    [repl databaseClosing];
    [_activeReplicators removeObjectIdenticalTo: repl];
}


- (void) replicatorDidStop: (NSNotification*)n {
    TDReplicator* repl = n.object;
    if (repl.error)     // Leave it around a while so clients can see the error
        MYAfterDelay(kActiveReplicatorCleanupDelay,
                     ^{[_activeReplicators removeObjectIdenticalTo: repl];});
    else
        [_activeReplicators removeObjectIdenticalTo: repl];
}


- (NSString*) lastSequenceWithCheckpointID: (NSString*)checkpointID {
    // This table schema is out of date but I'm keeping it the way it is for compatibility.
    // The 'remote' column now stores the opaque checkpoint IDs, and 'push' is ignored.
    return [_fmdb stringForQuery:@"SELECT last_sequence FROM replicators WHERE remote=?",
                                 checkpointID];
}

- (BOOL) setLastSequence: (NSString*)lastSequence withCheckpointID: (NSString*)checkpointID {
    return [_fmdb executeUpdate: 
            @"INSERT OR REPLACE INTO replicators (remote, push, last_sequence) VALUES (?, -1, ?)",
            checkpointID, lastSequence];
}


+ (NSString*) joinQuotedStrings: (NSArray*)strings {
    if (strings.count == 0)
        return @"";
    NSMutableString* result = [NSMutableString stringWithString: @"'"];
    BOOL first = YES;
    for (NSString* str in strings) {
        if (first)
            first = NO;
        else
            [result appendString: @"','"];
        NSRange range = NSMakeRange(result.length, str.length);
        [result appendString: str];
        [result replaceOccurrencesOfString: @"'" withString: @"''"
                                   options: NSLiteralSearch range: range];
    }
    [result appendString: @"'"];
    return result;
}


- (BOOL) findMissingRevisions: (TD_RevisionList*)revs {
    if (revs.count == 0)
        return YES;
    NSString* sql = $sprintf(@"SELECT docid, revid FROM revs, docs "
                              "WHERE revid in (%@) AND docid IN (%@) "
                              "AND revs.doc_id == docs.doc_id",
                             [TD_Database joinQuotedStrings: revs.allRevIDs],
                             [TD_Database joinQuotedStrings: revs.allDocIDs]);
    // ?? Not sure sqlite will optimize this fully. May need a first query that looks up all
    // the numeric doc_ids from the docids.
    FMResultSet* r = [_fmdb executeQuery: sql];
    if (!r)
        return NO;
    while ([r next]) {
        @autoreleasepool {
            TD_Revision* rev = [revs revWithDocID: [r stringForColumnIndex: 0]
                                           revID: [r stringForColumnIndex: 1]];
            if (rev)
                [revs removeRev: rev];
        }
    }
    [r close];
    return YES;
}


@end
