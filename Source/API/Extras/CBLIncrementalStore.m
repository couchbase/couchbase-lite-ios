//
//  CBLIncrementalStore.m
//  CBLIncrementalStore
//
//  Created by Christian Beer on 21.11.13.
//  Copyright (c) 2013 Christian Beer. All rights reserved.
//
//  Modified by Pasin Suriyentrakorn
//  Copyright (c) 2016 Couchbase. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLIncrementalStore.h"

#import <CouchbaseLite/CouchbaseLite.h>

#define COMMON_DIGEST_FOR_OPENSSL
#import <CommonCrypto/CommonDigest.h>

#if !__has_feature(objc_arc)
#  error This class requires ARC!
#endif

#define LOGGING 0
#define INFO(FMT, ...) if (!LOGGING) ; else NSLog(@"[CBLIS] INFO " FMT, ##__VA_ARGS__)
#define WARN(FMT, ...) NSLog(@"[CBLIS] WARNING " FMT, ##__VA_ARGS__)
#define ERROR(FMT, ...) NSLog(@"[CBLIS] ERROR " FMT, ##__VA_ARGS__)

#define kDefaultMaxRelationshipLoadDepth 3;

NSString* const kCBLISErrorDomain = @"CBLISErrorDomain";
NSString* const kCBLISObjectHasBeenChangedInStoreNotification = @"CBLISObjectHasBeenChangedInStoreNotification";
NSString* const kCBLISCustomPropertyMaxRelationshipLoadDepth = @"CBLISCustomPropertyMaxRelationshipLoadDepth";
NSString* const kCBLISCustomPropertyQueryBooleanWithNumber = @"CBLISCustomPropertyQueryBooleanWithNumber";

static NSString* const kCBLISMetadataDocumentID = @"CBLIS_metadata";
static NSString* const kCBLISMetadata_DefaultTypeKey = @"type_key";

static NSString* const kCBLISDefaultTypeKey = @"type";
static NSString* const kCBLISOldDefaultTypeKey = @"CBLIS_type";

static NSString* const kCBLISRevisionAttributeName = @"CBLIS_Rev";
static NSString* const kCBLISManagedObjectIDPrefix = @"CBL";
static NSString* const kCBLISToManyViewNameFormat = @"CBLIS_View_%@_%@_%@";

// Utility functions
static BOOL CBLISIsNull(id value);
static NSString* CBLISToManyViewNameForRelationship(NSRelationshipDescription* relationship);
static NSString* CBLISResultTypeName(NSFetchRequestResultType resultType);
static NSError* CBLISError(NSInteger code, NSString* desc, NSError *parent);

@interface NSManagedObjectID (CBLIncrementalStore)
- (NSString*) documentIDRepresentation;
@end

@interface CBLIncrementalStore ()

// TODO: check if there is a better way to not hold strong references on these MOCs
@property (nonatomic, strong) NSHashTable* observingManagedObjectContexts;
@property (nonatomic, strong) CBLManager* manager;
@property (nonatomic, strong) CBLDatabase* database;
@property (nonatomic, readonly) NSUInteger maxRelationshipLoadDepth;
@property (nonatomic) BOOL shouldNotifyLocalDatabaseChanges;

@end

@implementation CBLIncrementalStore
{
    NSCache* _queryBuilderCache;
    NSMutableDictionary* _fetchRequestResultCache;
    CBLLiveQuery* _conflictsQuery;
    NSString * _documentTypeKey;
    NSUInteger _relationshipSearchDepth;
    NSCache* _relationshipCache;
    NSCache* _recentSavedObjectIDs;
    BOOL _shouldNotifyLocalDatabaseChanges;

    struct {
        unsigned int storeWillSaveDocument:1;
    } _respondFlags;
}

@synthesize manager = _manager;
@synthesize database = _database;
@synthesize conflictHandler = _conflictHandler;
@synthesize customProperties = _customProperties;
@synthesize observingManagedObjectContexts = _observingManagedObjectContexts;
@synthesize shouldNotifyLocalDatabaseChanges = _shouldNotifyLocalDatabaseChanges;
@synthesize delegate = _delegate;

#pragma mark - Initialize

+ (void) initialize {
    if ([[self class] isEqual: [CBLIncrementalStore class]]) {
        [NSPersistentStoreCoordinator registerStoreClass: self
                                            forStoreType: [self type]];
    }
}

- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver: self
                                                    name: kCBLDatabaseChangeNotification
                                                  object: self.database];
    [_conflictsQuery removeObserver: self forKeyPath: @"rows"];
    _conflictsQuery = nil;
    self.database = nil;
}

static CBLManager* sCBLManager;

+ (void) setCBLManager: (CBLManager*)manager {
    assert(manager.dispatchQueue != nil);
    sCBLManager = manager;
}

+ (CBLManager*) CBLManager {
    return sCBLManager;
}

#pragma mark - Convenience Method

+ (NSManagedObjectContext*) createManagedObjectContextWithModel: (NSManagedObjectModel*)managedObjectModel
                                                   databaseName: (NSString*)databaseName
                                                          error: (NSError**)outError {
    return [self createManagedObjectContextWithModel: managedObjectModel databaseName: databaseName
                              importingDatabaseAtURL: nil importType: nil error: outError];
}


+ (NSManagedObjectContext*) createManagedObjectContextWithModel: (NSManagedObjectModel*)managedObjectModel
                                                   databaseName: (NSString*)databaseName
                                         importingDatabaseAtURL: (NSURL*)importUrl
                                                     importType: (NSString*)importType
                                                          error: (NSError**)outError {
    NSManagedObjectModel* model = [managedObjectModel mutableCopy];

    [self updateManagedObjectModel: model];

    NSPersistentStoreCoordinator* persistentStoreCoordinator =
    [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel: model];

    NSDictionary* options = @{
                              NSMigratePersistentStoresAutomaticallyOption : @YES,
                              NSInferMappingModelAutomaticallyOption : @YES
                              };

    NSURL* dbURL = [NSURL URLWithString: databaseName];
    NSError* error;
    CBLIncrementalStore* store = nil;

    if (importUrl) {
        NSPersistentStore* oldStore =
        [persistentStoreCoordinator addPersistentStoreWithType: importType
                                                 configuration: nil
                                                           URL: importUrl
                                                       options: options
                                                         error: &error];
        if (!oldStore) {
            if (outError)
                *outError = CBLISError(CBLIncrementalStoreErrorMigrationOfStoreFailed,
                                       @"Couldn't open store to import", error);
            return nil;
        }

        store = (CBLIncrementalStore*)
        [persistentStoreCoordinator migratePersistentStore: oldStore
                                                     toURL: dbURL
                                                   options: options
                                                  withType: [self type]
                                                     error: &error];

        if (!store) {
            if (outError) {
                NSString* errDesc = [NSString stringWithFormat:@"Migration of store at URL "
                                     "%@ failed: %@", importUrl, error.description];
                *outError = CBLISError(CBLIncrementalStoreErrorMigrationOfStoreFailed, errDesc, error);
            }
            return nil;
        }
    } else {
        store = (CBLIncrementalStore*)
        [persistentStoreCoordinator addPersistentStoreWithType: [self type]
                                                 configuration: nil
                                                           URL: dbURL
                                                       options: options
                                                         error: &error];

        if (!store) {
            if (outError) {
                NSString* errDesc = [NSString stringWithFormat: @"Initialization of store failed: %@",
                                     error.description];
                *outError = CBLISError(CBLIncrementalStoreErrorCreatingStoreFailed, errDesc, error);
            }
            return nil;
        }
    }

    NSManagedObjectContext* managedObjectContext =
    [[NSManagedObjectContext alloc] initWithConcurrencyType: NSMainQueueConcurrencyType];
    [managedObjectContext setPersistentStoreCoordinator: persistentStoreCoordinator];

    [store addObservingManagedObjectContext: managedObjectContext];

    return managedObjectContext;
}

/**
 *  This method has to be called once, before the NSManagedObjectModel is used by
 *  a NSPersistentStoreCoordinator. This method updates the entities in the
 *  managedObjectModel and adds some required properties.
 *
 *  @param managedObjectModel the managedObjectModel to use with this store
 */
+ (void) updateManagedObjectModel: (NSManagedObjectModel*)managedObjectModel {
    NSArray* entites = managedObjectModel.entities;
    for (NSEntityDescription* entity in entites) {
        if (entity.superentity) // only add to super-entities, not the sub-entities
            continue;

        NSMutableArray* properties = [entity.properties mutableCopy];
        for (NSPropertyDescription* prop in properties) {
            if ([prop.name isEqual: kCBLISRevisionAttributeName])
                return;
        }

        NSAttributeDescription* revAttribute = [NSAttributeDescription new];
        revAttribute.name = kCBLISRevisionAttributeName;
        revAttribute.attributeType = NSStringAttributeType;
        revAttribute.optional = YES;
        revAttribute.indexed = YES;

        [properties addObject: revAttribute];

        entity.properties = properties;
    }
}

#pragma mark - NSPersistentStore

+ (NSString*) type {
    return @"CBLIncrementalStore";
}

- (id) initWithPersistentStoreCoordinator: (NSPersistentStoreCoordinator*)root
                        configurationName: (NSString*)name
                                      URL: (NSURL*)url
                                  options: (NSDictionary*)options {
    self = [super initWithPersistentStoreCoordinator: root
                                   configurationName: name
                                                 URL: url
                                             options: options];
    if (!self) return nil;

    _fetchRequestResultCache = [[NSMutableDictionary alloc] init];
    _queryBuilderCache = [[NSCache alloc] init];
    _relationshipCache = [[NSCache alloc] init];
    _recentSavedObjectIDs = [[NSCache alloc] init];
    _respondFlags.storeWillSaveDocument = NO;

    self.conflictHandler = [self defaultConflictHandler];

    return self;
}

- (void)setDelegate:(id<CBLIncrementalStoreDelegate>)delegate {
    if (_delegate != delegate) {
        _delegate = delegate;
        _respondFlags.storeWillSaveDocument =
        [self.delegate respondsToSelector: @selector(storeWillSaveDocument:)];
    }
}

- (dispatch_queue_t)queue {
    dispatch_queue_t queue = self.manager.dispatchQueue;
    assert(queue);
    return queue;
}

-(BOOL) loadMetadata: (NSError**)outError {
    if (![self verifyManagedObjectModel: outError]) {
        return NO;
    }

    // Setup database:
    if (sCBLManager) {
        _manager = sCBLManager;
    } else {
        _manager = [[CBLManager alloc] init];
        _manager.dispatchQueue = dispatch_queue_create("CBLIncrementalStore", NULL);;
    }

    __block NSError* error;
    dispatch_sync(self.queue, ^{
        if ([self initDatabase: &error]) {
            [self initMetaData: &error];
            [self initRelationshipViews];
            [self initConflictsLiveQuery];
        }
    });

    if (error) {
        if (outError) {
            NSString* errorDesc = @"Load metada failed.";
            *outError = CBLISError(CBLIncrementalStoreLoadMetadataFailed, errorDesc, error);
        }
        return NO;
    }

    return YES;
}

