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
#import "TDBatcher.h"
#import "TDInternal.h"


// Maximum number of revisions to fetch simultaneously
#define kMaxOpenHTTPConnections 8


@interface TDPuller () <TDChangeTrackerClient>
- (void) pullRemoteRevisions;
- (void) pullRemoteRevision: (TDRevision*)rev;
- (void) insertRevisions: (NSArray*)revs;
@end


@implementation TDPuller


- (void)dealloc {
    [_changeTracker stop];
    [_changeTracker release];
    [_revsToPull release];
    [_revsToInsert release];
    [super dealloc];
}


- (void) start {
    if (_running)
        return;
    Assert(!_changeTracker);
    [super start];
    LogTo(Sync, @"*** STARTING PULLER to <%@> from #%@", _remote, _lastSequence);
    
    if (!_revsToInsert) {
        _revsToInsert = [[TDBatcher alloc] initWithCapacity: 100 delay: 0.25
                                                  processor: ^(NSArray *revs) {
                                                      [self insertRevisions: revs];
                                                  }];
    }
    
    _thread = [NSThread currentThread];
    _changeTracker = [[TDChangeTracker alloc]
                                   initWithDatabaseURL: _remote
                                                  mode: (_continuous ? kLongPoll :kOneShot)
                                          lastSequence: [_lastSequence intValue]
                                                client: self];
    [_changeTracker start];
    [self asyncTaskStarted];
}


- (void) stop {
    _changeTracker.client = nil;  // stop it from calling my -changeTrackerStopped
    [_changeTracker stop];
    [_changeTracker release];
    _changeTracker = nil;
    [_revsToPull release];
    _revsToPull = nil;
    [super stop];

    if (_asyncTaskCount == 0)
        [self stopped];
}


// Got a _changes feed entry from the TDChangeTracker.
- (void) changeTrackerReceivedChange: (NSDictionary*)change {
    SequenceNumber lastSequence = [[change objectForKey: @"seq"] longLongValue];
    NSString* docID = [change objectForKey: @"id"];
    if (!docID)
        return;
    BOOL deleted = [[change objectForKey: @"deleted"] isEqual: (id)kCFBooleanTrue];
    NSArray* changes = $castIf(NSArray, [change objectForKey: @"changes"]);
    for (NSDictionary* changeDict in changes) {
        @autoreleasepool {
            NSString* revID = $castIf(NSString, [changeDict objectForKey: @"rev"]);
            if (!revID)
                continue;
            TDRevision* rev = [[TDRevision alloc] initWithDocID: docID revID: revID deleted: deleted];
            rev.sequence = lastSequence;
            // Push each revision info to the inbox
            [self addToInbox: rev];
            [rev release];
        }
    }
    self.changesTotal += changes.count;
}


- (void) changeTrackerStopped:(TDChangeTracker *)tracker {
    LogTo(Sync, @"%@: ChangeTracker stopped", self);
    [_changeTracker release];
    _changeTracker = nil;
    
    [_batcher flush];
    [self asyncTasksFinished: 1];
}


// Process a bunch of remote revisions from the _changes feed at once
- (void) processInbox: (TDRevisionList*)inbox {
    // Ask the local database which of the revs are not known to it:
    LogTo(SyncVerbose, @"TDPuller: Looking up %@", inbox);
    NSUInteger total = _changesTotal - inbox.count;
    if (![_db findMissingRevisions: inbox]) {
        Warn(@"TDPuller failed to look up local revs");
        inbox = nil;
    }
    if (_changesTotal != total + inbox.count)
        self.changesTotal = total + inbox.count;
    
    if (inbox.count == 0)
        return;
    LogTo(Sync, @"%@ fetching %u remote revisions...", self, inbox.count);
    
    // Dump the revs into the queue of revs to pull from the remote db:
    if (!_revsToPull)
        _revsToPull = [[NSMutableArray alloc] initWithCapacity: 100];
    [_revsToPull addObjectsFromArray: inbox.allRevisions];
    
    [self pullRemoteRevisions];
}


// Start up some HTTP GETs, within our limit on the maximum simultaneous number
- (void) pullRemoteRevisions {
    while (_httpConnectionCount < kMaxOpenHTTPConnections && _revsToPull.count > 0) {
        [self pullRemoteRevision: [_revsToPull objectAtIndex: 0]];
        [_revsToPull removeObjectAtIndex: 0];
    }
}


// Fetches the contents of a revision from the remote db, including its parent revision ID.
// The contents are stored into rev.properties.
- (void) pullRemoteRevision: (TDRevision*)rev
{
    [self asyncTaskStarted];
    ++_httpConnectionCount;
    NSString* path = $sprintf(@"/%@?rev=%@&revs=true", rev.docID, rev.revID);
    [self sendAsyncRequest: @"GET" path: path body: nil
          onCompletion: ^(NSDictionary *properties, NSError *error) {
              if (properties) {
                  NSArray* history = nil;
                  NSDictionary* revisions = $castIf(NSDictionary,
                                                    [properties objectForKey: @"_revisions"]);
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

                  // Add to batcher ... eventually it will be fed to -insertRevisions:.
                  [_revsToInsert queueObject: $array(rev, history)];
                  [self asyncTaskStarted];
              } else {
                  self.changesProcessed++;
              }
              
              // Note that we've finished this task; then start another one if there
              // are still revisions waiting to be pulled:
              [self asyncTasksFinished: 1];
              --_httpConnectionCount;
              [self pullRemoteRevisions];
          }
     ];
}


// This will be called when _revsToInsert fills up:
- (void) insertRevisions:(NSArray *)revs {
    LogTo(Sync, @"%@ inserting %u revisions...", self, revs.count);
    SequenceNumber maxSequence = self.lastSequence.longLongValue;
    [_db beginTransaction];
    
    for (NSArray* revAndHistory in revs) {
        @autoreleasepool {
            TDRevision* rev = [revAndHistory objectAtIndex: 0];
            NSArray* history = [revAndHistory objectAtIndex: 1];
            // Insert the revision:
            maxSequence = MAX(maxSequence, rev.sequence);
            int status = [_db forceInsert: rev revisionHistory: history source: _remote];
            if (status >= 300) {
                if (status == 403)
                    LogTo(Sync, @"%@: Remote rev failed validation: %@", self, rev);
                else
                    Warn(@"%@ failed to write %@: status=%d", self, rev, status);
            }
        }
    }
    
    // Remember we've received this sequence:
    if (maxSequence > self.lastSequence.longLongValue)
        self.lastSequence = $sprintf(@"%lld", maxSequence);
    
    [_db endTransaction];
    LogTo(Sync, @"%@ finished inserting %u revisions", self, revs.count);
    
    [self asyncTasksFinished: revs.count];
    self.changesProcessed += revs.count;
}


@end
