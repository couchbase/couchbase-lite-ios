//
//  CBL_BlobStore.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/10/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBL_BlobStore.h"
#import "CBLSymmetricKey.h"
#import "CBLBase64.h"
#import "CBLMisc.h"
#import "CBLStatus.h"
#import <ctype.h>


#ifdef GNUSTEP
#define NSDataReadingMappedIfSafe NSMappedRead
#define NSDataWritingAtomic NSAtomicWrite
#endif

#define kFileExtension "blob"


@implementation CBL_BlobStore
{
    NSString* _tempDir;
}


@synthesize path=_path, encryptionKey=_encryptionKey;


- (instancetype) initWithPath: (NSString*)dir error: (NSError**)outError {
    Assert(dir);
    self = [super init];
    if (self) {
        _path = [dir copy];
        BOOL isDir;
        if (![[NSFileManager defaultManager] fileExistsAtPath: dir isDirectory: &isDir] || !isDir) {
            if (![[NSFileManager defaultManager] createDirectoryAtPath: dir
                                           withIntermediateDirectories: NO
                                                            attributes: nil
                                                                 error: outError]) {
                return nil;
            }
        }
    }
    return self;
}


+ (CBLBlobKey) keyForBlob: (NSData*)blob {
    NSCParameterAssert(blob);
    CBLBlobKey key;
    SHA_CTX ctx;
    SHA1_Init(&ctx);
    SHA1_Update(&ctx, blob.bytes, blob.length);
    SHA1_Final(key.bytes, &ctx);
    return key;
}

+ (NSData*) keyDataForBlob: (NSData*)blob {
    CBLBlobKey key = [self keyForBlob: blob];
    return [NSData dataWithBytes: &key length: sizeof(key)];
}


// Internal only. This file might be encrypted.
- (NSString*) rawPathForKey: (CBLBlobKey)key {
    char out[2*sizeof(key.bytes) + 1 + strlen(kFileExtension) + 1];
    char *dst = &out[0];
    for( size_t i=0; i<sizeof(key.bytes); i+=1 )
        dst += sprintf(dst,"%02X", key.bytes[i]);
    strlcat(out, ".", sizeof(out));
    strlcat(out, kFileExtension, sizeof(out));
    NSString* name =  [[NSString alloc] initWithCString: out encoding: NSASCIIStringEncoding];
    NSString* path = [_path stringByAppendingPathComponent: name];
    return path;
}

- (NSString*) blobPathForKey: (CBLBlobKey)key {
    if (_encryptionKey)
        return nil;
    return [self rawPathForKey: key];
}


+ (BOOL) getKey: (CBLBlobKey*)outKey forFilename: (NSString*)filename {
    if (filename.length != 2*sizeof(CBLBlobKey) + 1 + strlen(kFileExtension))
        return NO;
    if (![filename hasSuffix: @"."kFileExtension])
        return NO;
    if (outKey) {
        uint8_t* dst = &outKey->bytes[0];
        for (unsigned i=0; i<sizeof(CBLBlobKey); ++i) {
            unichar digit1 = [filename characterAtIndex: 2*i];
            unichar digit2 = [filename characterAtIndex: 2*i+1];
            if (!isxdigit(digit1) || !isxdigit(digit2))
                return NO;
            *dst++ = (uint8_t)( 16*digittoint(digit1) + digittoint(digit2) );
        }
    }
    return YES;
}


- (BOOL) hasBlobForKey: (CBLBlobKey)key {
    return [[NSFileManager defaultManager] fileExistsAtPath: [self rawPathForKey: key]
                                                isDirectory: NULL];
}


- (NSData*) blobForKey: (CBLBlobKey)key {
    NSString* path = [self rawPathForKey: key];
    NSData* blob =  [NSData dataWithContentsOfFile: path options: NSDataReadingMappedIfSafe
                                             error: NULL];
    if (_encryptionKey && blob) {
        blob = [_encryptionKey decryptData: blob];
        CBLBlobKey decodedKey = [[self class] keyForBlob: blob];
        if (memcmp(&key, &decodedKey, sizeof(key)) != 0) {
            Warn(@"Attachment %@ decoded incorrectly!", path);
            blob = nil;
        }
    }
    return blob;
}

- (NSInputStream*) blobInputStreamForKey: (CBLBlobKey)key
                                  length: (UInt64*)outLength
{
    NSString* path = [self rawPathForKey: key];
    if (outLength) {
        if (_encryptionKey) {
            *outLength = 0; // not known
        } else {
            NSDictionary* info = [[NSFileManager defaultManager] attributesOfItemAtPath: path
                                                                                  error: NULL];
            if (!info)
                return nil;
            *outLength = [info fileSize];
        }
    }
    NSInputStream* stream = [NSInputStream inputStreamWithFileAtPath: path];
    [stream open];
    if (_encryptionKey)
        stream = [_encryptionKey decryptStream: stream];
    return stream;
}

- (BOOL) storeBlob: (NSData*)blob
       creatingKey: (CBLBlobKey*)outKey
{
    *outKey = [[self class] keyForBlob: blob];
    NSString* path = [self rawPathForKey: *outKey];
    if ([[NSFileManager defaultManager] isReadableFileAtPath: path])
        return YES;

    if (_encryptionKey) {
        blob = [_encryptionKey encryptData: blob];
        if (!blob) {
            Warn(@"CBL_BlobStore: Failed to encode data for %@", path);
            return NO;
        }
    }

    NSError* error;
    if (![blob writeToFile: path options: NSDataWritingAtomic error: &error]) {
        Warn(@"CBL_BlobStore: Couldn't write to %@: %@", path, error);
        return NO;
    }
    return YES;
}


