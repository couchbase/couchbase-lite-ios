//
//  CBLSocketChangeTracker.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/2/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
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

#import "CBLSocketChangeTracker.h"
#import "CBLRemoteRequest.h"
#import "CBLAuthorizer.h"
#import "CBLCookieStorage.h"
#import "CBLStatus.h"
#import "CBLBase64.h"
#import "MYBlockUtils.h"
#import "MYURLUtils.h"
#import "WebSocketHTTPLogic.h"
#import <string.h>


#define kReadLength 4096u


@implementation CBLSocketChangeTracker
{
    WebSocketHTTPLogic* _http;
    NSInputStream* _trackingInput;
    CFAbsoluteTime _startTime;
    bool _gotResponseHeaders;
    bool _readyToRead;
}

- (BOOL) start {
    if (_trackingInput)
        return NO;

    LogTo(ChangeTracker, @"%@: Starting...", self);
    [super start];

    NSURL* url = self.changesFeedURL;

    if (!_http) {
        NSMutableURLRequest* urlRequest = [NSMutableURLRequest requestWithURL: url];
        if (self.usePOST) {
            urlRequest.HTTPMethod = @"POST";
            urlRequest.HTTPBody = self.changesFeedPOSTBody;
            [urlRequest setValue: @"application/json" forHTTPHeaderField: @"Content-Type"];
        }

        for (NSString* key in self.requestHeaders) {
            if ([key caseInsensitiveCompare: @"Cookie"] == 0) {
                urlRequest.HTTPShouldHandleCookies = NO;
                break;
            }
        }

        if (urlRequest.HTTPShouldHandleCookies) {
            [self.cookieStorage addCookieHeaderToRequest: urlRequest];
        }

        _http = [[WebSocketHTTPLogic alloc] initWithURLRequest: urlRequest];

        // Add headers from my .requestHeaders property:
        [self.requestHeaders enumerateKeysAndObjectsUsingBlock: ^(id key, id value, BOOL *stop) {
            _http[key] = value;
        }];
    }

    CFHTTPMessageRef request = [_http newHTTPRequest];

    if (_authorizer && !_http.credential) {
        // Let the Authorizer add its own credential:
        NSString* authHeader = [_authorizer authorizeHTTPMessage: request forRealm: nil];
        if (authHeader)
            CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Authorization"),
                                             (__bridge CFStringRef)(authHeader));
    }

    // Now open the connection:
    LogTo(SyncVerbose, @"%@: %@ %@", self, (self.usePOST ?@"POST" :@"GET"), url.resourceSpecifier);
    CFReadStreamRef cfInputStream = CFReadStreamCreateForHTTPRequest(NULL, request);
    CFRelease(request);
    if (!cfInputStream)
        return NO;

    CFReadStreamSetProperty(cfInputStream, kCFStreamPropertyHTTPShouldAutoredirect, kCFBooleanTrue);
    _http.handleRedirects = NO;  // CFStream will handle redirects instead

    // Configure HTTP proxy -- CFNetwork makes us do this manually, unlike NSURLConnection :-p
    NSDictionary* proxy = url.my_proxySettings;
    if (proxy) {
        LogTo(ChangeTracker, @"Changes feed using proxy %@", proxy);
        bool ok = CFReadStreamSetProperty(cfInputStream, kCFStreamPropertyHTTPProxy,
                                          (CFDictionaryRef)proxy);
        Assert(ok);
    }

    NSDictionary* tls = self.TLSSettings;
    if (tls)
        CFReadStreamSetProperty(cfInputStream, kCFStreamPropertySSLSettings, (CFTypeRef)tls);

    _gotResponseHeaders = false;
    _readyToRead = NO;

    _trackingInput = (NSInputStream*)CFBridgingRelease(cfInputStream);
    [_trackingInput setDelegate: self];
    [_trackingInput scheduleInRunLoop: [NSRunLoop currentRunLoop] forMode: NSRunLoopCommonModes];
    [_trackingInput open];
    _startTime = CFAbsoluteTimeGetCurrent();
    LogTo(ChangeTracker, @"%@: Started... <%@>", self, url.my_sanitizedString);
    return YES;
}


- (void) clearConnection {
    [_trackingInput close];
    [_trackingInput removeFromRunLoop: [NSRunLoop currentRunLoop] forMode: NSRunLoopCommonModes];
    _trackingInput = nil;
}


- (void) stop {
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(start)
                                               object: nil];    // cancel pending retries
    if (_trackingInput) {
        LogTo(ChangeTracker, @"%@: stop", self);
        [self clearConnection];
    }
    [super stop];
}


#pragma mark - SSL & AUTHORIZATION:


- (BOOL) checkSSLCert {
    BOOL trusted = YES;
    SecTrustRef sslTrust = (SecTrustRef) CFReadStreamCopyProperty((CFReadStreamRef)_trackingInput,
                                                                  kCFStreamPropertySSLPeerTrust);
    if (sslTrust) {
        NSURL* url = CFBridgingRelease(CFReadStreamCopyProperty((CFReadStreamRef)_trackingInput,
                                                                kCFStreamPropertyHTTPFinalURL));

        trusted = [self checkServerTrust: sslTrust forURL: url];
        CFRelease(sslTrust);
    }
    return trusted;
}