- (BOOL) verifyManagedObjectModel: (NSError**)outError {
    // Check data model if compatible with this store:
    NSArray* entites = self.persistentStoreCoordinator.managedObjectModel.entities;
    for (NSEntityDescription* entity in entites) {
        // Check if the entity has been updated and includes the *rev* attribute:
        NSDictionary* attributes = [entity attributesByName];
        if (![attributes objectForKey: kCBLISRevisionAttributeName]) {
            if (outError) {
                NSString* errDesc = @"Database Model is not compatible. "
                "You need to call +[updateManagedObjectModel:].";
                *outError = CBLISError(CBLIncrementalStoreErrorDatabaseModelIncompatible,
                                       errDesc, nil);
            }
            return NO;
        }

        // Check if the entity contains to-many relationship without an inverse relation and warn:
        NSDictionary* relationship = [entity relationshipsByName];
        for (NSRelationshipDescription* rel in [relationship allValues]) {
            if (rel.isToMany) {
                if (!rel.inverseRelationship)
                    WARN(@"'%@' entity has a to-many relationship '%@' that has no inverse relationship "
                         "defined. The inverse relationship is requried by the CBLIncrementalStore for "
                         "fetching to-many relationship entities.", entity.name, rel.name);
#if !TARGET_OS_IPHONE
#if (__MAC_OS_X_VERSION_MIN_REQUIRED >= 1070)
                if (rel.isOrdered)
                    WARN(@"'%@' entity has an ordered to-many relationship '%@', which is not supported "
                         "by the CBLIncrementalStore.", entity.name, rel.name);
#endif
#endif
            }
        }
    }
    return YES;
}

- (BOOL) initDatabase: (NSError**)outError {
    NSString* databaseName = [self.URL lastPathComponent];
    _database = [self.manager databaseNamed: databaseName error: outError];
    if (_database) {
        // Setup database change notification:
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(databaseChanged:)
                                                     name: kCBLDatabaseChangeNotification
                                                   object: _database];
        return YES;
    }
    return NO;
}

- (BOOL) initMetaData: (NSError**)outError {
    NSDictionary *metadata = [self metadataDocument: outError];
    if (metadata) {
        [self setMetadata: @{NSStoreUUIDKey: metadata[NSStoreUUIDKey],
                             NSStoreTypeKey: metadata[NSStoreTypeKey]}];
        return YES;
    }
    return NO;
}

- (NSDictionary*) metadataDocument: (NSError **)outError {
    NSDictionary* metaData = [self.database existingLocalDocumentWithID: kCBLISMetadataDocumentID];
    if (metaData)
        return metaData;

    NSMutableDictionary *properties = [NSMutableDictionary dictionary];

    CBLDocument* doc = [self.database existingDocumentWithID: kCBLISMetadataDocumentID];
    if (doc) {
        // Migration (from v1.0.4 to v1.1.0):
        // 1. Store metadata in a local document instead of a normal document.
        // 2. Document type key was changed from 'CBLIS_type' to just 'type'. However
        // for backward compatibility, the existing apps that already use CBLIS_type key will
        // continue to use CBLIS_type. Store 'CBLIS_Type as a value of kCBLISMetadata_DefaultTypeKey
        // in the metadata properties so that it can be referenced by the method -documentTypeKey.
        [properties addEntriesFromDictionary: doc.userProperties];
        properties[kCBLISMetadata_DefaultTypeKey] = kCBLISOldDefaultTypeKey;

        [doc deleteDocument: nil];
    }

    if (![properties objectForKey: NSStoreUUIDKey]) {
        properties[NSStoreUUIDKey] = [[NSProcessInfo processInfo] globallyUniqueString];
        properties[NSStoreTypeKey] = [[self class] type];
    }

    if (![self.database putLocalDocument: properties
                                  withID: kCBLISMetadataDocumentID
                                   error: outError]) {
        return nil;
    }

    return properties;
}

/** Initializes the views needed for querying objects by type for to-many relationships. */
- (void) initRelationshipViews {
    // Create a view for each to-many relationship
    NSArray* entites = self.persistentStoreCoordinator.managedObjectModel.entities;
    for (NSEntityDescription* entity in entites) {
        NSArray* properties = [entity properties];
        for (NSPropertyDescription* property in properties) {
            if ([property isKindOfClass:[NSRelationshipDescription class]]) {
                NSRelationshipDescription* rel = (NSRelationshipDescription*)property;
                if (rel.isToMany && rel.inverseRelationship) {
                    if (rel.inverseRelationship.toMany) // skip many-to-many
                        continue;

                    NSMutableArray* entityNames =
                    [NSMutableArray arrayWithObject: rel.destinationEntity.name];
                    for (NSEntityDescription* subentity in rel.destinationEntity.subentities) {
                        [entityNames addObject: subentity.name];
                    }

                    NSString* viewName = CBLISToManyViewNameForRelationship(rel);
                    NSRelationshipDescription* invRel = rel.inverseRelationship;
                    NSString* inverseRelPropName = invRel.name;
                    CBLView* view = [self.database viewNamed: viewName];
                    [view setMapBlock:^(NSDictionary* doc, CBLMapEmitBlock emit) {
                        NSString* type = [doc objectForKey: [self documentTypeKey]];
                        if (type && [entityNames containsObject: type] &&
                            [doc objectForKey: inverseRelPropName]) {
                            emit([doc objectForKey: inverseRelPropName], nil);
                        }
                    } version: @"1.0"];
                }
            }
        }
    }
}

- (void) initConflictsLiveQuery {
    _conflictsQuery = [self.database createAllDocumentsQuery].asLiveQuery;
    _conflictsQuery.allDocsMode = kCBLOnlyConflicts;
    [_conflictsQuery addObserver: self
                      forKeyPath: @"rows"
                         options: NSKeyValueObservingOptionNew context: nil];
    [_conflictsQuery start];
}

#pragma mark - Document Type Key

- (NSString*) documentTypeKey {
    if (_documentTypeKey)
        return _documentTypeKey;

    NSError* error;
    NSDictionary* metadata = [self metadataDocument: &error];
    if (!metadata) {
        // This shouldn't happen unless the metadata local doc was unexpectedly deleted.
        ERROR(@"Cannot get the metadata document while determining the document type key. "
              "The default 'type' key will be used. (Error: %@)", error);
    }

    if (metadata[kCBLISMetadata_DefaultTypeKey])
        _documentTypeKey = metadata[kCBLISMetadata_DefaultTypeKey];
    else
        _documentTypeKey = kCBLISDefaultTypeKey;

    return _documentTypeKey;
}

#pragma mark - Custom properties

- (void)setCustomProperties: (NSDictionary*)customProperties {
    _customProperties = customProperties;
    dispatch_sync(self.queue, ^{
        [self invalidateFetchResultCache];
    });
}

- (NSUInteger) maxRelationshipLoadDepth {
    id maxDepth = _customProperties[kCBLISCustomPropertyMaxRelationshipLoadDepth];
    NSUInteger maxDepthValue = [maxDepth unsignedIntegerValue];
    return maxDepthValue > 0 ? maxDepthValue : kDefaultMaxRelationshipLoadDepth;
}

- (BOOL) queryBooleanValueWithNumber {
    id queryBoolNum = _customProperties[kCBLISCustomPropertyQueryBooleanWithNumber];
    return [queryBoolNum boolValue]; // Default value is NO
}

#pragma mark - coredata values and relationship resolution

- (NSIncrementalStoreNode*) newValuesForObjectWithID: (NSManagedObjectID*)objectID
                                         withContext: (NSManagedObjectContext*)context
                                               error: (NSError**)outError {
    INFO(@"newValuesForObjectWithID in %@ on %@", context, [NSThread currentThread]);
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();

    __block NSDictionary* values;
    dispatch_sync(self.queue, ^{
        CBLDocument* doc = [self documentForObjectID: objectID];
        __block NSEntityDescription* entity = objectID.entity;
        NSString* docTypeKey = [self documentTypeKey];
        if (![entity.name isEqual: [doc propertyForKey: docTypeKey]]) {
            [context performBlockAndWait: ^{
                entity = [NSEntityDescription entityForName: [doc propertyForKey: docTypeKey]
                                     inManagedObjectContext: context];
            }];
        }
        values = [self coreDataPropsOfDocument: doc withEntity: entity];
    });

    assert(values);
    NSIncrementalStoreNode* node = [[NSIncrementalStoreNode alloc] initWithObjectID: objectID
                                                                         withValues: values
                                                                            version: 1];
    CFAbsoluteTime end = CFAbsoluteTimeGetCurrent();
    INFO(@"newValuesForObjectWithID finished in %f seconds", (end - start));
    return node;
}

- (id) newValueForRelationship: (NSRelationshipDescription*)relationship
               forObjectWithID: (NSManagedObjectID*)objectID
                   withContext: (NSManagedObjectContext*)context
                         error: (NSError**)outError {
    INFO(@"newValueForRelationship for %@ in %@ on %@",
         objectID.URIRepresentation.lastPathComponent, context, [NSThread currentThread]);
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();

    __block id newValue;
    dispatch_sync(self.queue, ^{
        if ([relationship isToMany]) {
            if (relationship.inverseRelationship.toMany) {
                // many-to-many
                CBLDocument* doc = [self documentForObjectID: objectID];
                NSArray* destinationIDs = [doc.properties valueForKey: relationship.name];
                NSMutableArray* result = [NSMutableArray arrayWithCapacity: destinationIDs.count];
                for (NSString* destinationID in destinationIDs) {
                    [result addObject:[self newObjectIDForEntity: relationship.destinationEntity
                                                 referenceObject: destinationID]];
                }
                newValue = result;
            } else {
                // one-to-many
                id result = nil;
                NSArray* rows = [self queryToManyRelation: relationship
                                             forParentKey: [objectID documentIDRepresentation]
                                                 prefetch: NO
                                                 outError: outError];
                if (rows) {
                    result = [NSMutableArray arrayWithCapacity: rows.count];
                    for (CBLQueryRow* row in rows) {
                        [result addObject: [self newObjectIDForEntity: relationship.destinationEntity
                                                      referenceObject: row.documentID]];
                    }
                }
                newValue = result;
            }
        } else {
            CBLDocument* doc = [self documentForObjectID: objectID];
            NSString* destinationID = [doc propertyForKey: relationship.name];
            if (destinationID)
                newValue = [self newObjectIDForEntity: relationship.destinationEntity
                                      referenceObject: destinationID];
            else
                newValue = [NSNull null];
        }
    });

    CFAbsoluteTime end = CFAbsoluteTimeGetCurrent();
    INFO(@"newValueForRelationship for %@ finished in %f seconds",
         objectID.URIRepresentation.lastPathComponent, (end - start));
    return newValue;
}

- (CBLDocument*) documentForObjectID: (NSManagedObjectID*)objectID {
    return [self.database documentWithID: [objectID documentIDRepresentation]];
}

#pragma mark - execute request

- (id) executeRequest: (NSPersistentStoreRequest*)request
          withContext: (NSManagedObjectContext*)context
                error: (NSError**)outError {
    INFO(@"Execute request with %@ on %@", context, [NSThread currentThread]);
    id result;
    if (request.requestType == NSSaveRequestType) {
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        NSSaveChangesRequest* saveRequest = (NSSaveChangesRequest*)request;
        result = [self executeSaveRequest: saveRequest withContext: context outError: outError];
        CFAbsoluteTime end = CFAbsoluteTimeGetCurrent();
        INFO(@"Execute request for save, inserted %lu, updated %lu, deleted %lu, locked %lu "
             "finished in %f seconds",
             (unsigned long)saveRequest.insertedObjects.count,
             (unsigned long)saveRequest.updatedObjects.count,
             (unsigned long)saveRequest.deletedObjects.count,
             (unsigned long)saveRequest.lockedObjects.count,
             (end - start));
    } else if (request.requestType == NSFetchRequestType) {
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        NSFetchRequest* fetchRequest = (NSFetchRequest*)request;
        result = [self executeFetchWithRequest: fetchRequest withContext: context outError: outError];
        CFAbsoluteTime end = CFAbsoluteTimeGetCurrent();
        INFO(@"Execute request for fetch, entity %@, type %@, predicate %@ finished in %f seconds",
             fetchRequest.entity.name, CBLISResultTypeName(fetchRequest.resultType),
             fetchRequest.predicate, (end - start));
    } else {
        WARN(@"Execute request : Unsupported request type : %lu",
             (unsigned long)request.requestType);
        if (outError) {
            NSString* errDesc = [NSString stringWithFormat:@"Unsupported requestType: %d",
                                 (int)request.requestType];
            *outError = CBLISError(CBLIncrementalStoreErrorUnsupportedRequestType, errDesc, nil);
        }
        result = nil;
    }
    return result;
}

