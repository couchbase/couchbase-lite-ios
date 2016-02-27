//
//  CBLWebSocketChangeTracker.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 11/12/13.
//  Copyright (c) 2013-2015 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLWebSocketChangeTracker.h"
#import "CBLAuthorizer.h"
#import "CBLCookieStorage.h"
#import "PSWebSocket.h"
#import "BLIPHTTPLogic.h"
#import "CBLMisc.h"
#import "CBLStatus.h"
#import "CBLGZip.h"
#import "MYBlockUtils.h"
#import "MYErrorUtils.h"
#import <libkern/OSAtomic.h>


UsingLogDomain(Sync);


#define kMaxPendingMessages 2


@interface CBLWebSocketChangeTracker () <PSWebSocketDelegate>
@end


@implementation CBLWebSocketChangeTracker
{
    NSThread* _thread;
    PSWebSocket* _ws;
    BOOL _running;
    CFAbsoluteTime _startTime;
    int32_t _pendingMessageCount;   // How many incoming WebSocket messages haven't been parsed yet?
    CBLGZip* _gzip;
}


- (NSURL*) changesFeedURL {
    // The options will be sent in a WebSocket message after opening (see -webSocketDidOpen: below)
    return CBLAppendToURL(_databaseURL, @"_changes?feed=websocket");
}


- (BOOL) start {
    if (_ws)
        return NO;
    LogTo(ChangeTracker, @"%@: Starting...", self);

    // A WebSocket has to be opened with a GET request, not a POST (as defined in the RFC.)
    // Instead of putting the options in the POST body as with HTTP, we will send them in an
    // initial WebSocket message, in -webSocketDidOpen:, below.
    _usePOST = NO;

    [super start];

    NSMutableURLRequest* request = [[_http URLRequest] mutableCopy];
    request.timeoutInterval = _heartbeat * 1.5;

    LogVerbose(Sync, @"%@: %@ %@", self, request.HTTPMethod, request.URL.resourceSpecifier);
    _ws = [PSWebSocket clientSocketWithRequest: request];
    _ws.delegate = self;
    NSDictionary* tls = self.TLSSettings;
    if (tls) {
        [_ws setStreamProperty: (__bridge CFDictionaryRef)tls
                        forKey: (__bridge NSString*)kCFStreamPropertySSLSettings];
    }
    [_ws open];
    _thread = [NSThread currentThread];
    _running = YES;
    _caughtUp = NO;
    _startTime = CFAbsoluteTimeGetCurrent();
    _pendingMessageCount = 0;
    LogTo(ChangeTracker, @"%@: Started... <%@>", self, request.URL);
    return YES;
}


- (void) stop {
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(start)
                                               object: nil];    // cancel pending retries
    if (_ws) {
        LogTo(ChangeTracker, @"%@: stop", self);
        _running = NO; // don't want to receive any more messages
        [_ws close];
    }
    [super stop];
}

- (void) setPaused:(BOOL)paused {
    [super setPaused: paused];

    // Pause the WebSocket if the client paused _or_ there are too many incoming messages:
    paused = paused || _pendingMessageCount >= kMaxPendingMessages;
    if (paused != _ws.readPaused)
        LogTo(ChangeTracker, @"%@: %@ WebSocket", self, (paused ? @"PAUSE" : @"RESUME"));
    _ws.readPaused = paused;
}


#pragma mark - WEBSOCKET DELEGATE API:

// THESE ARE CALLED ON THE WEBSOCKET'S DISPATCH QUEUE, NOT MY THREAD!!

- (BOOL)webSocket:(PSWebSocket *)webSocket validateServerTrust: (SecTrustRef)trust {
    __block BOOL ok;
    MYOnThreadSynchronously(_thread, ^{
        ok = [self checkServerTrust: trust forURL: _databaseURL];
    });
    return ok;
}

- (void) webSocketDidOpen: (PSWebSocket*)ws {
    MYOnThread(_thread, ^{
        LogVerbose(ChangeTracker, @"%@: WebSocket opened", self);
        _retryCount = 0;
        // Now that the WebSocket is open, send the changes-feed options (the ones that would have
        // gone in the POST body if this were HTTP-based.)
        [ws send: self.changesFeedPOSTBody];
    });
}

