//
//  CBLMultipartReader.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/30/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.
//
//  http://tools.ietf.org/html/rfc2046#section-5.1

#import "CBLMultipartReader.h"

#import "CollectionUtils.h"
#import "Test.h"


// Values of the _state ivar:
enum {
    kAtStart,
    kInPrologue,
    kInBody,
    kInHeaders,
    kAtEnd,
    kFailed,
};


@interface CBLMultipartReader ()
- (BOOL) parseContentType: (NSString*)contentType;
@end


static NSString* trim( NSString* str ) {
    return [str stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}


@implementation CBLMultipartReader


static NSData* kCRLFCRLF;


+ (void) initialize {
    if (!kCRLFCRLF)
        kCRLFCRLF = [[NSData alloc] initWithBytes: "\r\n\r\n" length: 4];
}


- (instancetype) initWithContentType: (NSString*)contentType
                            delegate: (id<CBLMultipartReaderDelegate>)delegate
{
    self = [super init];
    if (self) {
        if (![self parseContentType: contentType]) {
            return nil;
        }
        _delegate = delegate;
        _buffer = [[NSMutableData alloc] initWithCapacity: 1024];
        _state = kAtStart;
    }
    return self;
}


- (void) close {
    _buffer = nil;
    _headers = nil;
    _boundary = nil;
}


- (BOOL) parseContentType: (NSString*)contentType {
    // ContentType will look like "multipart/foo; boundary=bar"
    // But there may be other ';'-separated params, and the boundary string may be quoted.
    // This is really not a full MIME type parser, but should work well enough for our needs.
    BOOL first = YES;
    for (__strong NSString* param in [contentType componentsSeparatedByString: @";"]) {
        param = trim(param);
        if (first) {
            if (![param hasPrefix: @"multipart/"])
                return NO;
            first = NO;
        } else {
            if ([param hasPrefix: @"boundary="]) {
                NSString* boundary = [param substringFromIndex: 9];
                if ([boundary hasPrefix: @"\""]) {
                    if (boundary.length < 2 || ![boundary hasSuffix: @"\""])
                        return NO;
                    boundary = [boundary substringWithRange: NSMakeRange(1, boundary.length-2)];
                }
                if (boundary.length < 1)
                    return NO;
                boundary = [@"\r\n--" stringByAppendingString: boundary];
                _boundary = [boundary dataUsingEncoding: NSUTF8StringEncoding];
                break;
            }
        }
    }
    return (_boundary != nil);
}


@synthesize headers=_headers;


- (BOOL) parseHeaders: (NSString*)headersStr {
    if (!headersStr) {
        self.error = @"Unparseable UTF-8 in headers";
        return NO;
    }
    _headers = [[NSMutableDictionary alloc] init];
    BOOL first = YES;
    for (NSString* header in [headersStr componentsSeparatedByString: @"\r\n"]) {
        if (first)
            first = NO;     // first line is just the whitespace between separator and its CRLF
        else {
            NSRange colon = [header rangeOfString: @":"];
            if (colon.length == 0) {
                self.error = @"Missing ':' in header line";
                return NO;
            }
            NSString* key = trim([header substringToIndex: colon.location]);
            NSString* value = trim([header substringFromIndex: NSMaxRange(colon)]);
            _headers[key] = value;
        }
    }
    return YES;
}


- (NSRange) searchFor: (NSData*)pattern from: (NSUInteger)start {
    return [_buffer rangeOfData: pattern
                        options: 0
                          range: NSMakeRange(start, _buffer.length-start)];
}

- (void) deleteUpThrough: (NSRange)r {
    [_buffer replaceBytesInRange: NSMakeRange(0, NSMaxRange(r)) withBytes: NULL length: 0];
}

- (BOOL) appendAndTrimBuffer {
    NSUInteger bufLen = _buffer.length;
    NSUInteger boundaryLen = _boundary.length;
    if (bufLen > boundaryLen) {
        // Leave enough bytes in _buffer that we can find an incomplete boundary string
        NSRange trim = NSMakeRange(0, bufLen - boundaryLen);
        if (![_delegate appendToPart: [_buffer subdataWithRange: trim]])
            return NO;
        [self deleteUpThrough: trim];
    }
    return YES;
}


- (NSString*) error {
    return _error;
}

- (void) setError: (NSString*)error {
    _state = kFailed;
    if (!_error)
        _error = [error copy];
    [self close];
}

- (void) stop {
    self.error = @"Stopped";
}
         

- (void) appendData: (NSData*)data {
    if (!_buffer)
        return;
    NSUInteger newDataLen = data.length;
    if (newDataLen == 0)
        return;
    [_buffer appendData: data];
    
    int nextState;
    do {
        nextState = -1;
        NSUInteger bufLen = _buffer.length;
        id<CBLMultipartReaderDelegate> delegate = _delegate;
        switch (_state) {
            case kAtStart: {
                // The entire message might start with a boundary without a leading CRLF.
                NSUInteger testLen = _boundary.length - 2;
                if (bufLen >= testLen) {
                    if (memcmp(_buffer.bytes, _boundary.bytes + 2, testLen) == 0) {
                        [_buffer replaceBytesInRange: NSMakeRange(0, testLen)
                                           withBytes: NULL length: 0];
                        nextState = kInHeaders;
                    } else {
                        nextState = kInPrologue;
                    }
                }
                break;
            }
            case kInPrologue:
            case kInBody: {
                // Look for the next part boundary in the data we just added and the ending bytes of
                // the previous data (in case the boundary string is split across calls)
                if (bufLen < _boundary.length)
                    break;
                NSInteger start = MAX(0, (NSInteger)(bufLen - newDataLen - _boundary.length));
                NSRange r = [self searchFor: _boundary from: start];
                if (r.length > 0) {
                    if (_state == kInBody) {
                        if (![delegate appendToPart: [_buffer subdataWithRange: NSMakeRange(0, r.location)]]
                                || ![delegate finishedPart]) {
                            [self stop];
                            break;
                        }
                    }
                    [self deleteUpThrough: r];
                    nextState = kInHeaders;
                } else {
                    if (![self appendAndTrimBuffer]) {
                        [self stop];
                        break;
                    }
                }
                break;
            }
                
            case kInHeaders: {
                // First check for the end-of-message string ("--" after separator):
                if (bufLen >= 2 && memcmp(_buffer.bytes, "--", 2) == 0) {
                    _state = kAtEnd;
                    [self close];
                    return;
                }
                // Otherwise look for two CRLFs that delimit the end of the headers:
                NSRange r = [self searchFor: kCRLFCRLF from: 0];
                if (r.length > 0) {
                    NSString* headers = [[NSString alloc] initWithBytesNoCopy: (void*)_buffer.bytes
                                                                       length: r.location
                                                                     encoding: NSUTF8StringEncoding
                                                                 freeWhenDone: NO];
                    BOOL ok = [self parseHeaders: headers];
                    if (!ok)
                        return;  // parseHeaders already set .error
                    [self deleteUpThrough: r];
                    if (![delegate startedPart: _headers]) {
                        [self stop];
                        break;
                    }
                    nextState = kInBody;
                }
                break;
            }
                
            default:
                self.error = @"Unexpected data after end of MIME body";
                return;
        }
        if (nextState > 0)
            _state = nextState;
    } while (nextState >= 0 && _buffer.length > 0);
}


- (BOOL) finished {
    return _state == kAtEnd;
}


#if DEBUG
- (NSData*) boundary {return _boundary;}
#endif


@end




#if DEBUG  //// UNIT TESTS:
#import "CBLMisc.h"
#import "GTMNSData+zlib.h"


@interface CBL_TestMultipartReaderDelegate : NSObject <CBLMultipartReaderDelegate>
{
    NSMutableData* _currentPartData;
    NSMutableArray* _partList, *_headersList;
}
@property (readonly) NSArray* partList, *headerList;
@end


@implementation CBL_TestMultipartReaderDelegate

@synthesize partList=_partList, headerList=_headersList;

- (BOOL) startedPart: (NSDictionary*)headers {
    Assert(!_currentPartData);
    _currentPartData = [[NSMutableData alloc] init];
    if (!_partList)
        _partList = [[NSMutableArray alloc] init];
    [_partList addObject: _currentPartData];
    if (!_headersList)
        _headersList = [[NSMutableArray alloc] init];
    [_headersList addObject: headers];
    return YES;
}

- (BOOL) appendToPart: (NSData*)data {
    Assert(_currentPartData);
    [_currentPartData appendData: data];
    return YES;
}

- (BOOL) finishedPart {
    Assert(_currentPartData);
    _currentPartData = nil;
    return YES;
}


@end


TestCase(CBLMultipartReader_Types) {
    CBLMultipartReader* reader = [[CBLMultipartReader alloc] initWithContentType: @"multipart/related; boundary=\"BOUNDARY\"" delegate: nil];
    CAssertEqual(reader.boundary, [@"\r\n--BOUNDARY" dataUsingEncoding: NSUTF8StringEncoding]);

    reader = [[CBLMultipartReader alloc] initWithContentType: @"multipart/related; boundary=BOUNDARY" delegate: nil];
    CAssertEqual(reader.boundary, [@"\r\n--BOUNDARY" dataUsingEncoding: NSUTF8StringEncoding]);
    
    reader = [[CBLMultipartReader alloc] initWithContentType: @"multipart/related; boundary=\"BOUNDARY" delegate: nil];
    CAssertNil(reader);

    reader = [[CBLMultipartReader alloc] initWithContentType: @"multipart/related;boundary=X" delegate: nil];
    CAssertEqual(reader.boundary, [@"\r\n--X" dataUsingEncoding: NSUTF8StringEncoding]);
}



TestCase(CBLMultipartReader_Simple) {
    RequireTestCase(CBLMultipartReader_Types);
    NSData* mime = [@"--BOUNDARY\r\nFoo: Bar\r\n Header : Val ue \r\n\r\npart the first\r\n--BOUNDARY  \r\n\r\n2nd part\r\n--BOUNDARY--"
                            dataUsingEncoding: NSUTF8StringEncoding];
        
    NSArray* expectedParts = @[[@"part the first" dataUsingEncoding: NSUTF8StringEncoding],
                                    [@"2nd part" dataUsingEncoding: NSUTF8StringEncoding]];
    NSArray* expectedHeaders = @[$dict({@"Foo", @"Bar"},
                                            {@"Header", @"Val ue"}),
                                      $dict()];

    for (NSUInteger chunkSize = 1; chunkSize <= mime.length; ++chunkSize) {
        Log(@"--- chunkSize = %u", (unsigned)chunkSize);
        CBL_TestMultipartReaderDelegate* delegate = [[CBL_TestMultipartReaderDelegate alloc] init];
        CBLMultipartReader* reader = [[CBLMultipartReader alloc] initWithContentType: @"multipart/related; boundary=\"BOUNDARY\"" delegate: delegate];
        CAssert(!reader.finished);
        
        NSRange r = {0, 0};
        do {
            CAssert(r.location < mime.length, @"Parser didn't stop at end");
            r.length = MIN(chunkSize, mime.length - r.location);
            [reader appendData: [mime subdataWithRange: r]];
            CAssert(!reader.error, @"Reader got a parse error: %@", reader.error);
            r.location += chunkSize;
        } while (!reader.finished);
        CAssertEqual(delegate.partList, expectedParts);
        CAssertEqual(delegate.headerList, expectedHeaders);
    }
}

TestCase(CBLMultipartReader_GZipped) {
    NSData* mime = CBLContentsOfTestFile(@"MultipartStars.mime");
    CBL_TestMultipartReaderDelegate* delegate = [[CBL_TestMultipartReaderDelegate alloc] init];
    CBLMultipartReader* reader = [[CBLMultipartReader alloc] initWithContentType: @"multipart/related; boundary=\"BOUNDARY\"" delegate: delegate];
    [reader appendData: mime];
    Assert(reader.finished);

    CAssertEqual(delegate.headerList, (@[@{@"Content-Encoding": @"gzip",
                                           @"Content-Length": @"24",
                                           @"Content-Type": @"star-bellies"}]));

    NSData* stars = [NSData gtm_dataByInflatingData: delegate.partList[0]];
    AssertEq(stars.length, 100u);
    for (int i=0; i<100; i++)
        AssertEq(((char*)stars.bytes)[i], '*');
}

#endif
