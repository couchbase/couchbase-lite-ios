//
//  CBLDatabase.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 12/15/16.
//  Copyright © 2016 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLDocument, CBLDocumentFragment, CBLDatabaseChange, CBLDocumentChange;
@class CBLEncryptionKey;
@class CBLIndex, CBLPredicateQuery;
@protocol CBLConflictResolver, CBLDocumentChangeListener;

NS_ASSUME_NONNULL_BEGIN


/** Configuration for opening a database. */
@interface CBLDatabaseConfiguration : NSObject <NSCopying>

/** 
 Path to the directory to store the database in. If the directory doesn't already exist it will
 be created when the database is opened. The default directory will be in Application Support.
 You won't usually need to change this. 
 */
@property (nonatomic, copy, nullable) NSString* directory;


/** 
 The conflict resolver for this database. The default value is nil, which means the default
 algorithm will be used, where the revision with more history wins.
 An individual document can override this for itself by setting its own property.
 */
@property (nonatomic, nullable) id<CBLConflictResolver> conflictResolver;


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
 File protection/encryption options (iOS only.)
 Defaults to whatever file protection settings you've specified in your app's entitlements.
 Specifying a nonzero value here overrides those settings for the database files.
 If file protection is at the highest level, NSDataWritingFileProtectionCompleteUnlessOpen or
 NSDataWritingFileProtectionComplete, it will not be possible to read or write the database
 when the device is locked. This can make it impossible to run replications in the background
 or respond to push notifications. The default value is
 NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication which is the same default
 protection level as the iOS application data.
 */
@property (nonatomic) NSDataWritingOptions fileProtection;


/** 
 Initializes the CBLDatabaseConfiguration object.
 */
- (instancetype) init;

@end


/**
 Log domain. The log domains here are tentative and subject to change.
 */
typedef NS_ENUM(uint32_t, CBLLogDomain) {
    kCBLLogDomainAll,
    kCBLLogDomainDatabase,
    kCBLLogDomainQuery,
    kCBLLogDomainReplicator,
    kCBLLogDomainNetwork,
};


/**
 Log level. The default log level for all domains is kCBLLogLevelWarning.
 The log levels here are tentative and subject to change.
 */
typedef NS_ENUM(uint32_t, CBLLogLevel) {
    kCBLLogLevelDebug,
    kCBLLogLevelVerbose,
    kCBLLogLevelInfo,
    kCBLLogLevelWarning,
    kCBLLogLevelError,
    kCBLLogLevelNone
};

/** A Couchbase Lite database. */
@interface CBLDatabase : NSObject

/** The database's name. */
@property (readonly, nonatomic) NSString* name;

/** The database's path. If the database is closed or deleted, nil value will be returned. */
@property (readonly, nonatomic, nullable) NSString* path;

/** The number of documents in the database. */
@property (readonly, nonatomic) uint64_t count;

/** 
 The database's configuration. If the configuration is not specify when initializing
 the database, the default configuration will be returned.
 */
@property (readonly, copy, nonatomic) CBLDatabaseConfiguration *config;


#pragma mark - Initializers


/** 
 Initializes a database object with a given name and the default database configuration.
 If the database does not yet exist, it will be created.
 
 @param name The name of the database. May NOT contain capital letters!
 @param error On return, the error if any.
 */
- (nullable instancetype) initWithName: (NSString*)name
                                 error: (NSError**)error;

/**
 Initializes a Couchbase Lite database with a given name and database configuration.
 If the database does not yet exist, it will be created.
 
 @param name The name of the database. May NOT contain capital letters!
 @param config The database configuration, or nil for the default configuration.
 @param error On return, the error if any.
 */
- (nullable instancetype) initWithName: (NSString*)name
                                config: (nullable CBLDatabaseConfiguration*)config
                                 error: (NSError**)error NS_DESIGNATED_INITIALIZER;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;


#pragma mark - Get Existing Document


/** 
 Gets an existing CBLDocument object with the given ID. If the document with the given ID
 doesn't exist in the database, the value returned will be nil.
 
 @param documentID The document ID.
 @return The CBLDocument object.
 */
- (nullable CBLDocument*) documentWithID: (NSString*)documentID;


#pragma mark - Check Document Exists


/** 
 Checks whether the document of the given ID exists in the database or not.
 
 @param documentID The document ID.
 @return True if the database contains the document with the given ID, otherwise false.
 */
- (BOOL) contains: (NSString*)documentID;


#pragma mark - Subscript


/** 
 Gets a document fragment with the given document ID.
 
 @param documentID The document ID.
 @return The CBLDocumentFragment object.
 */
- (CBLDocumentFragment*) objectForKeyedSubscript: (NSString*)documentID;


#pragma mark - Save, Delete, Purge


/** 
 Saves the given document to the database.
 If the document in the database has been updated since it was read by this CBLDocument, a
 conflict occurs, which will be resolved by invoking the conflict handler. This can happen if
 multiple application threads are writing to the database, or a pull replication is copying
 changes from a server.
 
 @param document The document to be saved.
 @param error On return, the error if any.
 @return True on success, false on failure.
 */
- (BOOL) saveDocument: (CBLDocument*)document error: (NSError**)error;

/** 
 Deletes the given document.
 All properties are removed, and subsequent calls to -documentWithID: will return nil.
 Deletion adds a special "tombstone" revision to the database, as bookkeeping so that the
 change can be replicated to other databases. Thus, it does not free up all of the disk space
 occupied by the document. To delete a document entirely (but without the ability to replicate this), 
 use -purge:error:.
 
 @param document The document to be deleted.
 @param error On return, the error if any.
 @return True on success, false on failure.
 */
