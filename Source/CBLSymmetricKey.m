//
//  CBLSymmetricKey.m
//  Couchbase Lite
//
//  Created by Jens Alfke on 2/27/14.
//  Copyright (c) 2014-2015 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLSymmetricKey.h"
#import "CBLMisc.h"
#import <CommonCrypto/CommonCrypto.h>


/* Encrypted message format:
    IV (16 bytes)
    padded encrypted data (variable)
    Adler32 checksum of original data (4 bytes)
 */


#define kAlgorithm      kCCAlgorithmAES
#define kKeySize        kCCKeySizeAES256
#define kBlockSize      kCCBlockSizeAES128      // (All key sizes of AES use a 128-bit block.)
#define kIVSize         kBlockSize
#define kChecksumSize   sizeof(uint32_t)

#define kDefaultSalt @"Salty McNaCl"
#define kDefaultPBKDFRounds 64000       // Same as what SQLCipher uses


@implementation CBLSymmetricKey


@synthesize keyData=_keyData;


- (instancetype) init {
    NSMutableData* keyData = [NSMutableData dataWithLength: kKeySize];
    SecRandomCopyBytes(kSecRandomDefault, keyData.length, keyData.mutableBytes);
    return [self initWithKeyData: keyData];
}


- (instancetype) initWithKeyData: (NSData*)keyData {
    self = [super init];
    if (self) {
        if (keyData.length != kKeySize)
            return nil;
        _keyData = [keyData copy];
    }
    return self;
}


- (instancetype) initWithPassword: (NSString*)password
                             salt: (NSData*)salt
                           rounds: (uint32_t)rounds
{
    Assert(password);
    Assert(salt.length > 4, @"Insufficient salt");
    Assert(rounds > 200, @"Insufficient rounds");
    NSMutableData* keyData = [NSMutableData dataWithLength: kKeySize];
    NSData* passwordData = [password dataUsingEncoding: NSUTF8StringEncoding];
    int status = CCKeyDerivationPBKDF(kCCPBKDF2,
                                      passwordData.bytes, passwordData.length,
                                      salt.bytes, salt.length,
                                      kCCPRFHmacAlgSHA256, rounds,
                                      keyData.mutableBytes, keyData.length);
    if (status) {
        return nil;
    }
    return [self initWithKeyData: keyData];
}

- (instancetype) initWithPassword: (NSString*)password {
    return [self initWithPassword: password
                             salt: [kDefaultSalt dataUsingEncoding: NSUTF8StringEncoding]
                           rounds: kDefaultPBKDFRounds];
}


- (NSString*) hexData {
    return CBLHexFromBytes(_keyData.bytes, _keyData.length);
}


#pragma mark - ENCRYPTION / DECRYPTION:

typedef struct {
    uint8_t iv[kIVSize];
    uint8_t encoded[0]; // variable length
} Header;


- (CBLCryptorBlock) createEncryptor {
    Header header;
    SecRandomCopyBytes(kSecRandomDefault, kIVSize, header.iv);

    CCCryptorRef cryptor;
    CCCryptorStatus status = CCCryptorCreate(kCCEncrypt, kAlgorithm, kCCOptionPKCS7Padding, _keyData.bytes, _keyData.length,
                    header.iv, &cryptor);
    if (status != kCCSuccess)
        return nil;
    __block BOOL wroteIV = NO;

    return ^NSMutableData*(NSData* input) {
        NSMutableData* dataOut = [NSMutableData dataWithLength: input.length + kBlockSize];
        size_t bytesWritten;
        CCCryptorStatus status;
        if (input) {
            status = CCCryptorUpdate(cryptor, input.bytes, input.length,
                            dataOut.mutableBytes, dataOut.length, &bytesWritten);
        } else {
            status = CCCryptorFinal(cryptor, dataOut.mutableBytes, dataOut.length, &bytesWritten);
            CCCryptorRelease(cryptor);
        }
        if (status != kCCSuccess)
            return nil;
        dataOut.length = bytesWritten;
        if (!wroteIV) {
            // Prepend the IV to the output data:
            [dataOut replaceBytesInRange: NSMakeRange(0, 0)
                               withBytes: header.iv
                                  length: sizeof(header.iv)];
            wroteIV = YES;
        }
        return dataOut;
    };
}


