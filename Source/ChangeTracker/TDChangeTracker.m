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
#import "TDSocketChangeTracker.h"
#import "TDMisc.h"
#import "TDStatus.h"


#define kDefaultHeartbeat (5 * 60.0)


@interface TDChangeTracker ()
@property (readwrite, copy, nonatomic) id lastSequenceID;
@end


@implementation TDChangeTracker

@synthesize lastSequenceID=_lastSequenceID, databaseURL=_databaseURL, mode=_mode;
@synthesize heartbeat=_heartbeat, error=_error;
@synthesize client=_client, filterName=_filterName, filterParameters=_filterParameters;

- (id)initWithDatabaseURL: (NSURL*)databaseURL
                     mode: (TDChangeTrackerMode)mode
                conflicts: (BOOL)includeConflicts
             lastSequence: (id)lastSequenceID
                   client: (id<TDChangeTrackerClient>)client {
    NSParameterAssert(databaseURL);
    NSParameterAssert(client);
    self = [super init];
    if (self) {
        if ([self class] == [TDChangeTracker class]) {
            [self release];
            // TDConnectionChangeTracker doesn't work in continuous due to some bug in CFNetwork.
            if (mode == kContinuous && [databaseURL.scheme.lowercaseString hasPrefix: @"http"])
                self = [TDSocketChangeTracker alloc];
            else
                self = [TDConnectionChangeTracker alloc];
            return [self initWithDatabaseURL: databaseURL
                                        mode: mode
                                   conflicts: includeConflicts
                                lastSequence: lastSequenceID
                                      client: client];
        }
    
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
    if ([_client respondsToSelector: @selector(changeTrackerStopped:)])
        [_client changeTrackerStopped: self];
    _client = nil;  // don't call client anymore even if -stopped is called again (i.e. on dealloc)
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

- (BOOL) receivedChunk: (NSData*)chunk {
    LogTo(ChangeTracker, @"CHUNK: %@ %@", self, [chunk my_UTF8ToString]);
    if (chunk.length > 1) {
        id change = [TDJSON JSONObjectWithData: chunk options: 0 error: NULL];
        if (![self receivedChange: change]) {
            Warn(@"Received unparseable change line from server: %@", [chunk my_UTF8ToString]);
            return NO;
        }
    }
    return YES;
}

- (BOOL) receivedPollResponse: (NSData*)body {
    if (!body)
        return NO;
    id changeObj = [TDJSON JSONObjectWithData: body options: 0 error: NULL];
    NSDictionary* changeDict = $castIf(NSDictionary, changeObj);
    NSArray* changes = $castIf(NSArray, [changeDict objectForKey: @"results"]);
    if (!changes)
        return NO;
    for (NSDictionary* change in changes) {
        if (![self receivedChange: change])
            return NO;
    }
    return YES;
}

@end
