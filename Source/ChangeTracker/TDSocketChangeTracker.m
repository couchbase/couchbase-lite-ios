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
#import "TDStatus.h"
#import "TDBase64.h"
#import "MYBlockUtils.h"
#import "MYCertificateInfo.h"

#import <string.h>
#import <Security/SecCertificate.h>
#import <Security/SecureTransport.h>


// Values of _state:
enum {
    kStateStatus,
    kStateHeaders,
    kStateChunks,
};

#define kMaxRetries 6
#define kInitialRetryDelay 0.2
#define kReadLength 8192u


@implementation TDSocketChangeTracker


- (BOOL) start {
    NSAssert(!_trackingInput, @"Already started");
    NSAssert(_mode == kContinuous, @"TDSocketChangeTracker only supports continuous mode");
    
    [super start];
    NSMutableString* request = [NSMutableString stringWithFormat:
                                     @"GET /%@/%@ HTTP/1.1\r\n"
                                     @"Host: %@\r\n",
                                self.databaseName, self.changesFeedPath, _databaseURL.host];
    NSString* auth = self.authorizationHeader;
    if (auth)
        [request appendFormat: @"Authorization: %@\r\n", auth];
    LogTo(ChangeTracker, @"%@: Starting with request:\n%@", self, request);
    [request appendString: @"\r\n"];
    _trackingRequest = [request copy];
    
    /* Why are we using raw TCP streams rather than NSURLConnection? Good question.
        NSURLConnection seems to have some kind of bug with reading the output of _changes, maybe
        because it's chunked and the stream doesn't close afterwards. At any rate, at least on
        OS X 10.6.7, the delegate never receives any notification of a response. The workaround
        is to act as a dumb HTTP parser and do the job ourselves. */
    
    BOOL isSSL = (0 == [_databaseURL.scheme caseInsensitiveCompare: @"https"]);
    int port = _databaseURL.port.unsignedShortValue ?: (isSSL ? 443 : 80);
#if TARGET_OS_IPHONE
    CFReadStreamRef cfInputStream = NULL;
    CFWriteStreamRef cfOutputStream = NULL;
    CFStreamCreatePairWithSocketToHost(NULL,
                                       (CFStringRef)_databaseURL.host,
                                       port,
                                       &cfInputStream, &cfOutputStream);
    if (!cfInputStream)
        return NO;
    _trackingInput = (NSInputStream*)cfInputStream;
    _trackingOutput = (NSOutputStream*)cfOutputStream;
#else
    NSString* hostname = _databaseURL.host;
    if ($equal(hostname, @"localhost"))     // for some reason connection fails if "localhost" used
        hostname = @"127.0.0.1";
    NSInputStream* input;
    NSOutputStream* output;
    [NSStream getStreamsToHost: [NSHost hostWithName: hostname]
                          port: port
                   inputStream: &input outputStream: &output];
    if (!output)
        return NO;
    _trackingInput = [input retain];
    _trackingOutput = [output retain];
#endif
    
    if (isSSL) {
        [_trackingInput setProperty: NSStreamSocketSecurityLevelNegotiatedSSL
                             forKey: NSStreamSocketSecurityLevelKey];
        [_trackingOutput setProperty: NSStreamSocketSecurityLevelNegotiatedSSL
                              forKey: NSStreamSocketSecurityLevelKey];  

        // Disable peer name checking, because it will fail for certs with wildcard subdomains,
        // in particular for IrisCouch whose cert is for "*.iriscouch.com". (SecureTransport bug?)
        // TODO: FIXME: Add a manual hostname check after the connection opens!!!
        // Also, disable TLS 1.2 support because it breaks compatibility with some SSL servers;
        // workaround taken from Apple technote TN2287:
        // http://developer.apple.com/library/ios/#technotes/tn2287/
        NSDictionary *settings = $dict({(id)kCFStreamSSLPeerName, $null},
                                       {(id)kCFStreamSSLLevel,
                                        @"kCFStreamSocketSecurityLevelTLSv1_0SSLv3"});
        CFReadStreamSetProperty((CFReadStreamRef)_trackingInput,
                                kCFStreamPropertySSLSettings, (CFTypeRef)settings);
        CFWriteStreamSetProperty((CFWriteStreamRef)_trackingOutput,
                                 kCFStreamPropertySSLSettings, (CFTypeRef)settings);
    }
    
    _state = kStateStatus;
    _atEOF = _inputAvailable = _parsing = false;
    _checkPeerName = isSSL;
    
    _inputBuffer = [[NSMutableData alloc] initWithCapacity: kReadLength];
    
    [_trackingOutput setDelegate: self];
    [_trackingOutput scheduleInRunLoop: [NSRunLoop currentRunLoop] forMode: NSRunLoopCommonModes];
    [_trackingOutput open];
    [_trackingInput setDelegate: self];
    [_trackingInput scheduleInRunLoop: [NSRunLoop currentRunLoop] forMode: NSRunLoopCommonModes];
    [_trackingInput open];
    return YES;
}


