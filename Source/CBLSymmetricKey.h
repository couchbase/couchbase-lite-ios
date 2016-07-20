//
//  CBLSymmetricKey.h
//  Couchbase Lite
//
//  Created by Jens Alfke on 2/27/14.
//  Copyright (c) 2014 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>


/** Number of bytes in a 256-bit key */
#define kSymmetricKeyDataSize 32

#define kSymmetricKeyEncryptedContentType @"application/x-beanbag-aes-256"


/** Type of block returned by CBLSymmetricKey.createEncryptor.
    This block can be called repeatedly with input data and returns additional output data.
    At EOF, the block should be called with a nil parameter, and
    it will return the remaining encrypted data from its buffer. */
typedef NSMutableData* (^CBLCryptorBlock)(NSData* input);


/** Basic AES encryption. Uses a 256-bit (32-byte) key. */
@interface CBLSymmetricKey : NSObject

/** Creates an instance with a random key. */
- (instancetype) init;

/** Creates an instance with a key derived from a password.
    @param password  The password.
    @param salt  A fixed data blob that perturbs the generated key. Should be kept fixed for any particular app, but doesn't need to be secret.
    @param rounds  The number of rounds of hashing to perform. More rounds is more secure but takes longer. */
- (instancetype) initWithPassword: (NSString*)password
                             salt: (NSData*)salt
                           rounds: (uint32_t)rounds;

/** Creates an instance with a key derived from a password, using default salt and rounds. */
- (instancetype) initWithPassword: (NSString*)password;

/** Creates an instance from existing key data. */
- (instancetype) initWithKeyData: (NSData*)keyData;

/** Creates an instance with key data or a password string, or even a CBLSymmetricKey. */
- (instancetype) initWithKeyOrPassword: (id)keyOrPassword;

/** Creates an instance with a key read from the Keychain. */
- (instancetype) initWithKeychainItemNamed: (NSString*)itemName
                                     error: (NSError**)outError;

/** Deletes a symmetric key from the Keychain. */
+ (BOOL) deleteKeychainItemNamed: (NSString*)itemName
                           error: (NSError**)outError;

/** Saves a key to the Keychain under the given name. */
- (BOOL) saveKeychainItemNamed: (NSString*)itemName
                         error: (NSError**)outError;

/** The SymmetricKey's key data; can be used to reconstitute it. */
@property (readonly) NSData* keyData;

/** The key data encoded as hex. */
@property (readonly) NSString* hexData;

/** Encrypts a data blob.
    The output consists of a 16-byte random initialization vector,
    followed by PKCS7-padded ciphertext. */
- (NSData*) encryptData: (NSData*)data;

/** Decrypts data encoded by encryptData. */
- (NSData*) decryptData: (NSData*)encryptedData;

/** Streaming decryption. */
- (NSInputStream*) decryptStream: (NSInputStream*)encryptedStream;

/** Incremental encryption: returns a block that can be called repeatedly with input data and
    returns additional output data. At EOF the block should be called with a nil parameter, and
    it will return the remaining encrypted data from its buffer. */
- (CBLCryptorBlock) createEncryptor;

@end
