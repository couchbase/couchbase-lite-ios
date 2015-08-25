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
#import "CBL_BlobStore+Internal.h"
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

#define kEncryptionAlgorithm @"AES"


@implementation CBL_BlobStore
{
    NSString* _tempDir;
}


@synthesize path=_path, encryptionKey=_encryptionKey;


// private
- (instancetype) initInternalWithPath: (NSString*)dir
                        encryptionKey: (CBLSymmetricKey*)encryptionKey
{
    Assert(dir);
    self = [super init];
    if (self) {
        _path = [dir copy];
        _encryptionKey = encryptionKey;
    }
    return self;
}


- (instancetype) initWithPath: (NSString*)dir
                encryptionKey: (CBLSymmetricKey*)encryptionKey
                        error: (NSError**)outError
{
    self = [self initInternalWithPath: dir encryptionKey: encryptionKey];
    if (self) {
        BOOL isDir;
        if ([[NSFileManager defaultManager] fileExistsAtPath: dir isDirectory: &isDir] && isDir) {
            // Existing blob-store.
            if (![self verifyExistingStore: outError])
                return nil;
        } else {
            // New blob store; create directory:
            if (![[NSFileManager defaultManager] createDirectoryAtPath: dir
                                           withIntermediateDirectories: NO
                                                            attributes: nil
                                                                 error: outError]) {
                return nil;
            }
            if (encryptionKey) {
                if (![self markEncrypted: YES error: outError])  // note it's encrypted
                    return nil;
            }
        }
    }
    return self;
}


- (BOOL) verifyExistingStore: (NSError**)outError {
    NSString* markerPath = [_path stringByAppendingPathComponent: kEncryptionMarkerFilename];
    NSError* error;
    NSString* encryptionAlg = [NSString stringWithContentsOfFile: markerPath
                                                 encoding: NSUTF8StringEncoding
                                                    error: &error];
    if (encryptionAlg) {
        // "_encryption" file is present, so make sure we support its format & have a key:
        if (!_encryptionKey) {
            Warn(@"Opening encrypted blob-store without providing a key");
            return CBLStatusToOutNSError(kCBLStatusUnauthorized, outError);
        } else if (!$equal(encryptionAlg, kEncryptionAlgorithm)) {
            Warn(@"Blob-store uses unrecognized encryption '%@'", encryptionAlg);
            return CBLStatusToOutNSError(kCBLStatusUnauthorized, outError);
        }
    } else if (CBLIsFileNotFoundError(error)) {
        // No "_encryption" file was found, so on-disk store isn't encrypted:
        CBLSymmetricKey* encryptionKey = _encryptionKey;
        if (encryptionKey) {
            // This store was created before the db encryption fix, so its files are not
            // encrypted, even though they should be. Remedy that:
            NSLog(@"**** BlobStore should be encrypted; fixing it now...");
            _encryptionKey = nil;
            if (![self changeEncryptionKey: encryptionKey error: outError])
                return NO;
        }
    } else {
        // "_encryption" file was unreadable:
        if (outError) *outError = error;
        return NO;
    }
    return YES;
}


