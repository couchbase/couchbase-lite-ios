//
//  CBL_BlobStoreWriter.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/19/15.
//  Copyright © 2015 Couchbase, Inc. All rights reserved.
//

#import "CBL_BlobStoreWriter.h"
#import "CBL_BlobStore+Internal.h"
#import "CBLSymmetricKey.h"
#import "CBLBase64.h"
#import "CBLMisc.h"
#import "CBLProgressGroup.h"
#import "MYBlockUtils.h"

#ifdef GNUSTEP
#import <openssl/md5.h>
#endif


typedef struct {
    uint8_t bytes[MD5_DIGEST_LENGTH];
} CBLMD5Key;


@implementation CBL_BlobStoreWriter
{
    @private
    CBL_BlobStore* _store;
    NSString* _tempPath;
    NSFileHandle* _out;
    uint64_t _contentLength;
    SHA_CTX _shaCtx;
    MD5_CTX _md5Ctx;
    CBLMD5Key _MD5Digest;
    CBLCryptorBlock _encryptor;
    CBLProgressGroup* _progress;
}
@synthesize name=_name, bytesWritten=_bytesWritten, contentLength=_contentLength;
@synthesize blobKey=_blobKey, eTag=_eTag;


- (instancetype) initWithStore: (CBL_BlobStore*)store {
    self = [super init];
    if (self) {
        _store = store;
        SHA1_Init(&_shaCtx);
        MD5_Init(&_md5Ctx);
                
        // Open a temporary file in the store's temporary directory: 
        NSString* filename = [CBLCreateUUID() stringByAppendingPathExtension: @"blobtmp"];
        _tempPath = [[_store.tempDir stringByAppendingPathComponent: filename] copy];
        if (!_tempPath) {
            return nil;
        }
        // -fileHandleForWritingAtPath stupidly fails if the file doesn't exist, so we first have
        // to create it:
        int fd = open(_tempPath.fileSystemRepresentation, O_CREAT | O_TRUNC | O_WRONLY, 0600);
        if (fd < 0) {
            Warn(@"CBL_BlobStoreWriter can't create temp file at %@ (errno %d)", _tempPath, errno);
            return nil;
        }
        close(fd);
        if (![self openFile])
            return nil;
        CBLSymmetricKey* encryptionKey = _store.encryptionKey;
        if (encryptionKey)
            _encryptor = [encryptionKey createEncryptor];
}
    return self;
}


- (void) setProgress:(CBLProgressGroup *)progress {
    _progress = progress;
    if (_contentLength > 0) {
        progress.totalUnitCount = _contentLength;
        progress.completedUnitCount = _bytesWritten;
    }
}

- (void) setContentLength:(UInt64)contentLength {
    _contentLength = contentLength;
    _progress.totalUnitCount = contentLength;
}

- (CBLProgressGroup*) progress {
    return _progress;
}

- (void) appendData: (NSData*)data {
    Assert(_out, @"Not open");
    NSUInteger dataLen = data.length;
    _bytesWritten += dataLen;
    _progress.completedUnitCount = _bytesWritten;
    SHA1_Update(&_shaCtx, data.bytes, dataLen);
    MD5_Update(&_md5Ctx, data.bytes, dataLen);

    if (_encryptor)
        data = _encryptor(data);
    [_out writeData: data];
}


- (BOOL) appendInputStream: (NSInputStream*)readStream error: (NSError**)outError {
    while(YES) {
        @autoreleasepool {
            uint8_t buf[16384];
            NSInteger bytesRead = [readStream read: buf maxLength: sizeof(buf)];
            if (bytesRead > 0) {
                NSData* input = [[NSData alloc] initWithBytesNoCopy: buf length: bytesRead
                                                       freeWhenDone: NO];
                [self appendData: input];
            } else if (bytesRead == 0) {
                return YES;
            } else {
                if (outError)
                    *outError = readStream.streamError;
                return NO;
            }
        }
    }
}


