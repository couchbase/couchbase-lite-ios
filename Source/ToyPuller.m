//
//  ToyPuller.m
//  ToyCouch
//
//  Created by Jens Alfke on 12/2/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "ToyPuller.h"
#import "ToyDB.h"
#import "ToyRev.h"
#import "ToyDocument.h"

#import "CollectionUtils.h"
#import "Test.h"
#import <CouchCocoa/CouchChangeTracker.h>


@interface ToyPuller () <CouchChangeTrackerClient>
- (BOOL) pullRemoteRevisions: (ToyRevSet*)toyRevs;
@end


@implementation ToyPuller


- (void)dealloc {
    [_changeTracker stop];
    [_changeTracker release];
    [super dealloc];
}


- (void) start {
    if (_started)
        return;
    Assert(!_changeTracker);
    [super start];
    LogTo(Sync, @"*** STARTING PULLER to <%@> from #%@", _remote, _lastSequence);
    _changeTracker = [[CouchChangeTracker alloc]
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
    [super stop];
}


- (void) changeTrackerReceivedChange: (NSDictionary*)change {
    [self addToInbox: change];
}


- (void) processInbox: (NSArray*)inbox {
    id lastSequence = _lastSequence;
    ToyRevSet* revs = [[[ToyRevSet alloc] init] autorelease];
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
            ToyRev* rev = [[ToyRev alloc] initWithDocID: docID revID: revID deleted: deleted];
            [revs addRev: rev];
            [rev release];
        }
    }
    
    LogTo(Sync, @"ToyPuller: Looking up %@", revs);
    if (![_db findMissingRevisions: revs]) {
        Warn(@"ToyPuller failed to look up local revs");
        return;
    }
    
    if (revs.count > 0) {
        if (![self pullRemoteRevisions: revs])
            return;
        
        [_db beginTransaction];
        for (ToyRev* rev in revs) {
            int status = [_db forceInsert: rev];
            if (status >= 300) {
                _db.transactionFailed = YES;
                break;
            }
            LogTo(Sync, @"ToyPuller added doc %@", rev);
        }
        [_db endTransaction];
    }
    
    self.lastSequence = lastSequence;
}


- (BOOL) pullRemoteRevisions: (ToyRevSet*)toyRevs {
    //FIX: Make this async
    LogTo(Sync, @"ToyPuller getting remote docs %@", toyRevs);
    
    NSMutableSet* docIDs = [NSMutableSet setWithCapacity: toyRevs.count];
    for (ToyRev* rev in toyRevs) {
        if (!rev.deleted)
            [docIDs addObject: rev.docID];
    }
    if (docIDs.count == 0)
        return YES;
    
    NSDictionary* results = [self postRequest: @"/_all_docs?include_docs=true"
                                         body: $dict({@"keys", docIDs.allObjects})];
    if (!results)
        return NO;
    
    for (NSDictionary* row in [results objectForKey: @"rows"]) {
        ToyDocument* doc = [ToyDocument documentWithProperties: [row objectForKey: @"doc"]];
        ToyRev* rev = [toyRevs revWithDocID: doc.documentID revID: doc.revisionID];
        rev.document = doc;
    }
    return YES;
}


@end
