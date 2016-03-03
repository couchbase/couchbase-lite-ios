//
//  CBLMultipartBuffer.m
//  CouchbaseLite
//
//  Created by Robert Payne on 1/03/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

#import "CBLMultipartBuffer.h"

@implementation CBLMultipartBuffer {
    NSMutableData *_data;
    NSUInteger _offset;
}

@synthesize compactionLength=_compactionLength;

#pragma mark - Initialization

- (instancetype)init {
    if((self = [super init])) {
        _data = [NSMutableData dataWithCapacity:1024];
        _offset = 0;
        _compactionLength = 4096;
    }
    return self;
}

#pragma mark - Actions

- (BOOL)advance:(NSUInteger)amount {
    if (_offset + amount >= _data.length) {
        Warn(@"Preventing unsafe buffer overflow");
        return NO;
    }
    _offset += amount;
    return YES;
}
- (BOOL)hasBytesAvailable {
    return _data.length > _offset;
}
- (NSUInteger)bytesAvailable {
    return _data.length - _offset;
}
- (void)appendData:(NSData *)data {
    [_data appendData:data];
}
- (void)appendBytes:(const void *)bytes length:(NSUInteger)length {
    [_data appendBytes:bytes length:length];
}
- (void)compact {
    if(_offset > _compactionLength && _offset > (_data.length >> 1)) {
        _data = [NSMutableData dataWithBytes:(char *)_data.bytes + _offset
                                      length:_data.length - _offset];
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
- (NSData *)subdataWithRange:(NSRange)range {
    if (!self.hasBytesAvailable) {
        return nil;
    }
    return [[NSData dataWithBytes:self.bytes length:self.bytesAvailable freeWhenDone:NO] subdataWithRange:range];
}

@end