- (void)webSocket:(PSWebSocket *)webSocket didFailWithError:(NSError *)error {
    MYOnThread(_thread, ^{
        _ws = nil;
        NSError* myError = error;
        if ([error.domain isEqualToString: PSWebSocketErrorDomain]) {
            if (error.code == PSWebSocketErrorCodeHandshakeFailed) {
                // HTTP error; ask _httpLogic what to do:
                CFHTTPMessageRef response = (__bridge CFHTTPMessageRef)error.userInfo[PSHTTPResponseErrorKey];
                NSInteger status = CFHTTPMessageGetResponseStatusCode(response);
                [_http receivedResponse: response];
                if (_http.shouldRetry) {
                    // Retry due to redirect or auth challenge:
                    LogVerbose(ChangeTracker, @"%@ got HTTP response %ld, retrying...",
                          self, (long)status);
                    [self retry];
                    return;
                }
                // Failed, but map the error back to HTTP:
                NSString* message = CFBridgingRelease(CFHTTPMessageCopyResponseStatusLine(response));
                NSURL* url = webSocket.URLRequest.URL;
                myError = MYWrapError(error, CBLHTTPErrorDomain, status,
                                      @{NSLocalizedDescriptionKey: message,
                                        NSUnderlyingErrorKey: error,
                                        NSURLErrorFailingURLErrorKey: url});
            } else {
                // Map HTTP errors to my own error domain:
                NSNumber* status = error.userInfo[PSHTTPStatusErrorKey];
                if (status) {
                    myError = CBLStatusToNSErrorWithInfo((CBLStatus)status.integerValue, nil,
                                                         webSocket.URLRequest.URL, nil);
                }
            }
        }
        [self failedWithError: myError];
    });
}

/** Called when a WebSocket receives a textual message from its peer. */
- (void) webSocket: (PSWebSocket*)ws didReceiveMessage: (id)msg {
    MYOnThread(_thread, ^{
        __block NSData *data;
        if ([msg isKindOfClass: [NSData class]]) {
            // Binary messages are gzip-compressed; actually they're segments of a single stream.
            if (!_gzip)
                _gzip = [[CBLGZip alloc] initForCompressing: NO];
            NSMutableData* decoded = [NSMutableData new];
            [_gzip addBytes: [msg bytes] length: [msg length]
                   onOutput:^(const void *bytes, size_t length) {
                       [decoded appendBytes: bytes length: length];
            }];
            [_gzip flush:^(const void *bytes, size_t length) {
                [decoded appendBytes: bytes length: length];
            }];
            if (decoded.length == 0) {
                Warn(@"CBLWebSocketChangeTracker: Couldn't unzip compressed message; status=%d",
                     _gzip.status);
                [_ws closeWithCode: PSWebSocketStatusCodeUnhandledType
                            reason: @"Couldn't unzip change entry"];
            }
            data = decoded;
        } else if ([msg isKindOfClass: [NSString class]]) {
            data = [msg dataUsingEncoding: NSUTF8StringEncoding];
        }

        LogVerbose(ChangeTracker, @"%@: Got a message: %@", self, msg);
        if (data.length > 0 && ws == _ws && _running) {
            BOOL parsed = [self parseBytes: data.bytes length: data.length];
            if (parsed) {
                NSInteger changeCount = [self endParsingData];
                parsed = changeCount >= 0;
                if (changeCount == 0 && !_caughtUp) {
                    // Received an empty changes array: means server is waiting, so I'm caught up
                    LogTo(ChangeTracker, @"%@: caught up!", self);
                    _caughtUp = YES;
                    [self.client changeTrackerCaughtUp];
                }
            }
            if (!parsed) {
                Warn(@"Couldn't parse message: %@", msg);
                [_ws closeWithCode: PSWebSocketStatusCodeUnhandledType
                            reason: @"Unparseable change entry"];
            }
        }
        OSAtomicDecrement32Barrier(&_pendingMessageCount);
        [self setPaused: self.paused]; // this will resume the WebSocket unless self.paused
    });

    // Tell the WebSocket to pause its reader if too many messages are waiting to be processed:
    if (OSAtomicIncrement32Barrier(&_pendingMessageCount) >= kMaxPendingMessages)
        _ws.readPaused = YES;
}

/** Called after the WebSocket closes, either intentionally or due to an error. */
- (void)webSocket:(PSWebSocket *)ws
        didCloseWithCode:(NSInteger)code
        reason:(NSString *)reason
        wasClean:(BOOL)wasClean
{
    MYOnThread(_thread, ^{
        if (ws != _ws)
            return;
        _ws = nil;
        NSInteger effectiveCode = code;
        NSString* effectiveReason = reason;
        if (wasClean && (code == PSWebSocketStatusCodeNormal || code == 0)) {
            // Clean shutdown with no error/status:
            if (!_running) {
                // I closed the connection, so this is expected.
                LogTo(ChangeTracker, @"%@: closed", self);
                [self stop];
                return; // without reporting error

            } else {
                // Server closed the connection. It shouldn't do this unless it's going offline
                // or something; treat this as an (non-fatal) error.
                LogTo(ChangeTracker, @"%@: closed unexpectedly", self);
                effectiveCode = 503; // Service Unavailable
                if (!effectiveReason)
                    effectiveReason = @"Server closed connection";
            }
        }

        // Report error:
        LogTo(ChangeTracker, @"%@: closed with code %ld, reason '%@'",
              self, (long)effectiveCode, effectiveReason);
        [self failedWithErrorDomain: PSWebSocketErrorDomain code: effectiveCode
                            message: effectiveReason];
    });
}



@end