- (BOOL) readResponseHeader {
    CFHTTPMessageRef response;
    response = (CFHTTPMessageRef) CFReadStreamCopyProperty((CFReadStreamRef)_trackingInput,
                                                           kCFStreamPropertyHTTPResponseHeader);
    Assert(response);
    _gotResponseHeaders = true;
    [_http receivedResponse: response];
    CFRelease(response);

    if (_http.shouldContinue) {
        _retryCount = 0;
        _http = nil;
        return YES;
    } else if (_http.shouldRetry) {
        [self clearConnection];
        [self retry];
        return NO;
    } else {
        NSError* error = _http.error ?: CBLStatusToNSError(_http.httpStatus, _http.URL);
        [self failedWithError: error];
        return NO;
    }
}


- (void) setPaused:(BOOL)paused {
    if (paused != super.paused)
        LogTo(ChangeTracker, @"%@: %@", self, (paused ? @"PAUSE" : @"RESUME"));
    [super setPaused: paused];
    if (!paused && _readyToRead)
        [self readFromInput];
}


#pragma mark - STREAM HANDLING:


- (void) readFromInput {
    Assert(_readyToRead);
    _readyToRead = false;
    uint8_t buffer[kReadLength];
    NSInteger bytesRead = [_trackingInput read: buffer maxLength: sizeof(buffer)];
    if (bytesRead > 0)
        [self parseBytes: buffer length: bytesRead];
}


- (void) handleEOF {
    if (!_gotResponseHeaders) {
        [self failedWithError: [NSError errorWithDomain: NSURLErrorDomain
                                                   code: NSURLErrorNetworkConnectionLost
                                               userInfo: nil]];
        return;
    }
    if (_mode == kContinuous) {
        [self stop];
    } else if ([self endParsingData] >= 0) {
        // Successfully reached end.
        id<CBLChangeTrackerClient> client = _client;
        if (!_caughtUp) {
            _caughtUp = YES;
            [client changeTrackerCaughtUp];
        }
        [self clearConnection];
        if (_continuous) {
            if (_mode == kOneShot && _pollInterval == 0.0)
                _mode = kLongPoll;
            if (_pollInterval > 0.0)
                LogTo(ChangeTracker, @"%@: Next poll of _changes feed in %g sec...",
                      self, _pollInterval);
            [self retryAfterDelay: _pollInterval];       // Next poll...
        } else {
            [client changeTrackerFinished];
            [self stopped];
        }
    } else {
        // JSON must have been truncated, probably due to socket being closed early.
        if (_mode == kOneShot) {
            [self failedWithError: [NSError errorWithDomain: NSURLErrorDomain
                                                       code: NSURLErrorNetworkConnectionLost
                                                   userInfo: nil]];
            return;
        }
        NSTimeInterval elapsed = CFAbsoluteTimeGetCurrent() - _startTime;
        Warn(@"%@: Longpoll connection closed (by proxy?) after %.1f sec", self, elapsed);
        if (elapsed >= 30.0) {
            // Looks like the connection got closed by a proxy (like AWS' load balancer) while the
            // server was waiting for a change to send, due to lack of activity.
            // Lower the heartbeat time to work around this, and reconnect:
            self.heartbeat = MIN(_heartbeat, elapsed * 0.75);
            [self clearConnection];
            [self start];       // Next poll...
        } else {
            // Response data was truncated. This has been reported as an intermittent error
            // (see TouchDB issue #241). Treat it as if it were a socket error -- i.e. pause/retry.
            [self failedWithError: [NSError errorWithDomain: NSURLErrorDomain
                                                       code: NSURLErrorNetworkConnectionLost
                                                   userInfo: nil]];
        }
    }
}


- (void) failedWithError:(NSError*) error {
    [self clearConnection];
    [super failedWithError: error];
}


- (void) stream: (NSStream*)stream handleEvent: (NSStreamEvent)eventCode {
    __unused id keepMeAround = self; // retain myself so I can't be dealloced during this method
    switch (eventCode) {
        case NSStreamEventHasBytesAvailable: {
            LogTo(ChangeTrackerVerbose, @"%@: HasBytesAvailable %@", self, stream);
            if (!_gotResponseHeaders) {
                if (![self checkSSLCert] || ![self readResponseHeader])
                    return;
            }
            _readyToRead = true;
            if (!self.paused)
                [self readFromInput];
            break;
        }
            
        case NSStreamEventEndEncountered:
            LogTo(ChangeTracker, @"%@: EndEncountered %@", self, stream);
            [self handleEOF];
            break;
            
        case NSStreamEventErrorOccurred:
            [self failedWithError: stream.streamError];
            break;
            
        default:
            LogTo(ChangeTracker, @"%@: Event %lx on %@", self, (long)eventCode, stream);
            break;
    }
}


@end
