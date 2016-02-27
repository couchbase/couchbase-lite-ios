//
//  CBLChangeTracker.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/20/11.
//  Copyright (c) 2011-2015 Couchbase, Inc.
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
#import "CBLChangeMatcher.h"
#import "CBLAuthorizer.h"
#import "CBLClientCertAuthorizer.h"
#import "CBLCookieStorage.h"
#import "CBLMisc.h"
#import "CBLStatus.h"
#import "BLIPHTTPLogic.h"
#import "MYErrorUtils.h"
#import "MYURLUtils.h"
#import "WebSocket.h"


DefineLogDomain(ChangeTracker);


#define kDefaultHeartbeat (5 * 60.0)

#define kInitialRetryDelay 2.0      // Initial retry delay (doubles after every subsequent failure)
#define kMaxRetryDelay (10*60.0)    // ...but will never get longer than this


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
@synthesize requestHeaders = _requestHeaders, authorizer=_authorizer, cookieStorage=_cookieStorage;
@synthesize docIDs = _docIDs, pollInterval=_pollInterval, paused=_paused, activeOnly=_activeOnly;

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
        _usePOST = YES;
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
    // We add the basic query params to the URL even if we'll send a POST request. Yes, this is
    // redundant, since those params are in the JSON body too. This is for CouchDB compatibility:
    // for some reason it still expects most of the params in the URL, even with a POST; only the
    // filter-related params go in the body. (See #1139)
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
    if (_activeOnly && !_caughtUp)
        [path appendString: @"&active_only=true"];
    if (_limit > 0)
        [path appendFormat: @"&limit=%u", _limit];

    if (!_usePOST) {
        // Add filter or doc_ids to URL. If sending a POST, these will go in the JSON body instead.
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
    // Sync Gateway expects all the parameters here, but CouchDB expects them in the URL and
    // ignores these, _except_ the filter and filterParameters. For compatibility we put the
    // basic parameters in both places.
    NSMutableDictionary* post = $mdict({@"feed", self.feed},
                                       {@"heartbeat", @(round(_heartbeat*1000.0))},
                                       {@"style", (_includeConflicts ? @"all_docs" : nil)},
                                       {@"active_only", (_activeOnly && !_caughtUp ? @YES : nil)},
                                       {@"since", since},
                                       {@"limit", (_limit > 0 ? @(_limit) : nil)},
                                       {@"filter", filterName},
                                       {@"accept_encoding", @"gzip"});
    if (filterName && filterParameters)
        [post addEntriesFromDictionary: filterParameters];
    return [CBLJSON dataWithJSONObject: post options: 0 error: NULL];
}

- (NSDictionary*) TLSSettings {
    if (!_databaseURL.my_isHTTPS)
        return nil;
    NSArray* clientCerts = $castIf(CBLClientCertAuthorizer, _authorizer).certificateChain;
    // Enable SSL for this connection.
    // Disable TLS 1.2 support because it breaks compatibility with some SSL servers;
    // workaround taken from Apple technote TN2287:
    // http://developer.apple.com/library/ios/#technotes/tn2287/
    // Disable automatic cert-chain checking, because that's the only way to allow self-signed
    // certs. We will check the cert later in -checkSSLCert.
    return $dict( {(id)kCFStreamSSLLevel, (id)kCFStreamSocketSecurityLevelTLSv1},
                  {(id)kCFStreamSSLValidatesCertificateChain, @NO},
                  {(id)kCFStreamSSLCertificates, clientCerts});
}


- (BOOL) checkServerTrust: (SecTrustRef)sslTrust forURL: (NSURL*)url {
    return [_client changeTrackerApproveSSLTrust: sslTrust
                                                 forHost: url.host
                                                    port: (UInt16)url.port.intValue];
}


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%p %@]", [self class], self, self.databaseName];
}

- (void) dealloc {
    [self stop];
}

