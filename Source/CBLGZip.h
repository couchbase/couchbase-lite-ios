//
//  CBLGZip.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/26/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>


@protocol CBLCodec
/** Adds data to the codec.
    This may generate output data, which will be passed to the onOutput block. 
    A single call to this method might not invoke the output block at all, or on the other
    hand it might invoke it multple times.

    When compressing, you must tell the codec the input is complete by calling it one more time
    with a length of zero. This will trigger it to output the remaining buffered data.

    The return value is YES on success, NO on error. */
- (BOOL) addBytes: (const void*)bytes
           length: (size_t)length
         onOutput: (void(^)(const void*,size_t))onOutput;

/** The codec's current status. */
@property (readonly) int status;
@end



typedef enum : int {
    CBLGZipStatusOK = 0,
    CBLGZipStatusEOF = 1,    // decompressor reached EOF; not an error
    CBLGZipStatusErrno = -1,
    CBLGZipStatusStreamError = -2,
    CBLGZipStatusDataError = -3,
    CBLGZipStatusMemError = -4,
    CBLGZipStatusBufError = -5,
    CBLGZipStatusVersionError = -6,
    CBLGZipStatusReadPastEOF = -100  // not part of zlib C API
} CBLGZipStatus;



/** Incremental, stream-like GZip compressor/decompressor. */
@interface CBLGZip : NSObject <CBLCodec>

/** Initializes a codec instance.
    @param compressing  YES to compress, NO to decompress.
    @return  The initialized instance. */
- (instancetype)initForCompressing: (BOOL)compressing;

/** One-shot compression of NSData. */
+ (NSData*) dataByCompressingData: (NSData*)src;

/** One-shot decompression of NSData. */
+ (NSData*) dataByDecompressingData: (NSData*)src;

@end