- (NSArray*) allKeys {
    NSArray* blob = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: _path
                                                                            error: NULL];
    if (!blob)
        return nil;
    return [blob my_map: ^NSData*(id filename) {
        CBLBlobKey key;
        if ([[self class] getKey: &key forFilename: filename])
            return [NSData dataWithBytes: &key length: sizeof(key)];
        else
            return nil;
    }];
}


- (NSUInteger) count {
    NSUInteger n = 0;
    NSFileManager* fmgr = [NSFileManager defaultManager];
    for (NSString* filename in [fmgr contentsOfDirectoryAtPath: _path error: NULL]) {
        if ([[self class] getKey: NULL forFilename: filename])
            ++n;
    }
    return n;
}


- (UInt64) totalDataSize {
    UInt64 total = 0;
    NSFileManager* fmgr = [NSFileManager defaultManager];
    for (NSString* filename in [fmgr contentsOfDirectoryAtPath: _path error: NULL]) {
        if ([[self class] getKey: NULL forFilename: filename]) {
            NSString* itemPath = [_path stringByAppendingPathComponent: filename];
            NSDictionary* attrs = [fmgr attributesOfItemAtPath: itemPath error: NULL];
            if (attrs)
                total += attrs.fileSize;
        }
    }
    return total;
}


- (NSInteger) deleteBlobsExceptMatching: (BOOL(^)(CBLBlobKey))predicate
                                  error: (NSError**)outError
{
    NSFileManager* fmgr = [NSFileManager defaultManager];
    NSArray* blob = [fmgr contentsOfDirectoryAtPath: _path error: outError];
    if (!blob)
        return -1;
    NSUInteger numDeleted = 0;
    NSError* error = nil;
    for (NSString* filename in blob) {
        CBLBlobKey curKey;
        if ([[self class] getKey: &curKey forFilename: filename]) {
            if (!predicate(curKey)) {
                NSError* error1;
                if ([fmgr removeItemAtPath: [_path stringByAppendingPathComponent: filename]
                                     error: &error1])
                    ++numDeleted;
                else {
                    if (!error)
                        error = error1;
                    Warn(@"%@: Failed to delete '%@': %@", self, filename, error);
                }
            }
        }
    }
    if (error) {
        if (outError)
            *outError = error;
        return -1;
    }
    return numDeleted;
}


- (NSString*) tempDir {
    if (!_tempDir) {
        // Find a temporary directory suitable for files that will be moved into the store:
#ifdef GNUSTEP
        _tempDir = [NSTemporaryDirectory() copy];
#else
        NSError* error;
        NSURL* parentURL = [NSURL fileURLWithPath: _path isDirectory: YES];
        NSURL* tempDirURL = [[NSFileManager defaultManager] 
                                                 URLForDirectory: NSItemReplacementDirectory
                                                 inDomain: NSUserDomainMask
                                                 appropriateForURL: parentURL
                                                 create: YES error: &error];
        _tempDir = [tempDirURL.path copy];
        Log(@"CBL_BlobStore %@ created tempDir %@", _path, _tempDir);
        if (!_tempDir)
            Warn(@"CBL_BlobStore: Unable to create temp dir: %@", error);
#endif
    }
    return _tempDir;
}


@end




@implementation CBL_BlobStoreWriter
{
    @private
    CBL_BlobStore* _store;
    NSString* _tempPath;
    NSFileHandle* _out;
    UInt64 _length;
    SHA_CTX _shaCtx;
    MD5_CTX _md5Ctx;
    CBLBlobKey _blobKey;
    CBLMD5Key _MD5Digest;
    CBLCryptorBlock _encryptor;
}
@synthesize length=_length, blobKey=_blobKey;

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
        if (![[NSFileManager defaultManager] createFileAtPath: _tempPath
                                                     contents: nil
                                                   attributes: nil]) {
            return nil;
        }
        _out = [NSFileHandle fileHandleForWritingAtPath: _tempPath];
        if (!_out) {
            return nil;
        }
        CBLSymmetricKey* encryptionKey = _store.encryptionKey;
        if (encryptionKey)
            _encryptor = [encryptionKey createEncryptor];
    }
    return self;
}

- (void) appendData: (NSData*)data {
    NSUInteger dataLen = data.length;
    _length += dataLen;
    SHA1_Update(&_shaCtx, data.bytes, dataLen);
    MD5_Update(&_md5Ctx, data.bytes, dataLen);

    if (_encryptor)
        data = _encryptor(data);
    [_out writeData: data];
}

- (void) closeFile {
    if (_encryptor) {
        [_out writeData: _encryptor(nil)];  // write remaining encrypted data & clean up
        _encryptor = nil;
    }
    [_out closeFile];
    _out = nil;    
}

- (void) finish {
    Assert(_out, @"Already finished");
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
    return YES;
}

- (void) cancel {
    [self closeFile];
    if (_tempPath) {
        [[NSFileManager defaultManager] removeItemAtPath: _tempPath error: NULL];
        _tempPath = nil;
    }
}

- (void) dealloc {
    [self cancel];      // Close file, and delete it if it hasn't been installed yet
}


@end
