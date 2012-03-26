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
#import "TDBase64.h"


enum {
    kStateStatus,
    kStateHeaders,
    kStateChunks
};

#define kMaxRetries 7


@implementation TDSocketChangeTracker

- (BOOL) start {
    NSAssert(!_trackingInput, @"Already started");
    NSAssert(_mode == kContinuous, @"TDSocketChangeTracker only supports continuous mode");
    
    [super start];
    NSMutableString* request = [NSMutableString stringWithFormat:
                                     @"GET /%@/%@ HTTP/1.1\r\n"
                                     @"Host: %@\r\n",
                                self.databaseName, self.changesFeedPath, _databaseURL.host];
    NSURLCredential* credential = self.authCredential;
    if (credential) {
        NSString* auth = [NSString stringWithFormat: @"%@:%@",
                          credential.user, credential.password];
        auth = [TDBase64 encode: [auth dataUsingEncoding: NSUTF8StringEncoding]];
        [request appendFormat: @"Authorization: Basic %@\r\n", auth];
    }
    LogTo(ChangeTracker, @"%@: Starting with request:\n%@", self, request);
    [request appendString: @"\r\n"];
    _trackingRequest = [request copy];
    
    /* Why are we using raw TCP streams rather than NSURLConnection? Good question.
        NSURLConnection seems to have some kind of bug with reading the output of _changes, maybe
        because it's chunked and the stream doesn't close afterwards. At any rate, at least on
        OS X 10.6.7, the delegate never receives any notification of a response. The workaround
        is to act as a dumb HTTP parser and do the job ourselves. */
    
    int port = _databaseURL.port.unsignedShortValue ?: 80;
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
    NSInputStream* input;
    NSOutputStream* output;
    [NSStream getStreamsToHost: [NSHost hostWithName: _databaseURL.host]
                          port: port
                   inputStream: &input outputStream: &output];
    if (!output)
        return NO;
    _trackingInput = [input retain];
    _trackingOutput = [output retain];
#endif
    
    _state = kStateStatus;
    
    _inputBuffer = [[NSMutableData alloc] initWithCapacity: 1024];
    
    [_trackingOutput setDelegate: self];
    [_trackingOutput scheduleInRunLoop: [NSRunLoop currentRunLoop] forMode: NSRunLoopCommonModes];
    [_trackingOutput open];
    [_trackingInput setDelegate: self];
    [_trackingInput scheduleInRunLoop: [NSRunLoop currentRunLoop] forMode: NSRunLoopCommonModes];
    [_trackingInput open];
    return YES;
}


- (void) stop {
    if (_trackingInput || _trackingOutput) {
        LogTo(ChangeTracker, @"%@: stop", self);
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
        
        [super stop];
    }
}


- (BOOL) failUnparseable: (NSString*)line {
    Warn(@"Couldn't parse line from _changes: %@", line);
    [self setUpstreamError: @"Unparseable change line"];
    [self stop];
    return NO;
}


- (BOOL) appendToChangeLine: (const void*)bytes length: (NSUInteger)length {
    if (_changeBuffer)
        [_changeBuffer appendBytes: bytes length: length];
    else
        _changeBuffer = [[NSMutableData alloc] initWithBytes: bytes length: length];
    while (true) {
        const void* start = _changeBuffer.bytes;
        const void* eol = memchr(start, '\n', _changeBuffer.length);
        if (!eol)
            break;
        NSData* line = [_changeBuffer subdataWithRange: NSMakeRange(0, eol-start)];
        [_changeBuffer replaceBytesInRange: NSMakeRange(0, eol-start+1)
                                withBytes: NULL length: 0];
        // Finally! Parse the line as JSON:
        if (![self receivedChunk: line])
            return NO;
    }
    return YES;
}


- (void) readLines {
    const char* pos = _inputBuffer.bytes;
    const char* end = pos + _inputBuffer.length;
    BOOL keepGoing = YES;
    while (keepGoing && pos < end && _inputBuffer) {
        const char* lineStart = pos;
        const char* crlf = strnstr(pos, "\r\n", end-pos);
        if (!crlf)
            break;  // Wait till we have a complete line
        ptrdiff_t lineLength = crlf - pos;
        NSString* line = [[[NSString alloc] initWithBytes: pos
                                                   length: lineLength
                                                 encoding: NSUTF8StringEncoding] autorelease];
        pos = crlf + 2;
        LogTo(ChangeTracker, @"%@: LINE: \"%@\"", self, line);
        if (!line) {
            [self failUnparseable: @"invalid UTF-8"];
            break;
        }
        
        switch (_state) {
            case kStateStatus: {
                // Read the HTTP response status line:
                if (![line hasPrefix: @"HTTP/1.1 200 "])
                    [self failUnparseable: line];
                _state = kStateHeaders;
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
                [self appendToChangeLine: pos length: chunkLength];
                pos += chunkLength;
            }
        }
    }
    
    // Remove the parsed lines:
    [_inputBuffer replaceBytesInRange: NSMakeRange(0, pos - (const char*)_inputBuffer.bytes)
                            withBytes: NULL length: 0];
}


- (void) errorOccurred: (NSError*)error {
    [self stop];
    if (++_retryCount <= kMaxRetries) {
        NSTimeInterval retryDelay = 0.2 * (1 << (_retryCount-1));
        [self performSelector: @selector(start) withObject: nil afterDelay: retryDelay];
    } else {
        Warn(@"%@: Can't connect, giving up: %@", self, error);
        self.error = error;
    }
}


- (void) stream: (NSInputStream*)stream handleEvent: (NSStreamEvent)eventCode {
    [[self retain] autorelease];  // Delegate calling -stop might otherwise dealloc me
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
            while ([stream hasBytesAvailable]) {
                uint8_t buffer[8192];
                NSInteger bytesRead = [stream read: buffer maxLength: sizeof(buffer)];
                if (bytesRead > 0) {
                    [_inputBuffer appendBytes: buffer length: bytesRead];
                    LogTo(ChangeTracker, @"%@: read %ld bytes", self, (long)bytesRead);
                }
            }
            [self readLines];
            break;
        }
        case NSStreamEventEndEncountered:
            LogTo(ChangeTracker, @"%@: EndEncountered %@", self, stream);
            if (_inputBuffer.length > 0 || _changeBuffer.length > 0)
                Warn(@"%@ connection closed with unparsed data in buffer", self);
            [self stop];
            break;
        case NSStreamEventErrorOccurred:
            LogTo(ChangeTracker, @"%@: ErrorOccurred %@: %@", self, stream, stream.streamError);
            [self errorOccurred: stream.streamError];
            break;
            
        default:
            LogTo(ChangeTracker, @"%@: Event %lx on %@", self, (long)eventCode, stream);
            break;
    }
}


@end
