//
//  TDSocketChangeTracker.m
//  TouchDB
//
//  Created by Jens Alfke on 12/2/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
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

#import "TDSocketChangeTracker.h"
#import "TDRemoteRequest.h"
#import "TDAuthorizer.h"
#import "TDStatus.h"
#import "TDBase64.h"
#import "MYBlockUtils.h"
#import "MYURLUtils.h"
#import <string.h>


#define kMaxRetries 6
#define kInitialRetryDelay 0.2
#define kReadLength 8192u


@implementation TDSocketChangeTracker


- (BOOL) start {
    NSAssert(!_trackingInput, @"Already started");

    LogTo(ChangeTracker, @"%@: Starting...", self);
    [super start];
    
    CFHTTPMessageRef request = CFHTTPMessageCreateRequest(NULL, CFSTR("GET"),
                                                          (__bridge CFURLRef)self.changesFeedURL,
                                                          kCFHTTPVersion1_1);
    Assert(request);
    
    // Add headers.
    [self.requestHeaders enumerateKeysAndObjectsUsingBlock: ^(id key, id value, BOOL *stop) {
        CFHTTPMessageSetHeaderFieldValue(request, (__bridge CFStringRef)key, (__bridge CFStringRef)value);
    }];
    
    if (_unauthResponse && _credential) {
        NSString* password = _credential.password;
        if (password) {
            CFIndex unauthStatus = CFHTTPMessageGetResponseStatusCode(_unauthResponse);
            Assert(CFHTTPMessageAddAuthentication(request, _unauthResponse,
                                                  (__bridge CFStringRef)_credential.user,
                                                  (__bridge CFStringRef)password,
                                                  kCFHTTPAuthenticationSchemeBasic,
                                                  unauthStatus == 407));
        } else {
            Warn(@"%@: Unable to get password of %@", self, _credential);
        }
    } else if (_authorizer) {
        NSString* authHeader = [_authorizer authorizeHTTPMessage: request forRealm: nil];
        if (authHeader)
            CFHTTPMessageSetHeaderFieldValue(request, CFSTR("Authorization"),
                                             (__bridge CFStringRef)(authHeader));
    }

    CFReadStreamRef cfInputStream = CFReadStreamCreateForHTTPRequest(NULL, request);
    CFRelease(request);
    if (!cfInputStream)
        return NO;
    CFReadStreamSetProperty(cfInputStream, kCFStreamPropertyHTTPShouldAutoredirect, kCFBooleanTrue);
    if (_databaseURL.my_isHTTPS) {
        // Enable SSL for this connection.
        // Disable TLS 1.2 support because it breaks compatibility with some SSL servers;
        // workaround taken from Apple technote TN2287:
        // http://developer.apple.com/library/ios/#technotes/tn2287/
        NSDictionary *settings = $dict({(id)kCFStreamSSLLevel,
                                        @"kCFStreamSocketSecurityLevelTLSv1_0SSLv3"});
        CFReadStreamSetProperty(cfInputStream,
                                kCFStreamPropertySSLSettings, (CFTypeRef)settings);
    }
    
    _gotResponseHeaders = _atEOF = _inputAvailable = _parsing = false;
    
    _inputBuffer = [[NSMutableData alloc] initWithCapacity: kReadLength];
    
    _trackingInput = (NSInputStream*)CFBridgingRelease(cfInputStream);
    [_trackingInput setDelegate: self];
    [_trackingInput scheduleInRunLoop: [NSRunLoop currentRunLoop] forMode: NSRunLoopCommonModes];
    [_trackingInput open];
    _startTime = CFAbsoluteTimeGetCurrent();
    LogTo(ChangeTracker, @"%@: Started... <%@>", self, self.changesFeedURL);
    return YES;
}