- (id) executeSaveRequest: (NSSaveChangesRequest*)request
              withContext: (NSManagedObjectContext*)context
                 outError: (NSError**)outError {
    __block BOOL success = false;
    __block BOOL hasNewOrUpdate = false;

    NSMutableArray* insertedOrUpdatedObjects = [NSMutableArray array];
    for (NSManagedObject* object in request.insertedObjects) {
        NSDictionary* properties = [self propertiesForManagedObject: object];
        [insertedOrUpdatedObjects addObject: @[object, properties]];
    }
    for (NSManagedObject* object in request.updatedObjects) {
        NSDictionary* properties = [self propertiesForManagedObject: object];
        [insertedOrUpdatedObjects addObject: @[object, properties]];
    }

    NSMutableArray* objRevs = [NSMutableArray array];
    dispatch_sync(self.queue, ^{
        success = [self.database inTransaction: ^BOOL{
            // Insert:
            for (NSArray* objProps in insertedOrUpdatedObjects) {
                NSManagedObject* object = objProps[0];
                CBLSavedRevision* rev =
                [self insertOrUpdateObject: object withProperties: objProps[1]
                               withContext:context outError:outError];
                if (rev) {
                    hasNewOrUpdate = YES;
                    [objRevs addObject: @[object, rev]];
                    [_recentSavedObjectIDs setObject: object.objectID
                                              forKey: object.objectID.documentIDRepresentation];
                } else
                    return NO;
            }

            // Delete:
            for (NSManagedObject* object in [request deletedObjects]) {
                if ([self deleteObject:object withContext:context outError:outError]) {
                    [objRevs addObject:@[object]];
                    [_recentSavedObjectIDs setObject: object.objectID
                                              forKey: object.objectID.documentIDRepresentation];
                } else
                    return NO;
            }
            return YES;
        }];

        if (success) {
            for (NSArray* objRev in objRevs) {
                NSManagedObject* object = objRev[0];
                [self purgeCachedObjectsForEntityName: object.entity.name];
            }
        }
    });

    if (success && hasNewOrUpdate) {
        for (NSArray* objRev in objRevs) {
            if (objRev.count > 1) {
                NSManagedObject* object = objRev[0];
                CBLSavedRevision* rev = objRev[1];
                [self refreshManagedObject: object withRevId: rev.revisionID onContext: context];
            }
        }
    }

    return @[];
}

- (CBLSavedRevision*) insertOrUpdateObject: (NSManagedObject*)object
                            withProperties: (NSDictionary*)properties
                               withContext: (NSManagedObjectContext*)context
                                  outError: (NSError**)outError {
    CBLDocument* doc = [self documentForObjectID: object.objectID];
    CBLUnsavedRevision* revision = [doc newRevision];
    revision.userProperties = properties;

    // Add attachments:
    NSDictionary* propertyDesc = [object.entity propertiesByName];
    for (NSString* property in propertyDesc) {
        if ([kCBLISRevisionAttributeName isEqual: property]) continue;

        NSAttributeDescription* attr = [propertyDesc objectForKey: property];
        if (![attr isKindOfClass: [NSAttributeDescription class]]) continue;

        if ([attr isTransient]) continue;
        if ([attr attributeType] != NSBinaryDataAttributeType) continue;

        if ([[object changedValues] objectForKey: attr.name]) {
            NSData* data = [object valueForKey: attr.name];
            if (data)
                [revision setAttachmentNamed: attr.name
                             withContentType: @"application/binary"
                                     content: data];
            else if ([doc.currentRevision attachmentNamed: attr.name])
                [revision removeAttachmentNamed: attr.name];
        }
    }

    if (_respondFlags.storeWillSaveDocument) {
        NSDictionary* newProperties = [_delegate storeWillSaveDocument: revision.properties];
        if (newProperties != revision.properties)
            revision.properties = [newProperties mutableCopy];
    }
    return [revision save: outError];
}

- (BOOL) deleteObject: (NSManagedObject*)object
          withContext: (NSManagedObjectContext*)context
             outError: (NSError**)outError {
    CBLDocument* doc = [self.database existingDocumentWithID:object.objectID.documentIDRepresentation];
    if (!doc || doc.isDeleted)
        return YES;

    NSDictionary* properties = [self propertiesForDeletingDocument: doc];
    if (_respondFlags.storeWillSaveDocument) {
        NSDictionary* newProperties = [_delegate storeWillSaveDocument: properties];
        if (newProperties != properties)
            properties = newProperties;
    }
    return [doc putProperties: properties error: outError] != nil;
}

- (void) refreshManagedObject: (NSManagedObject*)object
                    withRevId: (NSString*)revId
                    onContext: (NSManagedObjectContext*)context {
    [object willChangeValueForKey: kCBLISRevisionAttributeName];
    [object setPrimitiveValue:revId forKey: kCBLISRevisionAttributeName];
    [object didChangeValueForKey: kCBLISRevisionAttributeName];

    [object willChangeValueForKey: @"objectID"];
    [context obtainPermanentIDsForObjects: @[object] error: nil];
    [object didChangeValueForKey: @"objectID"];

    [context refreshObject: object mergeChanges: YES];
}

- (NSArray*) obtainPermanentIDsForObjects: (NSArray*)array error: (NSError**)outError {
    NSMutableArray* result = [NSMutableArray arrayWithCapacity: array.count];
    for (NSManagedObject* object in array) {
        if (![object.objectID isTemporaryID]) {
            [result addObject: object.objectID];
        } else {
            NSString* uuid = [[NSProcessInfo processInfo] globallyUniqueString];
            NSManagedObjectID* objectID = [self newObjectIDForEntity: object.entity
                                                     referenceObject: uuid];
            [result addObject: objectID];
        }
    }
    return result;
}

- (NSManagedObjectID*) newObjectIDForEntity: (NSEntityDescription*)entity referenceObject: (id)obj {
    NSString* refObj = obj;
    if ([refObj hasPrefix: @"p"]) {
        refObj = [refObj substringFromIndex: 1];
    }

    // we need to prefix the refernceObject with a non-numeric prefix, because of a bug where
    // referenceObjects starting with a digit will only use the first digit part. As described here:
    // https://github.com/AFNetworking/AFIncrementalStore/issues/82
    refObj = [kCBLISManagedObjectIDPrefix stringByAppendingString: refObj];
    return [super newObjectIDForEntity: entity referenceObject: refObj];
}

#pragma mark - Query

- (NSArray*) executeFetchWithRequest: (NSFetchRequest*)request
                         withContext: (NSManagedObjectContext*)context
                            outError: (NSError**)outError {
    if (![self validateFetchRequest: request error: outError])
        return nil;

    __block NSArray* cachedObjects = nil;
    dispatch_sync(self.queue, ^{
        cachedObjects = [self cachedObjectsForFetchRequest: request];
    });

    if (cachedObjects) {
        NSArray* result = [self fetchResult: cachedObjects
                              forResultType: request.resultType
                      withPropertiesToFetch: request.propertiesToFetch
                                   outError: outError];
        return result;
    }

    NSArray* objects;
    BOOL useQueryBuilder = NO;
    if (![self containsRelationshipKeyPathsInSortDescriptors: request.sortDescriptors]) {
        NSPredicate* predicate = nil;
        NSMutableDictionary* templateVars = [NSMutableDictionary dictionary];
        if (request.predicate) {
            NSError* scanError;
            BOOL hasNonQueryBuilderExp;
            predicate = [self scanPredicate: request.predicate
                                 withEntity: request.entity
                            outTemplateVars: templateVars
                   outHasNonQueryBuilderExp: &hasNonQueryBuilderExp
                                   outError: &scanError];
            if (predicate) {
                useQueryBuilder = !hasNonQueryBuilderExp;
            } else {
                if (outError) *outError = scanError;
                return nil;
            }
        }

        if (useQueryBuilder) {
            objects = [self fetchByUsingQueryBuilderWithPredicate: predicate
                                              withOriginalRequest: request
                                                 withTemplateVars: templateVars
                                                      withContext: context
                                                         outError: nil];
            if (!objects) {
                useQueryBuilder = NO;
            }
        }
    }

    if (!useQueryBuilder) {
        objects = [self fetchByEntityAndDoPostFilterWithRequest: request
                                                    withContext: context
                                                       outError: outError];
    }

    if (!objects)
        return nil;

    dispatch_sync(self.queue, ^{
        [self cacheObjects: objects forFetchRequest: request];
    });

    NSArray* result = [self fetchResult: objects
                          forResultType: request.resultType
                  withPropertiesToFetch: request.propertiesToFetch
                               outError: outError];
    return result;
}

- (BOOL) validateFetchRequest: (NSFetchRequest*)request error: (NSError**)outError {
    NSError* error = nil;
    if ([request.propertiesToGroupBy count] > 0) {
        error = CBLISError(CBLIncrementalStoreErrorUnsupportedFetchRequest,
                           @"GroupBy request not implemented", nil);
    }
    if (outError)
        *outError = error;
    return !error;
}

- (NSArray*) fetchResult: (NSArray*)objects
           forResultType: (NSFetchRequestResultType)type
   withPropertiesToFetch: (NSArray*)propertiesToFetch
                outError: (NSError**)outError {
    if ([objects count] == 0) return objects;

    if (type == NSManagedObjectResultType)
        return objects;
    else if (type == NSCountResultType)
        return  @[@([objects count])];
    else if (type == NSManagedObjectIDResultType) {
        NSMutableArray* result = [NSMutableArray arrayWithCapacity: [objects count]];
        for (NSManagedObject* object in objects) {
            [result addObject: object.objectID];
        }
        return result;
    } else if (type == NSDictionaryResultType) {
        NSMutableArray* result = [NSMutableArray arrayWithCapacity: [objects count]];
        for (NSManagedObject* object in objects) {
            NSDictionary* properties = [self propertiesForManagedObject: object];
            if (propertiesToFetch) {
                NSMutableArray *propNameToFetch =
                [NSMutableArray arrayWithCapacity:propertiesToFetch.count];
                for (id prop in propertiesToFetch) {
                    if ([prop isKindOfClass:[NSPropertyDescription class]])
                        [propNameToFetch addObject:((NSPropertyDescription*)prop).name];
                    else
                        [propNameToFetch addObject:prop];
                }
                [result addObject: [properties dictionaryWithValuesForKeys: propNameToFetch]];
            } else {
                [result addObject: properties];
            }
        }
        return result;
    } else {
        if (outError) {
            NSString* errDesc = [NSString stringWithFormat:
                                 @"Unsupported fetch request result type: %d", (int)type];
            *outError = CBLISError(CBLIncrementalStoreErrorUnsupportedFetchRequestResultType,
                                   errDesc, nil);
        }
        return nil;
    }
}

