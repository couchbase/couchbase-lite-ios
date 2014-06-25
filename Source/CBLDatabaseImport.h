//
//  CBLDatabaseImport.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/24/14.
//
//

#import "CBLStatus.h"
@class CBLDatabase;


/** Imports from the v1.0 SQLite database format into a CBLDatabase. */
@interface CBLDatabaseImport : NSObject

- (instancetype) initWithPath: (NSString*)dbPath;

- (instancetype) initWithDatabase: (CBLDatabase*)db
                       sqliteFile: (NSString*)sqliteFile;

- (CBLStatus) import;

@property (readonly) NSUInteger numDocs, numRevs;

@end
