//
//  TDMultiInputStream.m
//  TouchDB
//
//  Created by Jens Alfke on 2/3/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDMultiInputStream.h"
#import "Logging.h"
#import "Test.h"


@implementation TDMultiInputStream


- (id)init {
    self = [super init];
    if (self) {
        _inputs = [[NSMutableArray alloc] init];
        _runLoopsAndModes = [[NSMutableArray alloc] init];
    }
    return self;
}


- (void)dealloc {
    [self close];
    [_runLoopsAndModes release];
    [super dealloc];
}


@synthesize delegate=_delegate;


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


- (BOOL) openNextInput {
    if (_currentInput && _inputs.count == 1)        // leave last input stream open
        return NO;
    
    if (_currentInput) {
        for (NSArray* pair in _runLoopsAndModes)
            [_currentInput removeFromRunLoop: [pair objectAtIndex: 0]
                                     forMode: [pair objectAtIndex: 1]];
        _currentInput.delegate = nil;
        [_currentInput close];
        [_inputs removeObjectAtIndex: 0];
        _currentInput = nil;
    }
    
    _currentInput = [_inputs objectAtIndex: 0];     // already retained by the array
    _currentInput.delegate = self;
    for (NSArray* pair in _runLoopsAndModes)
        [_currentInput scheduleInRunLoop: [pair objectAtIndex: 0]
                                 forMode: [pair objectAtIndex: 1]];
    [_currentInput open];
    return YES;
}


#pragma mark - NSINPUTSTREAM METHODS:


- (void) open {
    //Log(@"%@: Open!", self);
    [self openNextInput];
}


- (void) close {
    //Log(@"%@: Closed", self);
    [_currentInput close];
    _currentInput = nil;
    [_inputs release];
    _inputs = nil;
}


- (NSStreamStatus) streamStatus {
    if (!_inputs)
        return NSStreamStatusClosed;
    if (_inputs.count == 0)
        return NSStreamStatusAtEnd;
    if (!_currentInput)
        return NSStreamStatusNotOpen;
    return _currentInput.streamStatus;
}


- (NSInteger) read:(uint8_t *)buffer maxLength:(NSUInteger)len {
    NSInteger totalBytesRead = 0;
    while (len > 0 && _currentInput) {
        NSInteger bytesRead = [_currentInput read: buffer maxLength: len];
        //Log(@"%@: read %d bytes from %@", self, bytesRead, _currentInput);
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
    //Log(@"%@: client read %d bytes", self, totalBytesRead);
    return totalBytesRead;
}


- (BOOL) getBuffer:(uint8_t **)buffer length:(NSUInteger *)len {
    //Log(@"%@: client called getBuffer:length:", self);
    return [_currentInput getBuffer: buffer length: len];
}


- (BOOL) hasBytesAvailable {
    BOOL hasBytes = [_currentInput hasBytesAvailable];
    //Log(@"%@: client called hasBytesAvailable --> %d", self, hasBytes);
    return hasBytes;
}


#pragma mark - ASYNC STUFF:


- (void) scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode {
    [_runLoopsAndModes addObject: $array(aRunLoop, mode)];
    [_currentInput scheduleInRunLoop: aRunLoop forMode: mode];
}

- (void) removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode {
    [_runLoopsAndModes removeObject: $array(aRunLoop, mode)];
    [_currentInput removeFromRunLoop: aRunLoop forMode: mode];
}

// This is an internal message that gets sent when NSURLConnection uses this stream as an
// HTTPBodyStream. It's not really kosher to mess with undocumented private methods, but as
// NSInputStream itself doesn't implement this, you'll die of an exception without it...
- (void) _scheduleInCFRunLoop: (CFRunLoopRef)runLoop forMode: (CFStringRef)mode {
    NSRunLoop* currentRunLoop = [NSRunLoop currentRunLoop];
    if (runLoop == currentRunLoop.getCFRunLoop) {
        //Log(@"%@: schedule in CFRunLoop %p in mode %@", self, runLoop, mode);
        [self scheduleInRunLoop: currentRunLoop forMode: (NSString*)mode];
    } else
        Warn(@"Unknown CFRunLoop %p", runLoop);
}

// Another internal message sent by CFNetwork when this is used as an HTTPBodyStream.
- (void) _setCFClientFlags: (CFOptionFlags)flags
                  callback: (CFReadStreamClientCallBack)callback
                   context: (CFStreamClientContext*)context
{
    //Log(@"%@: setCFClientFlags: 0x%x callback: %p context: %p", self, flags, callback, context);
    _cfClientFlags = flags;
    _cfClientCallback = callback;
    if (context)
        _cfClientContext = *context;
}


- (void) sendEvent: (NSStreamEvent)event {
    //Log(@"%@ Sending event 0x%x", self, event);
    [_delegate stream: self handleEvent: event];
    if (_cfClientCallback && (_cfClientFlags & event) != 0)
        _cfClientCallback((CFReadStreamRef)self, (CFStreamEventType)event, _cfClientContext.info);
}


- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)event {
    if (stream == _currentInput) {
        //Log(@"%@ Received event 0x%x", self, event);
        switch (event) {
            case NSStreamEventEndEncountered:
                if (![self openNextInput])
                    [self sendEvent: event];
                break;
            case NSStreamEventErrorOccurred:
            case NSStreamEventHasBytesAvailable:
                [self sendEvent: event];
                break;
        }
    }
}