#pragma mark - Query (QueryBuilder)

- (NSArray*) fetchByUsingQueryBuilderWithPredicate: (NSPredicate*)predicate
                               withOriginalRequest: (NSFetchRequest*)request
                                  withTemplateVars: (NSDictionary*)templateVars
                                       withContext: (NSManagedObjectContext*)context
                                          outError: (NSError**)outError {
    __block CBLQueryEnumerator* rows = nil;
    dispatch_sync(self.queue, ^{
        NSPredicate* typePredicate = [self documentTypePredicateForFetchRequest: request];

        NSPredicate* compoundPredicate = [NSCompoundPredicate
                                          andPredicateWithSubpredicates: @[typePredicate, predicate]];

        CBLQueryBuilder* builder = [self cachedQueryBuilderForPredicate: compoundPredicate
                                                        sortDescriptors: request.sortDescriptors];
        if (!builder) {
            builder = [[CBLQueryBuilder alloc] initWithDatabase: self.database
                                                         select: nil
                                                 wherePredicate: compoundPredicate
                                                        orderBy: request.sortDescriptors
                                                          error: outError];

            if (!builder)
                return;

            [self cacheQueryBuilder: builder
                       forPredicate: compoundPredicate
                    sortDescriptors: request.sortDescriptors];
        }

        CBLQuery* query = [builder createQueryWithContext: templateVars];

        // This may result to fewer rows than expected.
        // https://github.com/couchbase/couchbase-lite-ios/issues/574
        if (request.fetchLimit > 0) {
            query.limit = request.fetchLimit;
        }

        if (request.fetchOffset > 0) {
            query.skip = request.fetchOffset;
        }

        rows = [query run: outError];
    });

    if (!rows)
        return nil;

    NSMutableArray* result = [NSMutableArray arrayWithCapacity: rows.count];
    for (CBLQueryRow* row in rows) {
        NSManagedObjectID* objectID = [self newObjectIDForEntity: request.entity
                                                 referenceObject: row.documentID];
        [result addObject: [context objectWithID: objectID]];
    }
    return result;
}

- (NSPredicate*) documentTypePredicateForFetchRequest:(NSFetchRequest *)request {
    if (request.includesSubentities && request.entity.subentities.count > 0) {
        NSMutableArray *types = [NSMutableArray arrayWithObject:request.entity.name];
        [types addObjectsFromArray:[self getSubentityNamesOfEntity:request.entity]];
        return [NSPredicate predicateWithFormat:@"%K in %@", [self documentTypeKey], types];
    } else
        return [NSPredicate predicateWithFormat:@"%K == %@", [self documentTypeKey],
                request.entityName];
}

- (NSArray*) getSubentityNamesOfEntity:(NSEntityDescription *)entity {
    NSMutableArray* subentities = [NSMutableArray array];
    for (NSEntityDescription* subentity in entity.subentities) {
        [subentities addObject:subentity.name];
        [subentities addObject:[self getSubentityNamesOfEntity:subentity]];
    }
    return subentities;
}

- (CBLQueryBuilder*) cachedQueryBuilderForPredicate: (NSPredicate*)predicate
                                    sortDescriptors: (NSArray*)sortDescriptors {
    NSString* key = [self cacheKeyForQueryBuilderWithPredicate: predicate
                                               sortDescriptors: sortDescriptors];
    return [_queryBuilderCache objectForKey: key];
}

- (void) cacheQueryBuilder: (CBLQueryBuilder*)builder
              forPredicate: (NSPredicate*)predicate
           sortDescriptors: (NSArray*)sortDescriptors {
    if (!builder) return;

    NSString* key = [self cacheKeyForQueryBuilderWithPredicate: predicate
                                               sortDescriptors: sortDescriptors];

    [_queryBuilderCache setObject: builder forKey: key];
}

- (NSString*) cacheKeyForQueryBuilderWithPredicate: (NSPredicate*)predicate
                                   sortDescriptors: (NSArray*)sortDescriptors {
    NSMutableDictionary* keys = [NSMutableDictionary dictionary];
    if (predicate)
        keys[@"predicate"] = [predicate predicateFormat];

    if (sortDescriptors) {
        NSMutableString* sortDesc = [NSMutableString string];
        for (NSSortDescriptor* sort in sortDescriptors) {
            [sortDesc appendFormat: @"%@", sort];
        }
        keys[@"sortDescriptors"] = sortDesc;
    }

    return [self digestCacheKey: keys];
}

- (BOOL) containsRelationshipKeyPathsInSortDescriptors: (NSArray*)sortDescriptors {
    for (NSSortDescriptor *sd in sortDescriptors) {
        if (NSNotFound != [sd.key rangeOfString:@"."].location)
            return YES;
    }
    return NO;
}

/*
 *   Scan thru the predicate and its subpredicates, validate keypaths,
 *   detect non query builder expressions, replace constant values with
 *   template variables, and generate a template variable dictionary.
 */
- (NSPredicate*) scanPredicate: (NSPredicate*)predicate
                    withEntity: (NSEntityDescription*)entity
               outTemplateVars: (NSMutableDictionary*)outTemplateVars
      outHasNonQueryBuilderExp: (BOOL*)outHasNonQueryBuilderExp
                      outError: (NSError**)outError {
    NSPredicate* output = nil;
    BOOL hasNonQueryBuilderExp = NO;

    if ([predicate isKindOfClass: [NSCompoundPredicate class]]) {
        NSCompoundPredicate* compound = (NSCompoundPredicate*)predicate;
        NSMutableArray* subpredicates = [NSMutableArray arrayWithCapacity:
                                         [compound.subpredicates count]];
        BOOL hasError = NO;
        for (NSPredicate* subpredicate in compound.subpredicates) {
            BOOL hasNonQueryBuilderInSubExp;
            NSPredicate* scanned = [self scanPredicate: subpredicate
                                            withEntity: entity
                                       outTemplateVars: outTemplateVars
                              outHasNonQueryBuilderExp: &hasNonQueryBuilderInSubExp
                                              outError: outError];
            hasNonQueryBuilderExp = hasNonQueryBuilderExp || hasNonQueryBuilderInSubExp;
            if (scanned) {
                [subpredicates addObject: scanned];
            } else {
                hasError = YES;
                break;
            }
        }

        if (!hasError) {
            output = [[NSCompoundPredicate alloc] initWithType: compound.compoundPredicateType
                                                 subpredicates: subpredicates];
        }
    } else if ([predicate isKindOfClass: [NSComparisonPredicate class]]) {
        NSComparisonPredicate* comparison = (NSComparisonPredicate*)predicate;
        NSExpression* lhs = comparison.leftExpression;
        NSExpression* rhs = comparison.rightExpression;

        // Scan the expression with a keypath first to get the current keypath of the expression.
        // We are using the keypath to generate a corresponding template variable name.
        NSArray* expressions = rhs.expressionType == NSKeyPathExpressionType ?
        @[rhs, lhs] : @[lhs, rhs];
        BOOL hasError = NO;
        NSString* keyPath = nil;

        BOOL shouldCreateCompundBoolPredicate = NO;
        for (NSExpression* expression in expressions) {
            if (expression.expressionType == NSKeyPathExpressionType) {
                BOOL needJoins;
                keyPath = [self scanKeyPathExpression: expression
                                           withEntity: entity
                                    outNeedJoinsQuery: &needJoins
                                             outError: outError];
                if (!keyPath) {
                    hasError = YES;
                    break;
                }

                if (needJoins) {
                    hasNonQueryBuilderExp = YES;
                }
            } else if (expression.expressionType == NSConstantValueExpressionType ||
                       expression.expressionType == NSAggregateExpressionType) {
                if (!keyPath) {
                    // Ignore the predicate without a keypath:
                    break;
                }

                NSExpression* newExpression = nil;
                id constantValue = expression.constantValue;

                if ([constantValue isKindOfClass:[NSArray class]]) {
                    if (comparison.predicateOperatorType == NSBetweenPredicateOperatorType) {
                        NSString* lowerVar = [self variableForKeyPath: keyPath
                                                               suffix: @"_LOWER"
                                                              current: outTemplateVars];
                        NSString* uppperVar = [self variableForKeyPath: keyPath
                                                                suffix: @"_UPPER"
                                                               current: outTemplateVars];
                        NSMutableArray* aggrs = [NSMutableArray array];
                        [aggrs addObject:[NSExpression expressionForVariable: lowerVar]];
                        [aggrs addObject:[NSExpression expressionForVariable: uppperVar]];
                        newExpression = [NSExpression expressionForAggregate: aggrs];

                        id lowerValue = [self scanConstantValue: constantValue[0]];
                        NSAssert(lowerValue, @"Unexpected nil value in the predicate : %@", predicate);
                        [outTemplateVars setObject: lowerValue forKey: lowerVar];

                        id upperValue = [self scanConstantValue: constantValue[1]];
                        NSAssert(upperValue, @"Unexpected nil value in the predicate : %@", predicate);
                        [outTemplateVars setObject: upperValue forKey: uppperVar];
                    } else {
                        NSMutableArray* values = [NSMutableArray array];
                        for (id value in constantValue) {
                            id exValue = [self scanConstantValue: value];
                            NSAssert(exValue, @"Unexpected nil value in the predicate : %@", predicate);
                            [values addObject: exValue];
                        }

                        NSString* varName = [self variableForKeyPath: keyPath
                                                              suffix: @"S"
                                                             current: outTemplateVars];
                        newExpression = [NSExpression expressionForVariable: varName];
                        [outTemplateVars setObject: values forKey: varName];
                    }
                } else {
                    id expValue = [self scanConstantValue: constantValue];
                    if (expValue) {
                        id exValue = [self scanConstantValue: constantValue];
                        if ([self isBooleanConstantValue: exValue] && [self queryBooleanValueWithNumber]) {
                            // Workaround for #756:
                            // Need to be able to query both JSON boolean value (true,false) and
                            // number boolean value(1,0).
                            // 1. Not templating the original boolean value expression.
                            // 2. Create an OR-compound predicate of the boolean expression and
                            //    the improvised boolean number expression
                            shouldCreateCompundBoolPredicate = YES;
                        } else {
                            NSString* varName = [self variableForKeyPath: keyPath
                                                                  suffix: nil
                                                                 current: outTemplateVars];
                            newExpression = [NSExpression expressionForVariable: varName];
                            [outTemplateVars setObject: expValue forKey: varName];
                        }
                    } else
                        break; // Not templating nil predicate:

                    if (comparison.predicateOperatorType == NSContainsPredicateOperatorType) {
                        // CBLQueryBuilder doesn't support CONTAINS operation with a non array exp.
                        hasNonQueryBuilderExp = YES;
                    }
                }

                if (newExpression) {
                    if (expression == comparison.leftExpression)
                        lhs = newExpression;
                    else
                        rhs = newExpression;
                }
            }
        }

        if (!hasError) {
            if  (lhs != comparison.leftExpression || rhs != comparison.rightExpression)
                output = [NSComparisonPredicate predicateWithLeftExpression: lhs
                                                            rightExpression: rhs
                                                                   modifier: comparison.comparisonPredicateModifier
                                                                       type: comparison.predicateOperatorType
                                                                    options: comparison.options];
            else
                output = comparison;

            if (shouldCreateCompundBoolPredicate)
                output = [self createCompoundBooleanPredicate: output];
        }
    }

    if (outHasNonQueryBuilderExp)
        *outHasNonQueryBuilderExp = hasNonQueryBuilderExp;

    if (!output && (outError && *outError == nil)) {
        NSString* errDesc = [NSString stringWithFormat:@"Unsupported predicate : %@", predicate];
        *outError = CBLISError(CBLIncrementalStoreErrorUnsupportedPredicate, errDesc, nil);
        return nil;
    }

    return output;
}


