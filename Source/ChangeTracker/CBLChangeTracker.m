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
#import "CBLAuthorizer.h"
#import "CBLMisc.h"
#import "CBLStatus.h"
#import "CBLJSONReader.h"


#define kDefaultHeartbeat (5 * 60.0)

#define kInitialRetryDelay 2.0      // Initial retry delay (doubles after every subsequent failure)
#define kMaxRetryDelay (10*60.0)    // ...but will never get longer than this


typedef void (^CBLChangeMatcherClient)(id sequence, NSString* docID, NSArray* revs, bool deleted);

@interface CBLChangeMatcher : CBLJSONDictMatcher
+ (CBLJSONMatcher*) changesFeedMatcherWithClient: (CBLChangeMatcherClient)client;
@end


@interface CBLChangeTracker ()
@property (readwrite, copy, nonatomic) id lastSequenceID;
@end


@implementation CBLChangeTracker
{
    CBLJSONReader* _parser;
}

@synthesize lastSequenceID=_lastSequenceID, databaseURL=_databaseURL, mode=_mode;
@synthesize limit=_limit, heartbeat=_heartbeat, error=_error, continuous=_continuous;
@synthesize client=_client, filterName=_filterName, filterParameters=_filterParameters;
@synthesize requestHeaders = _requestHeaders, authorizer=_authorizer;
@synthesize docIDs = _docIDs, pollInterval=_pollInterval;

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
            return [[CBLSocketChangeTracker alloc] initWithDatabaseURL: databaseURL
                                                                 mode: mode
                                                            conflicts: includeConflicts
                                                         lastSequence: lastSequenceID
                                                               client: client];
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

    // Add filter or doc_ids:
    NSString* filterName = _filterName;
    NSDictionary* filterParameters = _filterParameters;
    if (_docIDs) {
        filterName = @"_doc_ids";
        filterParameters = @{@"doc_ids": _docIDs};
    }
    if (filterName) {
        [path appendFormat: @"&filter=%@", CBLEscapeURLParam(filterName)];
        for (NSString* key in filterParameters) {
            NSString* value = filterParameters[key];
            if (![value isKindOfClass: [NSString class]]) {
                // It's ambiguous whether non-string filter params are allowed.
                // If we get one, encode it as JSON:
                NSError* error;
                value = [CBLJSON stringWithJSONObject: value options: CBLJSONWritingAllowFragments
                                                error: &error];
                if (!value) {
                    Warn(@"Illegal filter parameter %@ = %@", key, filterParameters[key]);
                    continue;
                }
            }
            [path appendFormat: @"&%@=%@", CBLEscapeURLParam(key),
                                           CBLEscapeURLParam(value)];
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
    __weak CBLChangeTracker* weakSelf = self;
    CBLJSONMatcher* root = [CBLChangeMatcher changesFeedMatcherWithClient:
        ^(id sequence, NSString *docID, NSArray *revs, bool deleted) {
            // Callback when the parser reads another change from the feed:
            CBLChangeTracker* strongSelf = weakSelf;
            strongSelf.lastSequenceID = sequence;
            [strongSelf.client changeTrackerReceivedSequence: sequence
                                                       docID: docID
                                                      revIDs: revs
                                                     deleted: deleted];
    }];
    _parser = [[CBLJSONReader alloc] initWithMatcher: root];
    return NO;
}

- (void) stop {
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(retry)
                                               object: nil];    // cancel pending retries
    [self stopped];
}

- (void) stopped {
    _retryCount = 0;
    _parser = nil;
    // Clear client ref so its -changeTrackerStopped: won't be called again during -dealloc
    id<CBLChangeTrackerClient> client = _client;
    _client = nil;
    if ([client respondsToSelector: @selector(changeTrackerStopped:)])
        [client changeTrackerStopped: self];    // note: this method might release/dealloc me
}


- (void) failedWithError: (NSError*)error {
    // If the error may be transient (flaky network, server glitch), retry:
    if (!CBLIsPermanentError(error) && (_continuous || CBLMayBeTransientError(error))) {
        NSTimeInterval retryDelay = kInitialRetryDelay * (1 << MIN(_retryCount, 16U));
        retryDelay = MIN(retryDelay, kMaxRetryDelay);
        ++_retryCount;
        Log(@"%@: Connection error #%d, retrying in %.1f sec: %@",
            self, _retryCount, retryDelay, error.localizedDescription);
        [self retryAfterDelay: retryDelay];
    } else {
        Warn(@"%@: Can't connect, giving up: %@", self, error);
        self.error = error;
        [self stop];
    }
}


- (void) retryAfterDelay: (NSTimeInterval)retryDelay {
    [self performSelector: @selector(retry) withObject: nil afterDelay: retryDelay];
}


