//
//  CBLMultipartBuffer.h
//  CouchbaseLite
//
//  Created by Robert Payne on 1/03/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

/** Streaming MIME multipart parsing buffer  */
@interface CBLMultipartBuffer : NSObject

/** The amount of bytes the buffer must be offset of before a compaction can happen */
@property (nonatomic, assign) NSUInteger compactionLength;

/** Advances the offset of the bytes pointers, will return NO if there is not enough memory left to advance */
- (BOOL)advance:(NSUInteger)amount;

/** Whether or not the buffer has bytes available */
- (BOOL)hasBytesAvailable;

/** The number of bytes the buffer has available */
- (NSUInteger)bytesAvailable;

/** Append more data to the buffer */
- (void)appendData:(NSData *)data;

/** Append raw bytes to the buffer */
- (void)appendBytes:(const void *)bytes length:(NSUInteger)length;

/** Compact the buffer, if the buffer's offset >= compactionLength the offset will be reset to offset - compactionLength and bytes removed */
- (void)compact;

/** Resets the buffer to zero bytes, zero offset */
- (void)reset;

/** An unmutable reference the buffers bytes */
- (const void *)bytes;

/** An mutable reference the buffers bytes */
- (void *)mutableBytes;

/** A NSData copy of the buffer */
- (NSData *)data;

@end