- (BOOL) start {
    if (!_http) {
        // Initialize HTTPLogic before sending first request:
        NSMutableURLRequest* urlRequest = [NSMutableURLRequest requestWithURL: self.changesFeedURL];
        if (_usePOST) {
            urlRequest.HTTPMethod = @"POST";
            urlRequest.HTTPBody = self.changesFeedPOSTBody;
            [urlRequest setValue: @"application/json" forHTTPHeaderField: @"Content-Type"];
        }

        // Add headers from my .requestHeaders property:
        [self.requestHeaders enumerateKeysAndObjectsUsingBlock: ^(id key, id value, BOOL *stop) {
            if ([key caseInsensitiveCompare: @"Cookie"] == 0)
                urlRequest.HTTPShouldHandleCookies = NO;
            [urlRequest setValue: value forHTTPHeaderField: key];
        }];
        
        if (urlRequest.HTTPShouldHandleCookies) {
            [self.cookieStorage addCookieHeaderToRequest: urlRequest];
        }

        // Let the Authorizer add its own headers:
        [$castIfProtocol(CBLCustomHeadersAuthorizer, _authorizer) authorizeURLRequest: urlRequest];

        _http = [[BLIPHTTPLogic alloc] initWithURLRequest: urlRequest];

        // If no credential yet, get it from authorizer if it has one:
        if (!_http.credential)
            _http.credential = $castIfProtocol(CBLCredentialAuthorizer, _authorizer).credential;
    }
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


- (void) failedWithErrorDomain: (NSString*)domain
                          code: (NSInteger)code
                       message: (NSString*) message {
    [self failedWithError: [NSError errorWithDomain: domain code: code
                                           userInfo: $dict({NSLocalizedDescriptionKey, message},
                                                           {NSURLErrorFailingURLErrorKey, self.changesFeedURL})]];
}


- (void) failedWithError: (NSError*)error {
    NSString* domain = error.domain;
    NSInteger code = error.code;
    NSDictionary* userInfo = @{NSURLErrorFailingURLErrorKey: self.changesFeedURL};
    if ($equal(domain, NSPOSIXErrorDomain)) {
        // Map POSIX errors from CFStream to higher-level NSURLError ones:
        if (code == ECONNREFUSED)
            error = MYWrapError(error, NSURLErrorDomain, NSURLErrorCannotConnectToHost, userInfo);
    } else if ($equal(domain, (id)kCFErrorDomainCFNetwork)) {
        if (code == kCFHostErrorHostNotFound || code == kCFHostErrorUnknown) {
            error = MYWrapError(error, NSURLErrorDomain, NSURLErrorCannotFindHost, userInfo);
        }
    } else if ($equal(domain, NSURLErrorDomain)) {
        // Map a lower-level auth failure to an HTTP status:
        if (code == NSURLErrorUserAuthenticationRequired)
            error = MYWrapError(error, CBLHTTPErrorDomain, kCBLStatusUnauthorized, userInfo);
    }

    // If the error may be transient (flaky network, server glitch), retry:
    if (!CBLIsPermanentError(error) && (_continuous || CBLMayBeTransientError(error))) {
        NSTimeInterval retryDelay = kInitialRetryDelay * (1 << MIN(_retryCount, 16U));
        retryDelay = MIN(retryDelay, kMaxRetryDelay);
        ++_retryCount;
        Log(@"%@: Connection error #%d, retrying in %.1f sec: %@",
            self, _retryCount, retryDelay, error.my_compactDescription);
        [self retryAfterDelay: retryDelay];
    } else {
        Log(@"%@: Can't connect, giving up: %@", self, error.my_compactDescription);
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
    LogVerbose(ChangeTracker, @"%@: read %ld bytes", self, (long)length);
    if (!_parser) {
        __weak CBLChangeTracker* weakSelf = self;
        CBLJSONMatcher* root = [CBLChangeMatcher changesFeedMatcherWithClient:
                                ^(id sequence, NSString *docID, NSArray *revs, bool deleted) {
                                    // Callback when the parser reads another change from the feed:
                                    CBLChangeTracker* strongSelf = weakSelf;
                                    if (!strongSelf) return; // already dealloced
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
        NSString* message = $sprintf(@"JSON error parsing _changes feed: %@", _parser.errorString);
        Warn(@"%@", message);
        [self failedWithErrorDomain: CBLHTTPErrorDomain code: kCBLStatusBadChangesFeed
                            message: message];
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