- (void) retry {
    if ([self start]) {
        [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(retry)
                                                   object: nil];    // cancel pending retries
    }
}

- (BOOL) parseBytes: (const void*)bytes length: (size_t)length {
    LogTo(ChangeTracker, @"%@: read %ld bytes", self, (long)length);
    if (![_parser parseBytes: bytes length: length]) {
        Warn(@"JSON error parsing _changes feed: %@", _parser.errorString);
        [self failedWithError: [NSError errorWithDomain: @"CBLChangeTracker"
                                                   code: kCBLStatusBadChangesFeed userInfo: nil]];
        return NO;
    }
    return YES;
}

- (BOOL) endParsingData {
    if (![_parser finish]) {
        Warn(@"Truncated changes feed");
        return NO;
    }
    return YES;
}


@end




#pragma mark - PARSER


@interface CBLRevInfoMatcher : CBLJSONDictMatcher
@end

@implementation CBLRevInfoMatcher
{
    NSMutableArray* _revIDs;
}

- (id)initWithArray: (NSMutableArray*)revIDs
{
    self = [super init];
    if (self) {
        _revIDs = revIDs;
    }
    return self;
}

- (bool) matchValue:(id)value forKey:(NSString *)key {
    if ([key isEqualToString: @"rev"])
        [_revIDs addObject: value];
    return true;
}

@end



@implementation CBLChangeMatcher
{
    id _sequence;
    NSString* _docID;
    NSMutableArray* _revs;
    bool _deleted;
    CBLTemplateMatcher* _revsMatcher;
    CBLChangeMatcherClient _client;
}

+ (CBLJSONMatcher*) changesFeedMatcherWithClient: (CBLChangeMatcherClient)client {
    CBLChangeMatcher* changeMatcher = [[CBLChangeMatcher alloc] initWithClient: client];
    id template = @[ @{@"results": @[changeMatcher]} ];
    return [[CBLTemplateMatcher alloc] initWithTemplate: template];
}

- (id) initWithClient: (CBLChangeMatcherClient)client {
    self = [super init];
    if (self) {
        _client = client;
        _revs = $marray();
        CBLRevInfoMatcher* m = [[CBLRevInfoMatcher alloc] initWithArray: _revs];
        _revsMatcher = [[CBLTemplateMatcher alloc] initWithTemplate: @[m]];
    }
    return self;
}

- (bool) matchValue:(id)value forKey:(NSString *)key {
    if ([key isEqualToString: @"deleted"])
        _deleted = [value boolValue];
    else if ([key isEqualToString: @"seq"])
        _sequence = value;
    else if ([self.key isEqualToString: @"id"])
        _docID = value;
    return true;
}

- (CBLJSONArrayMatcher*) startArray {
    if ([self.key isEqualToString: @"changes"])
        return (CBLJSONArrayMatcher*)_revsMatcher;
    return [super startArray];
}

- (id) end {
    //Log(@"Ended ChangeMatcher with seq=%@, id='%@', deleted=%d, revs=%@", _sequence, _docID, _deleted, _revs);
    if (!_sequence || !_docID || _revs.count == 0)
        return nil;
    _client(_sequence, _docID, [_revs copy], _deleted);
    _sequence = nil;
    _docID = nil;
    _deleted = false;
    [_revs removeAllObjects];
    return self;
}

@end


TestCase(CBLChangeMatcher) {
    NSString* kJSON = @"{\"results\":[\
    {\"seq\":1,\"id\":\"1\",\"changes\":[{\"rev\":\"2-751ac4eebdc2a3a4044723eaeb0fc6bd\"}],\"deleted\":true},\
    {\"seq\":2,\"id\":\"10\",\"changes\":[{\"rev\":\"2-566bffd5785eb2d7a79be8080b1dbabb\"}],\"deleted\":true},\
    {\"seq\":3,\"id\":\"100\",\"changes\":[{\"rev\":\"2-ec2e4d1833099b8a131388b628fbefbf\"}],\"deleted\":true}]}";
    NSMutableArray* docIDs = $marray();
    CBLJSONMatcher* root = [CBLChangeMatcher changesFeedMatcherWithClient:
        ^(id sequence, NSString *docID, NSArray *revs, bool deleted) {
            [docIDs addObject: docID];
        }];
    CBLJSONReader* parser = [[CBLJSONReader alloc] initWithMatcher: root];
    CAssert([parser parseData: [kJSON dataUsingEncoding: NSUTF8StringEncoding]]);
    CAssert([parser finish]);
    CAssertEqual(docIDs, (@[@"1", @"10", @"100"]));
}