static NSString* basicAuthString(NSString* username, NSString* password) {
    if (!username || !password)
        return nil;
    NSString* auth = [NSString stringWithFormat: @"%@:%@", username, password];
    auth = [TDBase64 encode: [auth dataUsingEncoding: NSUTF8StringEncoding]];
    return [NSString stringWithFormat: @"Basic %@", auth];
}


- (NSString*) authorizationHeader {
    NSString* auth = nil;
    if ([_client respondsToSelector: @selector(authorizationHeader)])
        auth = [_client authorizationHeader];
    if (!auth)
        auth = basicAuthString(_databaseURL.user, _databaseURL.password);
    if (!auth) {
        NSURLCredential* credential = self.authCredential;
        auth = basicAuthString(credential.user, credential.password);
    }
    return auth;
}


- (void) clearConnection {
    [_trackingInput close];
    [_trackingInput release];
    _trackingInput = nil;
    
    [_trackingOutput close];
    [_trackingOutput release];
    _trackingOutput = nil;
    
    [_inputBuffer release];
    _inputBuffer = nil;
    [_changeBuffer release];
    _changeBuffer = nil;
}


- (void) stop {
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(start)
                                               object: nil];    // cancel pending retries
    if (_trackingInput || _trackingOutput) {
        LogTo(ChangeTracker, @"%@: stop", self);
        [self clearConnection];
        [super stop];
    }
}


static NSString* peerCertName(NSInputStream* stream) {
    SecTrustRef trust = (SecTrustRef) CFReadStreamCopyProperty((CFReadStreamRef)stream,
                                                               kCFStreamPropertySSLPeerTrust);
    if (!trust) {
        Warn(@"Couldn't get SecTrust for %@", stream);
        return nil;
    }
    SecCertificateRef cert = SecTrustGetCertificateAtIndex(trust, 0);
    NSString* name;
    
#if 1 // Workaround for lack of SecCertificateCopyCommonName on iOS
    CFDataRef certData = SecCertificateCopyData(cert);
    NSError* err;
    MYCertificateInfo* info = [[[MYCertificateInfo alloc] initWithCertificateData: (NSData*)certData
                                                                            error: &err]
                               autorelease];
    CFRelease(certData);
    name = info.subject.commonName;
#else
    CFStringRef cfName = NULL;
    OSStatus err = SecCertificateCopyCommonName(cert, &cfName);
    name = [NSMakeCollectable(cfName) autorelease];
#endif
    
    CFRelease(trust);
    if (err)
        return nil;
    return name;
}

static NSString* parentDomain(NSString* domain) {
    NSRange dot = [domain rangeOfString: @"."];
    if (dot.length == 0)
        return @"";
    return [domain substringFromIndex: NSMaxRange(dot)];
}


