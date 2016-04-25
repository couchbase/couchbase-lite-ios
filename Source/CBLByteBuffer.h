//
//  CBLByteBuffer.h
//  CouchbaseLite
//
//  Created by Robert Payne on 1/03/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

/** A queue of bytes that's written to at the end and read from the beginning.  */
@interface CBLByteBuffer : NSObject

/** Removes/consumes bytes from the start of the buffer. */
- (void)advance:(NSUInteger)amount;

/** Whether or not the buffer has bytes available */
@property (readonly) BOOL hasBytesAvailable;

/** The number of bytes the buffer has available */
@property (readonly) NSUInteger bytesAvailable;

/** Appends more data to the buffer */
- (void)appendData:(NSData *)data;

/** Appends raw bytes to the buffer */
- (void)appendBytes:(const void *)bytes length:(NSUInteger)length;

/** Resets the buffer to zero bytes, zero offset */
- (void)reset;

/** An unmutable reference to the buffer's bytes */
@property (readonly) const void* bytes;

/** A mutable reference to the buffer's bytes */
@property (readonly) void* mutableBytes;

/** A copy of the available bytes in the buffer, or nil if there are no available bytes */
@property (readonly) NSData* data;

/** An NSData pointing to (without copying) the available bytes with the given range.
    The result becomes invalid as soon as any more data is written to the buffer. */
- (NSData *)subdataWithRangeNoCopy:(NSRange)range;

/** Searches for the first occurrence of a specific byte string in the buffer. */
- (NSRange) searchFor: (NSData*)pattern from: (NSUInteger)start;

@end