- (void) clearConnection {
    [_trackingInput close];
    _trackingInput = nil;
    _inputBuffer = nil;
    _changeBuffer = nil;
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


- (void)dealloc
{
    if (_unauthResponse) CFRelease(_unauthResponse);
}


#pragma mark - SSL & AUTHORIZATION:


- (BOOL) checkSSLCert {
    SecTrustRef sslTrust = (SecTrustRef) CFReadStreamCopyProperty((CFReadStreamRef)_trackingInput,
                                                                  kCFStreamPropertySSLPeerTrust);
    if (sslTrust) {
        NSURL* url = CFBridgingRelease(CFReadStreamCopyProperty((CFReadStreamRef)_trackingInput,
                                                                kCFStreamPropertyHTTPFinalURL));
        BOOL trusted = [TDRemoteRequest checkTrust: sslTrust forHost: url.host];
        CFRelease(sslTrust);
        if (!trusted) {
            //TODO: This error could be made more precise
            self.error = [NSError errorWithDomain: NSURLErrorDomain
                                             code: NSURLErrorServerCertificateUntrusted
                                         userInfo: nil];
            return NO;
        }
    }
    return YES;
}


- (NSURLCredential*) credentialForResponse: (CFHTTPMessageRef)response {
    NSString* realm;
    NSString* authenticationMethod;
    
    // Basic & digest auth: http://www.ietf.org/rfc/rfc2617.txt
    NSString* authHeader = CFBridgingRelease(CFHTTPMessageCopyHeaderFieldValue(response,
                                                                       CFSTR("WWW-Authenticate")));
    if (!authHeader)
        return nil;
    
    // Get the auth type:
    if ([authHeader hasPrefix: @"Basic"])
        authenticationMethod = NSURLAuthenticationMethodHTTPBasic;
    else if ([authHeader hasPrefix: @"Digest"])
        authenticationMethod = NSURLAuthenticationMethodHTTPDigest;
    else
        return nil;
    
    // Get the realm:
    NSRange r = [authHeader rangeOfString: @"realm=\""];
    if (r.length == 0)
        return nil;
    NSUInteger start = NSMaxRange(r);
    r = [authHeader rangeOfString: @"\"" options: 0
                            range: NSMakeRange(start, authHeader.length - start)];
    if (r.length == 0)
        return nil;
    realm = [authHeader substringWithRange: NSMakeRange(start, r.location - start)];
    
    NSURLCredential* cred;
    cred = [_databaseURL my_credentialForRealm: realm authenticationMethod: authenticationMethod];
    if (!cred.hasPassword)
        cred = nil;     // TODO: Add support for client certs
    return cred;
}


- (BOOL) readResponseHeader {
    CFHTTPMessageRef response;
    response = (CFHTTPMessageRef) CFReadStreamCopyProperty((CFReadStreamRef)_trackingInput,
                                                           kCFStreamPropertyHTTPResponseHeader);
    Assert(response);
    _gotResponseHeaders = true;

    // Handle authentication failure (401 or 407 status):
    CFIndex status = CFHTTPMessageGetResponseStatusCode(response);
    LogTo(ChangeTracker, @"%@ got status %ld", self, status);
    if ((status == 401 || status == 407) && !_credential
                                         && ![_requestHeaders objectForKey: @"Authorization"]) {
        _credential = [self credentialForResponse: response];
        LogTo(ChangeTracker, @"%@: Auth challenge; credential = %@", self, _credential);
        if (_credential) {
            // Recoverable auth failure -- try again with _credential:
            _unauthResponse = response;
            [self errorOccurred: TDStatusToNSError((TDStatus)status, self.changesFeedURL)];
            return NO;
        }
    }

    CFRelease(response);
    if (status >= 300) {
        self.error = TDStatusToNSError(status, self.changesFeedURL);
        [self stop];
        return NO;
    }
    _retryCount = 0;
    return YES;
}


#pragma mark - REGULAR-MDOE PARSING:


- (void) readEntireInput {
    // After one-shot or longpoll response is complete, parse it as a single JSON document:
    NSData* input = _inputBuffer;
    LogTo(ChangeTracker, @"%@: Got entire body, %u bytes", self, (unsigned)input.length);
    BOOL restart = NO;
    NSString* errorMessage = nil;
    NSInteger numChanges = [self receivedPollResponse: input errorMessage: &errorMessage];
    if (numChanges < 0) {
        // Oops, unparseable response:
        restart = [self checkInvalidResponse: input];
        if (!restart)
            [self setUpstreamError: errorMessage];
    } else {
        // Poll again if there was no error, and either we're in longpoll mode or it looks like we
        // ran out of changes due to a _limit rather than because we hit the end.
        restart = _mode == kLongPoll || numChanges == (NSInteger)_limit;
    }
    
    [self clearConnection];

    if (restart)
        [self start];       // Next poll...
    else
        [self stopped];
}


- (BOOL) checkInvalidResponse: (NSData*)body {
    NSString* bodyStr = [[body my_UTF8ToString] stringByTrimmingCharactersInSet:
                                              [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (_mode == kLongPoll && $equal(bodyStr, @"{\"results\":[")) {
        // Looks like the connection got closed by a proxy (like AWS' load balancer) before
        // the server had an actual change to send.
        NSTimeInterval elapsed = CFAbsoluteTimeGetCurrent() - _startTime;
        Warn(@"%@: Longpoll connection closed (by proxy?) after %.1f sec", self, elapsed);
        if (elapsed >= 30.0) {
            self.heartbeat = MIN(_heartbeat, elapsed * 0.75);
            return YES;  // should restart connection
        }
    } else if (bodyStr) {
        Warn(@"%@: Unparseable response:\n%@", self, bodyStr);
    } else {
        Warn(@"%@: Response is invalid UTF-8; as CP1252:\n%@", self,
             [[NSString alloc] initWithData: body encoding: NSWindowsCP1252StringEncoding]);
    }
    return NO;
}


#pragma mark - CONTINUOUS-MODE PARSING:


- (void) readLines {
    Assert(_gotResponseHeaders && _mode==kContinuous);
    NSMutableArray* changes = $marray();
    const char* pos = _inputBuffer.bytes;
    const char* end = pos + _inputBuffer.length;
    while (pos < end && _inputBuffer) {
        const char* eol = memchr(pos, '\n', end-pos);
        if (!eol)
            break;  // Wait till we have a complete line
        ptrdiff_t lineLength = eol - pos;
        if (lineLength > 0)
            [changes addObject: [NSData dataWithBytes: pos length: lineLength]];
        pos = eol + 1;
    }
    
    // Remove the parsed lines:
    [_inputBuffer replaceBytesInRange: NSMakeRange(0, pos - (const char*)_inputBuffer.bytes)
                            withBytes: NULL length: 0];
    
    if (changes.count > 0)
        [self asyncParseChangeLines: changes];
}


- (void) asyncParseChangeLines: (NSArray*)lines {
    static NSOperationQueue* sParseQueue;
    if (!sParseQueue)
        sParseQueue = [[NSOperationQueue alloc] init];
    
    LogTo(ChangeTracker, @"%@: Async parsing %u changes...", self, (unsigned)lines.count);
    Assert(!_parsing);
    _parsing = true;
    NSThread* resultThread = [NSThread currentThread];
    [sParseQueue addOperationWithBlock: ^{
        // Parse on background thread:
        NSMutableArray* parsedChanges = [NSMutableArray arrayWithCapacity: lines.count];
        for (NSData* line in lines) {
            id change = [TDJSON JSONObjectWithData: line options: 0 error: NULL];
            if (!change) {
                Warn(@"TDSocketChangeTracker received unparseable change line from server: %@", [line my_UTF8ToString]);
                break;
            }
            [parsedChanges addObject: change];
        }
        MYOnThread(resultThread, ^{
            // Process change lines on original thread:
            Assert(_parsing);
            _parsing = false;
            if (!_trackingInput)
                return;
            LogTo(ChangeTracker, @"%@: Notifying %u changes...", self, (unsigned)parsedChanges.count);
            if (![self receivedChanges: parsedChanges errorMessage: NULL]) {
                [self setUpstreamError: @"Unparseable change line"];
                [self stop];
            }
            
            // Read more data if there is any, or stop if stream's at EOF:
            if (_inputAvailable)
                [self readFromInput];
            else if (_atEOF)
                [self stop];
        });
    }];
}


- (BOOL) failUnparseable: (NSString*)line {
    Warn(@"Couldn't parse line from _changes: %@", line);
    [self setUpstreamError: @"Unparseable change line"];
    [self stop];
    return NO;
}


#pragma mark - STREAM HANDLING:


- (void) readFromInput {
    Assert(!_parsing);
    Assert(_inputAvailable);
    _inputAvailable = false;
    
    uint8_t* buffer;
    NSUInteger bufferLength;
    NSInteger bytesRead;
    if ([_trackingInput getBuffer: &buffer length: &bufferLength]) {
        [_inputBuffer appendBytes: buffer length: bufferLength];
        bytesRead = bufferLength;
    } else {
        uint8_t buffer[kReadLength];
        bytesRead = [_trackingInput read: buffer maxLength: sizeof(buffer)];
        if (bytesRead > 0)
            [_inputBuffer appendBytes: buffer length: bytesRead];
    }
    LogTo(ChangeTracker, @"%@: read %ld bytes", self, (long)bytesRead);

    if (_mode == kContinuous)
        [self readLines];
}


- (void) errorOccurred: (NSError*)error {
    LogTo(ChangeTracker, @"%@: ErrorOccurred: %@", self, error);
    if (++_retryCount <= kMaxRetries) {
        [self clearConnection];
        NSTimeInterval retryDelay = kInitialRetryDelay * (1 << (_retryCount-1));
        [self performSelector: @selector(start) withObject: nil afterDelay: retryDelay];
    } else {
        Warn(@"%@: Can't connect, giving up: %@", self, error);
        [self stop];

        // Map lower-level errors from CFStream to higher-level NSURLError ones:
        if ($equal(error.domain, NSPOSIXErrorDomain)) {
            if (error.code == ECONNREFUSED)
                error = [NSError errorWithDomain: NSURLErrorDomain
                                            code: NSURLErrorCannotConnectToHost
                                        userInfo: error.userInfo];
        }

        self.error = error;
    }
}


- (void) stream: (NSStream*)stream handleEvent: (NSStreamEvent)eventCode {
    switch (eventCode) {
        case NSStreamEventHasBytesAvailable: {
            LogTo(ChangeTracker, @"%@: HasBytesAvailable %@", self, stream);
            if (!_gotResponseHeaders) {
                if (![self checkSSLCert] || ![self readResponseHeader])
                    return;
            }
            _inputAvailable = true;
            // If still chewing on last bytes, don't eat any more yet
            if (!_parsing)
                [self readFromInput];
            break;
        }
            
        case NSStreamEventEndEncountered:
            LogTo(ChangeTracker, @"%@: EndEncountered %@", self, stream);
            _atEOF = true;
            if (!_gotResponseHeaders || (_mode == kContinuous && _inputBuffer.length > 0)) {
                [self errorOccurred: [NSError errorWithDomain: NSURLErrorDomain
                                                         code: NSURLErrorNetworkConnectionLost
                                                     userInfo: nil]];
                break;
            }
            if (_mode == kContinuous) {
                if (!_parsing)
                    [self stop];
            } else {
                [self readEntireInput];
            }
            break;
            
        case NSStreamEventErrorOccurred:
            [self errorOccurred: stream.streamError];
            break;
            
        default:
            LogTo(ChangeTracker, @"%@: Event %lx on %@", self, (long)eventCode, stream);
            break;
    }
}


@end