// Compares the name in the server's SSL cert against the hostname of the URL.
// This shouldn't be necessary; SecureTransport should do this check for us. But if we let it,
// it won't correctly match certs with wildcard subdomains (like "*.iriscouch.com"), so we
// have to turn that checking off and do it ourselves. See, this is why we can't have nice things.
- (BOOL) checkPeerName {
    NSString* certName = peerCertName(_trackingInput);
    NSString* hostName = _databaseURL.host;

    BOOL result = NO;
    if (0 == [certName caseInsensitiveCompare: hostName]) {
        // exact match
        result = YES;
    } else if ([certName hasPrefix: @"*."]) {
        // Cert has a wildcard subdomain; check if parent domains match:
        result = (0 == [parentDomain(certName) caseInsensitiveCompare: parentDomain(hostName)]);
    }
    if (!result) {
        Warn(@"%@: SSL name verification failed: expected '%@', cert has '%@'", 
             self, hostName, certName);
    }
    return result;
}


- (BOOL) failUnparseable: (NSString*)line {
    Warn(@"Couldn't parse line from _changes: %@", line);
    [self setUpstreamError: @"Unparseable change line"];
    [self stop];
    return NO;
}


- (BOOL) readServerResponse: (NSString*)line {
    int status;
    NSScanner* scanner = [NSScanner scannerWithString: line];
    if (![scanner scanString: @"HTTP/1.1 " intoString: nil] ||
            ![scanner scanInt: &status]) {
        return [self failUnparseable: line];
    }
    if (status >= 300) {
        self.error = TDStatusToNSError(status, self.changesFeedURL);
        return NO;
    }
    return YES;
}


- (void) readChangeLine: (const void*)bytes
                 length: (NSUInteger)length
              intoArray: (NSMutableArray*)changes
{
    if (_changeBuffer)
        [_changeBuffer appendBytes: bytes length: length];
    else
        _changeBuffer = [[NSMutableData alloc] initWithBytes: bytes length: length];
    while (_changeBuffer) {                 // abort loop if delegate calls -stop on me!
        const void* start = _changeBuffer.bytes;
        const void* eol = memchr(start, '\n', _changeBuffer.length);
        if (!eol)
            break;
        NSData* line = [_changeBuffer subdataWithRange: NSMakeRange(0, eol-start)];
        [_changeBuffer replaceBytesInRange: NSMakeRange(0, eol-start+1)
                                withBytes: NULL length: 0];
        if (line.length > 0)
            [changes addObject: line];
    }
}


- (void) readLines {
    NSMutableArray* changes = $marray();
    const char* pos = _inputBuffer.bytes;
    const char* end = pos + _inputBuffer.length;
    BOOL keepGoing = YES;
    while (keepGoing && pos < end && _inputBuffer) {
        const char* lineStart = pos;
        const char* crlf = memmem(pos, end-pos, "\r\n", 2);
        if (!crlf)
            break;  // Wait till we have a complete line
        ptrdiff_t lineLength = crlf - pos;
        NSString* line = [[[NSString alloc] initWithBytes: pos
                                                   length: lineLength
                                                 encoding: NSUTF8StringEncoding] autorelease];
        pos = crlf + 2;
        if (!line) {
            [self failUnparseable: @"invalid UTF-8"];
            break;
        }
        
        switch (_state) {
            case kStateStatus: {
                // Read the HTTP response status line:
                if ([self readServerResponse: line])
                    _state = kStateHeaders;
                else
                    [self stop];
                break;
            }
            case kStateHeaders:
                if (line.length == 0) {
                    _state = kStateChunks;
                    _retryCount = 0;  // successful connection
                }
                break;
            case kStateChunks: {
                if (line.length == 0)
                    break;      // There's an empty line between chunks
                NSScanner* scanner = [NSScanner scannerWithString: line];
                unsigned chunkLength;
                if (![scanner scanHexInt: &chunkLength]) {
                    [self failUnparseable: line];
                    break;
                }
                if (pos + chunkLength > end) {
                    keepGoing = NO;
                    pos = lineStart;
                    break;     // Don't read the chunk till it's complete
                }
                // Append the chunk to the current change line:
                [self readChangeLine: pos length: chunkLength intoArray: changes];
                pos += chunkLength;
            }
        }
    }
    
    // Remove the parsed lines:
    [_inputBuffer replaceBytesInRange: NSMakeRange(0, pos - (const char*)_inputBuffer.bytes)
                            withBytes: NULL length: 0];
    
    if (changes.count > 0)
        [self asyncParseChangeLines: changes];
}


