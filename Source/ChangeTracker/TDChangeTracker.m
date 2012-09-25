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
#import "TDAuthorizer.h"
#import "TDMisc.h"
#import "TDStatus.h"


#define kDefaultHeartbeat (5 * 60.0)

#define kInitialRetryDelay 2.0      // Initial retry delay (doubles after every subsequent failure)
#define kMaxRetryDelay 300.0        // ...but will never get longer than this


static NSURL* AddDotToURLHost( NSURL* url );


@interface TDChangeTracker ()
@property (readwrite, copy, nonatomic) id lastSequenceID;
@end


@implementation TDChangeTracker

@synthesize lastSequenceID=_lastSequenceID, databaseURL=_databaseURL, mode=_mode;
@synthesize limit=_limit, heartbeat=_heartbeat, error=_error;
@synthesize client=_client, filterName=_filterName, filterParameters=_filterParameters;
@synthesize requestHeaders = _requestHeaders, authorizer=_authorizer;

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
            id value = _filterParameters[key];
            [path appendFormat: @"&%@=%@", TDEscapeURLParam(key), 
                                           TDEscapeURLParam([value description])];
        }
    }

    return path;
}

- (NSURL*) changesFeedURL {
    // Really ugly workaround for CFNetwork, to make sure that long-running connections like these
    // don't end up using the same socket pool as regular connections to the same host; otherwise
    // the regular connections can get stuck indefinitely behind a long-running one.
    // (This substitution appends a "." to the host name, if it didn't already end with one.)
    NSURL* url = AddDotToURLHost(_databaseURL);

    NSMutableString* urlStr = [[url.absoluteString mutableCopy] autorelease];
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
    [_authorizer release];
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
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(retry)
                                               object: nil];    // cancel pending retries
    [self stopped];
}

- (void) stopped {
    _retryCount = 0;
    // Clear client ref so its -changeTrackerStopped: won't be called again during -dealloc
    id<TDChangeTrackerClient> client = _client;
    _client = nil;
    if ([client respondsToSelector: @selector(changeTrackerStopped:)])
        [client changeTrackerStopped: self];    // note: this method might release/dealloc me
}


- (void) failedWithError: (NSError*)error {
    // If the error may be transient (flaky network, server glitch), retry:
    if (TDMayBeTransientError(error)) {
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

- (NSInteger) receivedPollResponse: (NSData*)body errorMessage: (NSString**)errorMessage {
    if (!body) {
        *errorMessage = @"No body in response";
        return -1;
    }
    NSError* error;
    id changeObj = [TDJSON JSONObjectWithData: body options: 0 error: &error];
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

    if ([_client respondsToSelector: @selector(changeTrackerReceivedChanges:)]) {
        [_client changeTrackerReceivedChanges: changes];
        if (changes.count > 0)
            self.lastSequenceID = [[changes lastObject] objectForKey: @"seq"];
    } else {
        for (NSDictionary* change in changes) {
            if (![self receivedChange: change]) {
                *errorMessage = $sprintf(@"Invalid change object: %@",
                                         [TDJSON stringWithJSONObject: change
                                                              options:TDJSONWritingAllowFragments
                                                                error: nil]);
                return -1;
            }
        }
    }
    return changes.count;
}

@end


static NSURL* AddDotToURLHost( NSURL* url ) {
    CAssert(url);
    UInt8 urlBytes[1024];
    CFIndex nBytes = CFURLGetBytes((CFURLRef)url, urlBytes, sizeof(urlBytes) - 1);
    if (nBytes > 0) {
        CFRange range;
        CFURLGetByteRangeForComponent((CFURLRef)url, kCFURLComponentHost, &range);
        if (range.length >= 2) {
            CFIndex end = range.location + range.length - 1;
            if (urlBytes[end] == '/' || urlBytes[end] == ':')
                --end;
            if (isalpha(urlBytes[end])) {
                // Alright, insert the '.' after end:
                memmove(&urlBytes[end+2], &urlBytes[end+1], nBytes - end);
                urlBytes[end+1] = '.';
                NSURL* newURL = (id)(CFURLCreateWithBytes(NULL, urlBytes, nBytes + 1,
                                                          kCFStringEncodingUTF8, NULL));
                if (newURL)
                    url = [newURL autorelease];
                else
                    Warn(@"AddDotToURLHost: Failed to add dot to <%@> -- result is <%.*s>",
                         url, (int)nBytes+1, urlBytes);
            }
        }
    }
    return url;
}


#if DEBUG
static NSString* addDot( NSString* urlStr ) {
    return AddDotToURLHost([NSURL URLWithString: urlStr]).absoluteString;
}

TestCase(AddDotToURLHost) {
    CAssertEqual(addDot(@"http://x/y"),                 @"http://x./y");
    CAssertEqual(addDot(@"http://foo.com"),             @"http://foo.com.");
    CAssertEqual(addDot(@"http://foo.com/"),            @"http://foo.com./");
    CAssertEqual(addDot(@"http://foo.com/bar"),         @"http://foo.com./bar");
    CAssertEqual(addDot(@"http://foo.com:123/"),        @"http://foo.com.:123/");
    CAssertEqual(addDot(@"http://user:pass@foo.com/"),  @"http://user:pass@foo.com./");
    CAssertEqual(addDot(@"http://foo.com./"),           @"http://foo.com./");
    CAssertEqual(addDot(@"http://localhost/"),          @"http://localhost./");
    CAssertEqual(addDot(@"http://10.0.1.12/"),          @"http://10.0.1.12/");
}
#endif
