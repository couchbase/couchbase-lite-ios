//
//  CBLChangeTracker.m
//  CouchbaseLite
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

#import "CBLChangeTracker.h"
#import "CBLSocketChangeTracker.h"
#import "CBLLocalChangeTracker.h"
#import "CBLAuthorizer.h"
#import "CBLMisc.h"
#import "CBLStatus.h"

#import <objc/message.h>

#define kDefaultHeartbeat (5 * 60.0)

#define kInitialRetryDelay 2.0      // Initial retry delay (doubles after every subsequent failure)
#define kMaxRetryDelay 300.0        // ...but will never get longer than this


@interface CBLChangeTracker ()
@property (readwrite, copy, nonatomic) id lastSequenceID;
@end


@implementation CBLChangeTracker

@synthesize lastSequenceID=_lastSequenceID, databaseURL=_databaseURL, mode=_mode;
@synthesize limit=_limit, heartbeat=_heartbeat, error=_error;
@synthesize client=_client, filterName=_filterName, filterParameters=_filterParameters;
@synthesize requestHeaders = _requestHeaders, authorizer=_authorizer;
@synthesize docIDs = _docIDs;

- (instancetype) initWithDatabaseURL: (NSURL*)databaseURL
                                mode: (CBLChangeTrackerMode)mode
                           conflicts: (BOOL)includeConflicts
                        lastSequence: (id)lastSequenceID
                              client: (id<CBLChangeTrackerClient>)client
{
    NSParameterAssert(databaseURL);
    NSParameterAssert(client);
    self = [super init];
    if (self) {
        if([self class] == [CBLChangeTracker class]) {
            // CBLChangeTracker is abstract; instantiate a concrete subclass instead.
            Class cblURLProtocol = NSClassFromString(@"CBL_URLProtocol");
            if (cblURLProtocol && (BOOL) objc_msgSend(cblURLProtocol, sel_getUid("handlesURL:"), databaseURL)) {
                return [[CBLLocalChangeTracker alloc] initWithDatabaseURL: databaseURL
                                                                      mode: mode
                                                                 conflicts: includeConflicts
                                                              lastSequence: lastSequenceID
                                                                    client: client];
            }
            else {
                return [[CBLSocketChangeTracker alloc] initWithDatabaseURL: databaseURL
                                                                      mode: mode
                                                                 conflicts: includeConflicts
                                                              lastSequence: lastSequenceID
                                                                    client: client];
            }
        }
        _databaseURL = databaseURL;
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
    id seq = _lastSequenceID;
    if (seq) {
        // BigCouch is now using arrays as sequence IDs. These need to be sent back JSON-encoded.
        if ([seq isKindOfClass: [NSArray class]] || [seq isKindOfClass: [NSDictionary class]])
            seq = [CBLJSON stringWithJSONObject: seq options: 0 error: nil];
        [path appendFormat: @"&since=%@", CBLEscapeURLParam([seq description])];
    }
    if (_limit > 0)
        [path appendFormat: @"&limit=%u", _limit];
    if (_filterName) {
        [path appendFormat: @"&filter=%@", CBLEscapeURLParam(_filterName)];
        for (NSString* key in _filterParameters) {
            NSString* value = _filterParameters[key];
            if (![value isKindOfClass: [NSString class]]) {
                // It's ambiguous whether non-string filter params are allowed.
                // If we get one, encode it as JSON:
                NSError* error;
                value = [CBLJSON stringWithJSONObject: value options: CBLJSONWritingAllowFragments
                                                error: &error];
                if (!value) {
                    Warn(@"Illegal filter parameter %@ = %@", key, _filterParameters[key]);
                    continue;
                }
            }
            [path appendFormat: @"&%@=%@", CBLEscapeURLParam(key),
                                           CBLEscapeURLParam(value)];
        }
    }
    
    if (_docIDs) {
        
        if (_filterName) {
            Warn(@"You can't set both a replication filter and doc_ids, since doc_ids uses the internal _doc_ids filter.");
        } else {        
            NSError *error;
            NSString *docIDsParam = [CBLJSON stringWithJSONObject: _docIDs options: CBLJSONWritingAllowFragments
                                                           error: &error];
            if (!docIDsParam || error) {
                Warn(@"Illegal doc IDs %@, %@", [_docIDs description], [error localizedDescription]);
            }
            [path appendFormat:@"&filter=_doc_ids&doc_ids=%@", CBLEscapeURLParam(docIDsParam)];
        }
    }
    
    return path;
}

- (NSURL*) changesFeedURL {
    return CBLAppendToURL(_databaseURL, self.changesFeedPath);
}

- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%p %@]", [self class], self, self.databaseName];
}

