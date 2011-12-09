//
//  TDPuller.m
//  TouchDB
//
//  Created by Jens Alfke on 12/2/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TDPuller.h"
#import "TDDatabase.h"
#import "TDRevision.h"
#import "TDChangeTracker.h"



@interface TDPuller () <TDChangeTrackerClient>
- (BOOL) pullRemoteRevision: (TDRevision*)rev
                    history: (NSArray**)outHistory;
@end


@implementation TDPuller


- (void)dealloc {
    [_changeTracker stop];
    [_changeTracker release];
    [super dealloc];
}


- (void) start {
    if (_running)
        return;
    Assert(!_changeTracker);
    [super start];
    LogTo(Sync, @"*** STARTING PULLER to <%@> from #%@", _remote, _lastSequence);
    _changeTracker = [[TDChangeTracker alloc]
                                   initWithDatabaseURL: _remote
                                                  mode: (_continuous ? kLongPoll :kOneShot)
                                          lastSequence: [_lastSequence intValue]
                                                client: self];
    [_changeTracker start];
    // TODO: In non-continuous mode, only get the existing changes; don't listen for new ones
}


- (void) stop {
    [_changeTracker stop];
    [_changeTracker release];
    _changeTracker = nil;
    [super stop];
}


- (void) changeTrackerReceivedChange: (NSDictionary*)change {
    [self addToInbox: change];
}


- (void) changeTrackerStopped:(TDChangeTracker *)tracker {
    LogTo(Sync, @"%@: ChangeTracker stopped", self);
    [_changeTracker release];
    _changeTracker = nil;
    
    [self flushInbox];
    [self stop];
}


- (void) processInbox: (NSArray*)inbox {
    // Parse the _changes-feed entries into a list of TDRevs:
    id lastSequence = _lastSequence;
    TDRevisionList* revs = [[[TDRevisionList alloc] init] autorelease];
    for (NSDictionary* change in inbox) {
        lastSequence = [change objectForKey: @"seq"];
        NSString* docID = [change objectForKey: @"id"];
        if (!docID)
            continue;
        BOOL deleted = [[change objectForKey: @"deleted"] isEqual: (id)kCFBooleanTrue];
        for (NSDictionary* changeDict in $castIf(NSArray, [change objectForKey: @"changes"])) {
            NSString* revID = $castIf(NSString, [changeDict objectForKey: @"rev"]);
            if (!revID)
                continue;
            TDRevision* rev = [[TDRevision alloc] initWithDocID: docID revID: revID deleted: deleted];
            [revs addRev: rev];
            [rev release];
        }
    }
    
    // Ask the local database which of the revs are not known to it:
    LogTo(Sync, @"TDPuller: Looking up %@", revs);
    if (![_db findMissingRevisions: revs]) {
        Warn(@"TDPuller failed to look up local revs");
        return;
    }
    
    // Fetch and add each of the new revs:
    for (TDRevision* rev in revs) {
        NSArray* history;
        if (![self pullRemoteRevision: rev history: &history]) {
            Warn(@"%@ failed to download %@", self, rev);
            continue;
        }
        int status = [_db forceInsert: rev revisionHistory: history];
        if (status >= 300) {
            Warn(@"%@ failed to write %@: status=%d", self, rev, status);
            continue;
        }
        LogTo(Sync, @"%@ added %@", self, rev);
    }
    
    self.lastSequence = lastSequence;
}


// Fetches the contents of a revision from the remote db, including its parent revision ID.
// The contents are stored into rev.properties.
- (BOOL) pullRemoteRevision: (TDRevision*)rev
                    history: (NSArray**)outHistory
{
    NSString* path = $sprintf(@"/%@?rev=%@&revs=true", rev.docID, rev.revID);
    NSDictionary* properties = [self sendRequest: @"GET" path: path body: nil];
    if (!properties)
        return NO;  // GET failed
    
    NSArray* history = nil;
    NSDictionary* revisions = $castIf(NSDictionary, [properties objectForKey: @"_revisions"]);
    if (revisions) {
        // Extract the history, expanding the numeric prefixes:
        __block int start = [[revisions objectForKey: @"start"] intValue];
        NSArray* revIDs = $castIf(NSArray, [revisions objectForKey: @"ids"]);
        history = [revIDs my_map: ^(id revID) {
            return (start ? $sprintf(@"%d-%@", start--, revID) : revID);
        }];

        // Now remove the _revisions dict so it doesn't get stored in the local db:
        NSMutableDictionary* editedProperties = [[properties mutableCopy] autorelease];
        [editedProperties removeObjectForKey: @"_revisions"];
        properties = editedProperties;
    }
    rev.properties = properties;
    *outHistory = history;
    return YES;
}


@end