- (NSData*) encryptData: (NSData*)data {
    CBLCryptorBlock cryptor = [self createEncryptor];
    if (!cryptor)
        return nil;
    NSMutableData* encrypted = cryptor(data);
    NSMutableData* trailer = cryptor(nil);
    if (!encrypted || !trailer)
        return nil;
    [encrypted appendData: trailer];
    return encrypted;
}


- (NSData*) decryptData: (NSData*)encryptedData {
    const Header *header = encryptedData.bytes;
    size_t encodedLength = encryptedData.length - sizeof(Header);
    size_t lengthWritten;
    NSMutableData* decoded = [NSMutableData dataWithLength: encodedLength + 256];
    CCCryptorStatus status = CCCrypt(kCCDecrypt, kAlgorithm, kCCOptionPKCS7Padding,
                                     _keyData.bytes, _keyData.length,
                                     header->iv,
                                     header->encoded, encodedLength,
                                     decoded.mutableBytes, decoded.length,
                                     &lengthWritten);
    if (status)
        return nil;
    decoded.length = lengthWritten;
    return decoded;
}


#pragma mark - STREAMING:


static BOOL readFully(NSInputStream* in, void* dst, size_t len) {
    NSInteger n;
    for (size_t bytesRead = 0; bytesRead < len; bytesRead += n) {
        n = [in read: (uint8_t*)dst + bytesRead maxLength: (len - bytesRead)];
        if (n <= 0) {
            Warn(@"SymmetricKey: readFully failed, error=%@", in.streamError);
            return NO;
        }
    }
    return YES;
}


static BOOL writeFully(NSOutputStream* out, const void* src, size_t len) {
    NSInteger n;
    for (size_t bytesWritten = 0; bytesWritten < len; bytesWritten += n) {
        n = [out write: (const uint8_t*)src + bytesWritten maxLength: (len - bytesWritten)];
        if (n <= 0) {
            Warn(@"SymmetricKey: writeFully failed, error=%@", out.streamError);
            return NO;
        }
    }
    return YES;
}


static BOOL decryptStreamSync(NSInputStream* encryptedStream, NSOutputStream *writer,
                              NSData* keyData)
{
    Header header;
    if (!readFully(encryptedStream, &header.iv, sizeof(header.iv)))
        return NO;
    CCCryptorRef cryptor;
    CCCryptorStatus status = CCCryptorCreate(kCCDecrypt, kAlgorithm,
                                             kCCOptionPKCS7Padding,
                                             keyData.bytes, keyData.length,
                                             header.iv, &cryptor);
    if (status != kCCSuccess)
        return NO;
    // The CCCryptor docs say it can use a single buffer for input and output, but I found that it
    // produced garbage output, so I've split it into separate buffers. --jpa 3/2015
    static const size_t kInputBufferSize = 4096;
    uint8_t inBuffer[kInputBufferSize];
    uint8_t outBuffer[kInputBufferSize+kBlockSize];
    size_t bytesWritten;
    BOOL ok = YES;
    for(;;) {
        NSInteger bytesRead = [encryptedStream read: inBuffer maxLength: sizeof(inBuffer)];
        if (bytesRead == 0) {
            break;
        } else if (bytesRead < 0
                   || CCCryptorUpdate(cryptor, inBuffer, bytesRead,
                                      outBuffer, sizeof(outBuffer), &bytesWritten) != kCCSuccess
                   || !writeFully(writer, outBuffer, bytesWritten))
        {
            ok = NO;
            break;
        }
    };
    ok = (ok && CCCryptorFinal(cryptor, outBuffer, sizeof(outBuffer), &bytesWritten) == kCCSuccess
             && writeFully(writer, outBuffer, bytesWritten));
    CCCryptorRelease(cryptor);
    return ok;
}


- (NSInputStream*) decryptStream: (NSInputStream*)encryptedStream {
    CFReadStreamRef cfRead;
    CFWriteStreamRef cfWrite;
    CFStreamCreateBoundPair(NULL, &cfRead, &cfWrite, 4096);
    NSInputStream* reader = CFBridgingRelease(cfRead);
    NSOutputStream* writer = CFBridgingRelease(cfWrite);
    [reader open];
    [writer open];

    NSData* keyData = _keyData;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (!decryptStreamSync(encryptedStream, writer, keyData))
            Warn(@"CBLSymmetricKey: decryptStream failed (bad input?)");
        [writer close];
    });

    return reader;
}


@end
