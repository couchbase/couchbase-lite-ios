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
#import "CBLLogger.h"
@class CBLDatabaseConfiguration;
@class CBLDocument, CBLMutableDocument, CBLDocumentFragment;
@class CBLDatabaseChange, CBLDocumentChange;
@class CBLIndex;
@class CBLLog;
@class CBLBlob;
@protocol CBLConflictResolver;
@protocol CBLListenerToken;

NS_ASSUME_NONNULL_BEGIN


/**
Concurruncy control type used when saving or deleting a document.
*/
typedef NS_ENUM(uint32_t, CBLConcurrencyControl) {
    kCBLConcurrencyControlLastWriteWins,    ///< The last write operation will win if there is a conflict.
    kCBLConcurrencyControlFailOnConflict    ///< The operation will fail if there is a conflict.
};

/**
Maintenance Type used when performing database maintenance .
*/
typedef NS_ENUM(uint32_t, CBLMaintenanceType) {
    kCBLMaintenanceTypeCompact,             ///< Compact the database file and delete unused attachments.
    kCBLMaintenanceTypeReindex,             ///< (Volatile API) Rebuild the entire database's indexes.
    kCBLMaintenanceTypeIntegrityCheck       ///< (Volatile API) Check for the database’s corruption. If found, an error will be returned.
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
                                 error: (NSError**)error;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;


#pragma mark - Get Existing Document


/** 
 Gets an existing document with the given ID. If a document with the given ID
 doesn't exist in the database, the value returned will be nil.
 
 @param id The document ID.
 @return The CBLDocument object.
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
 Saves a document to the database. When write operations are executed concurrently and if conflicts
 occur, the conflict handler will be called. Use the conflict handler to directly edit the document
 to resolve the conflict. When the conflict handler returns 'true', the save method will save the
 edited document as the resolved document. If the conflict handler returns 'false', the save
 operation will be canceled with 'false' value returned as the conflict wasn't resolved.
 
 @param document The document.
 @param conflictHandler The conflict handler block which can be used to resolve it.
 @param error On return, error if any.
 @return True if successful. False if there is a conflict, but the conflict wasn't resolved as the
    conflict handler returns 'false' value.
*/
- (BOOL) saveDocument: (CBLMutableDocument*)document
      conflictHandler: (BOOL (^)(CBLMutableDocument*, CBLDocument* nullable))conflictHandler
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


/**
 Purges the document for the given documentID from the database.
 This is more drastic than deletion: it removes all traces of the document.
 The purge will NOT be replicated to other databases.
 
 @param documentID The ID of the document to be purged.
 @param error On return, the error if any.
 @return True on success, false on failure.
 */
- (BOOL) purgeDocumentWithID: (NSString*)documentID error: (NSError**)error;

#pragma mark - Blob Save/Get

/**
 Save a blob object directly into the database without associating it with any documents.
 
 Note: Blobs that are not associated with any documents will be removed from the database
 when compacting the database.
 
 @param blob The blob to save.
 @param error On return, the error if any.
 @return /True on success, false on failure.
 */
- (BOOL) saveBlob: (CBLBlob*)blob error: (NSError**)error;

/**
 Get a blob object using a blob’s metadata.
 If the blob of the specified metadata doesn’t exist, the nil value will be returned.
 
 @param properties The properties for getting the blob object. If dictionary is not valid, it will
 throw InvalidArgument exception. See the note section
 @return Blob on success, otherwise nil.
 
 @Note
 Key            | Value                     | Mandatory | Description
 ---------------------------------------------------------------------------------------------------
 @type          | constant string "blob"    | Yes       | Indicate Blob data type.
 content_type   | String                    | No        | Content type ex. text/plain.
 length         | Number                    | No        | Binary length of the Blob in bytes.
 digest         | String                    | Yes       | The cryptographic digest of the Blob's content.
 */
- (nullable CBLBlob*) getBlob: (NSDictionary*)properties;

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
 Close database synchronously. Before closing the database, the active replicators, listeners and live queries will be stopped.

 @param error On return, the error if any.
 @return True on success, false on failure.
 */
- (BOOL) close: (NSError**)error;

/**
 Close and delete the database synchronously. Before closing the database, the active replicators, listeners and live queries will be stopped.

 @param error On return, the error if any.
 @return True on success, false on failure.
 */
- (BOOL) delete: (NSError**)error;

/**
 Performs database maintenance.
 
 @param type Maintenance type.
 @param error On return, the error if any.
 @return True on success, false on failure.
 */
- (BOOL) performMaintenance: (CBLMaintenanceType)type error: (NSError**)error;

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
 Log object used for configuring console, file, and custom logger.

 @return log object
 */
+ (CBLLog*) log;

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


#pragma mark - DOCUMENT EXPIRATION

/**
 Sets an expiration date on a document.
 After this time the document will be purged from the database.
 
 @param documentID The ID of the document to set the expiration date for
 @param date The expiration date. Set nil date will reset the document expiration.
 @param error error On return, the error if any.
 @return True on success, false on failure.
 */
- (BOOL) setDocumentExpirationWithID: (NSString*)documentID
                          expiration: (nullable NSDate*)date
                               error: (NSError**)error;

/**
 Returns the expiration time of a document, if exists, else nil.
 
 @param documentID The ID of the document to set the expiration date for
 @return the expiration time of a document, if one has been set, else nil.
 */
- (nullable NSDate*) getDocumentExpirationWithID: (NSString*)documentID;

@end

NS_ASSUME_NONNULL_END
