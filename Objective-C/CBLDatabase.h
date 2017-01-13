//
//  CBLDatabase.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 12/15/16.
//  Copyright © 2016 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLDocument;

NS_ASSUME_NONNULL_BEGIN

/** Options for opening a database. All properties default to NO or nil. */
@interface CBLDatabaseOptions : NSObject <NSCopying>

/** Path to the directory to store the database files. If the path doesn't already exist it will 
 be created when the database is opened. Nil value means using the default directory which is in 
 the Application Support directory. */
@property (nonatomic, copy, nullable) NSString* directory;

/** File protection/encryption options (iOS only) */
@property (nonatomic) NSDataWritingOptions fileProtection;

/** A key to encrypt the database with. If the database does not exist and is being created, it
 will use this key, and the same key must be given every time it's opened.
 
 * The primary form of key is an NSData object 32 bytes in length: this is interpreted as a raw
 AES-256 key. To create a key, generate random data using a secure cryptographic randomizer
 like SecRandomCopyBytes or CCRandomGenerateBytes.
 * Alternatively, the value may be an NSString containing a passphrase. This will be run through
 64,000 rounds of the PBKDF algorithm to securely convert it into an AES-256 key.
 * A default nil value, of course, means the database is unencrypted. */
@property (nonatomic, strong, nullable) id encryptionKey;

@property (nonatomic) BOOL readOnly;                /** Open database read-only? */

/** Get the default options for a CBLDatabase */
+ (instancetype) defaultOptions;

@end

/** A CouchbaseLite database. */
@interface CBLDatabase : NSObject

/** Initializes a CouchbaseLite database with a given name and the default database options.
 @param name  The name of the database. May NOT contain capital letters!
 @param outError  On return, the error if any. */
- (instancetype) initWithName: (NSString*)name
                        error: (NSError**)outError;

/** Initializes a CouchbaseLite database with a given name and database options.
 @param name  The name of the database. May NOT contain capital letters!
 @param options  The database options.
 @param outError  On return, the error if any. */
- (instancetype) initWithName: (NSString*)name
                      options: (CBLDatabaseOptions*)options
                        error: (NSError**)outError NS_DESIGNATED_INITIALIZER;

- (instancetype) init NS_UNAVAILABLE;

/** Closes a database. */
- (BOOL) close: (NSError**)outError;

/** Changes the database's encryption key, or removes encryption if the new key is nil.
 @param key  The encryption key in the form of an NSString (a password) or an
 NSData object exactly 32 bytes in length (a raw AES key.) If a string is given,
 it will be internally converted to a raw key using 64,000 rounds of PBKDF2 hashing.
 A nil value will decrypt the database.
 @param outError  If an error occurs, it will be stored here if this parameter is non-NULL.
 @result  YES if the database was successfully re-keyed, or NO on error. */
- (BOOL) changeEncryptionKey: (nullable id)key error: (NSError**)outError;

/** Deletes a database. */
- (BOOL) deleteDatabase: (NSError**)outError;

/** Deletes a database of the given name in the given directory. */
+ (BOOL) deleteDatabase: (NSString*)name
            inDirectory: (nullable NSString*)directory
                  error: (NSError**)outError;

/** Check whether a database of the given name exists in the given directory or not. */
+ (BOOL) databaseExists: (NSString*)name
            inDirectory: (nullable NSString*)directory;

/** Runs a block of the batch database operations. Couchbase Lite will guarantee transaction 
 of the batch operations. If the block returns NO, the batch is rolled back. 
 Use this when performing bulk write operations like multiple inserts/updates; it saves the
 overhead of multiple database commits, greatly improving performance. */
- (bool) inBatch: (NSError**)outError do: (BOOL (^)())block;

/** Creates a new CBLDocument object with no properties and a new (random) UUID. 
 The document will be saved to the database when you call -save: on it. */
- (CBLDocument*) document;

/** Get or Create a CBLDocument object with the given ID. The existence of the CBLDocument in
 the database can be checked by calling -exists on it. CBLDocuments are cached, so there will 
 never be more than one instance in this CBLDatabase object at a time with the same documentID. */
- (CBLDocument*) documentWithID: (NSString*)docID;

/** Same as -documentWithID: */
- (CBLDocument*) objectForKeyedSubscript: (NSString*)docID;

/** Check whether the document of the given ID exists in the database or not. */
- (BOOL) documentExists: (NSString*)docID;

@end

NS_ASSUME_NONNULL_END

// TODO:
// * Conflict Resolution
// * Change Notification
// * Logging
// * Threading Support
