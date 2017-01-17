//
//  CBLBlob.m
//  CouchbaseLite
//
//  Created by Jim Borden on 2017/01/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLBlob.h"
#import "CBLInternal.h"
#import "CBLCoreBridge.h"

@implementation CBLBlob

@synthesize content = _content, contentType = _contentType, contentStream = _contentStream,
length = _length, digest = _digest;

- (NSDictionary *)properties {
    return @{
             @"digest":_digest,
             @"length":@(_length),
             @"content-type":_contentType
             };
}

- (instancetype)initWithContentType:(NSString *)contentType data:(NSData *)data {
    self = [super init];
    if(self) {
        _contentType = [contentType copy];
        _content = [data copy];
        _contentStream = [[NSInputStream alloc] initWithData:data];
        _length = [data length];
    }
    
    return self;
}

- (instancetype)initWithContentType:(NSString *)contentType contentStream:(NSInputStream *)stream {
    self = [super init];
    if(self) {
        _contentType = [contentType copy];
        _contentStream = stream;
    }
    
    return self;
}

- (instancetype)initWithContentType:(NSString *)contentType fileURL:(NSURL *)url {
    return [self initWithContentType:contentType contentStream:[[NSInputStream alloc] initWithURL:url]];
}

- (BOOL)install:(C4BlobStore *)store error:(NSError **)error {
    C4Error err;
    C4WriteStream* blobOut = c4blob_openWriteStream(store, &err);
    if(!blobOut) {
        return convertError(err, error);
    }
    
    uint8_t buffer[8192];
    NSInteger bytesRead = 0;
    _length = 0;
    [_contentStream open];
    while((bytesRead = [_contentStream read:buffer maxLength:8192]) > 0) {
        _length += bytesRead;
        if(!c4stream_write(blobOut, buffer, bytesRead, &err)) {
            c4stream_closeWriter(blobOut);
            return convertError(err, error);
        }
    }
    
    C4BlobKey key = c4stream_computeBlobKey(blobOut);
    if(!c4stream_install(blobOut, &err)) {
        c4stream_closeWriter(blobOut);
        return convertError(err, error);
    }
    
    C4SliceResult digestSlice = c4blob_keyToString(key);
    _digest = slice2string(digestSlice);
    c4slice_free(digestSlice);
    
    return YES;
}

- (void)dealloc {
    [_contentStream close];
}

@end
