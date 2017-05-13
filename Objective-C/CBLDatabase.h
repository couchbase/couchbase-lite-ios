//
//  CBLDatabase.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 12/15/16.
//  Copyright © 2016 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLDocument, CBLDocumentFragment, CBLPredicateQuery;
@protocol CBLConflictResolver;

NS_ASSUME_NONNULL_BEGIN

/** This notification is posted by a CBLDatabase in response to document changes. */
extern NSString* const kCBLDatabaseChangeNotification;

/** The key to access the document IDs of the documents that has been changed. */
extern NSString* const kCBLDatabaseChangesUserInfoKey;

/** The key to access the last sequence number as of the notified changes. */
extern NSString* const kCBLDatabaseLastSequenceUserInfoKey;

/** The key to check whether the changes are from the current database object or not. */
extern NSString* const kCBLDatabaseIsExternalUserInfoKey;


/** Types of database indexes. */
typedef NS_ENUM(uint32_t, CBLIndexType) {
    kCBLValueIndex,         ///< Regular index of property values
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

/** Path to the directory to store the database in. If the directory doesn't already exist it will
    be created when the database is opened.
    A nil value (the default) means to use the default directory, in Application Support. You
    won't usually need to change this. */
@property (nonatomic, copy, nullable) NSString* directory;

/** File protection/encryption options (iOS only.)
    Defaults to whatever file protection settings you've specified in your app's entitlements.
    Specifying a nonzero value here overrides those settings for the database files.
    If file protection is at the highest level, NSDataWritingFileProtectionCompleteUnlessOpen or
    NSDataWritingFileProtectionComplete, it will not be possible to read or write the database
    when the device is locked. This can make it impossible to run replications in the background
    or respond to push notifications. */
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

/** If YES, the database will be opened read-only. */
@property (nonatomic) BOOL readOnly;

/** Creates a new instance with a default set of options for a CBLDatabase. */
+ (instancetype) defaultOptions;

@end


/** A Couchbase Lite database. */
@interface CBLDatabase : NSObject

/** The database's name. */
@property (readonly, nonatomic) NSString* name;

/** The database's path. If the database is closed or deleted, nil value will be returned. */
@property (readonly, nonatomic, nullable) NSString* path;

/** Initializes a database object with a given name and the default database options.
    If the database does not yet exist, it will be created.
    @param name  The name of the database. May NOT contain capital letters!
    @param error  On return, the error if any. */
- (nullable instancetype) initWithName: (NSString*)name
                                 error: (NSError**)error;

/** Initializes a Couchbase Lite database with a given name and database options.
    If the database does not yet exist, it will be created, unless the `readOnly` option is used.
    @param name  The name of the database. May NOT contain capital letters!
    @param options  The database options, or nil for the default options.
    @param error  On return, the error if any. */
- (nullable instancetype) initWithName: (NSString*)name
                               options: (nullable CBLDatabaseOptions*)options
                                 error: (NSError**)error
    NS_DESIGNATED_INITIALIZER;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

/** Closes a database. */
- (BOOL) close: (NSError**)error;

/** Changes the database's encryption key, or removes encryption if the new key is nil.
    @param key  The encryption key in the form of an NSString (a password) or an
                NSData object exactly 32 bytes in length (a raw AES key.) If a string is given,
                it will be internally converted to a raw key using 64,000 rounds of PBKDF2 hashing.
                A nil value will decrypt the database.
    @param error  If an error occurs, it will be stored here if this parameter is non-NULL.
    @result  YES if the database was successfully re-keyed, or NO on error. */
- (BOOL) changeEncryptionKey: (nullable id)key error: (NSError**)error;

/** Deletes a database. */
- (BOOL) deleteDatabase: (NSError**)error;

/** Deletes a database of the given name in the given directory. */
+ (BOOL) deleteDatabase: (NSString*)name
            inDirectory: (nullable NSString*)directory
                  error: (NSError**)error;

/** Checks whether a database of the given name exists in the given directory or not. */
+ (BOOL) databaseExists: (NSString*)name
            inDirectory: (nullable NSString*)directory;

/** Runs a group of database operations in a batch. Use this when performing bulk write operations
    like multiple inserts/updates; it saves the overhead of multiple database commits, greatly
    improving performance. */
- (BOOL) inBatch: (NSError**)error do: (void (NS_NOESCAPE ^)())block;

/** Gets an existing CBLDocument object with the given ID. If the document with the given ID 
    doesn't exist in the database, the value returned will be nil.
    @param documentID   the document ID.
    @result the CBLDocument object.
    */
- (nullable CBLDocument*) documentWithID: (NSString*)documentID;

/** Gets a document fragment with the given document ID. */
- (CBLDocumentFragment*) objectForKeyedSubscript: (NSString*)documentID;

/** Checks whether the document of the given ID exists in the database or not. */
- (BOOL) documentExists: (NSString*)documentID;

/** The conflict resolver for this database.
    If nil, a default algorithm will be used, where the revision with more history wins.
    An individual document can override this for itself by setting its own property. */
@property (nonatomic, nullable) id<CBLConflictResolver> conflictResolver;


#pragma mark - SAVE DELETE PURGE


/** Saves the given document to the database.
    If the document in the database has been updated since it was read by this CBLDocument, a
    conflict occurs, which will be resolved by invoking the conflict handler. This can happen if
    multiple application threads are writing to the database, or a pull replication is copying
    changes from a server. */
- (BOOL) saveDocument: (CBLDocument*)document error: (NSError**)error;

/** Deletes the given document. All properties are removed, and subsequent calls 
    to -documentWithID: will return nil.
    Deletion adds a special "tombstone" revision to the database, as bookkeeping so that the
    change can be replicated to other databases. Thus, it does not free up all of the disk space
    occupied by the document.
    To delete a document entirely (but without the ability to replicate this), use -purge:error:. */
- (BOOL) deleteDocument: (CBLDocument*)document error: (NSError**)error;

/** Purges the given document from the database.
    This is more drastic than deletion: it removes all traces of the document.
    The purge will NOT be replicated to other databases. */
- (BOOL) purgeDocument: (CBLDocument*)document error: (NSError**)error;


#pragma mark - QUERYING:


/** Enumerates all documents in the database, ordered by document ID. */
- (NSEnumerator<CBLDocument*>*) allDocuments;

/** Compiles a database query, from any of several input formats.
 Once compiled, the query can be run many times with different parameter values.
 The rows will be sorted by ascending document ID, and no custom values are returned.
 @param where  The query specification. This can be an NSPredicate, or an NSString (interpreted
 as an NSPredicate format string), or nil to return all documents.
 @return  The CBLQuery. */
- (CBLPredicateQuery*) createQueryWhere: (nullable id)where;

/** Creates a value index (type kCBLValueIndex) on a given document property.
    This will speed up queries that test that property, at the expense of making database writes a
    little bit slower.
    @param expressions  Expressions to index, typically key-paths. Can be NSExpression objects,
                    or NSStrings that are expression format strings.
    @param error  If an error occurs, it will be stored here if this parameter is non-NULL.
    @return  True on success, false on failure. */
- (BOOL) createIndexOn: (NSArray*)expressions
                 error: (NSError**)error;

/** Creates an index on a given document property.
    This will speed up queries that test that property, at the expense of making database writes a
    little bit slower.
    @param expressions  Expressions to index, typically key-paths. Can be NSExpression objects,
                    or NSStrings that are expression format strings.
    @param type  Type of index to create (value, full-text or geospatial.)
    @param options  Options affecting the index, or NULL for default settings.
    @param error  If an error occurs, it will be stored here if this parameter is non-NULL.
    @return  True on success, false on failure. */
- (BOOL) createIndexOn: (NSArray*)expressions
                  type: (CBLIndexType)type
               options: (nullable const CBLIndexOptions*)options
                 error: (NSError**)error;

/** Deletes an existing index. Returns NO if the index did not exist.
    @param expressions  Expressions indexed (same parameter given to -createIndexOn:.)
    @param type  Type of index.
    @param error  If an error occurs, it will be stored here if this parameter is non-NULL.
    @return  True if the index existed and was deleted, false if it did not exist. */
- (BOOL) deleteIndexOn: (NSArray*)expressions
                  type: (CBLIndexType)type
                 error: (NSError**)error;

@end

NS_ASSUME_NONNULL_END

// TODO:
// * Logging
// * Threading Support
