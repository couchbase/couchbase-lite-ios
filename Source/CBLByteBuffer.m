//
//  CBLByteBuffer.m
//  CouchbaseLite
//
//  Created by Robert Payne on 1/03/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

#import "CBLByteBuffer.h"


// Initial capacity of the buffer
#define kInitialCapacity 32768

// How much free space there has to be at the start of _data before we'll slide it down or realloc
#define kCompactionLength 4096

@implementation CBLByteBuffer
{
    NSMutableData *_data;
    NSUInteger _offset;
    NSUInteger _capacity;
}

#pragma mark - Initialization

- (instancetype)init {
    if((self = [super init])) {
        _capacity = kInitialCapacity;
        _data = [NSMutableData dataWithCapacity:_capacity];
        _offset = 0;
    }
    return self;
}

#pragma mark - Actions

- (void)advance:(NSUInteger)amount {
    Assert(_offset + amount <= _data.length);
    _offset += amount;
}

- (BOOL)hasBytesAvailable {
    return _data.length > _offset;
}

- (NSUInteger)bytesAvailable {
    return _data.length - _offset;
}

- (void)appendData:(NSData *)data {
    [self appendBytes: data.bytes length: data.length];
}

- (void)appendBytes:(const void *)bytes length:(NSUInteger)length {
    [self makeRoom: length];
    [_data appendBytes:bytes length:length];
    _capacity = MAX(_capacity, _data.length);
}

- (void)compact {
    [self makeRoom: 0];
}

- (void)makeRoom: (NSUInteger)amount {
    if(_offset > kCompactionLength && _offset > (_data.length >> 1)) {
        void* dst = _data.mutableBytes, *src = dst + _offset;
        NSUInteger curLength = self.bytesAvailable;
        NSUInteger newLength = curLength + amount;
        if (newLength <= _capacity) {
            // There's enough room if we slide everything down:
            memcpy(dst, src, curLength);
            _data.length = curLength;
        } else {
            // No room, allocate a new buffer:
            _capacity = newLength + 1024;
            NSMutableData* newData = [NSMutableData dataWithCapacity: _capacity];
            [newData appendBytes: src length: curLength];
            _data = newData;
        }
        _offset = 0;
    }
}

- (void)reset {
    _offset = 0;
    _data.length = 0;
}

- (const void *)bytes {
    return _data.bytes + _offset;
}

- (void *)mutableBytes {
    return _data.mutableBytes + _offset;
}

- (NSData *)data {
    if (!self.hasBytesAvailable) {
        return nil;
    }
    return [NSData dataWithBytes:self.bytes length:self.bytesAvailable];
}

- (NSData *)subdataWithRangeNoCopy:(NSRange)range {
    Assert(NSMaxRange(range) <= self.bytesAvailable);
    return [[NSData alloc] initWithBytesNoCopy: _data.mutableBytes + _offset + range.location
                                        length: range.length
                                  freeWhenDone: NO];
}

- (NSRange) searchFor: (NSData*)pattern from: (NSUInteger)start {
    start += _offset;
    NSRange r = [_data rangeOfData: pattern
                           options: 0
                             range: NSMakeRange(start, _data.length-start)];
    if (r.length > 0)
        r.location -= _offset;
    return r;
}

@end