- (void) closeFile {
    [_out closeFile];
    _out = nil;    
}


- (BOOL) openFile {
    if (_out)
        return YES;
    _out = [NSFileHandle fileHandleForWritingAtPath: _tempPath];
    if (!_out) {
        BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath: _tempPath];
        Warn(@"CBL_BlobStoreWriter: Unable to get a file handle for the temp file at "
             "%@ (exists: %@)", _tempPath, (exists ? @"yes" : @"no"));
        return NO;
    }
    [_out seekToEndOfFile];
    return YES;
}


- (void) reset {
    [_out truncateFileAtOffset: 0];
    SHA1_Init(&_shaCtx);
    MD5_Init(&_md5Ctx);
    _progress.completedUnitCount = 0;
}


- (void) finish {
    Assert(_out, @"Already finished");
    if (_encryptor) {
        [_out writeData: _encryptor(nil)];  // write remaining encrypted data & clean up
        _encryptor = nil;
    }
    [self closeFile];
    SHA1_Final(_blobKey.bytes, &_shaCtx);
    MD5_Final(_MD5Digest.bytes, &_md5Ctx);
}


- (NSString*) MD5DigestString {
    return [@"md5-" stringByAppendingString: [CBLBase64 encode: &_MD5Digest
                                                        length: sizeof(_MD5Digest)]];
}


- (NSString*) SHA1DigestString {
    return [@"sha1-" stringByAppendingString: [CBLBase64 encode: &_blobKey
                                                         length: sizeof(_blobKey)]];
}


- (BOOL) verifyDigest: (NSString*)digestString {
    if (digestString == nil)
        return YES;
    NSString* actualDigest;
    if ([digestString hasPrefix: @"md5-"])
        actualDigest = self.MD5DigestString;
    else
        actualDigest = self.SHA1DigestString;
    if ([actualDigest isEqualToString: digestString]) {
        return YES;
    } else {
        Warn(@"Attachment '%@' has incorrect data (digests to %@; expected %@)",
             _name, actualDigest, digestString);
        return NO;
    }
}


- (NSData*) blobData {
    Assert(!_out, @"Not finished yet");
    NSData* data = [NSData dataWithContentsOfFile: _tempPath
                                          options: NSDataReadingMappedIfSafe
                                            error: NULL];
    CBLSymmetricKey* encryptionKey = _store.encryptionKey;
    if (encryptionKey && data)
        data = [encryptionKey decryptData: data];
    return data;
}


- (NSInputStream*) blobInputStream {
    Assert(!_out, @"Not finished yet");
    NSInputStream* stream = [NSInputStream inputStreamWithFileAtPath: _tempPath];
    [stream open];
    CBLSymmetricKey* encryptionKey = _store.encryptionKey;
    if (encryptionKey && stream)
        stream = [encryptionKey decryptStream: stream];
    return stream;
}


- (NSString*) filePath {
    return _store.encryptionKey ? nil : _tempPath;
}


- (BOOL) install {
    if (!_tempPath)
        return YES;  // already installed
    Assert(!_out, @"Not finished");
    // Move temp file to correct location in blob store:
    NSString* dstPath = [_store rawPathForKey: _blobKey];
    if ([[NSFileManager defaultManager] moveItemAtPath: _tempPath
                                                toPath: dstPath error:NULL]) {
        _tempPath = nil;
    } else {
        // If the move fails, assume it means a file with the same name already exists; in that
        // case it must have the identical contents, so we're still OK.
        [self cancel];
    }

    // mark progress as complete now that the attachment is available:
    [_progress finished];
return YES;
}


- (void) cancel {
    [self closeFile];
    _encryptor = nil;
    if (_tempPath) {
        [[NSFileManager defaultManager] removeItemAtPath: _tempPath error: NULL];
        _tempPath = nil;
    }
}


- (void) dealloc {
    [self cancel];      // Close file, and delete it if it hasn't been installed yet
}


@end