- (BOOL) isBooleanConstantValue: (id)value {
    return (value == (id)@(YES) || value == (id)@(NO));
}

- (NSCompoundPredicate*) createCompoundBooleanPredicate: (NSPredicate*)predicate {
    assert([predicate isKindOfClass:[NSComparisonPredicate class]]);

    NSComparisonPredicate* boolPredicate = (NSComparisonPredicate*)predicate;
    BOOL boolValue = boolPredicate.rightExpression.expressionType == NSConstantValueExpressionType ?
    [boolPredicate.rightExpression.constantValue boolValue] :
    [boolPredicate.leftExpression.constantValue boolValue];

    NSExpression* lhs;
    NSExpression* rhs;
    NSNumber* boolNumberValue;
    if (boolPredicate.predicateOperatorType == NSNotEqualToPredicateOperatorType) {
        // If the operator type is not equal, invert it to equal:
        NSExpression* newBoolExp = [NSExpression expressionForConstantValue:
                                    (boolValue ? @(NO) : @(YES))];
        lhs = boolPredicate.leftExpression.expressionType == NSKeyPathExpressionType ?
        boolPredicate.leftExpression : newBoolExp;
        rhs = boolPredicate.rightExpression.expressionType == NSKeyPathExpressionType ?
        boolPredicate.rightExpression : newBoolExp;
        boolPredicate =
        [NSComparisonPredicate predicateWithLeftExpression: lhs
                                           rightExpression: rhs
                                                  modifier: boolPredicate.comparisonPredicateModifier
                                                      type: NSEqualToPredicateOperatorType
                                                   options: boolPredicate.options];
        boolNumberValue = (boolValue ? @(0) : @(1));
    } else
        boolNumberValue = (boolValue ? @(1) : @(0));

    NSExpression* boolNumberExp = [NSExpression expressionForConstantValue: boolNumberValue];
    lhs = boolPredicate.leftExpression.expressionType == NSKeyPathExpressionType ?
    boolPredicate.leftExpression : boolNumberExp;
    rhs = boolPredicate.rightExpression.expressionType == NSKeyPathExpressionType ?
    boolPredicate.rightExpression : boolNumberExp;

    NSPredicate* boolNumberPredicate =
    [NSComparisonPredicate predicateWithLeftExpression: lhs
                                       rightExpression: rhs
                                              modifier: boolPredicate.comparisonPredicateModifier
                                                  type: boolPredicate.predicateOperatorType
                                               options: boolPredicate.options];
    return [NSCompoundPredicate orPredicateWithSubpredicates: @[boolPredicate, boolNumberPredicate]];
}


/*
 *   Scan an expression, detect if the expression is a joins query, and validate if
 *   the keypath is valid.
 */
- (NSString*) scanKeyPathExpression: (NSExpression*)expression
                         withEntity: (NSEntityDescription*)entity
                  outNeedJoinsQuery: (BOOL*)outNeedJoinsQuery
                           outError: (NSError**)outError {
    NSString* keyPath = expression.keyPath;

    BOOL needJoin = NO;
    if ([keyPath rangeOfString:@"."].location != NSNotFound) {
        needJoin = YES;
    } else {
        NSDictionary* properties = [entity propertiesByName];
        id propertyDesc = [properties objectForKey: keyPath];
        if (!propertyDesc) {
            keyPath = nil;
            if (outError) {
                NSString* errDesc = [NSString stringWithFormat: @"Predicate Keypath '%@' "
                                     "not found in the entity '%@'.", expression.keyPath, entity.name];
                *outError = CBLISError(CBLIncrementalStoreErrorPredicateKeyPathNotFoundInEntity,
                                       errDesc, nil);
            }
        }
    }

    if (outNeedJoinsQuery)
        *outNeedJoinsQuery = needJoin;

    return keyPath;
}

/*
 *   Generate a template variable name based on a given keyp aht and suffix.
 *   The given crrent dictionary contains a current template variable dict
 *   used for detecting variable name collision.
 */
- (NSString*) variableForKeyPath: (NSString*)keypath
                          suffix: (NSString*)suffix
                         current: (NSDictionary*)current {
    if (!keypath) return nil;

    NSUInteger idx = 0u;
    NSString* base = [NSString stringWithFormat: @"%@%@",
                      keypath.uppercaseString,
                      (suffix ? suffix.uppercaseString : @"")];

    NSString* variable = [NSString stringWithFormat: @"%@%lu", base, (unsigned long)idx];
    while ([current objectForKey: variable]) {
        variable = [NSString stringWithFormat: @"%@%lu", base, (unsigned long)++idx];
    }

    return variable;
}

/*
 *   Scan a constant value, resolve relationship couchbase lite document id if exists,
 *   and extract value within a nested constant value if exists.
 */
- (id) scanConstantValue: (id)value {
    if ([value isKindOfClass: [NSManagedObjectID class]])
        return [value documentIDRepresentation];
    else if ([value isKindOfClass: [NSManagedObject class]])
        return [[value objectID] documentIDRepresentation];
    else if ([value isKindOfClass:[NSDate class]])
        // CBLQueryBuilder doesn't convert an NSDate value to a json object:
        return [CBLJSON JSONObjectWithDate: value];
    else if ([value isKindOfClass: [NSExpression class]]) {
        // An aggregate expression can contain constant value exp in its value.
        NSExpression* expression = (NSExpression*)value;
        if (expression.expressionType == NSConstantValueExpressionType)
            return expression.constantValue;
        else {
            // Shouldn't happen here:
            assert(expression.expressionType != NSConstantValueExpressionType);
        }
    }
    return value;
}

#pragma mark - Query (PostFilter)

- (NSArray*) fetchByEntityAndDoPostFilterWithRequest: (NSFetchRequest*)request
                                         withContext: (NSManagedObjectContext*)context
                                            outError: (NSError**)outError {
    BOOL needSort = (request.sortDescriptors != nil);
    NSMutableArray* objects = [NSMutableArray array];
    dispatch_sync(self.queue, ^{
        NSPredicate* predicate = [self documentTypePredicateForFetchRequest:request];
        CBLQueryBuilder* builder = [self cachedQueryBuilderForPredicate: predicate
                                                        sortDescriptors: nil];
        if (!builder) {
            builder = [[CBLQueryBuilder alloc] initWithDatabase: self.database
                                                         select: nil
                                                 wherePredicate: predicate
                                                        orderBy: nil
                                                          error: outError];
        }

        if (!builder)
            return;
        [self cacheQueryBuilder: builder forPredicate: predicate sortDescriptors: nil];
        CBLQuery* query = [builder createQueryWithContext: nil];
        query.prefetch = request.predicate != nil;

        CBLQueryEnumerator* rows = [query run: outError];
        if (!rows)
            return;

        // Post filter:
        NSUInteger offset = 0;
        for (CBLQueryRow* row in rows) {
            _relationshipSearchDepth = 0;
            if (!request.predicate || [self evaluatePredicate: request.predicate
                                                   withEntity: request.entity
                                               withProperties: row.documentProperties
                                                     outError: outError]) {
                if (needSort || offset >= request.fetchOffset) {
                    NSManagedObjectID* objectID = [self newObjectIDForEntity: request.entity
                                                             referenceObject: row.documentID];
                    // This method will not return null and perform any operations to get data:
                    NSManagedObject* object = [context objectWithID: objectID];
                    [objects addObject: object];
                }
                if (!needSort && request.fetchLimit > 0 && objects.count == request.fetchLimit)
                    break;
                offset++;
            }
        }
    });

    if (needSort && objects.count > 0) {
        NSArray* sorted = [objects sortedArrayUsingDescriptors: request.sortDescriptors];
        if (request.fetchOffset > 0 || request.fetchLimit > 0) {
            if (request.fetchOffset >= sorted.count) {
                return @[];
            }

            NSUInteger limit = request.fetchLimit;
            if (request.fetchLimit == 0 || (request.fetchOffset + request.fetchLimit > sorted.count)) {
                limit = objects.count - request.fetchOffset;
            }

            NSRange range = NSMakeRange(request.fetchOffset, limit);
            sorted = [sorted subarrayWithRange: range];
        }
        return sorted;
    } else
        return objects;
}

- (BOOL) evaluatePredicate: (NSPredicate*)predicate
                withEntity: (NSEntityDescription*)entity
            withProperties: (NSDictionary*)properties
                  outError: (NSError**)outError {
    if ([predicate isKindOfClass:[NSCompoundPredicate class]]) {
        NSCompoundPredicate* compoundPredicate = (NSCompoundPredicate*)predicate;
        NSCompoundPredicateType type = compoundPredicate.compoundPredicateType;

        if (compoundPredicate.subpredicates.count == 0) {
            switch (type) {
                case NSAndPredicateType:
                    return YES;
                    break;
                case NSOrPredicateType:
                    return NO;
                    break;
                default:
                    return NO;
                    break;
            }
        }

        BOOL compoundResult = NO;
        for (NSPredicate* subpredicate in compoundPredicate.subpredicates) {
            NSError* error;
            BOOL result = [self evaluatePredicate: subpredicate
                                       withEntity: entity
                                   withProperties: properties
                                         outError: &error];
            if (error) {
                if (outError)* outError = error;
                return NO;
            }

            switch (type) {
                case NSAndPredicateType:
                    if (!result) return NO;
                    compoundResult = YES;
                    break;
                case NSOrPredicateType:
                    if (result) return YES;
                    break;
                case NSNotPredicateType:
                    return !result;
                    break;
                default:
                    break;
            }
        }
        return compoundResult;

    } else if ([predicate isKindOfClass:[NSComparisonPredicate class]]) {
        NSComparisonPredicate* comparisonPredicate = (NSComparisonPredicate*)predicate;
        BOOL toManySearch =
        [self isToManySearchExpression: comparisonPredicate.leftExpression withEntity: entity] ||
        [self isToManySearchExpression: comparisonPredicate.rightExpression withEntity: entity];
        if (toManySearch && !comparisonPredicate.comparisonPredicateModifier) {
            if (outError) {
                NSString* desc = [NSString stringWithFormat:@"Unsupported predicate : "
                                  "%@ (To-many key without ANY or ALL modifier "
                                  "is not allowed here.)", predicate];
                *outError = CBLISError(CBLIncrementalStoreErrorUnsupportedPredicate, desc, nil);
            }
            return NO;
        }

        id leftValue = [self evaluateExpression: comparisonPredicate.leftExpression
                                     withEntity: entity
                                 withProperties: properties];
        id rightValue = [self evaluateExpression: comparisonPredicate.rightExpression
                                      withEntity: entity
                                  withProperties: properties];

        NSExpression* leftExpression = [NSExpression expressionForConstantValue: leftValue];
        NSExpression* rightExpression = [NSExpression expressionForConstantValue: rightValue];
        NSPredicate* comp =
        [NSComparisonPredicate predicateWithLeftExpression: leftExpression
                                           rightExpression: rightExpression
                                                  modifier: comparisonPredicate.comparisonPredicateModifier
                                                      type: comparisonPredicate.predicateOperatorType
                                                   options: comparisonPredicate.options];
        BOOL result = [comp evaluateWithObject: nil];
        return result;
    }

    return NO;
}

