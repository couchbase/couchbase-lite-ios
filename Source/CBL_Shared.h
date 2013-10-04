//
//  CBL_Shared.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/20/13.
//
//

#import <Foundation/Foundation.h>
@class CBL_Server;


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

- (void) forgetDatabaseNamed: (NSString*)name;

@property CBL_Server* backgroundServer;

@end