@end




#pragma mark - UNIT TESTS:
#if DEBUG

static TDMultiInputStream* setupStream() {
    TDMultiInputStream* stream = [[[TDMultiInputStream alloc] init] autorelease];
    [stream addData: [@"<part the first>" dataUsingEncoding: NSUTF8StringEncoding]];
    [stream addData: [@"<2nd part>" dataUsingEncoding: NSUTF8StringEncoding]];
    return stream;
}

TestCase(TDConcatenatedInputStream_Sync) {
    for (unsigned bufSize = 1; bufSize < 128; ++bufSize) {
        TDMultiInputStream* mp = setupStream();
        CAssertEq(mp.streamStatus, (NSStreamStatus)NSStreamStatusNotOpen);
        [mp open];
        CAssertEq(mp.streamStatus, (NSStreamStatus)NSStreamStatusOpen);
        NSMutableData* output = [NSMutableData data];
        uint8_t buffer[bufSize];
        NSInteger nBytes;
        while ((nBytes = [mp read: buffer maxLength: sizeof(buffer)]) > 0) {
            CAssert((unsigned)nBytes <= bufSize);
            [output appendBytes: buffer length: nBytes];
        }
        CAssert(nBytes == 0, @"Stream returned an error");
        CAssertEq(mp.streamStatus, (NSStreamStatus)NSStreamStatusAtEnd);
        [mp close];
        CAssertEq(mp.streamStatus, (NSStreamStatus)NSStreamStatusClosed);
        
        CAssertEqual(output.my_UTF8ToString, @"<part the first><2nd part>");
    }
}

@interface TDConcatenatedInputStreamTester : NSObject <NSStreamDelegate>
{
    @public
    NSInputStream* _stream;
    NSMutableData* _output;
    BOOL _finished;
}
@end

@implementation TDConcatenatedInputStreamTester

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
        case NSStreamEventHasBytesAvailable: {
            Log(@"NSStreamEventHasBytesAvailable");
            uint8_t buffer[10];
            NSInteger length = [_stream read: buffer maxLength: sizeof(buffer)];
            Log(@"    read %d bytes", length);
            Assert(length > 0);
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

TestCase(TDConcatenatedInputStream_Async) {
    TDMultiInputStream* stream = setupStream();
    TDConcatenatedInputStreamTester *tester = [[[TDConcatenatedInputStreamTester alloc] initWithStream: stream] autorelease];
    NSRunLoop* rl = [NSRunLoop currentRunLoop];
    [stream scheduleInRunLoop: rl forMode: NSDefaultRunLoopMode];
    Log(@"Opening stream");
    [stream open];
    
    while (!tester->_finished) {
        Log(@"...waiting for stream...");
        [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]];
    }

    [stream removeFromRunLoop: rl forMode: NSDefaultRunLoopMode];
    Log(@"Closing stream");
    [stream close];
    CAssertEqual(tester->_output.my_UTF8ToString, @"<part the first><2nd part>");
}


TestCase(TDConcatenatedInputStream) {
    RequireTestCase(TDConcatenatedInputStream_Sync);
    RequireTestCase(TDConcatenatedInputStream_Async);
}

#endif
