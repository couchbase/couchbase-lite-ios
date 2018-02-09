//
//  CBLBlobStream.m
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLBlobStream.h"
#import "CBLStatus.h"

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
