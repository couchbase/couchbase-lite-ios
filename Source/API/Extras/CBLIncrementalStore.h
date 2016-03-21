//
//  CBLIncrementalStore.h
//  CBLIncrementalStore
//
//  Created by Christian Beer on 21.11.13.
//  Copyright (c) 2013 Christian Beer. All rights reserved.
//
//  Modified by Pasin Suriyentrakorn
//  Copyright (c) 2016 Couchbase. All rights reserved.
//

#import <CoreData/CoreData.h>

extern NSString* const kCBLISErrorDomain;
extern NSString* const kCBLISObjectHasBeenChangedInStoreNotification;

/** Maximum number of relationship loading allowed in a fetch request. Default value is 3. */
extern NSString* const kCBLISCustomPropertyMaxRelationshipLoadDepth;

/** Enable query boolean value with number. After CBL 1.1.0, CBLIS stores a boolean value as
 * a JSON boolean value instead of a number value of 1 or 0. If the application
 * uses CBLIS and has stored boolean values since CBL 1.1.0 or below, setting this option to
 * YES is required for quering data with boolean value predicates. Default value is NO. */
extern NSString* const kCBLISCustomPropertyQueryBooleanWithNumber;

/** Error codes for CBLIncrementalStore. */
typedef enum
{
    CBLIncrementalStoreErrorCreatingStoreFailed,
    CBLIncrementalStoreErrorMigrationOfStoreFailed,
    CBLIncrementalStoreLoadMetadataFailed,
    CBLIncrementalStoreErrorDatabaseModelIncompatible,
    CBLIncrementalStoreErrorQueryingCouchbaseLiteFailed,
    CBLIncrementalStoreErrorUnsupportedRequestType,
    CBLIncrementalStoreErrorUnsupportedPredicate,
    CBLIncrementalStoreErrorPredicateKeyPathNotFoundInEntity,
    CBLIncrementalStoreErrorUnsupportedFetchRequestResultType,
    CBLIncrementalStoreErrorUnsupportedFetchRequest
} CBLIncrementalStoreError;

@class CBLIncrementalStore;
@class CBLDocument;
@class CBLDatabase;
@class CBLManager;


/** Block that handles conflicts and can merge all conflicting revisions into one, dismiss all conflicts, etc.
 * Is called with all conflicting revisions of the document, as an array of CBLRevision.
 * The first object in the array will be the default "winning" revision that shadows the others.
 *
 * @parameter conflictingRevisions the conflicting revisions of that document as CBLRevision instances.
 */
typedef void(^CBLISConflictHandler)(NSArray* conflictingRevisions);

@protocol CBLIncrementalStoreDelegate <NSObject>
@optional
- (NSDictionary *) storeWillSaveDocument:(NSDictionary *)document;
@end


/** NSIncrementalStore implementation that persists the data in a CouchbaseLite database. Before using this store you need to call #updateManagedObjectModel:
 * to prepare the Core Data model. To be informed about changes, you need to call #addObservingManagedObjectContext: with every NSManagedObjectContext.
 *
 * The last path component of the database URL is used for the database name. Examples: cblite://test-database, cblite://test/abc/database-name.
 *
 * There are also convenience methods to create the whole Core Data stack with one line of code.
 *
 * @author Christian Beer http://chbeer.de
 */
@interface CBLIncrementalStore : NSIncrementalStore

/** The underlying CouchbaseLite database. */
@property (nonatomic, strong, readonly) CBLDatabase* database;

/** Conflict handling block that gets called when conflicts are to be handled. Initialied with a generic conflicts handler, can be set to NULL to not handle conflicts at all. */
@property (nonatomic, copy) CBLISConflictHandler conflictHandler;

/** Delegate allowing some more customization to the developer's implementation */
@property (nonatomic, weak) id<CBLIncrementalStoreDelegate> delegate;

/** An optional dictionary of extra properties for the incremental store.*/
@property (nonatomic, copy) NSDictionary* customProperties;

