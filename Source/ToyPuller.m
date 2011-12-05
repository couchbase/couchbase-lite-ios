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


#define kProcessDelay 0.5


@interface ToyPuller () <CouchChangeTrackerClient>
- (BOOL) pullRemoteRevisions: (ToyRevSet*)toyRevs;
@end


@implementation ToyPuller


- (id) initWithDB: (ToyDB*)db remote: (NSURL*)remote {
    NSParameterAssert(db);
    NSParameterAssert(remote);
    self = [super init];
    if (self) {
        _db = [db retain];
        _remote = [remote retain];
    }
    return self;
}


- (void)dealloc {
    [_db release];
    [_changeTracker stop];
    [_changeTracker release];
    [_remote release];
    [_lastSequence release];
    [_inbox release];
    [super dealloc];
}


@synthesize remote=_remote, lastSequence=_lastSequence;


- (void) start {
    Assert(!_changeTracker);
    LogTo(Sync, @"*** STARTING PULLER to <%@> from #%@", _remote, _lastSequence);
    _changeTracker = [[CouchChangeTracker alloc] initWithDatabaseURL: _remote
                                                        lastSequence: [_lastSequence intValue]
                                                              client: self];
    [_changeTracker start];
}


- (void) stop {
    [_changeTracker stop];
    [_changeTracker release];
    [NSObject cancelPreviousPerformRequestsWithTarget: self];
}


- (NSURLCredential*) authCredential {
    return nil;
}

- (void) changeTrackerReceivedChange: (NSDictionary*)change {
    if (!_inbox) {
        _inbox = [[NSMutableArray alloc] init];
        [self performSelector: @selector(processInbox) withObject: nil afterDelay: kProcessDelay];
    }
    [_inbox addObject: change];
    LogTo(Sync, @"ToyPuller: Received #%@ (%@)",
          [change objectForKey: @"seq"], [change objectForKey: @"id"]);
}


- (void) processInbox {
    if (_inbox.count == 0)
        return;
    
    LogTo(Sync, @"*** BEGIN processInbox (%i sequences)", _inbox.count);
    NSArray* inbox = [_inbox autorelease];
    _inbox = nil;
    
    NSString* lastSequence = _lastSequence;
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
    LogTo(Sync, @"*** END processInbox (lastSequence=%@)", lastSequence);
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
    
    NSString* urlStr = [_remote.absoluteString stringByAppendingString: @"/_all_docs?include_docs=true"];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL: [NSURL URLWithString: urlStr]];
    request.HTTPMethod = @"POST";
    NSDictionary* what = $dict({@"keys", docIDs.allObjects});
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject: what options: 0 error: nil];
    [request addValue: @"application/json" forHTTPHeaderField: @"Content-Type"];
    
    NSHTTPURLResponse* response;
    NSError* error = nil;
    NSData* body = [NSURLConnection sendSynchronousRequest: request
                                         returningResponse: (NSURLResponse**)&response
                                                     error: &error];
    if (!body || error || response.statusCode >= 300) {
        Warn(@"ToyDB: Batch-fetch failed (status %i)", response.statusCode);
        return NO;
    }
    
    NSDictionary* results = $castIf(NSDictionary,
            [NSJSONSerialization JSONObjectWithData: body options:0 error:nil]);
    if (!results) {
        Warn(@"ToyDB: Batch-fetch returned unparseable data");
        return NO;
    }
    
    for (NSDictionary* row in [results objectForKey: @"rows"]) {
        ToyDocument* doc = [ToyDocument documentWithProperties: [row objectForKey: @"doc"]];
        ToyRev* rev = [toyRevs revWithDocID: doc.documentID revID: doc.revisionID];
        rev.document = doc;
    }
    return YES;
}


@end
