//
//  TDMultipartWriter.m
//  TouchDB
//
//  Created by Jens Alfke on 1/10/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

//  http://tools.ietf.org/html/rfc2046#section-5.1

#import "TDMultipartWriter.h"
#import "CollectionUtils.h"


@implementation TDMultipartWriter


- (id) initWithContentType: (NSString*)type boundary: (NSString*)boundary {
    self = [super init];
    if (self) {
        _contentType = [type copy];
        _boundary = [boundary copy];
        _body = [[NSMutableData alloc] initWithCapacity: 1024];
    }
    return self;
}


- (id) initWithContentType: (NSString*)type {
    CFUUIDRef uuid = CFUUIDCreate(NULL);
    NSString* boundary = NSMakeCollectable(CFUUIDCreateString(NULL, uuid));
    CFRelease(uuid);
    self = [self initWithContentType: type boundary: boundary];
    [boundary release];
    return self;
}


- (void)dealloc {
    [_contentType release];
    [_boundary release];
    [_body release];
    [super dealloc];
}


- (NSString*) contentType {
    return $sprintf(@"%@; boundary=\"%@\"", _contentType, _boundary);
}


@synthesize body=_body;


- (void) addBoundary {
    [_body appendData: [_boundary dataUsingEncoding: NSUTF8StringEncoding]];
}


- (void) addPart: (NSData*)part withHeaders: (NSDictionary*)headers {
    if (_body.length == 0) {
        [_body appendBytes: "--" length: 2];
        [self addBoundary];
    } else {
        _body.length -= 2;   // remove the trailing "--" added last time
    }
    [_body appendBytes: "\r\n" length: 2];

    for (NSString* name in headers) {
        NSString* line = $sprintf(@"%@: %@\r\n", name, [headers objectForKey: name]);
        [_body appendData: [line dataUsingEncoding: NSUTF8StringEncoding]];
    }

    [_body appendBytes: "\r\n" length: 2];
    [_body appendData: part];
    [_body appendBytes: "\r\n--" length: 4];
    [self addBoundary];
    [_body appendBytes: "--" length: 2];
}


@end



TestCase(TDMultipartWriter) {
    TDMultipartWriter* mp = [[[TDMultipartWriter alloc] initWithContentType: @"multipart/related"
                                                       boundary: @"BOUNDARY"] autorelease];
    CAssertEqual(mp.contentType, @"multipart/related; boundary=\"BOUNDARY\"");
    CAssertEqual(mp.body.my_UTF8ToString, @"");
    [mp addPart: [@"part the first" dataUsingEncoding: NSUTF8StringEncoding]
        withHeaders: nil];
    CAssertEqual(mp.body.my_UTF8ToString,
                 @"--BOUNDARY\r\n\r\npart the first\r\n--BOUNDARY--");
    [mp addPart: [@"2nd part" dataUsingEncoding: NSUTF8StringEncoding]
        withHeaders: nil];
    CAssertEqual(mp.body.my_UTF8ToString,
                 @"--BOUNDARY\r\n\r\npart the first\r\n--BOUNDARY\r\n\r\n2nd part\r\n--BOUNDARY--");
}