- (void) dealloc {
    if (_tempDir)
        [[NSFileManager defaultManager] removeItemAtPath: _tempDir error: NULL];
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
    NSData* blob = [NSData dataWithContentsOfFile: path options: NSDataReadingUncached error: NULL];
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
    if (_encryptionKey) {
        [stream open];
        stream = [_encryptionKey decryptStream: stream];
    }
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


// Adds/removes the "_encryption" file that marks an encrypted blob-store
- (BOOL) markEncrypted: (BOOL)encrypted error: (NSError**)outError {
    NSString* encMarkerPath = [_path stringByAppendingPathComponent: kEncryptionMarkerFilename];
    if (encrypted) {
        return [kEncryptionAlgorithm writeToFile: encMarkerPath atomically: YES
                                        encoding: NSUTF8StringEncoding error: outError];
    } else {
        return CBLRemoveFileIfExists(encMarkerPath, outError);
    }
}


- (BOOL) changeEncryptionKey: (CBLSymmetricKey*)newKey error: (NSError**)outError {
    // Find all the blob files:
    Log(@"CBLBlobStore: %@ %@", (newKey ? @"encrypting" : @"decrypting"), _path);
    NSFileManager* fmgr = [NSFileManager defaultManager];
    NSArray* blobs = [fmgr contentsOfDirectoryAtPath: _path error: outError];
    if (!blobs)
        return NO;
    blobs = [blobs pathsMatchingExtensions: @[@kFileExtension]];
    if (blobs.count == 0) {
        // No blobs, so nothing to encrypt. Just add/remove the encryption marker file:
        Log(@"    No blobs to copy; done.");
        _encryptionKey = newKey;
        return [self markEncrypted: (newKey != nil) error: outError];
    }

    // Create a new empty attachment store with the new encryption key:
    NSString* tempPath = [self createTempDir: outError];
    if (!tempPath)
        return NO;
    CBL_BlobStore* tempStore = [[CBL_BlobStore alloc] initInternalWithPath: tempPath
                                                             encryptionKey: newKey];
    if (![tempStore markEncrypted: (newKey != nil) error: outError])
        return NO;

    // Copy each of my blobs into the new store (which will update its encryption):
    BOOL ok = YES;
    for (NSString* blobName in blobs) {
        // Copy file by reading with old key and writing with new one:
        Log(@"    Copying %@", blobName);
        NSString* srcFile = [_path stringByAppendingPathComponent: blobName];
        NSInputStream* readStream = [NSInputStream inputStreamWithFileAtPath: srcFile];
        [readStream open];
        if (readStream.streamError) {
            if (outError)
                *outError = readStream.streamError;
            [readStream close];
            ok = NO;
            break;
        }
        if (_encryptionKey)
            readStream = [_encryptionKey decryptStream: readStream];

        CBL_BlobStoreWriter* writer = [[CBL_BlobStoreWriter alloc] initWithStore: tempStore];
        ok = [writer appendInputStream: readStream error: outError];
        [readStream close];
        if (ok) {
            [writer finish];
            [writer install];
        } else {
            [writer cancel];
            break;
        }
    }

    if (ok) {
        // Replace my directory with the new one:
        Log(@"    Installing new blob store %@", tempPath);
        if (CBLSafeReplaceDir(tempPath, _path, outError))
            _encryptionKey = newKey;
        else
            ok = NO;
    }
    if (!ok) {
        Warn(@"Changing blob-store encryption key failed! path= %@ ; error=%@",
             _path, (outError ? *outError : nil));
        [fmgr removeItemAtPath: tempPath error: NULL];
    }
    return ok;
}


- (NSString*) tempDir {
    if (!_tempDir) {
        // Find a temporary directory suitable for files that will be moved into the store:
        _tempDir = [self createTempDir: NULL];
        LogTo(CBLDatabase, @"CBL_BlobStore %@ created tempDir %@", _path, _tempDir);
    }
    return _tempDir;
}


- (NSString*) createTempDir: (NSError**)outError {
    NSError* error;
    NSString* tempDir;
#ifdef GNUSTEP
    NSString* name = $sprintf(@"CouchbaseLite-Temp-%@", CBLCreateUUID());
    tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent: name];
    NSDictionary* attrs = @{NSFilePosixPermissions: @(0700)};
    if (![[NSFileManager defaultManager] createDirectoryAtPath: tempDir
                                   withIntermediateDirectories: YES
                                                    attributes: attrs
                                                         error: &error])
        tempDir = nil;
#else
    NSURL* parentURL = [NSURL fileURLWithPath: _path isDirectory: YES];
    tempDir = [[[NSFileManager defaultManager] URLForDirectory: NSItemReplacementDirectory
                                                      inDomain: NSUserDomainMask
                                             appropriateForURL: parentURL
                                                        create: YES
                                                         error: &error] path];
#endif
    if (!tempDir) {
        Warn(@"CBL_BlobStore: Unable to create temp dir: %@", error);
        if (outError) *outError = error;
    }
    return tempDir;
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
            Warn(@"CBL_BlobStoreWriter: Unable to create a temp file at %@", _tempPath);
            return nil;
        }
        _out = [NSFileHandle fileHandleForWritingAtPath: _tempPath];
        if (!_out) {
            BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath: _tempPath];
            Warn(@"CBL_BlobStoreWriter: Unable to get a file handle for the temp file at "
                  "%@ (exists: %@)", _tempPath, (exists ? @"yes" : @"no"));
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
