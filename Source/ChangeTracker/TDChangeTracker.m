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


@implementation TDChangeTracker

@synthesize lastSequenceNumber=_lastSequenceNumber, databaseURL=_databaseURL, mode=_mode;
@synthesize error=_error, client=_client, filterName=_filterName;

- (id)initWithDatabaseURL: (NSURL*)databaseURL
                     mode: (TDChangeTrackerMode)mode
             lastSequence: (NSUInteger)lastSequence
                   client: (id<TDChangeTrackerClient>)client {
    NSParameterAssert(databaseURL);
    NSParameterAssert(client);
    self = [super init];
    if (self) {
        if ([self class] == [TDChangeTracker class]) {
            [self release];
            // TDConnectionChangeTracker doesn't work in continuous due to some bug in CFNetwork.
            if (mode == kContinuous && [databaseURL.scheme.lowercaseString hasPrefix: @"http"]) {
                return (id) [[TDSocketChangeTracker alloc] initWithDatabaseURL: databaseURL
                                                                          mode: mode
                                                                  lastSequence: lastSequence
                                                                        client: client];
            } else {
                return (id) [[TDConnectionChangeTracker alloc] initWithDatabaseURL: databaseURL
                                                                              mode: mode
                                                                      lastSequence: lastSequence
                                                                            client: client];
            }
        }
    
        _databaseURL = [databaseURL retain];
        _client = client;
        _mode = mode;
        _lastSequenceNumber = lastSequence;
    }
    return self;
}

- (NSString*) databaseName {
    return _databaseURL.lastPathComponent;
}

- (NSString*) changesFeedPath {
    static NSString* const kModeNames[3] = {@"normal", @"longpoll", @"continuous"};
    NSMutableString* path;
    path = [NSMutableString stringWithFormat: @"_changes?feed=%@&heartbeat=300000&since=%u",
                                    kModeNames[_mode],
                                    _lastSequenceNumber];
    if (_filterName)
        [path appendFormat: @"&filter=%@", _filterName];
    return path;
}

- (NSURL*) changesFeedURL {
    return [NSURL URLWithString: [NSString stringWithFormat: @"%@/%@",
                                  _databaseURL.absoluteString, self.changesFeedPath]];
}

- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%@]", [self class], self.databaseName];
}

- (void)dealloc {
    [self stop];
    [_databaseURL release];
    [_error release];
    [super dealloc];
}

- (NSURLCredential*) authCredential {
    if ([_client respondsToSelector: @selector(authCredential)])
        return _client.authCredential;
    else
        return nil;
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
    if (!seq)
        return NO;
    [_client changeTrackerReceivedChange: change];
    _lastSequenceNumber = [seq intValue];
    return YES;
}

- (void) receivedChunk: (NSData*)chunk {
    if (chunk.length <= 1)
        return;
    id change = [NSJSONSerialization JSONObjectWithData: chunk options: 0 error: nil];
    if (![self receivedChange: change])
        Warn(@"Received unparseable change line from server: %@", [chunk my_UTF8ToString]);
}

- (BOOL) receivedPollResponse: (NSData*)body {
    if (!body)
        return NO;
    id changeObj = [NSJSONSerialization JSONObjectWithData: body options: 0 error: nil];
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
