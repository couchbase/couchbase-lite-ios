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
{
    NSData *_content;
    NSInputStream *_contentStream;
}

@synthesize contentType = _contentType, length = _length, digest = _digest;

- (NSDictionary *)properties {
    return @{
             @"digest":_digest,
             @"length":@(_length),
             @"content-type":_contentType
             };
}

- (NSDictionary *)jsonRepresentation {
    return @{
             @"_cbltype":@"blob",
             @"digest":_digest,
             @"length":@(_length),
             @"content-type":_contentType
             };
}

- (NSData *)content {
    if(_content != nil) {
        return _content;
    }
    
    NSMutableData *result = [NSMutableData new];
    uint8_t buffer[8192];
    NSInteger bytesRead;
    [_contentStream open];
    while((bytesRead = [_contentStream read:buffer maxLength:8192]) > 0) {
        [result appendBytes:buffer length:bytesRead];
    }
    [_contentStream close];
    
    _content = [result copy];
    return _content;
}

- (NSInputStream *)contentStream {
    if(_contentStream != nil) {
        return _contentStream;
    }
    
    return [[NSInputStream alloc] initWithData:_content];
}

- (BOOL)validateNonNullFor:(NSString *)pathName
                     value:(id)value
                     error:(NSError **)outError {
    if(value == nil) {
        NSString *msg = [NSString stringWithFormat:@"CBLBlob cannot have nil %@", pathName];
        if(outError != nil) {
            *outError = [NSError errorWithDomain:@"LiteCore" code:kC4ErrorInvalidParameter userInfo:
                         @{NSLocalizedDescriptionKey:msg}];
        }
        
        return NO;
    }
    
    return YES;
}

- (instancetype)initWithContentType:(NSString *)contentType data:(NSData *)data error:(NSError * _Nullable __autoreleasing * _Nullable)outError {
    self = [super init];
    if(self) {
        if(![self validateNonNullFor:@"contentType" value:contentType error:outError] ||
           ![self validateNonNullFor:@"data" value:data error:outError]) {
            return nil;
        }
        
        _contentType = [contentType copy];
        _content = [data copy];
        _length = [data length];
    }
    
    return self;
}

- (instancetype)initWithContentType:(NSString *)contentType contentStream:(NSInputStream *)stream error:(NSError * _Nullable __autoreleasing * _Nullable)outError {
    self = [super init];
    if(self) {
        if(![self validateNonNullFor:@"contentType" value:contentType error:outError] ||
           ![self validateNonNullFor:@"stream" value:stream error:outError]) {
            return nil;
        }
        
        _contentType = [contentType copy];
        _contentStream = stream;
    }
    
    return self;
}

- (instancetype)initWithContentType:(NSString *)contentType fileURL:(NSURL *)url error:(NSError * _Nullable __autoreleasing * _Nullable)outError {
    return [self initWithContentType:contentType contentStream:[[NSInputStream alloc] initWithURL:url] error:outError];
}

- (instancetype)initWithProperties:(NSDictionary *)properties dataStream:(CBLBlobStream *)stream error:(NSError * _Nullable __autoreleasing * _Nullable)outError {
    self = [self initWithContentType:properties[@"content-type"] contentStream:(NSInputStream *)stream error:outError];
    if(self) {
        if(![self validateNonNullFor:@"properties" value:properties error:outError]) {
            return nil;
        }
        
        _length = [properties[@"length"] integerValue];
        _digest = properties[@"digest"];
    }
    
    return self;
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
    NSInputStream *contentStream = [self contentStream];
    [contentStream open];
    while((bytesRead = [contentStream read:buffer maxLength:8192]) > 0) {
        _length += bytesRead;
        if(!c4stream_write(blobOut, buffer, bytesRead, &err)) {
            [contentStream close];
            c4stream_closeWriter(blobOut);
            return convertError(err, error);
        }
    }
    
    [contentStream close];
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