/** Returns the type of this store to use with addPersistentStore:...
 *
 * @returns the type of this store.
 */
+ (NSString*) type;

/** Configures which CBLManager instance to use. The CBLManager instance set to the store
 * requires to have a dispatch queue set. The default value (nil) means to use the default
 * CBLManager instance created by the CBLIncrementalStore.
 */
+ (void) setCBLManager: (CBLManager*)manager;
+ (CBLManager*) CBLManager;

/** Updates the managedObjectModel to be used with this store. Adds a property named `cblisRev` to store the current `_rev`
 * value of the CouchbaseLite representation of that entity.
 *
 * @param managedObjectModel the NSManagedObjectModel that should be used with this store.
 */
+ (void) updateManagedObjectModel: (NSManagedObjectModel*)managedObjectModel;

/** Convenience method that creates the whole Core Data stack using the given database model and persists the data the given database.
 * You don't need to run #updateManagedObjectModel: before.
 * To get a reference to the underlying CBLIncrementalStore you can call `context.persistentStoreCoordinator.persistentStores[0]` afterwards.
 *
 * @param managedObjectModel the NSManagedObjectModel that defines the database model
 * @param databaseName the name of the database where the data is stored
 * @param outError an optional error reference. Contains an NSError when the return is nil
 * @returns a new NSManagedObjectContext ready to use, or nil if there was an error
 */
+ (NSManagedObjectContext*) createManagedObjectContextWithModel: (NSManagedObjectModel*)managedObjectModel
                                                   databaseName: (NSString*)databaseName
                                                          error: (NSError**)outError;

/** Convenience method that creates the whole Core Data stack using the given database model, persists the data the given database and
 * imports the data from an existing Core Data database. You don't need to run #updateManagedObjectModel: before.
 * To get a reference to the underlying CBLIncrementalStore you can call `context.persistentStoreCoordinator.persistentStores[0]` afterwards.
 *
 * @param managedObjectModel the NSManagedObjectModel that defines the database model
 * @param databaseName the name of the database where the data is stored
 * @param importUrl NSURL to an existing Core Data database that should be used to create this database. If the CouchbaseLite database already existed the data is not imported!
 * @param importType Core Data type of the imported database. Like `NSSQLiteStoreType` or `NSXMLStoreType`.
 * @param outError an optional error reference. Contains an NSError when the return is nil
 * @returns a new NSManagedObjectContext ready to use, or nil if there was an error
 */
+ (NSManagedObjectContext*) createManagedObjectContextWithModel: (NSManagedObjectModel*)managedObjectModel
                                                   databaseName: (NSString*)databaseName
                                         importingDatabaseAtURL: (NSURL*)importUrl
                                                     importType: (NSString*)importType
                                                          error: (NSError**)outError;


/** Register a NSManagedObjectContext to be informed about changes in the CouchbaseLite database.
 * A NSManagedObjectContextObjectsDidChangeNotification is sent to this context on changes.
 */
- (void) addObservingManagedObjectContext: (NSManagedObjectContext*)context;

/** Deregister a NSManagedObjectContext from observing changes.*/
- (void) removeObservingManagedObjectContext: (NSManagedObjectContext*)context;


/** Purges this object from the database. This operation will be executed on the same dispatch queue
 * as the database.
 *
 * In multiple context setup, if the object was created on a context aside from the root context, and
 * the object hasn't been retrieved back from the store, the object ID of the object may be still a
 * tempory ID as in general the ID will not be refreshed with the permanent ID from its root
 * context. As a result, the object may not be purged as expected due to ID mismatching. To avoid
 * the issue, call NSManagedObjectContext's -obtainPermanentIDsForObjects:error: to obtain
 * its permanent ID.
 *
 * @param object the NSManagedObject object to be purged
 * @param outError an optional error reference. Contains an NSError when the return is NO.
 * @returns YES of success, otherwise return NO.
 */
- (BOOL) purgeObject: (NSManagedObject*)object error: (NSError**)outError;

@end