- (BOOL) isToManySearchExpression: (NSExpression*)expression withEntity: (NSEntityDescription*)entity {
    if (expression.expressionType != NSKeyPathExpressionType)
        return NO;

    NSPropertyDescription* propertyDesc = [entity.propertiesByName objectForKey: expression.keyPath];
    if (!propertyDesc) {
        NSArray* keyProp = [self parseKeyPathComponents: expression.keyPath];
        if ([keyProp count] == 2)
            propertyDesc = [entity.propertiesByName objectForKey: keyProp[0]];
    }

    return propertyDesc &&
    [propertyDesc isKindOfClass:[NSRelationshipDescription class]] &&
    ((NSRelationshipDescription*)propertyDesc).isToMany;
}

- (NSArray*) parseKeyPathComponents: (NSString*)keyPath {
    if (!keyPath) return nil;

    if ([keyPath rangeOfString:@"."].location != NSNotFound)
        return [keyPath componentsSeparatedByString: @"."];
    else
        return @[keyPath];
}

- (id) evaluateExpression: (NSExpression*)expression
               withEntity: (NSEntityDescription*)entity
           withProperties: (NSDictionary*)properties {
    id value = nil;
    switch (expression.expressionType) {
        case NSConstantValueExpressionType:
            value = [self scanConstantValue: [expression constantValue]];
            break;
        case NSEvaluatedObjectExpressionType:
            value = properties;
            break;
        case NSKeyPathExpressionType: {
            NSPropertyDescription* propertyDesc =
            [entity.propertiesByName objectForKey: expression.keyPath];
            if (propertyDesc) {
                value = [properties objectForKey: expression.keyPath];
                if ([propertyDesc isKindOfClass: [NSAttributeDescription class]]) {
                    if (!value) break;
                } else if ([propertyDesc isKindOfClass: [NSRelationshipDescription class]]) {
                    NSRelationshipDescription* relation = (NSRelationshipDescription*)propertyDesc;
                    if (!relation.isToMany) {
                        // Use the current value which is a doc id:
                        break;
                    } else {
                        if (relation.inverseRelationship.toMany) {
                            // Use the current value which an array of doc id:
                            break;
                        } else {
                            // one-to-many
                            NSString* parentDocId = [properties objectForKey: @"_id"];
                            if (parentDocId) {
                                NSArray* rows = [self queryToManyRelation: relation
                                                             forParentKey: parentDocId
                                                                 prefetch: NO
                                                                 outError: nil];
                                if (rows) {
                                    NSMutableArray* docIds = [NSMutableArray array];
                                    for (CBLQueryRow* row in rows)
                                        [docIds addObject: row.documentID];
                                    value = docIds;
                                }
                            }
                        }
                    }
                }
            } else if ([expression.keyPath rangeOfString:@"."].location != NSNotFound) {
                NSArray* keyPathComponents = [self parseKeyPathComponents: expression.keyPath];
                if ([keyPathComponents count] < 2) break;
                NSString* srcKeyPath = keyPathComponents[0];
                NSString* destKeyPath = [[keyPathComponents subarrayWithRange:
                                          NSMakeRange(1, keyPathComponents.count - 1)]
                                         componentsJoinedByString: @"."];

                propertyDesc = [entity.propertiesByName objectForKey: srcKeyPath];
                if (![propertyDesc isKindOfClass: [NSRelationshipDescription class]])
                    break;

                NSRelationshipDescription* relation = (NSRelationshipDescription*)propertyDesc;
                if (!relation.isToMany) {
                    // one-to-one (multiple level fetching):
                    NSString* subDocId = [properties objectForKey: srcKeyPath];
                    if (subDocId) {
                        _relationshipSearchDepth++;
                        if (_relationshipSearchDepth > self.maxRelationshipLoadDepth) {
                            WARN(@"Excess the maximum relationship search depth (current=%lu vs max=%lu)",
                                 (unsigned long)_relationshipSearchDepth,
                                 (unsigned long)self.maxRelationshipLoadDepth);
                            break;
                        }

                        CBLDocument* subDocument = [self.database existingDocumentWithID: subDocId];
                        if (subDocument) {
                            NSEntityDescription* subEntity = relation.destinationEntity;
                            NSExpression *subExpression = [NSExpression expressionForKeyPath:destKeyPath];
                            return [self evaluateExpression: subExpression
                                                 withEntity: subEntity
                                             withProperties: subDocument.properties];
                        }
                    }
                    break;
                } else {
                    // one(many)-to-many (1 level fetching):
                    if (relation.inverseRelationship.toMany) {
                        // many-to-many
                        value = [properties objectForKey: srcKeyPath];
                        NSMutableArray* values = [NSMutableArray array];
                        for (NSString* childDocId in value) {
                            CBLDocument* document = [self.database existingDocumentWithID: childDocId];
                            if (document) {
                                id propValue = [document.properties objectForKey: destKeyPath];
                                if (propValue)
                                    [values addObject: propValue];
                            }
                        }
                        value = values;
                    } else {
                        // one-to-many
                        NSString* parentDocId = [properties objectForKey: @"_id"];
                        if (parentDocId) {
                            NSArray* rows = [self queryToManyRelation: relation
                                                         forParentKey: parentDocId
                                                             prefetch: YES
                                                             outError: nil];
                            if (rows) {
                                NSMutableArray* values = [NSMutableArray array];
                                for (CBLQueryRow* row in rows) {
                                    id propValue = row.documentProperties[destKeyPath];
                                    if (propValue)
                                        [values addObject: propValue];
                                }
                                value = values;
                            }
                        }
                    }
                }
            }
        }
            break;
        default:
            NSAssert(NO, @"[devel] Expression Type not yet supported: %@", expression);
            break;
    }

    return value;
}

- (NSArray*) queryToManyRelation: (NSRelationshipDescription*)relation
                    forParentKey: (NSString*)parentKey
                        prefetch: (BOOL)prefetch
                        outError: (NSError**)outError {
    NSString* viewName = CBLISToManyViewNameForRelationship(relation);
    CBLView* view = [self.database existingViewNamed: viewName];
    if (view) {
        NSString* cacheKey = [NSString stringWithFormat:@"%@/%@", view, parentKey];
        CBLQueryEnumerator* result = [_relationshipCache objectForKey: cacheKey];
        if (result && (SInt64)result.sequenceNumber == view.database.lastSequenceNumber)
            return [result allObjects];

        CBLQuery* query = [view createQuery];
        query.keys = @[parentKey];
        query.prefetch = prefetch;
        result = [self queryEnumeratorForQuery: query error: outError];
        if (result)
            [_relationshipCache setObject: result forKey: cacheKey];
        return [result allObjects];
    }
    return nil;
}

#pragma mark - Misc

- (id) convertCoreDataValue: (id)value toCBLOfType: (NSAttributeType)type {
    id result = nil;

    switch (type) {
        case NSInteger16AttributeType:
        case NSInteger32AttributeType:
        case NSInteger64AttributeType:
            result = CBLISIsNull(value) ? @(0) : value;
            break;
        case NSDecimalAttributeType:
        case NSDoubleAttributeType:
        case NSFloatAttributeType:
            result = CBLISIsNull(value) ? @(0.0f) : value;
            break;
        case NSStringAttributeType:
            result = CBLISIsNull(value) ? @"" : value;
            break;
        case NSBooleanAttributeType:
            result = CBLISIsNull(value) ? @(NO) : [value boolValue] ? @(YES) : @(NO);
            break;
        case NSDateAttributeType:
            result = CBLISIsNull(value) ? nil : [CBLJSON JSONObjectWithDate: value];
            break;
        case NSBinaryDataAttributeType:
        case NSUndefinedAttributeType:
            result = value;
            break;
        default:
            WARN(@"Unsupported attribute type : %d", (int)type);
            break;
    }

    return result;
}

- (id) convertCBLValue: (id)value toCoreDataOfType: (NSAttributeType)type {
    id result = nil;

    switch (type) {
        case NSInteger16AttributeType:
        case NSInteger32AttributeType:
        case NSInteger64AttributeType:
            if (CBLISIsNull(value))
                result = @(0);
            else if ([value isKindOfClass: [NSNumber class]])
                result = @([value longValue]);
            else {
                WARN(@"Invalid value (%@) for the attribute type : %d", value, (int)type);
                result = nil;
            }
            break;
        case NSDecimalAttributeType:
            if (CBLISIsNull(value))
                result = [NSDecimalNumber numberWithDouble:0.0f];
            else if ([value isKindOfClass: [NSNumber class]])
                result = [NSDecimalNumber numberWithDouble: [value doubleValue]];
            else {
                WARN(@"Invalid value (%@) for the attribute type : %d", value, (int)type);
                result = nil;
            }
            break;
        case NSDoubleAttributeType:
        case NSFloatAttributeType:
            if (CBLISIsNull(value))
                result = @(0.0f);
            else if ([value isKindOfClass: [NSNumber class]])
                result = @([value doubleValue]);
            else {
                WARN(@"Invalid value (%@) for the attribute type : %d", value, (int)type);
                result = nil;
            }
            break;
        case NSStringAttributeType:
            if (CBLISIsNull(value))
                result = @"";
            else if ([value isKindOfClass: [NSString class]])
                result = value;
            else {
                WARN(@"Invalid value (%@) for the attribute type : %d", value, (int)type);
                result = nil;
            } break;
        case NSBooleanAttributeType:
            if (CBLISIsNull(value))
                result = @(NO);
            else if ([value isKindOfClass: [NSNumber class]])
                result = @([value boolValue]);
            else {
                WARN(@"Invalid value (%@) for the attribute type : %d", value, (int)type);
                result = nil;
            } break;
        case NSDateAttributeType:
            result = CBLISIsNull(value) ? nil : [CBLJSON dateWithJSONObject: value];
            break;
        case NSTransformableAttributeType:
            result = value;
            break;
        default:
            WARN(@"Unsupported attribute type : %d", (int)type);
            break;
    }

    return result;
}

- (NSDictionary*) propertiesForManagedObject: (NSManagedObject*)object {
    NSEntityDescription* entity = object.entity;
    NSDictionary* propsByName = [entity propertiesByName];

    NSMutableDictionary* properties = [NSMutableDictionary dictionary];
    [properties setObject: entity.name forKey: [self documentTypeKey]];

    if ([propsByName objectForKey: kCBLISRevisionAttributeName]) {
        id rev = [object valueForKey: kCBLISRevisionAttributeName];
        if (!CBLISIsNull(rev))
            [properties setObject: rev forKey: @"_rev"];
    }

    [properties setObject: [object.objectID documentIDRepresentation] forKey: @"_id"];

    for (NSString* name in propsByName) {
        if ([kCBLISRevisionAttributeName isEqual: name])
            continue;

        id desc = [propsByName objectForKey: name];
        if ([desc isKindOfClass: [NSAttributeDescription class]]) {
            NSAttributeDescription* attr = desc;
            if ([attr isTransient])
                continue;

            // skip binary attributes to not load them into memory here. They are added as attachments
            if ([attr attributeType] == NSBinaryDataAttributeType)
                continue;

            id value = [object valueForKey: name];

            if (value) {
                NSAttributeType attributeType = [attr attributeType];
                if (attr.valueTransformerName) {
                    NSValueTransformer* transformer =
                    [NSValueTransformer valueTransformerForName: attr.valueTransformerName];

                    if (!transformer) {
                        WARN(@"Value transformer for attribute %@ with name %@ not found",
                             attr.name, attr.valueTransformerName);
                        continue;
                    }

                    value = [transformer transformedValue: value];

                    Class transformedClass = [[transformer class] transformedValueClass];
                    if (transformedClass == [NSString class]) {
                        attributeType = NSStringAttributeType;
                    } else if (transformedClass == [NSData class]) {
                        value = [value base64EncodedStringWithOptions:0];
                        attributeType = NSStringAttributeType;
                    } else {
                        WARN(@"Unsupported value transformer transformedValueClass: %@",
                             NSStringFromClass(transformedClass));
                        continue;
                    }
                }
                value = [self convertCoreDataValue: value toCBLOfType: attributeType];
                if (value) {
                    [properties setObject: value forKey: name];
                }
            }
        } else if ([desc isKindOfClass: [NSRelationshipDescription class]]) {
            id relValue = [object valueForKey: name];
            if (relValue) {
                NSRelationshipDescription* rel = desc;
                if ([rel isToMany]) {
                    if (rel.inverseRelationship.toMany) {
                        // many-to-many relationship, embed an array of doc ids:
                        NSMutableArray* subentities  = [NSMutableArray array];
                        for (NSManagedObject* subentity in relValue)
                            [subentities addObject: [subentity.objectID documentIDRepresentation]];
                        [properties setObject:subentities forKey:name];
                    }
                } else {
                    NSManagedObjectID* objectID = [relValue valueForKey: @"objectID"];
                    [properties setObject: [objectID documentIDRepresentation] forKey: name];
                }
            }
        }
    }

    return properties;
}


