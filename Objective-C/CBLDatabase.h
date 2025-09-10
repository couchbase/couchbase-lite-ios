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
#import <CouchbaseLite/CBLQueryFactory.h>
#import <CouchbaseLite/CBLCollectionTypes.h>

@class CBLBlob;
@class CBLCollection;
@class CBLDatabaseConfiguration;
@class CBLDocument;
@class CBLDocumentFragment;
@class CBLDocumentChange;
@class CBLIndex;
@class CBLIndexConfiguration;
@class CBLLog;
@class CBLMutableDocument;
@class CBLQuery;
@class CBLScope;
@protocol CBLConflictResolver;
@protocol CBLListenerToken;

NS_ASSUME_NONNULL_BEGIN

/**
Maintenance Type used when performing database maintenance .
*/
typedef NS_ENUM(uint32_t, CBLMaintenanceType) {
    kCBLMaintenanceTypeCompact,             ///< Compact the database file and delete unused attachments.
    kCBLMaintenanceTypeReindex,             ///< (Volatile API) Rebuild the entire database's indexes.
    kCBLMaintenanceTypeIntegrityCheck,      ///< (Volatile API) Check for the database’s corruption. If found, an error will be returned.
    kCBLMaintenanceTypeOptimize,            ///< Quickly updates database statistics that may help optimize queries that have been run by this Database since it was opened
    kCBLMaintenanceTypeFullOptimize         ///< Fully scans all indexes to gather database statistics that help optimize queries.
};

/** A Couchbase Lite database. */
@interface CBLDatabase : NSObject <CBLQueryFactory>

/** The database's name. */
@property (readonly, nonatomic) NSString* name;

/** The database's path. If the database is closed or deleted, nil value will be returned. */
@property (readonly, atomic, nullable) NSString* path;

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
 
 @Note This method will copy the database without changing the encryption key of the original
 database. The encryption key specified in the given config is the encryption key used for both
 the original and copied database. To change or add the encryption key for the copied database,
 call [Database changeEncryptionKey:error:] for the copy.
 @Note It is recommended to close the source database before calling this method.
 
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

#pragma mark -- Scopes

/**
 Get scope names that have at least one collection.
 
 @note The default scope is exceptional as it will always be listed even though there are no collections under it.
 
 @param error On return, the error if any. CBLErrorNotOpen code will be returned if the database is closed.
 @return returns the scope names, or nil if an error occurred.
 */
- (nullable NSArray<CBLScope*>*) scopes: (NSError**)error;

/**
 Get a scope object by name. As the scope cannot exist by itself without having a collection,
 the nil value will be returned if there are no collections under the given scope’s name.
 
 @note The default scope is exceptional, and it will always be returned.
 
 @param name Scope name, if empty, it will use default scope name.
 @param error On return, the error if any. CBLErrorNotOpen code will be returned if the database is closed.
 @return Scope object, or nil if an error occurred.
 */
- (nullable CBLScope*) scopeWithName: (nullable NSString*)name
                               error: (NSError**)error NS_SWIFT_NOTHROW;

#pragma mark -- Collections

/** Get all collections in the specified scope.
 
 @param scope Scope name
 @param error On return, the error if any. CBLErrorNotOpen code will be returned if the database is closed.
 @return list of collections in the scope, or nil if an error occurred.
 */
- (nullable NSArray<CBLCollection*>*) collections: (nullable NSString*)scope
                                            error: (NSError**)error;

/**
 Create a named collection in the specified scope.
 
 @param name name for the new collection
 @param scope collection will be created under this scope, if not specified, use the default scope.
 @param error On return, the error if any. CBLErrorNotOpen code will be returned if the database is closed.
 @return Newly created collection or if already exists, the existing collection will be returned
        , or nil if an error occurred.
 */
- (nullable CBLCollection*) createCollectionWithName: (NSString*)name
                                               scope: (nullable NSString*)scope
                                               error: (NSError**)error;

/**
 Get a collection in the specified scope by name.
 
 @param name Name of the collection to be fetched.
 @param scope Name of the scope the collection resides, if not specified uses the default scope.
 @param error On return, the error if any. CBLErrorNotOpen code will be returned
        if the database is closed. CBLErrorNotFound code will be returned if the
        collection doesn't exist.
 @return collection instance or If the collection doesn't exist, a nil value will be returned.
 */
- (nullable CBLCollection*) collectionWithName: (NSString*)name
                                         scope: (nullable NSString*)scope
                                         error: (NSError**)error NS_SWIFT_NOTHROW;

/**
 Delete a collection by name  in the specified scope. If the collection doesn't exist, the operation will be no-ops.
 
 @note The default collection cannot be deleted.
 
 @param name Name of the collection to be deleted
 @param scope Name of the scope the collection resides, if not specified uses the default scope.
 @param error On return, the error if any. CBLErrorNotOpen code will be returned if the database is closed.
 @return True on success, false on failure.
 */
- (BOOL) deleteCollectionWithName: (NSString*)name
                            scope: (nullable NSString*)scope
                            error: (NSError**)error;

/**
 Get the default scope.
 
 @param error On return, the error if any. CBLErrorNotOpen code will be returned if the database is closed.
 @return Default Scope, or nil if an error occurred.
 */
- (nullable CBLScope*) defaultScope: (NSError**)error;

/**
 Get the default collection.
 
 @param error On return, the error if any.
 @return Default collection, or nil if an error occurred.
 */
- (nullable CBLCollection*) defaultCollection: (NSError**)error;

@end

NS_ASSUME_NONNULL_END
