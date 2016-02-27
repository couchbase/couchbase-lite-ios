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
#import "CBLMisc.h"
#import "CBLStatus.h"
#import "CBLBase64.h"
#import "CBLGZip.h"
#import "MYBlockUtils.h"
#import "MYErrorUtils.h"
#import "MYURLUtils.h"
#import "BLIPHTTPLogic.h"
#import <string.h>


UsingLogDomain(SyncPerf);
UsingLogDomain(Sync);


#define kReadLength 4096u


@implementation CBLSocketChangeTracker
{
    NSInputStream* _trackingInput;
    CFAbsoluteTime _startTime;
    CBLGZip* _gzip;
    bool _gotResponseHeaders;
    bool _readyToRead;
    NSString* _serverName;
}

- (BOOL) start {
    if (_trackingInput)
        return NO;

    LogTo(ChangeTracker, @"%@: Starting...", self);
    [super start];

    NSURL* url = self.changesFeedURL;

    CFHTTPMessageRef request = [_http newHTTPRequest];
    CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Accept-Encoding"), CFSTR("gzip"));

    // Now open the connection:
    LogTo(SyncPerf, @"%@: %@ %@", self, (_usePOST ?@"POST" :@"GET"), url.resourceSpecifier);
    LogVerbose(Sync, @"%@: %@ %@", self, (_usePOST ?@"POST" :@"GET"), url.resourceSpecifier);
    CFReadStreamRef cfInputStream = CFReadStreamCreateForHTTPRequest(NULL, request);
    CFRelease(request);
    if (!cfInputStream)
        return NO;

    CFReadStreamSetProperty(cfInputStream, kCFStreamPropertyHTTPShouldAutoredirect, kCFBooleanTrue);
    _http.handleRedirects = NO;  // CFStream will handle redirects instead

    // Configure HTTP proxy -- CFNetwork makes us do this manually, unlike NSURLConnection :-p
    CFDictionaryRef proxySettings = CFNetworkCopySystemProxySettings();
    if (proxySettings) {
        LogTo(ChangeTracker, @"Changes feed using proxy settings %@", proxySettings);
        __unused Boolean ok = CFReadStreamSetProperty(cfInputStream, kCFStreamPropertyHTTPProxy, proxySettings);
        Assert(ok);
        CFRelease(proxySettings);
    }

    NSDictionary* tls = self.TLSSettings;
    if (tls)
        CFReadStreamSetProperty(cfInputStream, kCFStreamPropertySSLSettings, (CFTypeRef)tls);

    _gotResponseHeaders = false;
    _readyToRead = NO;
    _gzip = nil;
    _serverName = nil;

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
        if (!trusted) {
            //TODO: This error could be made more precise
            LogTo(ChangeTracker, @"%@: Untrustworthy SSL certificate", self);
            [self failedWithErrorDomain: NSURLErrorDomain
                                   code: NSURLErrorServerCertificateUntrusted
                                message: @"Untrustworthy SSL certificate"];
        }
    }
    return trusted;
}