- (NSDictionary*) coreDataPropsOfDocument: (CBLDocument*)doc withEntity: (NSEntityDescription*)entity {
    NSDictionary* properties = doc.properties;
    NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity: properties.count];
    NSDictionary* propertiesByName = [entity propertiesByName];
    for (NSString* name in propertiesByName) {
        id desc = [propertiesByName objectForKey: name];
        if ([desc isKindOfClass: [NSAttributeDescription class]]) {
            NSAttributeDescription* attr = desc;
            // Transient - ignore:
            if ([attr isTransient]) {
                continue;
            }

            // Binary:
            if ([attr attributeType] == NSBinaryDataAttributeType) {
                id value = [doc.currentRevision attachmentNamed: name].content;
                if (value) {
                    [result setObject: value forKey: name];
                }
                continue;
            }

            id value = nil;
            if ([kCBLISRevisionAttributeName isEqual: name]) {
                value = [properties objectForKey: @"_rev"];
            } else {
                value = [properties objectForKey: name];
            }

            if (value) {
                NSAttributeType attributeType = [attr attributeType];
                if (attr.valueTransformerName) {
                    NSValueTransformer* transformer =
                    [NSValueTransformer valueTransformerForName: attr.valueTransformerName];
                    Class transformedClass = [[transformer class] transformedValueClass];
                    if (transformedClass == [NSString class]) {
                        value = [transformer reverseTransformedValue: value];
                    } else if (transformedClass == [NSData class]) {
                        value = [transformer reverseTransformedValue:
                                 [[NSData alloc]initWithBase64EncodedString: value options: 0]];
                    } else {
                        INFO(@"Unsupported value transformer transformedValueClass: %@",
                             NSStringFromClass(transformedClass));
                        continue;
                    }
                }
                value = [self convertCBLValue: value toCoreDataOfType: attributeType];
                if (value) {
                    [result setObject: value forKey: name];
                }
            }
        } else if ([desc isKindOfClass: [NSRelationshipDescription class]]) {
            NSRelationshipDescription* rel = desc;
            if (![rel isToMany]) { // only handle to-one relationships
                id value = [properties objectForKey: name];
                if (!CBLISIsNull(value)) {
                    NSManagedObjectID* destination = [self newObjectIDForEntity: rel.destinationEntity
                                                                referenceObject: value];
                    [result setObject: destination forKey: name];
                }
            }
        }
    }
    return result;
}

/** Convenience method to execute a CouchbaseLite query */
- (CBLQueryEnumerator*) queryEnumeratorForQuery: (CBLQuery*)query error: (NSError**)outError {
    NSError* error;
    CBLQueryEnumerator* rows = [query run: &error];
    if (!rows) {
        if (outError)
            *outError = CBLISError(CBLIncrementalStoreErrorQueryingCouchbaseLiteFailed,
                                   @"Error querying CouchbaseLite", nil);
        return nil;
    }

    return rows;
}

#pragma mark - Cache

- (NSData*) SHA1: (NSData*)input {
    unsigned char digest[SHA_DIGEST_LENGTH];
    SHA_CTX ctx;
    SHA1_Init(&ctx);
    SHA1_Update(&ctx, input.bytes, input.length);
    SHA1_Final(digest, &ctx);
    return [NSData dataWithBytes: &digest length: sizeof(digest)];
}

- (NSString*) digestCacheKey: (id)key {
    if (!key) return nil;

    NSError* error;
    NSData* data = [CBLJSON dataWithJSONObject: key options:0 error: &error];
    if (!data) {
#ifdef DEBUG_DETAILS
        ERROR(@"Invalid cache key : %@", key);
#endif
        return nil;
    }
    NSString* encoded = [CBLJSON base64StringWithData: data];
    return encoded;
}

- (NSString*) cacheKeyForFetchRequest: (NSFetchRequest*)request {
    NSMutableDictionary* keys = [NSMutableDictionary dictionary];

    if (request.predicate)
        keys[@"predicate"] = [request.predicate predicateFormat];

    if (request.sortDescriptors) {
        NSMutableString* sortDesc = [NSMutableString string];
        for (NSSortDescriptor* sort in request.sortDescriptors) {
            [sortDesc appendFormat:@"%@", sort];
        }
        keys[@"sortDescriptors"] = sortDesc;
    }

    if (request.fetchLimit > 0)
        keys[@"fetchLimit"] = @(request.fetchLimit);

    if (request.fetchOffset > 0)
        keys[@"fetchOffset"] = @(request.fetchOffset);

    keys[@"includesSubentities"] = @(request.includesSubentities);

    NSString* digestedKey = [self digestCacheKey: keys];
    return [NSString stringWithFormat:@"%@-%@", request.entityName, digestedKey];
}

- (NSArray*) cachedObjectsForFetchRequest: (NSFetchRequest*)request {
    NSString* key = [self cacheKeyForFetchRequest: request];
    if (!key) return nil;
    return [_fetchRequestResultCache objectForKey: key];
}

- (void) cacheObjects: (NSArray*)objects forFetchRequest: (NSFetchRequest*)request {
    NSString* key = [self cacheKeyForFetchRequest: request];
    if (!key) return;
    [_fetchRequestResultCache setObject: objects forKey: key];
}

- (void) purgeCachedObjectsForEntityName: (NSString*)entity {
    NSString* prefix = [NSString stringWithFormat: @"%@-", entity];
    for (NSString* key in [_fetchRequestResultCache allKeys]) {
        if ([key hasPrefix: prefix]) {
            [_fetchRequestResultCache removeObjectForKey: key];
        }
    }
}

- (void) invalidateFetchResultCache {
    [_fetchRequestResultCache removeAllObjects];
}

#pragma mark - Purge

- (BOOL) purgeObject: (NSManagedObject*)object error:(NSError **)outError {
    if ([object.objectID isTemporaryID]) {
        WARN(@"The object has a tempory ID so the object many not be purged as expected due to "
             "ID mismatching. Please call NSManagedObjectContext's -obtainPermanentIDsForObjects:error:"
             "to obtain its permanent ID.");
    }

    __block BOOL success;
    dispatch_sync(self.queue, ^{
        NSString* docID = [object.objectID documentIDRepresentation];
        CBLDocument* doc = [self.database documentWithID: docID];
        success = [doc purgeDocument: outError];
    });

    if (success) {
        NSMutableSet* deletedIDs = [NSMutableSet setWithCapacity: 1];
        [deletedIDs addObject: object.objectID];
        [self refreshObservingContextsWithUpdatedIDs: nil deletedIDs: deletedIDs
                                    thenNotifyChange: NO];
    }
    return success;
}

#pragma mark - Change Handling

- (void) addObservingManagedObjectContext: (NSManagedObjectContext*)context {
    if (!_observingManagedObjectContexts) {
        _observingManagedObjectContexts =
        [[NSHashTable alloc] initWithOptions: NSPointerFunctionsWeakMemory capacity: 2];
    }
    [_observingManagedObjectContexts addObject:context];
}

- (void) removeObservingManagedObjectContext: (NSManagedObjectContext*)context {
    [_observingManagedObjectContexts removeObject:context];
}

- (NSArray*) sortedObservingManagedObjectContexts {
    return [self.observingManagedObjectContexts.allObjects sortedArrayUsingDescriptors:
            @[[NSSortDescriptor sortDescriptorWithKey:
               NSStringFromSelector(@selector(parentContext)) ascending:YES]]];
}

- (void) databaseChanged: (NSNotification*)notification {
    NSArray* changes = notification.userInfo[@"changes"];
    if (changes.count == 0)
        return;

    CBLDatabaseChange* change = changes.firstObject;
    if (change.source == nil)
        [self processLocalChanges: changes];
    else
        [self processRemoteChanges: changes];
}

- (void) processLocalChanges: (NSArray*)changes {
    INFO(@"processLocalChanges : %lu on %@", (unsigned long)changes.count,
         [NSThread currentThread]);

    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();

    NSMutableSet* updatedIDs = nil;
    NSMutableSet* deletedIDs = nil;
    for (CBLDatabaseChange* change in changes) {
        if (!change.isCurrentRevision)
            continue;
        if ([change.documentID hasPrefix: @"CBLIS"])
            continue;

        NSString* entity = [self entityNameForDatabaseChange: change];
        [self purgeCachedObjectsForEntityName: entity];

        if (self.shouldNotifyLocalDatabaseChanges) {
            BOOL isDeleted;
            NSManagedObjectID *objectID = [self objectIDForChange: change isDeleted: &isDeleted];
            if (objectID) {
                if (isDeleted) {
                    if (!deletedIDs) deletedIDs = [NSMutableSet set];
                    [deletedIDs addObject: objectID];
                } else {
                    if (!updatedIDs) updatedIDs = [NSMutableSet set];
                    [updatedIDs addObject: objectID];
                }
            }
        }
    }

    if (self.shouldNotifyLocalDatabaseChanges && updatedIDs.count > 0 && deletedIDs.count > 0)
        [self notifyChangeNotificationWithUpdatedIDs: updatedIDs deletedIDs: deletedIDs];

    CFAbsoluteTime end = CFAbsoluteTimeGetCurrent();
    INFO(@"processLocalChanges : Finished in %f seconds", (end - start));
}

- (void) processRemoteChanges: (NSArray*)changes {
    INFO(@"processRemoteChanges : %lu on %@", (unsigned long)changes.count,
         [NSThread currentThread]);

    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();

    NSMutableSet* updatedIDs = [NSMutableSet set];
    NSMutableSet* deletedIDs = [NSMutableSet set];

    for (CBLDatabaseChange* change in changes) {
        if (!change.isCurrentRevision)
            continue;
        if ([change.documentID hasPrefix: @"CBLIS"])
            continue;

        BOOL isDeleted;
        NSManagedObjectID *objectID = [self objectIDForChange: change isDeleted: &isDeleted];
        if (isDeleted)
            [deletedIDs addObject: objectID];
        else
            [updatedIDs addObject: objectID];
    }

    if (updatedIDs.count > 0 || deletedIDs.count > 0) {
        [self refreshObservingContextsWithUpdatedIDs: updatedIDs deletedIDs: deletedIDs
                                    thenNotifyChange: YES];
    }

    CFAbsoluteTime end = CFAbsoluteTimeGetCurrent();
    INFO(@"processRemoteChanges : Finished in %f seconds", (end - start));
}

