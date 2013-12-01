//
//  CBLIncrementalStore.h
//  CBLIncrementalStore
//
//  Created by Christian Beer on 21.11.13.
//  Copyright (c) 2013 Christian Beer. All rights reserved.
//

#import <CoreData/CoreData.h>

extern NSString * const kCBLIncrementalStoreErrorDomain;
extern NSString * const kCBISObjectHasBeenChangedInStoreNotification;

typedef enum
{
    CBLIncrementalStoreErrorUndefinedError = 0,
    CBLIncrementalStoreErrorCreatingStoreFailed,
    CBLIncrementalStoreErrorMigrationOfStoreFailed,
    CBLIncrementalStoreErrorStoringMetadataFailed,
    CBLIncrementalStoreErrorDatabaseModelIncompatible,
    CBLIncrementalStoreErrorCBLManagerSharedInstanceMissing,
    CBLIncrementalStoreErrorCreatingDatabaseFailed,
    CBLIncrementalStoreErrorPersistingInsertedObjectsFailed,
    CBLIncrementalStoreErrorPersistingUpdatedObjectsFailed,
    CBLIncrementalStoreErrorPersistingDeletedObjectsFailed,
    CBLIncrementalStoreErrorQueryingCouchbaseLiteFailed,
    CBLIncrementalStoreErrorUnsupportedRequestType
} CBLIncrementalStoreError;

@class CBLDocument;
@class CBLDatabase;


typedef void(^CBLISConflictHandler)(CBLDocument *doc, NSArray *conflictingRevisions);


/** NSIncrementalStore implementation for CouchbaseLite iOS.
 *
 */
@interface CBLIncrementalStore : NSIncrementalStore

@property (nonatomic, strong, readonly) CBLDatabase *database;

/** Conflict handling block that gets called when conflicts are to be handled. Initialied with a generic conflicts handler, can be set to NULL to not handle conflicts at all. */
@property (nonatomic, copy) CBLISConflictHandler conflictHandler;

+ (NSString *)type;

+ (void) updateManagedObjectModel:(NSManagedObjectModel*)managedObjectModel;

+ (NSManagedObjectContext*) createManagedObjectContextWithModel:(NSManagedObjectModel*)managedObjectModel databaseName:(NSString*)databaseName error:(NSError**)outError;
+ (NSManagedObjectContext*) createManagedObjectContextWithModel:(NSManagedObjectModel*)managedObjectModel databaseName:(NSString*)databaseName importingDatabaseAtURL:(NSURL*)importUrl importType:(NSString*)importType error:(NSError**)outError;

- (void) addObservingManagedObjectContext:(NSManagedObjectContext*)context;
- (void) removeObservingManagedObjectContext:(NSManagedObjectContext*)context;

@end
