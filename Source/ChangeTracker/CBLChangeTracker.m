//
//  CBLChangeTracker.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/20/11.
//  Copyright 2011-2013 Couchbase, Inc.
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
#import "CBLWebSocketChangeTracker.h"
#import "CBLAuthorizer.h"
#import "CBLMisc.h"
#import "CBLStatus.h"
#import "CBLJSONReader.h"
#import "MYURLUtils.h"


#define kDefaultHeartbeat (5 * 60.0)

#define kInitialRetryDelay 2.0      // Initial retry delay (doubles after every subsequent failure)
#define kMaxRetryDelay (10*60.0)    // ...but will never get longer than this


typedef void (^CBLChangeMatcherClient)(id sequence, NSString* docID, NSArray* revs, bool deleted);

@interface CBLChangeMatcher : CBLJSONDictMatcher
+ (CBLJSONMatcher*) changesFeedMatcherWithClient: (CBLChangeMatcherClient)client
                               expectWrapperDict: (BOOL)expectWrapperDict;
@end


@interface CBLChangeTracker ()
@property (readwrite, copy, nonatomic) id lastSequenceID;
@end


@implementation CBLChangeTracker
{
    CBLJSONReader* _parser;
    NSInteger _parsedChangeCount;
}

@synthesize lastSequenceID=_lastSequenceID, databaseURL=_databaseURL, mode=_mode;
@synthesize limit=_limit, heartbeat=_heartbeat, error=_error, continuous=_continuous;
@synthesize client=_client, filterName=_filterName, filterParameters=_filterParameters;
@synthesize requestHeaders = _requestHeaders, authorizer=_authorizer;
@synthesize docIDs = _docIDs, pollInterval=_pollInterval, usePOST=_usePOST;
@synthesize paused=_paused;

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
            Class klass = (mode==kWebSocket) ? [CBLWebSocketChangeTracker class]
                                             : [CBLSocketChangeTracker class];
            return [[klass alloc] initWithDatabaseURL: databaseURL
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

- (NSString*) feed {
    static NSString* const kModeNames[4] = {@"normal", @"longpoll", @"continuous", @"websocket"};
    return kModeNames[_mode];
}

- (NSString*) changesFeedPath {
    if (_usePOST)
        return @"_changes";
    
    NSMutableString* path;
    path = [NSMutableString stringWithFormat: @"_changes?feed=%@&heartbeat=%.0f",
                                              self.feed, _heartbeat*1000.0];
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

- (NSData*) changesFeedPOSTBody {
    // The replicator always stores the last sequence as a string, but the server may treat it as
    // an integer. As a heuristic, convert it to a number if it looks like one:
    id since = _lastSequenceID;
    NSInteger n;
    if ([since isKindOfClass: [NSString class]] && CBLParseInteger(since, &n) && n >= 0)
        since = @(n);

    NSString* filterName = _filterName;
    NSDictionary* filterParameters = _filterParameters;
    if (_docIDs) {
        filterName = @"_doc_ids";
        filterParameters = @{@"doc_ids": _docIDs};
    }
    NSMutableDictionary* post = $mdict({@"feed", self.feed},
                                       {@"heartbeat", @(_heartbeat*1000.0)},
                                       {@"style", (_includeConflicts ? @"all_docs" : nil)},
                                       {@"since", since},
                                       {@"limit", (_limit > 0 ? @(_limit) : nil)},
                                       {@"filter", filterName});
    if (filterName && filterParameters)
        [post addEntriesFromDictionary: filterParameters];
    return [CBLJSON dataWithJSONObject: post options: 0 error: NULL];
}

- (NSDictionary*) TLSSettings {
    if (!_databaseURL.my_isHTTPS)
        return nil;
    // Enable SSL for this connection.
    // Disable TLS 1.2 support because it breaks compatibility with some SSL servers;
    // workaround taken from Apple technote TN2287:
    // http://developer.apple.com/library/ios/#technotes/tn2287/
    // Disable automatic cert-chain checking, because that's the only way to allow self-signed
    // certs. We will check the cert later in -checkSSLCert.
    return $dict( {(id)kCFStreamSSLLevel, (id)kCFStreamSocketSecurityLevelTLSv1},
                  {(id)kCFStreamSSLValidatesCertificateChain, @NO} );
}


- (BOOL) checkServerTrust: (SecTrustRef)sslTrust forURL: (NSURL*)url {
    BOOL trusted = [_client changeTrackerApproveSSLTrust: sslTrust
                                                 forHost: url.host
                                                    port: (UInt16)url.port.intValue];
    if (!trusted) {
        //TODO: This error could be made more precise
        LogTo(ChangeTracker, @"%@: Rejected server certificate", self);
        [self failedWithError: [NSError errorWithDomain: NSURLErrorDomain
                                                   code: NSURLErrorServerCertificateUntrusted
                                               userInfo: nil]];
    }
    return trusted;
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
    _parser = nil;
    // Clear client ref so its -changeTrackerStopped: won't be called again during -dealloc
    id<CBLChangeTrackerClient> client = _client;
    _client = nil;
    if ([client respondsToSelector: @selector(changeTrackerStopped:)])
        [client changeTrackerStopped: self];    // note: this method might release/dealloc me
}


- (void) failedWithError: (NSError*)error {
    // Map lower-level errors from CFStream to higher-level NSURLError ones:
    NSString* domain = error.domain;
    NSInteger code = error.code;
    if ($equal(domain, NSPOSIXErrorDomain)) {
        if (code == ECONNREFUSED)
            error = [NSError errorWithDomain: NSURLErrorDomain
                                        code: NSURLErrorCannotConnectToHost
                                    userInfo: error.userInfo];
    } else if ($equal(domain, NSURLErrorDomain)) {
        if (code == NSURLErrorUserAuthenticationRequired)
            error = [NSError errorWithDomain: CBLHTTPErrorDomain
                                        code: kCBLStatusUnauthorized
                                    userInfo: error.userInfo];
    }

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
    LogTo(ChangeTrackerVerbose, @"%@: read %ld bytes", self, (long)length);
    if (!_parser) {
        __weak CBLChangeTracker* weakSelf = self;
        CBLJSONMatcher* root = [CBLChangeMatcher changesFeedMatcherWithClient:
                                ^(id sequence, NSString *docID, NSArray *revs, bool deleted) {
                                    // Callback when the parser reads another change from the feed:
                                    CBLChangeTracker* strongSelf = weakSelf;
                                    strongSelf->_parsedChangeCount++;
                                    strongSelf.lastSequenceID = sequence;
                                    [strongSelf.client changeTrackerReceivedSequence: sequence
                                                                               docID: docID
                                                                              revIDs: revs
                                                                             deleted: deleted];
                                }
                                expectWrapperDict: (_mode != kWebSocket)];
        _parser = [[CBLJSONReader alloc] initWithMatcher: root];
        _parsedChangeCount = 0;
    }
    
    if (![_parser parseBytes: bytes length: length]) {
        Warn(@"JSON error parsing _changes feed: %@", _parser.errorString);
        [self failedWithError: [NSError errorWithDomain: @"CBLChangeTracker"
                                                   code: kCBLStatusBadChangesFeed userInfo: nil]];
        return NO;
    }
    return YES;
}

- (NSInteger) endParsingData {
    if (!_parser) {
        Warn(@"Connection closed before first byte");
        return - 1;
    }
    
    BOOL ok = [_parser finish];
    _parser = nil;
    if (!ok) {
        Warn(@"Truncated changes feed");
        return -1;
    }
    return _parsedChangeCount;
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

+ (CBLJSONMatcher*) changesFeedMatcherWithClient: (CBLChangeMatcherClient)client
                               expectWrapperDict: (BOOL)expectWrapperDict
{
    CBLChangeMatcher* changeMatcher = [[CBLChangeMatcher alloc] initWithClient: client];
    id template = @[changeMatcher];
    if (expectWrapperDict)
        template = @{@"results": template};
    return [[CBLTemplateMatcher alloc] initWithTemplate: @[template]];
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
    if (!_sequence || !_docID)
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
    NSString* kJSON = @"[\
    {\"seq\":1,\"id\":\"1\",\"changes\":[{\"rev\":\"2-751ac4eebdc2a3a4044723eaeb0fc6bd\"}],\"deleted\":true},\
    {\"seq\":2,\"id\":\"10\",\"changes\":[{\"rev\":\"2-566bffd5785eb2d7a79be8080b1dbabb\"}],\"deleted\":true},\
    {\"seq\":3,\"id\":\"100\",\"changes\":[{\"rev\":\"2-ec2e4d1833099b8a131388b628fbefbf\"}],\"deleted\":true}]";
    NSMutableArray* docIDs = $marray();
    CBLJSONMatcher* root = [CBLChangeMatcher changesFeedMatcherWithClient:
        ^(id sequence, NSString *docID, NSArray *revs, bool deleted) {
            [docIDs addObject: docID];
        } expectWrapperDict: NO];
    CBLJSONReader* parser = [[CBLJSONReader alloc] initWithMatcher: root];
    CAssert([parser parseData: [kJSON dataUsingEncoding: NSUTF8StringEncoding]]);
    CAssert([parser finish]);
    CAssertEqual(docIDs, (@[@"1", @"10", @"100"]));

    kJSON = [NSString stringWithFormat: @"{\"results\":%@}", kJSON];
    docIDs = $marray();
    root = [CBLChangeMatcher changesFeedMatcherWithClient:
                            ^(id sequence, NSString *docID, NSArray *revs, bool deleted) {
                                [docIDs addObject: docID];
                            } expectWrapperDict: YES];
    parser = [[CBLJSONReader alloc] initWithMatcher: root];
    CAssert([parser parseData: [kJSON dataUsingEncoding: NSUTF8StringEncoding]]);
    CAssert([parser finish]);
    CAssertEqual(docIDs, (@[@"1", @"10", @"100"]));
}
