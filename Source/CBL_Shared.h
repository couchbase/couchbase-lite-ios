//
//  CBL_Shared.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/20/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//
//

#import <Foundation/Foundation.h>
@class CBL_Server, MYReadWriteLock;


/** Container for shared state between CBLDatabase instances that represent the same database file. API is thread-safe. */
@interface CBL_Shared : NSObject

- (void) setValue: (id)value
          forType: (NSString*)type
             name: (NSString*)name
  inDatabaseNamed: (NSString*)dbName;

- (id) valueForType: (NSString*)type
               name: (NSString*)name
    inDatabaseNamed: (NSString*)dbName;

- (bool) hasValuesOfType: (NSString*)type
         inDatabaseNamed: (NSString*)dbName;

- (NSDictionary*) valuesOfType: (NSString*)type
               inDatabaseNamed: (NSString*)dbName;

- (MYReadWriteLock*) lockForDatabaseNamed: (NSString*)dbName;

- (void) openedDatabase: (NSString*)dbName;
- (void) closedDatabase: (NSString*)dbName;
- (BOOL) isDatabaseOpened: (NSString*)dbName;

// Blocks till everyone who opened the database has closed it
- (void) forgetDatabaseNamed: (NSString*)name;

@property CBL_Server* backgroundServer;

#if DEBUG
- (NSUInteger) countForOpenedDatabase: (NSString*)dbName;
#endif

@end
