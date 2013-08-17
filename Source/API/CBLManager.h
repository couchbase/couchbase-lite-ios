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
+ (instancetype) sharedInstance;

/** Returns YES if the given name is a valid database name.
    (Only the characters in "abcdefghijklmnopqrstuvwxyz0123456789_$()+-/" are allowed.) */
+ (BOOL) isValidDatabaseName: (NSString*)name                           __attribute__((nonnull));

/** The default directory to use for a CBLManager. This is in the Application Support directory. */
+ (NSString*) defaultDirectory;

/** Default initializer. Stores databases in the default directory. */
- (instancetype) init;

/** Initializes a CouchbaseLite manager that stores its data at the given path.
    @param directory  Path to data directory. If it doesn't already exist it will be created.
    @param options  If non-NULL, a pointer to options (read-only and no-replicator).
    @param outError  On return, the error if any. */
- (instancetype) initWithDirectory: (NSString*)directory
                           options: (const CBLManagerOptions*)options
                             error: (NSError**)outError                 __attribute__((nonnull(1)));


/** Releases all resources used by the CBLManager instance and closes all its databases. */
- (void) close;

/** The root directory of this manager (as specified at initialization time.) */
@property (readonly) NSString* directory;

/** Returns the database with the given name, or nil if it doesn't exist.
    Multiple calls with the same name will return the same CBLDatabase instance. */
- (CBLDatabase*) databaseNamed: (NSString*)name
                         error: (NSError**)outError                     __attribute__((nonnull(1)));

/** Same as -databaseNamed:. Enables "[]" access in Xcode 4.4+ */
- (CBLDatabase*) objectForKeyedSubscript: (NSString*)key __attribute__((nonnull));

/** Returns the database with the given name, creating it if it didn't already exist.
    Multiple calls with the same name will return the same CBLDatabase instance.
     NOTE: Database names may not contain capital letters! */
- (CBLDatabase*) createDatabaseNamed: (NSString*)name
                               error: (NSError**)outError               __attribute__((nonnull(1)));

/** An array of the names of all existing databases. */
@property (readonly) NSArray* allDatabaseNames;

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
                        error: (NSError**)outError                  __attribute__((nonnull(1,2)));

/** Asynchronously dispatches a block to run on a background thread. The block will be given a
    CBLDatabase instance to use; <em>it must use that database instead of any CBL objects that are
    in use on the surrounding code's thread.</em> Otherwise thread-safety will be violated, and
    Really Bad Things that are intermittent and hard to debug can happen. */
- (void) asyncTellDatabaseNamed: (NSString*)dbName to: (void (^)(CBLDatabase*))block;

/** The base URL of the database manager's REST API. You can access this URL within this process,
    using NSURLConnection or other APIs that use that (such as XMLHTTPRequest inside a WebView),
    but it isn't available outside the process.
    This method is only available if you've linked with the CouchbaseLiteListener framework. */
@property (readonly) NSURL* internalURL;

@end


/** Returns the version of Couchbase Lite */
extern NSString* CBLVersionString( void );

/** NSError domain used for HTTP status codes returned by a lot of Couchbase Lite APIs --
    for example code 404 is "not found", 403 is "forbidden", etc. */
extern NSString* const CBLHTTPErrorDomain;
