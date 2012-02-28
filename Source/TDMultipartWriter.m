//
//  TDMultipartWriter.m
//  TouchDB
//
//  Created by Jens Alfke on 2/2/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TDMultipartWriter.h"
#import "TDMisc.h"
#import "CollectionUtils.h"
#import "Test.h"


@implementation TDMultipartWriter


- (id) initWithContentType: (NSString*)type boundary: (NSString*)boundary {
    self = [super init];
    if (self) {
        _contentType = [type copy];
        _boundary = [(boundary ?: TDCreateUUID()) copy];
        NSString* separatorStr = $sprintf(@"\r\n--%@\r\n\r\n", _boundary);
        _separatorData = [[separatorStr dataUsingEncoding: NSUTF8StringEncoding] retain];
        // Account for the final boundary to be written by -open. Add it in now, because the
        // client is probably going to ask for my .length *before* it calls -open.
        _length += _separatorData.length - 2;
    }
    return self;
}


- (void)dealloc {
    [_boundary release];
    [_separatorData release];
    [super dealloc];
}


@synthesize boundary=_boundary, length=_length;


- (NSString*) contentType {
    return $sprintf(@"%@; boundary=\"%@\"", _contentType, _boundary);
}


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
    NSDictionary* info = [[NSFileManager defaultManager] attributesOfItemAtPath: path error: NULL];
    if (!info)
        return NO;
    if (![super addFile: path])
        return NO;
    _length += [info fileSize];
    return YES;
}
     
     
- (void) opened {
    // Append the final boundary:
    NSString* trailerStr = $sprintf(@"\r\n--%@--", _boundary);
    NSData* trailerData = [trailerStr dataUsingEncoding: NSUTF8StringEncoding];
    [super addStream: [NSInputStream inputStreamWithData: trailerData]];
    // _length was already adjusted for this in -init
    
    [super opened];
}


- (void) openForURLRequest: (NSMutableURLRequest*)request;
{
    request.HTTPBodyStream = [self openForInputStream];
    [request setValue: self.contentType forHTTPHeaderField: @"Content-Type"];
}


@end





TestCase(TDMultipartWriter) {
    NSString* expectedOutput = @"\r\n--BOUNDARY\r\n\r\n<part the first>\r\n--BOUNDARY\r\nContent-Type: something\r\n\r\n<2nd part>\r\n--BOUNDARY--";
    RequireTestCase(TDMultiStreamWriter);
    for (unsigned bufSize = 1; bufSize < expectedOutput.length+1; ++bufSize) {
        TDMultipartWriter* mp = [[[TDMultipartWriter alloc] initWithContentType: @"foo/bar" 
                                                                           boundary: @"BOUNDARY"] autorelease];
        CAssertEqual(mp.contentType, @"foo/bar; boundary=\"BOUNDARY\"");
        CAssertEqual(mp.boundary, @"BOUNDARY");
        [mp addData: [@"<part the first>" dataUsingEncoding: NSUTF8StringEncoding]];
        [mp setNextPartsHeaders: $dict({@"Content-Type", @"something"})];
        [mp addData: [@"<2nd part>" dataUsingEncoding: NSUTF8StringEncoding]];
        CAssertEq(mp.length, expectedOutput.length);

        NSData* output = [mp allOutput];
        CAssertEqual(output.my_UTF8ToString, expectedOutput);
        [mp close];
    }
}
