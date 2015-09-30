//
//  CBLGZip.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/26/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import "CBLGZip.h"
#import <zlib.h>

#define kBufferSize (8*1024)


@implementation CBLGZip
{
    z_stream _strm;
    BOOL _open;
    BOOL _compressing;
    uint8_t _buffer[kBufferSize];
}

@synthesize status=_status;


- (instancetype) initForCompressing: (BOOL)compressing {
    self = [super init];
    if (self) {
        _strm.next_out  = _buffer;
        _strm.avail_out = (uInt)kBufferSize;
        _strm.total_out = 0;
        _compressing = compressing;
        int rval;
        if (compressing)
            rval = deflateInit2(&_strm,
                                Z_DEFAULT_COMPRESSION,
                                Z_DEFLATED, // Only legal value
                                15 + 16,    // Default window size, plus write gzip header
                                8,          // Default mem level
                                Z_DEFAULT_STRATEGY);
        else
            rval = inflateInit2(&_strm,
                                15 + 32);   // Default window size, plus accept gzip headers
        if (rval != Z_OK)
            return nil;
        _open = YES;
        _status = Z_OK;
    }
    return self;
}

- (void) dealloc {
    [self close];
}

- (BOOL) close {
    if (_open) {
        int status;
        if (_compressing)
            status = deflateEnd(&_strm);
        else
            status = inflateEnd(&_strm);
        if (_status < Z_OK && _status >= Z_OK)
            _status = status;
        _open = NO;
    }
    return (_status >= Z_OK);
}

- (BOOL) addBytes: (const void*)bytes length: (size_t)length
         onOutput: (void(^)(const void*,size_t))onOutput
{
    if (!_open) {
        if (length == 0)
            return YES;
        if (_status >= 0)
            _status = CBLGZipStatusReadPastEOF;
        return NO;
    }
    _strm.next_in  = (Bytef*) bytes;
    _strm.avail_in = (uInt)length;
    do {
        int rval;
        if (_compressing)
            rval = deflate(&_strm, (length > 0 ? Z_NO_FLUSH : Z_FINISH));
        else
            rval = inflate(&_strm, Z_SYNC_FLUSH);
        if (rval == Z_BUF_ERROR || rval == Z_STREAM_END || length == 0) {
            // Output is full, or at EOF, so deliver it:
            onOutput(_buffer, kBufferSize - _strm.avail_out);
            _strm.next_out  = _buffer;
            _strm.avail_out = (uInt)kBufferSize;
            if (rval == Z_BUF_ERROR)
                rval = Z_OK;
        }
        if (rval != Z_OK) {
            _status = rval;
            [self close];
            return rval == Z_STREAM_END;
        }
    } while (_strm.avail_in > 0 || length == 0);
    return YES;
}

+ (NSData*) processData: (NSData*)input compress: (BOOL)compress {
    NSUInteger capacity = input.length;
    capacity = compress ? (capacity / 2) : (capacity * 2);
    NSMutableData* output = [NSMutableData dataWithCapacity: capacity];
    CBLGZip* gzip = [[self alloc] initForCompressing: compress];
    [gzip addBytes: input.bytes length: input.length onOutput: ^(const void *bytes, size_t len) {
        [output appendBytes: bytes length: len];
    }];
    [gzip addBytes: NULL length: 0 onOutput: ^(const void *bytes, size_t len) {
        [output appendBytes: bytes length: len];
    }];
    if (gzip.status < CBLGZipStatusOK) {
        Warn(@"GZip error %d %scompressing data", gzip.status, (compress ?"" :"de"));
        return nil;
    }
    return output;
}

+ (NSData*) dataByCompressingData: (NSData*)src {
    return [self processData: src compress: YES];
}

+ (NSData*) dataByDecompressingData: (NSData*)src {
    return [self processData: src compress: NO];
}


@end
