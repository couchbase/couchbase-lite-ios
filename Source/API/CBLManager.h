//
//  CBLManager.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/19/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLDatabase;

#if __has_feature(nullability) // Xcode 6.3+
#pragma clang assume_nonnull begin
#else
#define nullable
#define __nullable
#endif

/** Option flags for CBLManager initialization. */
typedef struct CBLManagerOptions {
    bool                 readOnly;          /**< No modifications to databases are allowed. */
    NSDataWritingOptions fileProtection;    /**< File protection/encryption options (iOS only) */
} CBLManagerOptions;


/** Top-level CouchbaseLite object; manages a collection of databases as a CouchDB server does.
    A CBLManager and all the objects descending from it may only be used on a single
    thread. To work with databases on another thread, copy the database manager (by calling
    -copy) and use the copy on the other thread. */
@interface CBLManager : NSObject <NSCopying>

/** A shared per-process instance. This should only be used on the main thread. */
+ (instancetype) sharedInstance;

/** Returns YES if the given name is a valid database name.
    (Only the characters in "abcdefghijklmnopqrstuvwxyz0123456789_$()+-/" are allowed.) */
+ (BOOL) isValidDatabaseName: (NSString*)name;

/** The default directory to use for a CBLManager. This is in the Application Support directory. */
+ (NSString*) defaultDirectory;

/** Default initializer. Stores databases in the default directory. */
- (instancetype) init;

/** Initializes a CouchbaseLite manager that stores its data at the given path.
    @param directory  Path to data directory. If it doesn't already exist it will be created.
    @param options  If non-NULL, a pointer to options (read-only and no-replicator).
    @param outError  On return, the error if any. */
- (instancetype) initWithDirectory: (NSString*)directory
                           options: (const CBLManagerOptions* __nullable)options
                             error: (NSError**)outError;

/** Creates a copy of this CBLManager, which can be used on a different thread. */
- (instancetype) copy;

/** Releases all resources used by the CBLManager instance and closes all its databases. */
- (void) close;

/** The root directory of this manager (as specified at initialization time.) */
@property (readonly) NSString* directory;

/** Should the databases and attachments be excluded from iCloud or Time Machine backup?
    Defaults to NO. */
@property BOOL excludedFromBackup;

#pragma mark - DATABASES:

/** Returns the database with the given name, creating it if it didn't already exist.
    Multiple calls with the same name will return the same CBLDatabase instance.
    NOTE: Database names may not contain capital letters! */
- (nullable CBLDatabase*) databaseNamed: (NSString*)name
                                  error: (NSError**)outError;

/** Returns the database with the given name, or nil if it doesn't exist.
    Multiple calls with the same name will return the same CBLDatabase instance. */
- (nullable CBLDatabase*) existingDatabaseNamed: (NSString*)name
                                          error: (NSError**)outError;

/** Returns YES if a database with the given name exists. Does not open the database. */
- (BOOL) databaseExistsNamed: (NSString*)name;

/** Registers an encryption key for a database. This must be called before opening an encrypted
    database, or before creating a database that's to be encrypted.
    If the key is incorrect (or no key is given for an encrypted database), the subsequent call
    to open the database will fail with an error with code 401.
    To use this API, the database storage engine must support encryption. In the case of SQLite,
    this means the application must be linked with SQLCipher <http://sqlcipher.net> instead of
    regular SQLite. Otherwise opening the database will fail with an error. */
- (BOOL) registerEncryptionKey: (nullable id)encryptionKey
              forDatabaseNamed: (NSString*)name;

/** Same as -existingDatabaseNamed:. Enables "[]" access in Xcode 4.4+ */
- (nullable CBLDatabase*) objectForKeyedSubscript: (NSString*)key;

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

#pragma mark - CONCURRENCY:

/** The dispatch queue used to serialize access to the database manager (and its child objects.)
    Setting this is optional: by default the objects are bound to the thread on which the database
    manager was instantiated. By setting a dispatch queue, you can call the objects from within that
    queue no matter what the underlying thread is, and notifications will be posted on that queue
    as well. */
@property (strong, nullable) dispatch_queue_t dispatchQueue;

/** Runs the block asynchronously on the database manager's dispatch queue or thread.
    Unlike the rest of the API, this can be called from any thread, and provides a limited form
    of multithreaded access to Couchbase Lite. */
- (void) doAsync: (void (^)())block;

/** Asynchronously dispatches a block to run on a background thread. The block will be given a
    CBLDatabase instance to use; <em>it must use that database instead of any CBL objects that are
    in use on the surrounding code's thread.</em> Otherwise thread-safety will be violated, and
    Really Bad Things that are intermittent and hard to debug can happen.
    (Note: Unlike most of the API, this method is thread-safe.) */
- (void) backgroundTellDatabaseNamed: (NSString*)dbName to: (void (^)(CBLDatabase*))block;

#pragma mark - OTHER API:

/** The base URL of the database manager's REST API. You can access this URL within this process,
    using NSURLConnection or other APIs that use that (such as XMLHTTPRequest inside a WebView),
    but it isn't available outside the process.
    This method is only available if you've linked with the CouchbaseLiteListener framework. */
@property (readonly) NSURL* internalURL;

/** Enables Couchbase Lite logging of the given type, process-wide. A partial list of types is here:
    http://docs.couchbase.com/couchbase-lite/cbl-ios/#useful-logging-channels 
    It's usually more convenient to enable logging via command-line args, as discussed on that
    same page; but in some environments you may not have access to the args, or may want to use
    other criteria to enable logging. */
+ (void) enableLogging: (NSString*)type;

/** Redirects Couchbase Lite logging: instead of writing to the console/stderr, it will call the
    given block. Passing a nil block restores the default behavior. */
+ (void) redirectLogging: (nullable void (^)(NSString* type, NSString* message))callback;


@property (readonly, nonatomic, nullable) NSMutableDictionary* customHTTPHeaders;

@end


/** Returns the version of Couchbase Lite */
extern NSString* CBLVersion( void );

/** NSError domain used for HTTP status codes returned by a lot of Couchbase Lite APIs --
    for example code 404 is "not found", 403 is "forbidden", etc. */
extern NSString* const CBLHTTPErrorDomain;



#if __has_feature(nullability)
#pragma clang assume_nonnull end
#endif
