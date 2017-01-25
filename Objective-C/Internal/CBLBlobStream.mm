//
//  CBLBlobStream.m
//  CouchbaseLite
//
//  Created by Jim Borden on 2017/01/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLBlobStream.h"

@implementation CBLBlobStream
{
    C4ReadStream* _readStream;
    BOOL _hasBytesAvailable;
    C4BlobStore* _store;
    C4BlobKey _key;
}

- (BOOL)hasBytesAvailable {
    if(_readStream == nullptr) {
        return [super hasBytesAvailable];
    }
    
    return _hasBytesAvailable;
}

- (instancetype)initWithStore:(C4BlobStore *)store key:(C4BlobKey)key error:(NSError *__autoreleasing *)error
{
    self = [super init];
    if(self) {
        _store = store;
        _key = key;
        _hasBytesAvailable = NO;
    }
    
    return self;
}

- (void)open {
    _readStream = c4blob_openReadStream(_store, _key, nullptr);
    _hasBytesAvailable = YES;
}

- (void)close {
    C4ReadStream* rs = _readStream;
    _readStream = nullptr;
    c4stream_close(rs);
}

- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)len {
    if(_readStream == nullptr) {
        return [super read:buffer maxLength:len];
    }
    
    C4Error err;
    size_t retVal = c4stream_read(_readStream, buffer, len, &err);
    _hasBytesAvailable = retVal > 0 && retVal == len;
    return retVal;
}

- (BOOL)getBuffer:(uint8_t * _Nullable *)buffer length:(NSUInteger *)len {
    if(_readStream == nullptr) {
        return [super getBuffer:buffer length:len];
    }
    
    *buffer = nullptr;
    *len = 0;
    return NO;
}

- (void)dealloc {
    c4stream_close(_readStream);
}

@end
