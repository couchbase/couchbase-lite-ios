//
//  CBLManager.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/19/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLDatabase;


/** Option flags for CBLManager initialization. */
typedef struct CBLManagerOptions {
    bool readOnly;      /**< No modifications to databases are allowed. */
    bool noReplicator;  /**< Persistent replications will not run. */
} CBLManagerOptions;


/** Top-level CouchbaseLite object; manages a collection of databases as a CouchDB server does.
    A CBLManager and all the objects descending from it may only be used on a single
    thread. To work with databases on another thread, create a new CBLManager instance for
    that thread (and be sure to use the .noReplicator option.) The easist way to do this is simply
    to call -copy on the existing manager. */
@interface CBLManager : NSObject <NSCopying>

/** A shared per-process instance. This should only be used on the main thread. */
+ (CBLManager*) sharedInstance;

/** Default initializer. Stores databases in the default Application Support directory. */
- (id)init;

/** Initializes a CouchbaseLite manager that stores its data at the given path.
    @param directory  Path to data directory. If it doesn't already exist it will be created.
    @param options  If non-NULL, a pointer to options (read-only and no-replicator).
    @param outError  On return, the error if any. */
- (id) initWithDirectory: (NSString*)directory
                 options: (const CBLManagerOptions*)options
                   error: (NSError**)outError;


/** Releases all resources used by the CBLManager instance and closes all its databases. */
- (void) close;

/** Returns the database with the given name, or nil if it doesn't exist.
    Multiple calls with the same name will return the same CouchDatabase instance. */
- (CBLDatabase*) databaseNamed: (NSString*)name;

/** Same as -databaseNamed:. Enables "[]" access in Xcode 4.4+ */
- (CBLDatabase*) objectForKeyedSubscript: (NSString*)key;

/** Returns the database with the given name, creating it if it didn't already exist.
    Multiple calls with the same name will return the same CouchDatabase instance.
     NOTE: Database names may not contain capital letters! */
- (CBLDatabase*) createDatabaseNamed: (NSString*)name error: (NSError**)outError;

/** An array of the names of all existing databases. */
@property (readonly) NSArray* allDatabaseNames;

/** The 'cbl:' URL of the database manager's REST API.
    Only available if you've linked with the CouchbaseLiteListener framework. */
@property (readonly) NSURL* internalURL;

/** Replaces or installs a database from a file.
    This is primarily used to install a canned database on first launch of an app, in which case you should first check .exists to avoid replacing the database if it exists already. The canned database would have been copied into your app bundle at build time.
    @param databaseName  The name of the database to replace.
    @param databasePath  Path of the database file that should replace it.
    @param attachmentsPath  Path of the associated attachments directory, or nil if there are no attachments.
    @param outError  If an error occurs, it will be stored into this parameter on return.
    @return  YES if the database was copied, NO if an error occurred. */
- (BOOL) replaceDatabaseNamed: (NSString*)databaseName
             withDatabaseFile: (NSString*)databasePath
              withAttachments: (NSString*)attachmentsPath
                        error: (NSError**)outError;


@end