- (NSManagedObjectID*) objectIDForChange: (CBLDatabaseChange*)change isDeleted: (BOOL*)isDeleted {
    CBLDocument* doc = [self.database documentWithID: change.documentID];
    CBLRevision* rev = [doc revisionWithID: change.revisionID];
    NSDictionary* properties = [rev properties];
    NSString* type = [properties objectForKey: [self documentTypeKey]];
    if (!type) {
        WARN(@"Couldn't find type property on changed document : %@ (source = %@)",
             properties, change.source);
        return nil;
    }

    if (isDeleted)
        *isDeleted = rev.isDeletion;

    NSDictionary *entitiesByName = self.persistentStoreCoordinator.managedObjectModel.entitiesByName;
    NSEntityDescription* entity = entitiesByName[type];
    return [self newObjectIDForEntity: entity referenceObject: change.documentID];
}

- (NSString*) entityNameForDatabaseChange: (CBLDatabaseChange*)change {
    NSManagedObjectID* mID = [_recentSavedObjectIDs objectForKey: change.documentID];
    NSString* entityName = mID.entity.name;
    if (!entityName) {
        CBLDocument* doc = [self.database documentWithID: change.documentID];
        NSDictionary* properties = [doc revisionWithID: change.revisionID].properties;
        entityName = [properties objectForKey: [self documentTypeKey]];
    }
    return entityName;
}

- (void) refreshObservingContextsWithUpdatedIDs: (NSSet*)updatedIDs deletedIDs: (NSSet*)deletedIDs
                               thenNotifyChange: (BOOL)notifyChange {
    NSMutableArray* contexts = [[self sortedObservingManagedObjectContexts] mutableCopy];
    if (contexts.count > 0) {
        [self refreshContexts: contexts
               withUpdatedIDs: updatedIDs deletedIDs: deletedIDs
                 onCompletion: ^{
                     if (notifyChange)
                         [self notifyChangeNotificationWithUpdatedIDs: updatedIDs
                                                           deletedIDs: deletedIDs];
                 }
         ];
    } else {
        if (notifyChange)
            [self notifyChangeNotificationWithUpdatedIDs: updatedIDs deletedIDs: deletedIDs];
    }
}

- (void) refreshContexts: (NSMutableArray*) contexts
          withUpdatedIDs: (NSSet*)updatedIDs deletedIDs: (NSSet*)deletedIDs
            onCompletion: (void (^)())completionBlock {
    INFO(@"refreshContextsWithUpdatedIDs : updated %lu, deleted %lu on %@",
         (unsigned long)updatedIDs.count, (unsigned long)deletedIDs.count, [NSThread currentThread]);
    NSManagedObjectContext* context = [contexts firstObject];
    [contexts removeObjectAtIndex:0];
    [context performBlock: ^{
        INFO(@"Start refresh context : %@", context.parentContext ? @"Child" : @"Root");

        NSMutableSet* refreshedIDs = [NSMutableSet set];
        NSMutableSet* updatedEntities = [NSMutableSet set];

        for (NSManagedObjectID* mID in updatedIDs) {
            NSManagedObject* mObj = [context objectRegisteredForID: mID];
            if (!mObj)
                mObj = [context objectWithID: mID];

            for (NSString* relName in mID.entity.relationshipsByName) {
                NSRelationshipDescription* rel = mID.entity.relationshipsByName[relName];
                if (rel.toMany)
                    continue;

                NSRelationshipDescription* invRel = rel.inverseRelationship;
                if (!invRel)
                    continue;

                NSManagedObject *relObj = [mObj valueForKey: relName];
                if (relObj)
                    [refreshedIDs addObject: relObj.objectID];
            }
        }

        NSMutableArray* objectsToRefresh = [NSMutableArray array];
        [objectsToRefresh addObjectsFromArray: updatedIDs.allObjects];
        [objectsToRefresh addObjectsFromArray: refreshedIDs.allObjects];

        INFO(@"Refreshing context : %@ (%@ / %@ objects)",
             (context.parentContext ? @"Child" : @"Root"),
             @(objectsToRefresh.count), @(context.registeredObjects.count));

        for (NSManagedObjectID* mID in deletedIDs) {
            NSManagedObject* obj = [context objectRegisteredForID: mID];
            if (obj)
                [context deleteObject: obj];
            [updatedEntities addObject: mID.entity.name];
        }

        for (NSManagedObjectID* mID in objectsToRefresh) {
            NSManagedObject* obj = [context objectRegisteredForID: mID];
            if (obj) {
                [obj willAccessValueForKey: nil];
                [context refreshObject: obj mergeChanges: YES];
            }
            [updatedEntities addObject: mID.entity.name];
        }

        if (!context.parentContext) {
            dispatch_sync(self.queue, ^{
                for (NSString* entity in updatedEntities) {
                    [self purgeCachedObjectsForEntityName: entity];
                }
            });
        }

        [context processPendingChanges];

        INFO(@"Finish refresh context : %@", context.parentContext ? @"Child" : @"Root");

        if (contexts.count > 0)
            [self refreshContexts: contexts withUpdatedIDs: updatedIDs deletedIDs: deletedIDs
                     onCompletion: completionBlock];
        else {
            if (completionBlock) {
                completionBlock();
            }
        }
    }];
}

- (void) notifyChangeNotificationWithUpdatedIDs: (NSSet*)updatedIDs
                                     deletedIDs: (NSSet*)deletedIDs {
    NSMutableDictionary* userInfo = [NSMutableDictionary dictionary];
    if (updatedIDs.count > 0)
        [userInfo setObject: updatedIDs forKey: NSUpdatedObjectsKey];
    if (deletedIDs.count > 0)
        [userInfo setObject: deletedIDs forKey: NSDeletedObjectsKey];

    __weak id weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        CBLIncrementalStore* strongSelf = weakSelf;
        [[NSNotificationCenter defaultCenter]
         postNotificationName: kCBLISObjectHasBeenChangedInStoreNotification
         object: strongSelf
         userInfo: userInfo];
    });
}

#pragma mark - Conflicts handling

- (void) observeValueForKeyPath: (NSString*)keyPath ofObject: (id)object
                         change: (NSDictionary*)change context: (void*)context {
    if ([@"rows" isEqualToString: keyPath]) {
        [self resolveConflicts];
    }
}

- (void) resolveConflicts  {
    // Resolve conflicts
    for (CBLQueryRow* row in _conflictsQuery.rows) {
        if ([kCBLISMetadataDocumentID isEqual: row.documentID])
            continue; // For v1.0.4 and below.
        if (self.conflictHandler)
            self.conflictHandler(row.conflictingRevisions);
    }
}

- (CBLISConflictHandler) defaultConflictHandler {
    __weak CBLIncrementalStore* weakSelf = self;

    CBLISConflictHandler handler = ^(NSArray* conflictingRevisions) {
        // Merges changes by
        // - taking the winning revision
        // - adding missing values from other revisions (starting with biggest version)
        CBLSavedRevision* winningRev = conflictingRevisions[0];
        NSMutableDictionary* mergedProps = [winningRev.properties mutableCopy];

        NSRange range = NSMakeRange(1, conflictingRevisions.count - 1);
        NSArray* otherRevs = [conflictingRevisions subarrayWithRange: range];

        NSSortDescriptor* sort = [NSSortDescriptor sortDescriptorWithKey: @"revisionID" ascending: NO];
        otherRevs = [otherRevs sortedArrayUsingDescriptors: @[sort]];

        CBLIncrementalStore* strongSelf = weakSelf;
        [strongSelf.database inTransaction: ^BOOL{
            // Merge missing keys from other conflicting revisions to not loose any values:
            NSError* error;
            for (CBLSavedRevision* rev in otherRevs) {
                for (NSString* key in rev.properties) {
                    if (![key hasPrefix: @"_"]) {
                        if (![mergedProps objectForKey: key]) {
                            id value = [rev propertyForKey: key];
                            if (value)
                                [mergedProps setObject: value forKey: key];
                        }
                    }
                }

                CBLUnsavedRevision *newRev = [rev createRevision];
                newRev.isDeletion = YES;
                if (![newRev saveAllowingConflict: &error])
                    return NO;
            }

            CBLUnsavedRevision* newRev = [winningRev createRevision];
            [newRev setProperties: mergedProps];
            return [newRev saveAllowingConflict: &error] != nil;
        }];
    };
    return handler;
}

#pragma mark - Delete properties

/*
 * Returns the properties that are stored for deleting a document.
 * Must contain at least "_rev" and "_deleted" = true for CouchbaseLite and type key for this store.
 * Can be overridden if you need more for filtered syncing.
 */
- (NSDictionary*) propertiesForDeletingDocument: (CBLDocument*)doc {
    NSMutableDictionary *contents = [NSMutableDictionary dictionary];
    NSString *typeKey = [self documentTypeKey];

    [contents addEntriesFromDictionary:@{
                                         @"_deleted": @YES,
                                         @"_rev": [doc propertyForKey:@"_rev"],
                                         typeKey: [doc propertyForKey: typeKey]
                                         }];

    return [NSDictionary dictionaryWithDictionary:contents];
}

@end


@implementation NSManagedObjectID (CBLIncrementalStore)

/** Returns an internal representation of this objectID that is used as _id in Couchbase. */
- (NSString*) documentIDRepresentation {
    // +1 because of "p" prefix in managed object IDs
    NSString* uuid = [[self.URIRepresentation lastPathComponent]
                      substringFromIndex: kCBLISManagedObjectIDPrefix.length + 1];
    return uuid;
}

@end

#pragma mark - Utilities

/** Checks if value is nil or NSNull. */
BOOL CBLISIsNull(id value) {
    return value == nil || [value isKindOfClass: [NSNull class]];
}

/** Returns name of a view that returns objectIDs for all destination entities of a to-many relationship.*/
NSString* CBLISToManyViewNameForRelationship(NSRelationshipDescription* relationship) {
    NSString* entityName = relationship.entity.name;
    NSString* destinationName = relationship.destinationEntity.name;
    NSString* relationshipName = relationship.name;
    return [NSString stringWithFormat: kCBLISToManyViewNameFormat,
            entityName, destinationName, relationshipName];
}

/** Returns a readable name for a NSFetchRequestResultType*/
NSString* CBLISResultTypeName(NSFetchRequestResultType resultType) {
    switch (resultType) {
        case NSManagedObjectResultType:
            return @"NSManagedObjectResultType";
        case NSManagedObjectIDResultType:
            return @"NSManagedObjectIDResultType";
        case NSDictionaryResultType:
            return @"NSDictionaryResultType";
        case NSCountResultType:
            return @"NSCountResultType";
        default:
            return @"Unknown";
            break;
    }
}

NSError* CBLISError(NSInteger code, NSString* desc, NSError *parent) {
    NSMutableDictionary *userInfo = nil;
    if (desc || parent) {
        userInfo = [NSMutableDictionary dictionary];
        if (desc)
            userInfo[NSLocalizedDescriptionKey] = desc;
        if (parent)
            userInfo[NSUnderlyingErrorKey] = parent;
    }
    return [NSError errorWithDomain: kCBLISErrorDomain code: code userInfo: userInfo];
}
