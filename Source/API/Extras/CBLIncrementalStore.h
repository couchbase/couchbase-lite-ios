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


/** NSIncrementalStore implementation for CouchbaseLite iOS. 
 *
 */
@interface CBLIncrementalStore : NSIncrementalStore

+ (NSString *)type;

+ (void) updateManagedObjectModel:(NSManagedObjectModel*)managedObjectModel;

+ (NSManagedObjectContext*) createManagedObjectContextWithModel:(NSManagedObjectModel*)managedObjectModel databaseName:(NSString*)databaseName error:(NSError**)outError;
+ (NSManagedObjectContext*) createManagedObjectContextWithModel:(NSManagedObjectModel*)managedObjectModel databaseName:(NSString*)databaseName importingDatabaseAtURL:(NSURL*)importUrl importType:(NSString*)importType error:(NSError**)outError;

- (NSArray*) replicateWithURL:(NSURL*)replicationURL exclusively:(BOOL)exclusively;
- (NSArray*) replications;

- (void) addObservingManagedObjectContext:(NSManagedObjectContext*)context;
- (void) removeObservingManagedObjectContext:(NSManagedObjectContext*)context;

@end
