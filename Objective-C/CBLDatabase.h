//
//  CBLDatabase.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 12/15/16.
//  Copyright © 2016 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLDocument, CBLQuery;

NS_ASSUME_NONNULL_BEGIN

extern NSString* const kCBLDatabaseChangeNotification;
extern NSString* const kCBLDatabaseChangesUserInfoKey;
extern NSString* const kCBLDatabaseLastSequenceUserInfoKey;
extern NSString* const kCBLDatabaseIsExternalUserInfoKey;

/** Types of indexes. */
typedef NS_ENUM(uint32_t, CBLIndexType) {
    kCBLValueIndex,         ///< Regular index of property value
    kCBLFullTextIndex,      ///< Full-text index
    kCBLGeoIndex,           ///< Geospatial index of GeoJSON values
};


/** Options for creating a database index. */
typedef struct {
    const char * _Nullable language;    ///< Full-text: Language code, e.g. "en" or "de". This
                                        ///<    affects how word breaks and word stems are parsed.
                                        ///<    NULL for current locale, "" to disable stemming.
    BOOL ignoreDiacritics;              ///< Full-text: True to ignore accents/diacritical marks.
} CBLIndexOptions;

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
                      options: (nullable CBLDatabaseOptions*)options
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


#pragma mark - QUERYING:


/** Compiles a database query, from any of several input formats.
    Once compiled, the query can be run many times with different parameter values.
    @param query  The query specification. This can be an NSPredicate or an NSString (interpreted 
                    as an NSPredicate format string), or nil to return all documents.
    @param error  If the query cannot be parsed, an error will be stored here.
    @return  The CBLQuery, or nil on error. */
- (nullable CBLQuery*) createQuery: (nullable id)query
                             error: (NSError**)error;

/** Compiles a Couchbase Lite query, from any of several input formats, specifying sorting.
    Once compiled, the query can be run many times with different parameter values.
    @param where  The query specification; see above for details.
    @param sortDescriptors  An array of NSSortDescriptors specifying how to sort the result.
    @param error  If the query cannot be parsed, an error will be stored here.
    @return  The CBLQuery, or nil on error. */
- (nullable CBLQuery*) createQueryWhere: (nullable id)where
                                orderBy: (nullable NSArray*)sortDescriptors
                                  error: (NSError**)error;

/** Creates a value index (type kCBLValueIndex) on a given document property.
    This will speed up queries that test that property, at the expense of making database writes a
    little bit slower.
    @param expressions  Expressions to index, typically key-paths.
    @param error  If an error occurs, it will be stored here if this parameter is non-NULL.
    @return  True on success, false on failure. */
- (bool) createIndexOn: (NSArray<NSExpression*>*)expressions
                 error: (NSError**)error;

/** Creates an index on a given document property.
    This will speed up queries that test that property, at the expense of making database writes a
    little bit slower.
    @param expressions  Expressions to index, typically key-paths.
    @param type  Type of index to create (value, full-text or geospatial.)
    @param options  Options affecting the index, or NULL for default settings.
    @param error  If an error occurs, it will be stored here if this parameter is non-NULL.
    @return  True on success, false on failure. */
- (bool) createIndexOn: (NSArray<NSExpression*>*)expressions
                  type: (CBLIndexType)type
               options: (nullable const CBLIndexOptions*)options
                 error: (NSError**)error;

/** Deletes an existing index. Returns NO if the index did not exist.
    @param expressions  Expressions indexed (same parameter given to -createIndexOn:.)
    @param type  Type of index.
    @param error  If an error occurs, it will be stored here if this parameter is non-NULL.
    @return  True if the index existed and was deleted, false if it did not exist. */
- (bool) deleteIndexOn: (NSArray<NSExpression*>*)expressions
                  type: (CBLIndexType)type
                 error: (NSError**)error;

@end

NS_ASSUME_NONNULL_END

// TODO:
// * Conflict Resolution
// * Change Notification
// * Logging
// * Threading Support
