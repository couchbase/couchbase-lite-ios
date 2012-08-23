//
//  TouchDatabaseManager.h
//  TouchDB
//
//  Created by Jens Alfke on 6/19/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class TouchDatabase, TouchReplication, TouchLiveQuery;
@class TDDatabaseManager, TDServer;


/** Top-level TouchDB object; manages a collection of databases like a CouchDB server. */
@interface TouchDatabaseManager : NSObject
{
    @private
    TDDatabaseManager* _mgr;
    TDServer* _server;
    NSMutableArray* _replications;
}

/** A shared per-process instance. This should only be used on the main thread. */
+ (TouchDatabaseManager*) sharedInstance;

/** Preferred initializer. Starts up an in-process server in the default Application Support directory. */
- (id)init;

/** Starts up a database manager that stores its data at the given path.
    @param directory  Path to data directory. If it doesn't already exist it will be created. */
- (id) initWithDirectory: (NSString*)directory error: (NSError**)outError;


/** Releases all resources used by the TouchDatabaseManager instance and closes all its databases. */
- (void) close;

/** Returns the database with the given name, or nil if it doesn't exist.
    Multiple calls with the same name will return the same CouchDatabase instance. */
- (TouchDatabase*) databaseNamed: (NSString*)name;

/** Returns the database with the given name, creating it if it didn't already exist.
    Multiple calls with the same name will return the same CouchDatabase instance. */
- (TouchDatabase*) createDatabaseNamed: (NSString*)name error: (NSError**)outError;

/** An array of the names of all existing databases. */
@property (readonly) NSArray* allDatabaseNames;


@end
