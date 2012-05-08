//
//  TDMultiStreamWriter.m
//  TouchDB
//
//  Created by Jens Alfke on 2/3/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TDMultiStreamWriter.h"
#import "Logging.h"
#import "Test.h"


#define kDefaultBufferSize 32768


@interface TDMultiStreamWriter () <NSStreamDelegate>
- (BOOL) openNextInput;
- (BOOL) refillBuffer;
@end


@implementation TDMultiStreamWriter


- (id)initWithBufferSize: (NSUInteger)bufferSize {
    self = [super init];
    if (self) {
        _inputs = [[NSMutableArray alloc] init];
        _bufferLength = 0;
        _bufferSize = bufferSize;
        _buffer = malloc(_bufferSize);
        if (!_buffer) {
            [self release];
            return nil;
        }
    }
    return self;
}

- (id)init {
    return [self initWithBufferSize: kDefaultBufferSize];
}


- (void)dealloc {
    [self close];
    [_output release];
    [_input release];
    [super dealloc];
}


- (void) addStream: (NSInputStream*)stream {
    [_inputs addObject: stream];
}

- (void) addData: (NSData*)data {
    if (data.length > 0)
        [self addStream: [NSInputStream inputStreamWithData: data]];
}

- (BOOL) addFile: (NSString*)path {
    NSInputStream* input = [NSInputStream inputStreamWithFileAtPath: path];
    if (!input)
        return NO;
    [self addStream: input];
    return YES;
}


#pragma mark - OPENING:


- (BOOL) isOpen {
    return _output.delegate != nil;
}


- (void) opened {
    _output.delegate = self;
    [_output scheduleInRunLoop: [NSRunLoop currentRunLoop] forMode: NSDefaultRunLoopMode];
    [_output open];
}


- (NSInputStream*) openForInputStream {
    if (_input)
        return _input;
    Assert(!_output, @"Already open");
    LogTo(TDMultiStreamWriter, @"%@: Open!", self);
#ifdef GNUSTEP
    Assert(NO, @"Unimplemented CFStreamCreateBoundPair");   // TODO: Add this to CNUstep base fw
#else
    CFStreamCreateBoundPair(NULL, (CFReadStreamRef*)&_input, (CFWriteStreamRef*)&_output,
                            _bufferSize);
#endif
    [self opened];
    return _input;
}


- (void) openForOutputTo: (NSOutputStream*)output {
    Assert(output);
    Assert(!_output, @"Already open");
    Assert(!_input);
    _output = [output retain];
    [self opened];
}


- (void) close {
    LogTo(TDMultiStreamWriter, @"%@: Closed", self);
    [_output close];
    _output.delegate = nil;
    
    free(_buffer);
    _buffer = NULL;
    _bufferSize = 0;
    
    [_currentInput close];
    _currentInput = nil;
    [_inputs release];
    _inputs = nil;
}


#pragma mark - I/O:


- (BOOL) openNextInput {
    if (_currentInput) {
        [_currentInput close];
        [_inputs removeObjectAtIndex: 0];
        _currentInput = nil;
    }
    if (_inputs.count > 0) {
        _currentInput = [_inputs objectAtIndex: 0];     // already retained by the array
        [_currentInput open];
        return YES;
    }
    return NO;
}


- (NSInteger) read:(uint8_t *)buffer maxLength:(NSUInteger)len {
    NSInteger totalBytesRead = 0;
    while (len > 0 && _currentInput) {
        NSInteger bytesRead = [_currentInput read: buffer maxLength: len];
        LogTo(TDMultiStreamWriter, @"%@:     read %d bytes from %@", self, bytesRead, _currentInput);
        if (bytesRead > 0) {
            // Got some data from the stream:
            totalBytesRead += bytesRead;
            buffer += bytesRead;
            len -= bytesRead;
            if (_currentInput.streamStatus != NSStreamStatusAtEnd) {
                // Not at EOF on this stream, but we shouldn't call -read: again right away
                // or it might block.
                break;
            }
        } else if (bytesRead < 0) {
            // There was a read error:
            Warn(@"%@: Read error on %@", self, _currentInput);
            return bytesRead;
        }

        // At EOF on stream, so go to the next one:
        if (![self openNextInput] || !_currentInput.hasBytesAvailable)
            break;
    }
    return totalBytesRead;
}


- (BOOL) refillBuffer {
    LogTo(TDMultiStreamWriter, @"%@:   Refilling buffer", self);
    NSInteger bytesRead = [self read: _buffer+_bufferLength maxLength: _bufferSize-_bufferLength];
    if (bytesRead <= 0) {
        LogTo(TDMultiStreamWriter, @"%@:     at end of input, can't refill", self);
        return NO;
    }
    _bufferLength += bytesRead;
    LogTo(TDMultiStreamWriter, @"%@:   refilled buffer to %u bytes", self, _bufferLength);
    //LogTo(TDMultiStreamWriter, @"%@:   buffer is now \"%.*s\"", self, _bufferLength, _buffer);
    return YES;
}