- (void) dealloc {
    [self stop];
}

- (void) setUpstreamError: (NSString*)message {
    Warn(@"%@: Server error: %@", self, message);
    self.error = [NSError errorWithDomain: @"CBLChangeTracker" code: kCBLStatusUpstreamError userInfo: nil];
}

- (BOOL) start {
    self.error = nil;
    return NO;
}

- (void) stop {
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(retry)
                                               object: nil];    // cancel pending retries
    [self stopped];
}

- (void) stopped {
    _retryCount = 0;
    // Clear client ref so its -changeTrackerStopped: won't be called again during -dealloc
    id<CBLChangeTrackerClient> client = _client;
    _client = nil;
    if ([client respondsToSelector: @selector(changeTrackerStopped:)])
        [client changeTrackerStopped: self];    // note: this method might release/dealloc me
}


- (void) failedWithError: (NSError*)error {
    // If the error may be transient (flaky network, server glitch), retry:
    if (CBLMayBeTransientError(error)) {
        NSTimeInterval retryDelay = kInitialRetryDelay * (1 << MIN(_retryCount, 16U));
        retryDelay = MIN(retryDelay, kMaxRetryDelay);
        ++_retryCount;
        Log(@"%@: Connection error, retrying in %.1f sec: %@",
            self, retryDelay, error.localizedDescription);
        [self performSelector: @selector(retry) withObject: nil afterDelay: retryDelay];
    } else {
        Warn(@"%@: Can't connect, giving up: %@", self, error);
        self.error = error;
        [self stopped];
    }
}


- (void) retry {
    if ([self start]) {
        [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(retry)
                                                   object: nil];    // cancel pending retries
    }
}


- (BOOL) receivedChange: (NSDictionary*)change {
    if (![change isKindOfClass: [NSDictionary class]])
        return NO;
    id seq = change[@"seq"];
    if (!seq) {
        // If a continuous feed closes (e.g. if its database is deleted), the last line it sends
        // will indicate the last_seq. This is normal, just ignore it and return success:
        return change[@"last_seq"] != nil;
    }
    [_client changeTrackerReceivedChange: change];
    self.lastSequenceID = seq;
    return YES;
}

- (BOOL) receivedChanges: (NSArray*)changes errorMessage: (NSString**)errorMessage {
    if ([_client respondsToSelector: @selector(changeTrackerReceivedChanges:)]) {
        [_client changeTrackerReceivedChanges: changes];
        if (changes.count > 0)
            self.lastSequenceID = [[changes lastObject] objectForKey: @"seq"];
    } else {
        for (NSDictionary* change in changes) {
            if (![self receivedChange: change]) {
                if (errorMessage) {
                    *errorMessage = $sprintf(@"Invalid change object: %@",
                                             [CBLJSON stringWithJSONObject: change
                                                                  options:CBLJSONWritingAllowFragments
                                                                    error: nil]);
                }
                return NO;
            }
        }
    }
    return YES;
}

- (NSInteger) receivedPollResponse: (NSData*)body errorMessage: (NSString**)errorMessage {
    if (!body) {
        *errorMessage = @"No body in response";
        return -1;
    }
    NSError* error;
    id changeObj = [CBLJSON JSONObjectWithData: body options: 0 error: &error];
    if (!changeObj) {
        *errorMessage = $sprintf(@"JSON parse error: %@", error.localizedDescription);
        return -1;
    }
    NSDictionary* changeDict = $castIf(NSDictionary, changeObj);
    NSArray* changes = $castIf(NSArray, changeDict[@"results"]);
    if (!changes) {
        *errorMessage = @"No 'changes' array in response";
        return -1;
    }
    if (![self receivedChanges: changes errorMessage: errorMessage])
        return -1;
    return changes.count;
}

@end