- (BOOL) readResponseHeader {
    CFHTTPMessageRef response;
    response = (CFHTTPMessageRef) CFReadStreamCopyProperty((CFReadStreamRef)_trackingInput,
                                                           kCFStreamPropertyHTTPResponseHeader);
    if (!response) {
        [self failedWithErrorDomain: NSURLErrorDomain code: NSURLErrorNetworkConnectionLost
                            message: @"Connection lost"];
        return NO;
    }
    CFAutorelease(response);
    _gotResponseHeaders = true;
    LogTo(SyncPerf, @"%@ got HTTP response headers (%ld) after %.3f sec",
          self, CFHTTPMessageGetResponseStatusCode(response), CFAbsoluteTimeGetCurrent()-_startTime);

    _serverName = CFBridgingRelease(CFHTTPMessageCopyHeaderFieldValue(response,
                                                                      CFSTR("Server")));
    NSString* encoding = CFBridgingRelease(CFHTTPMessageCopyHeaderFieldValue(response,
                                                                    CFSTR("Content-Encoding")));
    BOOL compressed = [encoding isEqualToString: @"gzip"];

    [_http receivedResponse: response];
    if (_http.shouldContinue) {
        _retryCount = 0;
        _http = nil;
        if (compressed)
            _gzip = [[CBLGZip alloc] initForCompressing: NO];
        NSDictionary* headers = CFBridgingRelease(CFHTTPMessageCopyAllHeaderFields(response));
        [_client changeTrackerReceivedHTTPHeaders: headers];
        return YES;
    } else if (_http.shouldRetry) {
        [self clearConnection];
        [self retry];
        return NO;
    } else {
        NSError* error = _http.error ?: CBLStatusToNSErrorWithInfo(_http.httpStatus,
                                                                   nil, _http.URL, nil);
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


- (BOOL) readGzippedBytes: (const void*)bytes length: (size_t)length {
    __weak CBLSocketChangeTracker* weakSelf = self;
    BOOL ok = [_gzip addBytes: bytes
                       length: length
                     onOutput: ^(const void *decompressedBytes, size_t decompressedLength) {
        [weakSelf parseBytes: decompressedBytes length: decompressedLength];
    }];
    if (!ok) {
        [self failedWithErrorDomain: @"zlib" code:_gzip.status
                            message: @"Invalid gzipped response data"];
    }
    return ok;
}


- (void) readFromInput {
    Assert(_readyToRead);
    _readyToRead = false;
    uint8_t buffer[kReadLength];
    while (_trackingInput.hasBytesAvailable) {
        NSInteger bytesRead = [_trackingInput read: buffer maxLength: sizeof(buffer)];
        if (bytesRead > 0) {
            if (_gzip)
                [self readGzippedBytes: buffer length: bytesRead];
            else
                [self parseBytes: buffer length: bytesRead];
        }
    }
}


- (void) handleEOF {
    if (!_gotResponseHeaders) {
        [self readResponseHeader];
        if (!_gotResponseHeaders)
            return;
    }
    self.paused = NO;   // parse any incoming bytes that have been waiting
    if (_gzip) {
        [self readGzippedBytes: NULL length: 0]; // flush gzip decoder
        _gzip = nil;
    }
    LogTo(SyncPerf, @"%@ reached EOF after %.3f sec", self, CFAbsoluteTimeGetCurrent()-_startTime);
    if (_mode == kContinuous || _error) {
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
            [self failedWithErrorDomain: NSURLErrorDomain code: NSURLErrorNetworkConnectionLost
                                message: @"Truncated response received"];
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
            [self failedWithErrorDomain: NSURLErrorDomain code: NSURLErrorNetworkConnectionLost
                                                 message: @"Truncated response received"];
        }
    }
}


- (void) failedWithError:(NSError*) error {
    [self clearConnection];

    // Work around Cloudant's lack of support of POST to _changes. a 405 (Method Not Allowed) is
    // a dead giveaway, but Cloudant returns a 401 instead if the database is write-protected.
    // This could also happen with a read-protected SG or CouchDB database, so if we get a 401
    // double-check that it's Cloudant. (See issue #1020.)
    if (_usePOST) {
        if ([error my_hasDomain: CBLHTTPErrorDomain code: kCBLStatusMethodNotAllowed]
            || ([error my_hasDomain: NSURLErrorDomain code: NSURLErrorUserAuthenticationRequired]
                    && [_serverName rangeOfString: @"CouchDB/1.0.2"].length > 0)) {
                LogTo(ChangeTracker, @"Apparently server is Cloudant; retrying with a GET...");
                _usePOST = NO;
                _http = nil;
                [self retryAfterDelay: 0.0];
                return;
            }
    }

    [super failedWithError: error];
}


- (void) stream: (NSStream*)stream handleEvent: (NSStreamEvent)eventCode {
    __unused id keepMeAround = self; // retain myself so I can't be dealloced during this method
    switch (eventCode) {
        case NSStreamEventHasBytesAvailable: {
            LogVerbose(ChangeTracker, @"%@: HasBytesAvailable %@", self, stream);
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