- (BOOL) deleteDocument: (CBLDocument*)document error: (NSError**)error;

/** 
 Purges the given document from the database.
 This is more drastic than deletion: it removes all traces of the document. 
 The purge will NOT be replicated to other databases.
 
 @param document The document to be purged.
 @param error On return, the error if any.
 @return True on success, false on failure.
 */
- (BOOL) purgeDocument: (CBLDocument*)document error: (NSError**)error;


#pragma mark - Batch Operation


/** 
 Runs a group of database operations in a batch. Use this when performing bulk write operations
 like multiple inserts/updates; it saves the overhead of multiple database commits, greatly
 improving performance.
 
 @param error On return, the error if any.
 @param block The block to execute a group of database operations.
 @return True on success, false on failure.
 */
- (BOOL) inBatch: (NSError**)error do: (void (NS_NOESCAPE ^)(void))block;


#pragma mark - Databaes Maintenance


/**
 Closes a database.

 @param error On return, the error if any.
 @return True on success, false on failure.
 */
- (BOOL) close: (NSError**)error;

/**
 Deletes a database.

 @param error On return, the error if any.
 @return True on success, false on failure.
 */
- (BOOL) deleteDatabase: (NSError**)error;

/**
 Compacts the database file by deleting unused attachment files and vacuuming 
 the SQLite database

 @param error On return, the error if any.
 @return True on success, false on failure.
 */
- (BOOL) compact: (NSError**)error;

/**
 Changes the database's encryption key, or removes encryption if the new key is nil.
 
 @param key  The encryption key.
 @param error On return, the error if any.
 @return True if the database was successfully re-keyed, or false on failure.
 */
- (BOOL) setEncryptionKey: (nullable CBLEncryptionKey*)key error: (NSError**)error;

/**
 Deletes a database of the given name in the given directory.

 @param name The database name.
 @param directory The directory where the database is located at.
 @param error On return, the error if any.
 @return True on success, false on failure.
 */
+ (BOOL) deleteDatabase: (NSString*)name
            inDirectory: (nullable NSString*)directory
                  error: (NSError**)error;

/**
 Checks whether a database of the given name exists in the given directory or not.

 @param name The database name.
 @param directory The directory where the database is located at.
 @return True on success, false on failure.
 */
+ (BOOL) databaseExists: (NSString*)name
            inDirectory: (nullable NSString*)directory;


/**
 Copies a canned databaes from the given path to a new database with the given name and
 the configuration. The new database will be created at the directory specified in the
 configuration. Without given the database configuration, the default configuration that
 is equivalent to setting all properties in the configuration to nil will be used.
 
 @param path The source database path.
 @param name The name of the new database to be created.
 @param config The database configuration for the new database.
 @param error On return, the error if any.
 @return True on success, false on failure.
 */
+ (BOOL) copyFromPath: (NSString*)path
           toDatabase: (NSString*)name
               config: (nullable CBLDatabaseConfiguration*)config
                error: (NSError**)error;

#pragma mark - Logging

/**
 Sets log level for the given log domain.

 @param level The log level.
 @param domain The log domain.
 */
+ (void) setLogLevel: (CBLLogLevel)level domain: (CBLLogDomain)domain;

#pragma mark - Change Listener


/** 
 Adds a database change listener block.
 
 @param block The block to be executed when the change is received.
 @return An opaque object to act as the listener and for removing the listener
         when calling the -removeChangeListener: method.
 */
- (id<NSObject>) addChangeListener: (void (^)(CBLDatabaseChange*))block;

/** 
 Adds a document change listener block for the given document ID.
 
 @param documentID The document.
 @param block The block to be executed when the change is received.
 @return An opaque object to act as the listener and for removing the listener 
         when calling the -removeChangeListener: method.
 */
- (id<NSObject>) addChangeListenerForDocumentID: (NSString*)documentID
                                     usingBlock: (void (^)(CBLDocumentChange*))block;

/** 
 Removes a change listener. The given change listener is the opaque object 
 returned by the -addChangeListener: or -addChangeListenerForDocumentID:usingBlock: method.
 
 @param listener The listener object to be removed.
 */
- (void) removeChangeListener: (id<NSObject>)listener;


#pragma mark - Index


/** All index names. */
@property (atomic, readonly) NSArray<NSString*>* indexes;

/**
 Creates an index which could be a value index or a full-text search index with the given name.
 The name can be used for deleting the index. Creating a new different index with an existing
 index name will replace the old index; creating the same index with the same name will be no-ops.
 
 @param index The index.
 @param name The index name.
 @param error error On return, the error if any.
 @return True on success, false on failure.
 */
- (BOOL) createIndex: (CBLIndex*)index withName: (NSString*)name error: (NSError**)error;


/**
 Deletes the index of the given index name.

 @param name The index name.
 @param error error On return, the error if any.
 @return True on success, false on failure.
 */
- (BOOL) deleteIndexForName: (NSString*)name error: (NSError**)error;


#pragma mark - Querying


/**
 Enumerates all documents in the database, ordered by document ID.

 @return All documents.
 */
- (NSEnumerator<CBLDocument*>*) allDocuments;

/** 
 Compiles a database query, from any of several input formats.
 Once compiled, the query can be run many times with different parameter values.
 The rows will be sorted by ascending document ID, and no custom values are returned.
 
 @param where The query specification. This can be an NSPredicate, or an NSString (interpreted
              as an NSPredicate format string), or nil to return all documents.
 @return The CBLQuery.
 */
- (CBLPredicateQuery*) createQueryWhere: (nullable id)where;

@end

NS_ASSUME_NONNULL_END
