//
//  CBLDatabaseImport.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/24/14.
//  Copyright (c) 2014-2015 Couchbase, Inc. All rights reserved.
//

#import "CBLStatus.h"
@class CBLDatabase;


/** Imports from the v1.0 SQLite database format into a CBLDatabase.
    This class is optional: the source file does not need to be built into the app or the
    Couchbase Lite library. If it's not present, Couchbase Lite will ignore old v1.0 databases
    instead of importing them. */
@interface CBLDatabaseUpgrade : NSObject

- (instancetype) initWithDatabase: (CBLDatabase*)db
                       sqliteFile: (NSString*)sqliteFile;

@property BOOL canRemoveOldAttachmentsDir;

- (CBLStatus) import;

- (void) backOut;

- (void) deleteSQLiteFiles;

@property (readonly) NSUInteger numDocs, numRevs;

@end
