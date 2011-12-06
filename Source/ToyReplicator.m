//
//  ToyReplicator.m
//  ToyCouch
//
//  Created by Jens Alfke on 12/6/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "ToyReplicator.h"
#import "ToyDB.h"

#import "CollectionUtils.h"
#import "Test.h"


#define kProcessDelay 0.5


@implementation ToyReplicator

- (id) initWithDB: (ToyDB*)db remote: (NSURL*)remote continuous: (BOOL)continuous {
    NSParameterAssert(db);
    NSParameterAssert(remote);
    self = [super init];
    if (self) {
        _db = [db retain];
        _remote = [remote retain];
        _continuous = continuous;
    }
    return self;
}

- (void)dealloc {
    [self stop];
    [_db release];
    [_remote release];
    [_lastSequence release];
    [_inbox release];
    [super dealloc];
}

@synthesize db=_db, remote=_remote, lastSequence=_lastSequence;

- (void) start {
    _started = YES;
}

- (void) stop {
    if (_inbox) {
        [_inbox release];
        _inbox = nil;
        [NSObject cancelPreviousPerformRequestsWithTarget: self
                                                 selector: @selector(doProcessInbox) object: nil];
    }
    _started = NO;
}

- (void) addToInbox: (NSDictionary*)change {
    if (!_inbox) {
        _inbox = [[NSMutableArray alloc] init];
        [self performSelector: @selector(doProcessInbox) withObject: nil afterDelay: kProcessDelay];
    }
    [_inbox addObject: change];
    LogTo(Sync, @"%@: Received #%@ (%@)",
          self, [change objectForKey: @"seq"], [change objectForKey: @"id"]);
}

- (void) processInbox: (NSArray*)inbox {
}

- (void) doProcessInbox {
    if (_inbox.count == 0)
        return;
    
    LogTo(Sync, @"*** %@: BEGIN processInbox (%i sequences)", self, _inbox.count);
    NSArray* inbox = [_inbox autorelease];
    _inbox = nil;
    [self processInbox: inbox];
    LogTo(Sync, @"*** %@: END processInbox (lastSequence=%@)", self, _lastSequence);
}

- (id) postRequest: (NSString*)relativePath body: (id)body
{
    NSString* urlStr = [_remote.absoluteString stringByAppendingString: relativePath];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL: [NSURL URLWithString: urlStr]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject: body options: 0 error: nil];
    [request addValue: @"application/json" forHTTPHeaderField: @"Content-Type"];
    
    NSHTTPURLResponse* response;
    NSError* error = nil;
    NSData* data = [NSURLConnection sendSynchronousRequest: request
                                         returningResponse: (NSURLResponse**)&response
                                                     error: &error];
    if (!data || error || response.statusCode >= 300) {
        Warn(@"%@: POST to %@ failed (status %i)", self, relativePath, response.statusCode);
        return nil;
    }
    
    NSDictionary* results = $castIf(NSDictionary,
                                    [NSJSONSerialization JSONObjectWithData: data options:0 error:nil]);
    if (!results)
        Warn(@"%@: POST to %@ returned unparseable data '%@'",
             self, relativePath, [data my_UTF8ToString]);
    return results;
}

@end
