//
//  CBLBlobStream.m
//  CouchbaseLite
//
//  Created by Jim Borden on 2017/01/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLBlobStream.h"
#import "CBLCoreBridge.h"


@implementation CBLBlobStream
{
    C4BlobStore* _store;
    C4BlobKey _key;
    C4ReadStream* _readStream;
    BOOL _hasBytesAvailable;
    BOOL _closed;
    C4Error _error;
}


- (instancetype)initWithStore:(C4BlobStore *)store
                          key:(C4BlobKey)key
{
    self = [super init];
    if(self) {
        _store = store;
        _key = key;
        _hasBytesAvailable = NO;
    }
    
    return self;
}


- (void)dealloc {
    c4stream_close(_readStream);
}


- (void)open {
    Assert(!_readStream, @"Stream is already open");
    _readStream = c4blob_openReadStream(_store, _key, &_error);
    if (_readStream) {
        _error.code = 0;
        _hasBytesAvailable = YES;
        _closed = NO;
    }
}


- (void)close {
    if (_readStream) {
        c4stream_close(_readStream);
        _readStream = nullptr;
        _hasBytesAvailable = NO;
        _closed = YES;
        _error.code = 0;
    }
}


- (NSStreamStatus)streamStatus {
    if (_error.code)
        return NSStreamStatusError;
    else if (_closed)
        return NSStreamStatusClosed;
    else if (!_readStream)
        return NSStreamStatusNotOpen;
    else if (_hasBytesAvailable)
        return NSStreamStatusOpen;
    else
        return NSStreamStatusAtEnd;
}


- (BOOL)hasBytesAvailable {
    return _hasBytesAvailable;
}


- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)len {
    Assert(_readStream != nullptr, @"Stream is not open");
    size_t retVal = c4stream_read(_readStream, buffer, len, &_error);
    if (retVal == 0 && _error.code != 0)
        return -1;
    _hasBytesAvailable = retVal > 0 && retVal == len;
    return retVal;
}


- (BOOL)getBuffer:(uint8_t * _Nullable *)buffer length:(NSUInteger *)len {
    Assert(_readStream != nullptr, @"Stream is not open");
    *buffer = nullptr;
    *len = 0;
    return NO;
}


- (NSError*) streamError {
    NSError* error = nil;
    if (_error.code != 0)
        convertError(_error, &error);
    return error;
}


- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSRunLoopMode)mode {
    Assert(NO, @"CBLBlobStream does not support scheduling");
}


@end
