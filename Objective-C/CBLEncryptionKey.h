//
//  CBLEncryptionKey.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/22/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The encryption key, a raw AES-256 key data which has exactly 32 bytes in length
 or a password string. If the password string is given, it will be internally converted to a
 raw AES key using 64,000 rounds of PBKDF2 hashing.
 */
@interface CBLEncryptionKey : NSObject


/**
 Initializes the encryption key with a raw AES-256 key data which has 32 bytes in length.
 To create a key, generate random data using a secure cryptographic randomizer like
 SecRandomCopyBytes or CCRandomGenerateBytes.
 
 @param key The raw AES-256 key data.
 @return The CBLEncryptionKey object.
 */
- (instancetype) initWithKey: (NSData*)key;


/**
 Initializes the encryption key with the given password string. The password string will be
 internally converted to a raw AES-256 key using 64,000 rounds of PBKDF2 hashing.

 @param password The password string.
 @return The CBLEncryptionKey object.
 */
- (instancetype) initWithPassword: (NSString*)password;

@end

NS_ASSUME_NONNULL_END
