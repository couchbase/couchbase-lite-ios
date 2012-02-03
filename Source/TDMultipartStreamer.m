//
//  TDMultipartStreamer.m
//  TouchDB
//
//  Created by Jens Alfke on 2/2/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDMultipartStreamer.h"
#import "TDMisc.h"
#import "CollectionUtils.h"
#import "Test.h"


@implementation TDMultipartStreamer


- (id) initWithBoundary: (NSString*)boundary {
    self = [super init];
    if (self) {
        _boundary = [(boundary ?: TDCreateUUID()) copy];
        NSString* separatorStr = $sprintf(@"\r\n--%@\r\n\r\n", _boundary);
        _separatorData = [[separatorStr dataUsingEncoding: NSUTF8StringEncoding] retain];
        // Account for the final boundary to be written by -open. Add it in now, because the
        // client is probably going to ask for my .length *before* it calls -open.
        _length += _separatorData.length - 2;
    }
    return self;
}


- (id)init {
    return [self initWithBoundary: nil];
}


- (void)dealloc {
    [_boundary release];
    [_separatorData release];
    [super dealloc];
}


@synthesize boundary=_boundary, length=_length;


- (void) setNextPartsHeaders: (NSDictionary*)headers {
    setObj(&_nextPartsHeaders, headers);
}


- (void) addStream:(NSInputStream *)partStream {
    [self addStream: partStream length: 0];
}


- (void) addStream: (NSInputStream*)partStream length:(UInt64)length {
    NSData* separator = _separatorData;
    if (_nextPartsHeaders.count) {
        NSMutableString* headers = [NSMutableString stringWithFormat: @"\r\n--%@\r\n", _boundary];
        for (NSString* name in _nextPartsHeaders) {
            [headers appendFormat: @"%@: %@\r\n", name, [_nextPartsHeaders objectForKey: name]];
        }
        [headers appendString: @"\r\n"];
        separator = [headers dataUsingEncoding: NSUTF8StringEncoding];
        [self setNextPartsHeaders: nil];
    }
    [super addStream: [NSInputStream inputStreamWithData: separator]];
    [super addStream: partStream];
    _length += separator.length + length;
}

- (void) addData: (NSData*)data {
    [super addData: data];
    _length += data.length;
}


- (BOOL) addFile: (NSString*)path {
    NSDictionary* info = [[NSFileManager defaultManager] attributesOfItemAtPath: path error: nil];
    if (!info)
        return NO;
    if (![super addFile: path])
        return NO;
    _length += [info fileSize];
    return YES;
}
     
     
- (void) open {
    // Append the final boundary:
    NSString* trailerStr = $sprintf(@"\r\n--%@--", _boundary);
    NSData* trailerData = [trailerStr dataUsingEncoding: NSUTF8StringEncoding];
    [super addStream: [NSInputStream inputStreamWithData: trailerData]];
    // _length was already adjusted for this in -init
    
    [super open];
}

@end





TestCase(TDMultipartStreamer) {
    NSString* expectedOutput = @"\r\n--BOUNDARY\r\n\r\n<part the first>\r\n--BOUNDARY\r\nContent-Type: something\r\n\r\n<2nd part>\r\n--BOUNDARY--";
    RequireTestCase(TDConcatenatedInputStream);
    for (unsigned bufSize = 1; bufSize < expectedOutput.length+1; ++bufSize) {
        TDMultipartStreamer* mp = [[[TDMultipartStreamer alloc] initWithBoundary: @"BOUNDARY"] autorelease];
        CAssertEqual(mp.boundary, @"BOUNDARY");
        [mp addData: [@"<part the first>" dataUsingEncoding: NSUTF8StringEncoding]];
        [mp setNextPartsHeaders: $dict({@"Content-Type", @"something"})];
        [mp addData: [@"<2nd part>" dataUsingEncoding: NSUTF8StringEncoding]];
        CAssertEq(mp.length, expectedOutput.length);
        [mp open];
        CAssertEq(mp.length, expectedOutput.length);

        NSMutableData* output = [NSMutableData data];
        uint8_t buffer[bufSize];
        NSInteger nBytes;
        while ((nBytes = [mp read: buffer maxLength: sizeof(buffer)]) > 0) {
            CAssert(nBytes <= bufSize);
            [output appendBytes: buffer length: nBytes];
        }
        CAssert(nBytes == 0, @"Stream returned an error");
        [mp close];
        CAssertEqual(output.my_UTF8ToString, expectedOutput);
    }
}
