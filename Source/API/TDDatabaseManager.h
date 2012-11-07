//
//  TDDatabaseManager.h
//  TouchDB
//
//  Created by Jens Alfke on 6/19/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class TDDatabase, TDReplication, TDLiveQuery;
@class TD_DatabaseManager, TD_Server;


typedef struct TDDatabaseManagerOptions {
    bool readOnly;
    bool noReplicator;
} TDDatabaseManagerOptions;


/** Top-level TouchDB object; manages a collection of databases as a CouchDB server does. */
@interface TDDatabaseManager : NSObject
{
    @private
    TDDatabaseManagerOptions _options;
    TD_DatabaseManager* _mgr;
    TD_Server* _server;
    NSMutableArray* _replications;
}

/** A shared per-process instance. This should only be used on the main thread. */
+ (TDDatabaseManager*) sharedInstance;

/** Preferred initializer. Starts up an in-process server, on the current thread, that stores databases in the default Application Support directory. */
- (id)init;

/** Starts up a database manager, on the current thread, that stores its data at the given path.
    @param directory  Path to data directory. If it doesn't already exist it will be created.
    @param options  If non-NULL, a pointer to options (read-only and no-replicator).
    @param outError  On return, the error if any. */
- (id) initWithDirectory: (NSString*)directory
                 options: (const TDDatabaseManagerOptions*)options
                   error: (NSError**)outError;


/** Releases all resources used by the TDDatabaseManager instance and closes all its databases. */
- (void) close;

/** Returns the database with the given name, or nil if it doesn't exist.
    Multiple calls with the same name will return the same CouchDatabase instance. */
- (TDDatabase*) databaseNamed: (NSString*)name;

/** Same as -databaseNamed:. Enables "[]" access in Xcode 4.4+ */
- (TDDatabase*) objectForKeyedSubscript: (NSString*)key;

/** Returns the database with the given name, creating it if it didn't already exist.
    Multiple calls with the same name will return the same CouchDatabase instance.
     NOTE: Database names may not contain capital letters! */
- (TDDatabase*) createDatabaseNamed: (NSString*)name error: (NSError**)outError;

/** An array of the names of all existing databases. */
@property (readonly) NSArray* allDatabaseNames;


@end