#pragma mark - ASYNC PARSING:


- (void) asyncParseChangeLines: (NSArray*)lines {
    static NSOperationQueue* sParseQueue;
    if (!sParseQueue)
        sParseQueue = [[NSOperationQueue alloc] init];
    
    LogTo(ChangeTracker, @"%@: Async parsing %u changes...", self, lines.count);
    Assert(!_parsing);
    _parsing = true;
    NSThread* resultThread = [NSThread currentThread];
    [sParseQueue addOperationWithBlock: ^{
        // Parse on background thread:
        bool allParsed = true;
        NSMutableArray* parsedChanges = [NSMutableArray arrayWithCapacity: lines.count];
        for (NSData* line in lines) {
            id change = [TDJSON JSONObjectWithData: line options: 0 error: NULL];
            if (!change) {
                Warn(@"TDSocketChangeTracker received unparseable change line from server: %@", [line my_UTF8ToString]);
                allParsed = false;
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
            LogTo(ChangeTracker, @"%@: Notifying %u changes...", self, parsedChanges.count);
            for (id change in parsedChanges) {
                if (![self receivedChange: change]) {
                    [self failUnparseable: change];
                    break;
                }
            }
            if (!allParsed) {
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
        self.error = error;
    }
}


- (void) stream: (NSStream*)stream handleEvent: (NSStreamEvent)eventCode {
    [[self retain] autorelease];  // Delegate calling -stop might otherwise dealloc me
    
    // Verify SSL peer name before first read or write:
    if (eventCode == NSStreamEventHasSpaceAvailable || eventCode == NSStreamEventHasBytesAvailable) {
        if (_checkPeerName && ![self checkPeerName]) {
            [self errorOccurred: [NSError errorWithDomain: NSOSStatusErrorDomain
                                                     code: errSSLHostNameMismatch
                                                 userInfo: nil]];
        }
        _checkPeerName = NO;
    }
    
    switch (eventCode) {
        case NSStreamEventHasSpaceAvailable: {
            LogTo(ChangeTracker, @"%@: HasSpaceAvailable %@", self, stream);
            if (_trackingRequest) {
                const char* buffer = [_trackingRequest UTF8String];
                NSUInteger written = [(NSOutputStream*)stream write: (void*)buffer maxLength: strlen(buffer)];
                NSAssert(written == strlen(buffer), @"Output stream didn't write entire request");
                // FIX: It's unlikely but possible that the stream won't take the entire request; need to
                // write the rest later.
                [_trackingRequest release];
                _trackingRequest = nil;
            }
            break;
        }
        case NSStreamEventHasBytesAvailable: {
            LogTo(ChangeTracker, @"%@: HasBytesAvailable %@", self, stream);
            _inputAvailable = true;
            // If still chewing on last bytes, don't eat any more yet
            if (!_parsing)
                [self readFromInput];
            break;
        }
        case NSStreamEventEndEncountered:
            LogTo(ChangeTracker, @"%@: EndEncountered %@", self, stream);
            _atEOF = true;
            if (_state < kStateChunks || _mode == kContinuous || _inputBuffer.length > 0)
                [self errorOccurred: [NSError errorWithDomain: NSURLErrorDomain
                                                         code: NSURLErrorNetworkConnectionLost
                                                     userInfo: nil]];
            else if (!_parsing)
                [self stop];
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
