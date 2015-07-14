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
#import "MYBlockUtils.h"
#import <libkern/OSAtomic.h>


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
    self.usePOST = NO;

    [super start];

    NSMutableURLRequest* request = [[_http URLRequest] mutableCopy];
    request.timeoutInterval = _heartbeat * 1.5;

    LogTo(SyncVerbose, @"%@: %@ %@", self, request.HTTPMethod, request.URL.resourceSpecifier);
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
        LogTo(ChangeTrackerVerbose, @"%@: WebSocket opened", self);
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
                    LogTo(ChangeTrackerVerbose, @"%@ got HTTP response %ld, retrying...",
                          self, (long)status);
                    [self retry];
                    return;
                }
                // Failed, but map the error back to HTTP:
                NSString* message = CFBridgingRelease(CFHTTPMessageCopyResponseStatusLine(response));
                if (message.length == 0)
                    message = error.localizedDescription;
                NSString* urlStr = webSocket.URLRequest.URL.absoluteString;
                myError = [NSError errorWithDomain: CBLHTTPErrorDomain
                                              code: status
                                          userInfo: @{NSLocalizedDescriptionKey: message,
                                                      NSUnderlyingErrorKey: error,
                                                      NSURLErrorFailingURLStringErrorKey: urlStr}];
            } else {
                // Map HTTP errors to my own error domain:
                NSNumber* status = error.userInfo[PSHTTPStatusErrorKey];
                if (status) {
                    myError = CBLStatusToNSErrorWithInfo((CBLStatus)status.integerValue, nil,
                                                       self.changesFeedURL, nil);
                }
            }
        }
        [self failedWithError: myError];
    });
}

/** Called when a WebSocket receives a textual message from its peer. */
- (void) webSocket: (PSWebSocket*)ws didReceiveMessage: (id)msg {
    if (![msg isKindOfClass: [NSString class]]) {
        Warn(@"Unhandled binary message");
        [_ws closeWithCode: PSWebSocketStatusCodeUnhandledType reason: @"Unknown message"];
        return;
    }
    MYOnThread(_thread, ^{
        LogTo(ChangeTrackerVerbose, @"%@: Got a message: %@", self, msg);
        if ([msg length] > 0 && ws == _ws && _running) {
            NSData *data = [msg dataUsingEncoding: NSUTF8StringEncoding];
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
        if (wasClean && (code == PSWebSocketStatusCodeNormal || code == 0)) {
            LogTo(ChangeTracker, @"%@: closed", self);
            [self stop];
        } else {
            NSDictionary* userInfo = $dict({NSLocalizedFailureReasonErrorKey, reason},
                                           {NSURLErrorFailingURLStringErrorKey,
                                               self.changesFeedURL.absoluteString});
            NSError* error = [NSError errorWithDomain: PSWebSocketErrorDomain code: code
                                             userInfo: userInfo];
            [self failedWithError: error];
        }
    });
}



@end
