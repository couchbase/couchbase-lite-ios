//
//  CBLDatabaseConfiguration.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 11/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLEncryptionKey;
@protocol CBLConflictResolver;

NS_ASSUME_NONNULL_BEGIN

@interface CBLDatabaseConfiguration : NSObject

/**
 Path to the directory to store the database in. If the directory doesn't already exist it will
 be created when the database is opened. The default directory will be in Application Support.
 You won't usually need to change this.
 */
@property (nonatomic, copy) NSString* directory;


/**
 The conflict resolver for this replicator. Setting nil means using the default
 conflict resolver, where the revision with more history wins.
 */
@property (nonatomic) id<CBLConflictResolver> conflictResolver;


/**
 A key to encrypt the database with. If the database does not exist and is being created, it
 will use this key, and the same key must be given every time it's opened.
 
 * The primary form of key is an NSData object 32 bytes in length: this is interpreted as a raw
 AES-256 key. To create a key, generate random data using a secure cryptographic randomizer
 like SecRandomCopyBytes or CCRandomGenerateBytes.
 * Alternatively, the value may be an NSString containing a password. This will be run through
 64,000 rounds of the PBKDF algorithm to securely convert it into an AES-256 key.
 * A default nil value, of course, means the database is unencrypted.
 */
@property (nonatomic, nullable) CBLEncryptionKey* encryptionKey;


/**
 Initializes the CBLDatabaseConfiguration object.
 */
- (instancetype) init;


/**
 Initializes the CBLDatabaseConfiguration object with the configuration object.

 @param config The configuration object.
 @return The CBLDatabaseConfiguration object.
 */
- (instancetype) initWithConfig: (nullable CBLDatabaseConfiguration*)config;

@end

NS_ASSUME_NONNULL_END
