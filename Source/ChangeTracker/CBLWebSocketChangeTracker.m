//
//  CBLWebSocketChangeTracker.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 11/12/13.
//
//

#import "CBLWebSocketChangeTracker.h"
#import "CBLAuthorizer.h"
#import "WebSocketClient.h"
#import "CBLMisc.h"
#import "MYBlockUtils.h"


#define kMaxPendingMessages 2


@interface CBLWebSocketChangeTracker () <WebSocketDelegate>
@end


@implementation CBLWebSocketChangeTracker
{
    NSThread* _thread;
    WebSocketClient* _ws;
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
    [super start];

    // A WebSocket has to be opened with a GET request, not a POST (as defined in the RFC.)
    // Instead of putting the options in the POST body as with HTTP, we will send them in an
    // initial WebSocket message, in -webSocketDidOpen:, below.
    NSURL* url = self.changesFeedURL;
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL: url];
    request.timeoutInterval = _heartbeat * 1.5;

    // Add headers from my .requestHeaders property:
    [self.requestHeaders enumerateKeysAndObjectsUsingBlock: ^(id key, id value, BOOL *stop) {
        [request setValue: value forHTTPHeaderField: key];
    }];

    if (_authorizer) {
        // Let the Authorizer add its own credential:
        NSString* authHeader = [_authorizer authorizeURLRequest: request forRealm: nil];
        if (authHeader)
            [request setValue: authHeader forHTTPHeaderField: @"Authorization"];
    }

    LogTo(SyncVerbose, @"%@: %@ %@", self, request.HTTPMethod, url.resourceSpecifier);
    _ws = [[WebSocketClient alloc] initWithURLRequest: request];
    _ws.delegate = self;
    [_ws useTLS: self.TLSSettings];
    NSError* error;
    if (![_ws connect: &error]) {
        self.error = error;
        _ws = nil;
        return NO;
    }
    _thread = [NSThread currentThread];
    _running = YES;
    _caughtUp = NO;
    _startTime = CFAbsoluteTimeGetCurrent();
    _pendingMessageCount = 0;
    LogTo(ChangeTracker, @"%@: Started... <%@>", self, url);
    return YES;
}


- (void) stop {
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(start)
                                               object: nil];    // cancel pending retries
    if (_ws) {
        LogTo(ChangeTracker, @"%@: stop", self);
        _running = NO; // don't want to receive any more messages
        [_ws disconnect];
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

- (void) webSocket: (WebSocket*)ws didSecureWithTrust: (SecTrustRef)trust atURL:(NSURL *)url {
    MYOnThread(_thread, ^{
        [self checkServerTrust: trust forURL: url];
    });
}

- (void) webSocketDidOpen: (WebSocket *)ws {
    MYOnThread(_thread, ^{
        LogTo(ChangeTrackerVerbose, @"%@: WebSocket opened", self);
        _retryCount = 0;
        // Now that the WebSocket is open, send the changes-feed options (the ones that would have
        // gone in the POST body if this were HTTP-based.)
        [ws sendBinaryMessage: self.changesFeedPOSTBody];
    });
}

/** Called when a WebSocket receives a textual message from its peer. */
- (BOOL) webSocket: (WebSocket *)ws
         didReceiveMessage: (NSString *)msg
{
    MYOnThread(_thread, ^{
        LogTo(ChangeTrackerVerbose, @"%@: Got a message: %@", self, msg);
        if (msg.length > 0 && ws == _ws && _running) {
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
                [_ws closeWithCode: kWebSocketCloseDataError reason: @"Unparseable change entry"];
            }
        }
        OSAtomicDecrement32Barrier(&_pendingMessageCount);
        [self setPaused: self.paused]; // this will resume the WebSocket unless self.paused
    });
    // Tell the WebSocket to pause its reader if too many messages are waiting to be processed:
    return (OSAtomicIncrement32Barrier(&_pendingMessageCount) < kMaxPendingMessages);
}

/** Called after the WebSocket closes, either intentionally or due to an error. */
- (void) webSocket:(WebSocket *)ws
         didCloseWithError: (NSError*)error
{
    MYOnThread(_thread, ^{
        if (ws != _ws)
            return;
        _ws = nil;
        if (error == nil) {
            LogTo(ChangeTracker, @"%@: closed", self);
            [self stop];
        } else {
            [self failedWithError: error];
        }
    });
}



@end
