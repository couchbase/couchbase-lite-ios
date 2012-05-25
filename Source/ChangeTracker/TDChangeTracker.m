//
//  TDChangeTracker.m
//  TouchDB
//
//  Created by Jens Alfke on 6/20/11.
//  Copyright 2011 Couchbase, Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.
//
// <http://wiki.apache.org/couchdb/HTTP_database_API#Changes>

#import "TDChangeTracker.h"
#import "TDConnectionChangeTracker.h"
#import "TDMisc.h"
#import "TDStatus.h"


#define kDefaultHeartbeat (5 * 60.0)


@interface TDChangeTracker ()
@property (readwrite, copy, nonatomic) id lastSequenceID;
@end


@implementation TDChangeTracker

@synthesize lastSequenceID=_lastSequenceID, databaseURL=_databaseURL, mode=_mode;
@synthesize limit=_limit, heartbeat=_heartbeat, error=_error;
@synthesize client=_client, filterName=_filterName, filterParameters=_filterParameters;
@synthesize requestHeaders = _requestHeaders;

- (id)initWithDatabaseURL: (NSURL*)databaseURL
                     mode: (TDChangeTrackerMode)mode
                conflicts: (BOOL)includeConflicts
             lastSequence: (id)lastSequenceID
                   client: (id<TDChangeTrackerClient>)client {
    NSParameterAssert(databaseURL);
    NSParameterAssert(client);
    Assert([self class] != [TDChangeTracker class]); // abstract!
    self = [super init];
    if (self) {
        _databaseURL = [databaseURL retain];
        _client = client;
        _mode = mode;
        _heartbeat = kDefaultHeartbeat;
        _includeConflicts = includeConflicts;
        self.lastSequenceID = lastSequenceID;
    }
    return self;
}

- (NSString*) databaseName {
    return _databaseURL.path.lastPathComponent;
}

- (NSString*) changesFeedPath {
    static NSString* const kModeNames[3] = {@"normal", @"longpoll", @"continuous"};
    NSMutableString* path;
    path = [NSMutableString stringWithFormat: @"_changes?feed=%@&heartbeat=%.0f",
                                              kModeNames[_mode], _heartbeat*1000.0];
    if (_includeConflicts)
        [path appendString: @"&style=all_docs"];
    if (_lastSequenceID)
        [path appendFormat: @"&since=%@", TDEscapeURLParam([_lastSequenceID description])];
    if (_limit > 0)
        [path appendFormat: @"&limit=%u", _limit];
    if (_filterName) {
        [path appendFormat: @"&filter=%@", TDEscapeURLParam(_filterName)];
        for (NSString* key in _filterParameters) {
            id value = [_filterParameters objectForKey: key];
            [path appendFormat: @"&%@=%@", TDEscapeURLParam(key), 
                                           TDEscapeURLParam([value description])];
        }
    }

    return path;
}

- (NSURL*) changesFeedURL {
    NSMutableString* urlStr = [[_databaseURL.absoluteString mutableCopy] autorelease];
    if (![urlStr hasSuffix: @"/"])
        [urlStr appendString: @"/"];
    [urlStr appendString: self.changesFeedPath];
    return [NSURL URLWithString: urlStr];
}

- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%p %@]", [self class], self, self.databaseName];
}

- (void) dealloc {
    [self stop];
    [_filterName release];
    [_filterParameters release];
    [_databaseURL release];
    [_lastSequenceID release];
    [_error release];
    [_requestHeaders release];
    [super dealloc];
}

- (void) setUpstreamError: (NSString*)message {
    Warn(@"%@: Server error: %@", self, message);
    self.error = [NSError errorWithDomain: @"TDChangeTracker" code: kTDStatusUpstreamError userInfo: nil];
}

- (BOOL) start {
    self.error = nil;
    return NO;
}

- (void) stop {
    [self stopped];
}

- (void) stopped {
    // Clear client ref so its -changeTrackerStopped: won't be called again during -dealloc
    id<TDChangeTrackerClient> client = _client;
    _client = nil;
    if ([client respondsToSelector: @selector(changeTrackerStopped:)])
        [client changeTrackerStopped: self];    // note: this method might release/dealloc me
}

- (BOOL) receivedChange: (NSDictionary*)change {
    if (![change isKindOfClass: [NSDictionary class]])
        return NO;
    id seq = [change objectForKey: @"seq"];
    if (!seq) {
        // If a continuous feed closes (e.g. if its database is deleted), the last line it sends
        // will indicate the last_seq. This is normal, just ignore it and return success:
        return [change objectForKey: @"last_seq"] != nil;
    }
    [_client changeTrackerReceivedChange: change];
    self.lastSequenceID = seq;
    return YES;
}

- (NSInteger) receivedPollResponse: (NSData*)body {
    if (!body)
        return -1;
    id changeObj = [TDJSON JSONObjectWithData: body options: 0 error: NULL];
    NSDictionary* changeDict = $castIf(NSDictionary, changeObj);
    NSArray* changes = $castIf(NSArray, [changeDict objectForKey: @"results"]);
    if (!changes)
        return -1;
    for (NSDictionary* change in changes) {
        if (![self receivedChange: change])
            return -1;
    }
    return changes.count;
}

@end