- (BOOL) writeToOutput {
    Assert(_bufferLength > 0);
    NSInteger bytesWritten = [_output write: _buffer maxLength: _bufferLength];
    LogTo(TDMultiStreamWriter, @"%@:   Wrote %d (of %u) bytes to _output", self, bytesWritten, _bufferLength);
    if (bytesWritten <= 0)
        return NO;
    Assert(bytesWritten <= (NSInteger)_bufferLength);
    _bufferLength -= bytesWritten;
    memmove(_buffer, _buffer+bytesWritten, _bufferLength);
    //LogTo(TDMultiStreamWriter, @"%@:     buffer is now \"%.*s\"", self, _bufferLength, _buffer);
    if (_bufferLength <= _bufferSize/2)
        [self refillBuffer];
    return _bufferLength > 0;
}


- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)event {
    if (stream != _output)
        return;
    LogTo(TDMultiStreamWriter, @"%@: Received event 0x%x", self, event);
    switch (event) {
        case NSStreamEventOpenCompleted:
            [self openNextInput];
            [self refillBuffer];
            break;
            
        case NSStreamEventHasSpaceAvailable:
            if (![self writeToOutput]) {
                LogTo(TDMultiStreamWriter, @"%@:   At end -- closing _output!", self);
                [self close];
            }
            break;
    }
}


- (NSData*) allOutput {
    NSOutputStream* output = [NSOutputStream outputStreamToMemory];
    [self openForOutputTo: output];
    
    while (self.isOpen) {
        [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                 beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]];
    }
    
    return [output propertyForKey: NSStreamDataWrittenToMemoryStreamKey];
}


@end




#pragma mark - UNIT TESTS:
#if DEBUG

static TDMultiStreamWriter* createWriter(unsigned bufSize) {
    TDMultiStreamWriter* stream = [[[TDMultiStreamWriter alloc] initWithBufferSize: bufSize] autorelease];
    [stream addData: [@"<part the first, let us make it a bit longer for greater interest>" dataUsingEncoding: NSUTF8StringEncoding]];
    [stream addData: [@"<2nd part, again unnecessarily prolonged for testing purposes beyond any reasonable length...>" dataUsingEncoding: NSUTF8StringEncoding]];
    return stream;
}

TestCase(TDMultiStreamWriter_Sync) {
    for (unsigned bufSize = 1; bufSize < 128; ++bufSize) {
        Log(@"Buffer size = %u", bufSize);
        TDMultiStreamWriter* mp = createWriter(bufSize);
        NSData* outputBytes = [mp allOutput];
        CAssertEqual(outputBytes.my_UTF8ToString, @"<part the first, let us make it a bit longer for greater interest><2nd part, again unnecessarily prolonged for testing purposes beyond any reasonable length...>");
    }
}


@interface TDMultiStreamWriterTester : NSObject <NSStreamDelegate>
{
    @public
    NSInputStream* _stream;
    NSMutableData* _output;
    BOOL _finished;
}
@end

@implementation TDMultiStreamWriterTester

- (id)initWithStream: (NSInputStream*)stream {
    self = [super init];
    if (self) {
        _stream = stream;
        _output = [[NSMutableData alloc] init];
        stream.delegate = self;
    }
    return self;
}

- (void)dealloc {
    [_output release];
    [super dealloc];
}

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)event {
    AssertEq(stream, _stream);
    switch (event) {
        case NSStreamEventOpenCompleted:
            Log(@"NSStreamEventOpenCompleted");
            break;
        case NSStreamEventHasBytesAvailable: {
            Log(@"NSStreamEventHasBytesAvailable");
            uint8_t buffer[10];
            NSInteger length = [_stream read: buffer maxLength: sizeof(buffer)];
            Log(@"    read %d bytes", length);
            //Assert(length > 0);
            [_output appendBytes: buffer length: length];
            break;
        }
        case NSStreamEventEndEncountered:
            Log(@"NSStreamEventEndEncountered");
            _finished = YES;
            break;
        default:
            Assert(NO, @"Unexpected stream event %d", (int)event);
    }
}

@end

TestCase(TDMultiStreamWriter_Async) {
    TDMultiStreamWriter* writer = createWriter(16);
    NSInputStream* input = [writer openForInputStream];
    CAssert(input);
    TDMultiStreamWriterTester *tester = [[[TDMultiStreamWriterTester alloc] initWithStream: input] autorelease];
    NSRunLoop* rl = [NSRunLoop currentRunLoop];
    [input scheduleInRunLoop: rl forMode: NSDefaultRunLoopMode];
    Log(@"Opening stream");
    [input open];
    
    while (!tester->_finished) {
        Log(@"...waiting for stream...");
        [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]];
    }

    [input removeFromRunLoop: rl forMode: NSDefaultRunLoopMode];
    Log(@"Closing stream");
    [input close];
    [writer close];
    CAssertEqual(tester->_output.my_UTF8ToString, @"<part the first, let us make it a bit longer for greater interest><2nd part, again unnecessarily prolonged for testing purposes beyond any reasonable length...>");
}


TestCase(TDMultiStreamWriter) {
#ifndef GNUSTEP     // FIXME: Fix NSString bugs in GNUstep to make these tests work
    RequireTestCase(TDMultiStreamWriter_Sync);
    RequireTestCase(TDMultiStreamWriter_Async);
#endif
}

#endif // DEBUG
