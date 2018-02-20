//
//  CBLEncryptionKey.h
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

#import <Foundation/Foundation.h>

#ifdef COUCHBASE_ENTERPRISE

NS_ASSUME_NONNULL_BEGIN

/**
 An encryption key for a database. This is a symmetric key that be kept secret.
 It should be stored either in the Keychain, or in the user's memory (hopefully not a sticky note.)
 */
@interface CBLEncryptionKey : NSObject

/**
 Initializes the encryption key with a raw AES-128 key 16 bytes in length.
 To create a key, generate random data using a secure cryptographic randomizer like
 SecRandomCopyBytes or CCRandomGenerateBytes.
 
 @param key The raw AES-128 key data.
 @return The CBLEncryptionKey object.
 */
- (instancetype) initWithKey: (NSData*)key;


/**
 Initializes the encryption key with the given password string. The password string will be
 internally converted to a raw AES-128 key using 64,000 rounds of PBKDF2 hashing.

 @param password The password string.
 @return The CBLEncryptionKey object.
 */
- (instancetype) initWithPassword: (NSString*)password;


/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

#endif
