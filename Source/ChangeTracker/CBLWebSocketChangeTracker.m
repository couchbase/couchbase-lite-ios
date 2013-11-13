//
//  CBLWebSocketChangeTracker.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 11/12/13.
//
//

#import "CBLWebSocketChangeTracker.h"
#import "WebSocketClient.h"
#import "MYBlockUtils.h"


@interface CBLWebSocketChangeTracker () <WebSocketDelegate>
@end


@implementation CBLWebSocketChangeTracker
{
    NSThread* _thread;
    WebSocketClient* _ws;
    CFAbsoluteTime _startTime;
}


- (BOOL) start {
    if (_ws)
        return NO;
    LogTo(ChangeTracker, @"%@: Starting...", self);
    [super start];

    NSURL* url = self.changesFeedURL;
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL: url];
    request.timeoutInterval = _heartbeat * 1.5;

    // Add headers from my .requestHeaders property:
    [self.requestHeaders enumerateKeysAndObjectsUsingBlock: ^(id key, id value, BOOL *stop) {
        [request setValue: value forHTTPHeaderField: key];
    }];

    // Add cookie headers from the NSHTTPCookieStorage:
    NSArray* cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL: url];
    NSDictionary* cookieHeaders = [NSHTTPCookie requestHeaderFieldsWithCookies: cookies];
    for (NSString* headerName in cookieHeaders)
        [request addValue: cookieHeaders[headerName] forHTTPHeaderField: headerName];

    // TODO: Authorization

    LogTo(SyncVerbose, @"%@: GET %@", self, url.resourceSpecifier);
    _ws = [[WebSocketClient alloc] initWithURLRequest: request];
    _ws.delegate = self;
    NSError* error;
    if (![_ws connect: &error]) {
        self.error = error;
        _ws = nil;
        return NO;
    }
    _thread = [NSThread currentThread];
    _startTime = CFAbsoluteTimeGetCurrent();
    LogTo(ChangeTracker, @"%@: Started... <%@>", self, url);
    return YES;
}


- (void) stop {
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(start)
                                               object: nil];    // cancel pending retries
    if (_ws) {
        LogTo(ChangeTracker, @"%@: stop", self);
        [_ws disconnect];
    }
    [super stop];
}


#pragma mark - WEBSOCKET DELEGATE API:

// THESE ARE CALLED ON THE WEBSOCKET'S DISPATCH QUEUE, NOT MY THREAD!!

/** Called when a WebSocket receives a textual message from its peer. */
- (void) webSocket:(WebSocket *)ws
         didReceiveMessage:(NSString *)msg
{
    MYOnThread(_thread, ^{
        LogTo(ChangeTrackerVerbose, @"Got a message: %@", msg);
        if (msg.length > 0) {
            NSData *data = [msg dataUsingEncoding: NSUTF8StringEncoding];
            if (![self parseBytes: data.bytes length: data.length] || ![self endParsingData]) {
                Warn(@"Couldn't parse message: %@", msg);
                [_ws closeWithCode: kWebSocketCloseDataError reason: @"Unparseable change entry"];
            }
        }
    });
}

/** Called after the WebSocket closes, either intentionally or due to an error. */
- (void) webSocket:(WebSocket *)ws
  didCloseWithCode: (WebSocketCloseCode)code
            reason: (NSString*)reason
{
    MYOnThread(_thread, ^{
        _ws = nil;
        if (code == kWebSocketCloseNormal) {
            LogTo(ChangeTracker, @"%@: closed", self);
            [self stop];
        } else {
            LogTo(ChangeTracker, @"%@: disconnected with error %d / %@", self, code, reason);
            NSDictionary* info = $dict({NSLocalizedFailureReasonErrorKey, reason});
            NSError* error = [NSError errorWithDomain: @"WebSocket"
                                                 code: code
                                             userInfo: info];
            [self failedWithError: error];
        }
    });
}



@end
