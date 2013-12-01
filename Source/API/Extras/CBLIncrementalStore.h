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

@class CBLDatabase;

/** NSIncrementalStore implementation for CouchbaseLite iOS. 
 *
 */
@interface CBLIncrementalStore : NSIncrementalStore

@property (nonatomic, strong, readonly) CBLDatabase *database;
+ (NSString *)type;

+ (void) updateManagedObjectModel:(NSManagedObjectModel*)managedObjectModel;

+ (NSManagedObjectContext*) createManagedObjectContextWithModel:(NSManagedObjectModel*)managedObjectModel databaseName:(NSString*)databaseName error:(NSError**)outError;
+ (NSManagedObjectContext*) createManagedObjectContextWithModel:(NSManagedObjectModel*)managedObjectModel databaseName:(NSString*)databaseName importingDatabaseAtURL:(NSURL*)importUrl importType:(NSString*)importType error:(NSError**)outError;

- (void) addObservingManagedObjectContext:(NSManagedObjectContext*)context;
- (void) removeObservingManagedObjectContext:(NSManagedObjectContext*)context;

@end
