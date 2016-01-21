//
//  CBLManager.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/19/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import "CBLBase.h"
@class CBLDatabase;

NS_ASSUME_NONNULL_BEGIN
/** Option flags for CBLManager initialization. */
typedef struct CBLManagerOptions {
    bool                 readOnly;          /**< No modifications to databases are allowed. */
    NSDataWritingOptions fileProtection;    /**< File protection/encryption options (iOS only) */
} CBLManagerOptions;




/** Options for opening a database. All properties default to NO or nil. */
@interface CBLDatabaseOptions : NSObject
@property (nonatomic) BOOL create;                  /**< Create database if it doesn't exist? */
@property (nonatomic) BOOL readOnly;                /**< Open database read-only? */

/** The underlying storage engine to use. Legal values are kCBLSQLiteStorage, kCBLForestDBStorage, 
    or nil.
    * If the database is being created, the given storage engine will be used, or the default if
      the value is nil.
    * If the database exists, and the value is not nil, the database will be upgraded to that
      storage engine if possible. (SQLite-to-ForestDB upgrades are supported.) */
@property (nonatomic, copy) NSString* storageType;

/** A key to encrypt the database with. If the database does not exist and is being created, it
    will use this key, and the same key must be given every time it's opened.

    * The primary form of key is an NSData object 32 bytes in length: this is interpreted as a raw
      AES-256 key. To create a key, generate random data using a secure cryptographic randomizer
      like SecRandomCopyBytes or CCRandomGenerateBytes.
    * Alternatively, the value may be an NSString containing a passphrase. This will be run through
      64,000 rounds of the PBKDF algorithm to securely convert it into an AES-256 key.
    * On Mac OS only, the value may be @YES. This instructs Couchbase Lite to use a key stored in
      the user's Keychain, or generate one there if it doesn't exist yet.
    * A default nil value, of course, means the database is unencrypted. */
@property (nonatomic, strong) id encryptionKey;
@end




/** Top-level Couchbase Lite object; manages a collection of databases.
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
- (nullable instancetype) initWithDirectory: (NSString*)directory
                                    options: (const CBLManagerOptions* __nullable)options
                                      error: (NSError**)outError;

/** Creates a copy of this CBLManager, which can be used on a different thread. */
- (instancetype) copy;

/** Releases all resources used by the CBLManager instance and closes all its databases. */
- (void) close;

/** Default storage engine type for newly-created databases.
    There are two options, "SQLite" (the default) or "ForestDB". */
@property (copy, nonatomic) NSString* storageType;

/** The root directory of this manager (as specified at initialization time.) */
@property (readonly) NSString* directory;

/** Should the databases and attachments be excluded from iCloud or Time Machine backup?
    Defaults to NO. */
@property BOOL excludedFromBackup;

#pragma mark - DATABASES:

/** Returns the database with the given name, creating it if it didn't already exist.
    Multiple calls with the same name will return the same CBLDatabase instance.
    NOTE: Database names may not contain capital letters!
    This is equivalent to calling -openDatabaseNamed:withOptions:error: with a default set of
    options with the `create` flag set. */
- (nullable CBLDatabase*) databaseNamed: (NSString*)name
                                  error: (NSError**)outError;

/** Returns the database with the given name, or nil if it doesn't exist.
    Multiple calls with the same name will return the same CBLDatabase instance.
    This is equivalent to calling -openDatabaseNamed:withOptions:error: with a default set of
    options. */
- (nullable CBLDatabase*) existingDatabaseNamed: (NSString*)name
                                          error: (NSError**)outError;

/** Returns the database with the given name. If the database is not yet open, the options given
    will be applied; if it's already open, the options are ignored.
    Multiple calls with the same name will return the same CBLDatabase instance.
    @param name  The name of the database. May NOT contain capital letters!
    @param options  Options to use when opening, such as the encryption key; if nil, a default
                    set of options will be used.
    @param outError  On return, the error if any.
    @return  The database instance, or nil on error. */
- (nullable CBLDatabase*) openDatabaseNamed: (NSString*)name
                                withOptions: (nullable CBLDatabaseOptions*)options
                                      error: (NSError**)outError;

/** Returns YES if a database with the given name exists. Does not open the database. */
- (BOOL) databaseExistsNamed: (NSString*)name;

/** Same as -existingDatabaseNamed:. Enables "[]" access in Xcode 4.4+ */
- (nullable CBLDatabase*) objectForKeyedSubscript: (NSString*)key;

/** An array of the names of all existing databases. */
@property (readonly) CBLArrayOf(NSString*)* allDatabaseNames;


#ifdef CBL_DEPRECATED
/** Replaces or installs a database from a file. This is primarily used to install a canned database 
    on first launch of an app, in which case you should first check .exists to avoid replacing the 
    database if it exists already. The canned database would have been copied into your app bundle 
    at build time. This property is deprecated for the new .cblite2 database file. If the database 
    file is a directory and has the .cblite2 extension, 
    use -replaceDatabaseNamed:withDatabaseDir:error: instead.
 @param databaseName  The name of the database to replace.
 @param databasePath  Path of the database file that should replace it.
 @param attachmentsPath  Path of the associated attachments directory, or nil if there are no attachments.
 @param outError  If an error occurs, it will be stored into this parameter on return.
 @return  YES if the database was copied, NO if an error occurred. */
- (BOOL) replaceDatabaseNamed: (NSString*)databaseName
             withDatabaseFile: (NSString*)databasePath
              withAttachments: (nullable NSString*)attachmentsPath
                        error: (NSError**)outError;
#endif

/** Replaces or installs a database from a file. This is primarily used to install a canned database 
    on first launch of an app, in which case you should first check .exists to avoid replacing the 
    database if it exists already. The canned database would have been copied into your app bundle 
    at build time. If the database file is not a directory and has the .cblite extension,
    use -replaceDatabaseNamed:withDatabaseFile:withAttachments:error: instead.
    @param databaseName  The name of the database to replace.
    @param databaseDir  Path of the database directory that should replace it.
    @param outError  If an error occurs, it will be stored into this parameter on return.
    @return  YES if the database was copied, NO if an error occurred. */
- (BOOL) replaceDatabaseNamed: (NSString*)databaseName
              withDatabaseDir: (NSString*)databaseDir
                        error: (NSError**)outError;

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
+ (void) enableLogging: (nullable NSString*)type;

/** Redirects Couchbase Lite logging: instead of writing to the console/stderr, it will call the
    given block. Passing a nil block restores the default behavior. */
+ (void) redirectLogging: (nullable void (^)(NSString* type, NSString* message))callback;


@property (readonly, nonatomic, nullable) NSMutableDictionary* customHTTPHeaders;


/** This method has been superseded by -openDatabaseNamed:options:error:. */
- (BOOL) registerEncryptionKey: (nullable id)keyOrPassword
              forDatabaseNamed: (NSString*)name;

@end


/** Returns the version of Couchbase Lite */
extern NSString* CBLVersion( void );

/** NSError domain used for HTTP status codes returned by a lot of Couchbase Lite APIs --
    for example code 404 is "not found", 403 is "forbidden", etc. */
extern NSString* const CBLHTTPErrorDomain;

/** SQLite storage type used for setting CBLDatabaseOptions.storageType. */
extern NSString* const kCBLSQLiteStorage;

/** ForestDB storage type used for setting CBLDatabaseOptions.storageType. */
extern NSString* const kCBLForestDBStorage;

NS_ASSUME_NONNULL_END
