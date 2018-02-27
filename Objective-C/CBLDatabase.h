//
//  CBLDatabase.h
//  CouchbaseLite
//
//  Copyright (c) 2016 Couchbase, Inc All rights reserved.
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
@class CBLDatabaseConfiguration;
@class CBLDocument, CBLMutableDocument, CBLDocumentFragment;
@class CBLDatabaseChange, CBLDocumentChange;
@class CBLIndex;
@protocol CBLConflictResolver;
@protocol CBLListenerToken;

NS_ASSUME_NONNULL_BEGIN

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


/**
Concurruncy control type used when saving or deleting a document.
*/
typedef NS_ENUM(uint32_t, CBLConcurrencyControl) {
    kCBLConcurrencyControlLastWriteWins,    ///< The last write operation will win if there is a conflict.
    kCBLConcurrencyControlFailOnConflict    ///< The operation will fail if there is a conflict.
};

/** A Couchbase Lite database. */
@interface CBLDatabase : NSObject

/** The database's name. */
@property (readonly, nonatomic) NSString* name;

/** The database's path. If the database is closed or deleted, nil value will be returned. */
@property (readonly, atomic, nullable) NSString* path;

/** The number of documents in the database. */
@property (readonly, atomic) uint64_t count;

/** 
 The database's configuration. The returned configuration object is readonly;
 an NSInternalInconsistencyException exception will be thrown if
 the configuration object is modified.
 */
@property (readonly, nonatomic) CBLDatabaseConfiguration *config;


#pragma mark - Initializers


/** 
 Initializes a database object with a given name and the default database configuration.
 If the database does not yet exist, it will be created.
 
 @param name The name of the database.
 @param error On return, the error if any.
 */
- (nullable instancetype) initWithName: (NSString*)name
                                 error: (NSError**)error;

/**
 Initializes a Couchbase Lite database with a given name and database configuration.
 If the database does not yet exist, it will be created.
 
 @param name The name of the database.
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
 Gets an existing CBLMutableDocument object with the given ID. If the document with the given ID
 doesn't exist in the database, the value returned will be nil.
 
 @param id The document ID.
 @return The CBLMutableDocument object.
 */
- (nullable CBLDocument*) documentWithID: (NSString*)id;


#pragma mark - Subscript


/** 
 Gets a document fragment with the given document ID.
 
 @param documentID The document ID.
 @return The CBLDocumentFragment object.
 */
- (CBLDocumentFragment*) objectForKeyedSubscript: (NSString*)documentID;


#pragma mark - Save, Delete, Purge


/**
 Saves a document to the database. When write operations are executed
 concurrently, the last writer will overwrite all other written values.
 Calling this method is the same as calling the -saveDocument:concurrencyControl:error:
 method with kCBLConcurrencyControlLastWriteWins concurrency control.

 @param document The document.
 @param error On return, the error if any.
 @return True on success, false on failure.
 */
- (BOOL) saveDocument: (CBLMutableDocument*)document error: (NSError**)error;

/**
 Saves a document to the database. When used with kCBLConcurrencyControlLastWriteWins
 concurrency control, the last write operation will win if there is a conflict.
 When used with kCBLConcurrencyControlFailOnConflict concurrency control,
 save will fail with 'CBLErrorConflict' error code returned.

 @param document The document.
 @param concurrencyControl The concurrency control.
 @param error On return, the error if any.
 @return True on success, false on failure.
 */
- (BOOL) saveDocument: (CBLMutableDocument*)document
   concurrencyControl: (CBLConcurrencyControl)concurrencyControl
                error: (NSError**)error;

/**
 Deletes a document from the database. When write operations are executed
 concurrently, the last writer will overwrite all other written values.
 Calling this method is the same as calling the -deleteDocument:concurrencyControl:error:
 method with kCBLConcurrencyControlLastWriteWins concurrency control.

 @param document The document.
 @param error On return, the error if any.
 @return /True on success, false on failure.
 */
- (BOOL) deleteDocument: (CBLDocument*)document error: (NSError**)error;

/**
 Deletes a document from the database. When used with kCBLConcurrencyControlLastWriteWins
 concurrency control, the last write operation will win if there is a conflict.
 When used with kCBLConcurrencyControlFailOnConflict concurrency control,
 delete will fail with 'CBLErrorConflict' error code returned.

 @param document The document.
 @param concurrencyControl The concurrency control.
 @param error On return, the error if any.
 @return True on success, false on failure.
 */
- (BOOL) deleteDocument: (CBLDocument*)document
     concurrencyControl: (CBLConcurrencyControl)concurrencyControl
                  error: (NSError**)error;

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
- (BOOL) inBatch: (NSError**)error usingBlock: (void (NS_NOESCAPE ^)(void))block;


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
- (BOOL) delete: (NSError**)error;

/**
 Compacts the database file by deleting unused attachment files and vacuuming 
 the SQLite database

 @param error On return, the error if any.
 @return True on success, false on failure.
 */
- (BOOL) compact: (NSError**)error;

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
           withConfig: (nullable CBLDatabaseConfiguration*)config
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
 Adds a database change listener. Changes will be posted on the main queue.
 
 @param listener The listener to post the changes.
 @return An opaque listener token object for removing the listener.
 */
- (id<CBLListenerToken>) addChangeListener: (void (^)(CBLDatabaseChange*))listener;

/**
 Adds a database change listener with the dispatch queue on which changes
 will be posted. If the dispatch queue is not specified, the changes will be
 posted on the main queue.

 @param queue The dispatch queue.
 @param listener The listener to post changes.
 @return An opaque listener token object for removing the listener.
 */
- (id<CBLListenerToken>) addChangeListenerWithQueue: (nullable dispatch_queue_t)queue
                                           listener: (void (^)(CBLDatabaseChange*))listener;

/** 
 Adds a document change listener for the document with the given ID. Changes
 will be posted on the main queue.
 
 @param id The document ID.
 @param listener The listener to post changes.
 @return An opaque listener token object for removing the listener.
 */
- (id<CBLListenerToken>) addDocumentChangeListenerWithID: (NSString*)id
                                                listener: (void (^)(CBLDocumentChange*))listener;


/**
 Adds a document change listener for the document with the given ID and the
 dispatch queue on which changes will be posted. If the dispatch queue
 is not specified, the changes will be posted on the main queue.
 
 @param id The document ID.
 @param queue The dispatch queue.
 @param listener The listener to post changes.
 @return An opaque listener token object for removing the listener.
 */
- (id<CBLListenerToken>) addDocumentChangeListenerWithID: (NSString*)id
                                                   queue: (nullable dispatch_queue_t)queue
                                                listener: (void (^)(CBLDocumentChange*))listener;
/** 
 Removes a change listener with the given listener token.
 
 @param token The listener token.
 */
- (void) removeChangeListenerWithToken: (id<CBLListenerToken>)token;


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


@end

NS_ASSUME_NONNULL_END
