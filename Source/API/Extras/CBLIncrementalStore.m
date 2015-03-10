//
//  CBLIncrementalStore.m
//  CBLIncrementalStore
//
//  Created by Christian Beer on 21.11.13.
//  Copyright (c) 2013 Christian Beer. All rights reserved.
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

#define INFO(FMT, ...)  NSLog(@"[CBLIS] INFO " FMT, ##__VA_ARGS__)
#define WARN(FMT, ...)  NSLog(@"[CBLIS] WARNING " FMT, ##__VA_ARGS__)
#define ERROR(FMT, ...)  NSLog(@"[CBLIS] ERROR " FMT, ##__VA_ARGS__)

NSString* const kCBLISErrorDomain = @"CBLISErrorDomain";
NSString* const kCBLISObjectHasBeenChangedInStoreNotification = @"kCBLISObjectHasBeenChangedInStoreNotification";

static NSString* const kCBLISTypeKey = @"CBLIS_type";
static NSString* const kCBLISCurrentRevisionAttributeName = @"CBLIS_Rev";
static NSString* const kCBLISManagedObjectIDPrefix = @"CBL";
static NSString* const kCBLISMetadataDocumentID = @"CBLIS_metadata";
static NSString* const kCBLISFetchEntityByPropertyViewNameFormat = @"CBLIS/fetch_%@_by_%@";
static NSString* const kCBLISFetchEntityToManyViewNameFormat = @"CBLIS/%@_tomany_%@";


// Utility functions
static BOOL CBLISIsNull(id value);
static NSString* CBLISToManyViewNameForRelationship(NSRelationshipDescription* relationship);
static NSString* CBLISResultTypeName(NSFetchRequestResultType resultType);

@interface NSManagedObjectID (CBLIncrementalStore)
- (NSString*) couchbaseLiteIDRepresentation;
@end


@interface CBLIncrementalStore ()

// TODO: check if there is a better way to not hold strong references on these MOCs
@property (nonatomic, strong) NSHashTable* observingManagedObjectContexts;
@property (nonatomic, strong, readwrite) CBLDatabase* database;
@property (nonatomic, strong) id changeObserver;

@end

@implementation CBLIncrementalStore
{
    NSMutableArray* _coalescedChanges;
    NSCache* _queryBuilderCache;
    NSMutableDictionary* _fetchRequestResultCache;
    NSMutableDictionary* _entityAndPropertyToFetchViewName;
    CBLLiveQuery* _conflictsQuery;
}

@synthesize database = _database;
@synthesize changeObserver = _changeObserver;
@synthesize conflictHandler = _conflictHandler;

@synthesize observingManagedObjectContexts = _observingManagedObjectContexts;

static CBLManager* sCBLManager;

+ (void) setCBLManager: (CBLManager*)manager {
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
    
    NSError* error;
    
    NSPersistentStoreCoordinator* persistentStoreCoordinator =
        [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel: model];
    
    NSDictionary* options = @{
                              NSMigratePersistentStoresAutomaticallyOption : @YES,
                              NSInferMappingModelAutomaticallyOption : @YES
                              };
    
    CBLIncrementalStore* store = nil;
    if (importUrl) {
        NSPersistentStore* oldStore = [persistentStoreCoordinator addPersistentStoreWithType: importType
                                                                               configuration: nil
                                                                                         URL: importUrl
                                                                                     options: options
                                                                                       error: &error];
        if (!oldStore) {
            if (outError)* outError = [NSError errorWithDomain: kCBLISErrorDomain
                                                          code: CBLIncrementalStoreErrorMigrationOfStoreFailed
                                                      userInfo: @{
                                                                  NSLocalizedDescriptionKey: @"Couldn't open store to import",
                                                                  NSUnderlyingErrorKey: error
                                                                  }];
            return nil;
        }
        
        store = (CBLIncrementalStore*)[persistentStoreCoordinator migratePersistentStore: oldStore
                                                                                   toURL: [NSURL URLWithString: databaseName]
                                                                                 options: options
                                                                                withType: [self type] error: &error];
        
        if (!store) {
            NSString* errDesc = [NSString stringWithFormat:@"Migration of store at URL %@ failed: %@", importUrl, error.description];
            if (outError)* outError = [NSError errorWithDomain: kCBLISErrorDomain
                                                          code: CBLIncrementalStoreErrorMigrationOfStoreFailed
                                                      userInfo: @{
                                                                  NSLocalizedDescriptionKey: errDesc,
                                                                  NSUnderlyingErrorKey: error
                                                                  }];
            return nil;
        }
    } else {
        store = (CBLIncrementalStore*)[persistentStoreCoordinator addPersistentStoreWithType: [self type]
                                                                               configuration: nil
                                                                                         URL: [NSURL URLWithString:databaseName]
                                                                                     options: options
                                                                                       error: &error];
        
        if (!store) {
            NSString* errDesc = [NSString stringWithFormat: @"Initialization of store failed: %@", error.description];
            if (outError) *outError = [NSError errorWithDomain: kCBLISErrorDomain
                                                          code: CBLIncrementalStoreErrorCreatingStoreFailed
                                                      userInfo: @{
                                                                  NSLocalizedDescriptionKey: errDesc,
                                                                  NSUnderlyingErrorKey: error
                                                                  }];
            return nil;
        }
    }
    
    NSManagedObjectContext* managedObjectContext =
        [[NSManagedObjectContext alloc] initWithConcurrencyType: NSMainQueueConcurrencyType];
    [managedObjectContext setPersistentStoreCoordinator: persistentStoreCoordinator];
    
    [store addObservingManagedObjectContext: managedObjectContext];
    
    return managedObjectContext;
}

#pragma mark -

+ (void) initialize {
    if ([[self class] isEqual: [CBLIncrementalStore class]]) {
        [NSPersistentStoreCoordinator registerStoreClass: self
                                            forStoreType: [self type]];
    }
}

- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver: self.changeObserver];
    
    [_conflictsQuery stop];
    [_conflictsQuery removeObserver: self forKeyPath: @"rows"];
    _conflictsQuery = nil;
    
    self.database = nil;
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
        if (entity.superentity) { // only add to super-entities, not the sub-entities
            continue;
        }
        
        NSMutableArray* properties = [entity.properties mutableCopy];
        
        for (NSPropertyDescription* prop in properties) {
            if ([prop.name isEqual: kCBLISCurrentRevisionAttributeName]) {
                return;
            }
        }
        
        NSAttributeDescription* revAttribute = [NSAttributeDescription new];
        revAttribute.name = kCBLISCurrentRevisionAttributeName;
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
    
    _coalescedChanges = [[NSMutableArray alloc] init];
    _fetchRequestResultCache = [[NSMutableDictionary alloc] init];
    _queryBuilderCache = [[NSCache alloc] init];
    _entityAndPropertyToFetchViewName = [[NSMutableDictionary alloc] init];
    
    self.conflictHandler = [self defaultConflictHandler];
    
    return self;
}

#pragma mark - NSIncrementalStore

-(BOOL) loadMetadata: (NSError**)outError {
    // check data model if compatible with this store
    NSArray* entites = self.persistentStoreCoordinator.managedObjectModel.entities;
    for (NSEntityDescription* entity in entites) {
        NSDictionary* attributesByName = [entity attributesByName];
        
        if (![attributesByName objectForKey: kCBLISCurrentRevisionAttributeName]) {
            if (outError) {
                NSString *errDesc = @"Database Model not compatible. You need to call +[updateManagedObjectModel:].";
                *outError = [NSError errorWithDomain: kCBLISErrorDomain
                                                code: CBLIncrementalStoreErrorDatabaseModelIncompatible
                                            userInfo: @{ NSLocalizedFailureReasonErrorKey: errDesc }];
            }
            return NO;
        }
    }

    NSString* databaseName = [self.URL lastPathComponent];
    
    CBLManager* manager = [[self class] CBLManager];
    if (!manager)
        manager = [CBLManager sharedInstance];

    NSError* error;
    self.database = [manager databaseNamed: databaseName error: &error];
    if (!self.database) {
        if (outError) *outError = [NSError errorWithDomain: kCBLISErrorDomain
                                                      code: CBLIncrementalStoreErrorCreatingDatabaseFailed
                                                  userInfo: @{
                                                              NSLocalizedDescriptionKey: @"Could not create database",
                                                              NSUnderlyingErrorKey: error
                                                              }];
        return NO;
    }

    [self initializeViews];
    
    
    __weak __typeof(self) weakSelf = self;
    self.changeObserver = [[NSNotificationCenter defaultCenter] addObserverForName: kCBLDatabaseChangeNotification
                                                                            object: self.database queue:nil
                                                                        usingBlock: ^(NSNotification* note) {
                                                                            NSArray* changes = note.userInfo[@"changes"];
                                                                            [weakSelf couchDocumentsChanged:changes];
                                                                        }];
    
    CBLDocument* doc = [self.database documentWithID: kCBLISMetadataDocumentID];
    
    BOOL success = NO;
    
    NSDictionary* metaData = doc.properties;
    if (![metaData objectForKey: NSStoreUUIDKey]) {
        
        metaData = @{
                     NSStoreUUIDKey: [[NSProcessInfo processInfo] globallyUniqueString],
                     NSStoreTypeKey: [[self class] type]
                     };
        [self setMetadata: metaData];
        
        NSError* error;
        success = [doc putProperties: metaData error: &error] != nil;
        if (!success) {
            if (outError) *outError = [NSError errorWithDomain: kCBLISErrorDomain
                                                          code: CBLIncrementalStoreErrorStoringMetadataFailed
                                                      userInfo: @{
                                                                  NSLocalizedDescriptionKey: @"Could not store metadata in database",
                                                                  NSUnderlyingErrorKey: error
                                                                  }];
            return NO;
        }
        
    } else {
        [self setMetadata: doc.properties];
        success = YES;
    }
    
    if (success) {
        // create a live-query for conflicting documents
        CBLQuery* query = [self.database createAllDocumentsQuery];
        query.allDocsMode = kCBLOnlyConflicts;
        CBLLiveQuery* liveQuery = query.asLiveQuery;
        [liveQuery addObserver: self forKeyPath: @"rows" options: NSKeyValueObservingOptionNew context: nil];
        [liveQuery start];
        
        _conflictsQuery = liveQuery;
    }
    
    return success;
}


- (void) notifyNewRevisionForManagedObject: (NSManagedObject*)object
                                 withRevId: (NSString*)revId
                               withContext: (NSManagedObjectContext*)context {
    [object willChangeValueForKey: kCBLISCurrentRevisionAttributeName];
    [object setPrimitiveValue:revId forKey: kCBLISCurrentRevisionAttributeName];
    [object didChangeValueForKey: kCBLISCurrentRevisionAttributeName];

    [object willChangeValueForKey: @"objectID"];
    [context obtainPermanentIDsForObjects: @[object] error: nil];
    [object didChangeValueForKey: @"objectID"];

    [context refreshObject: object mergeChanges: YES];
}


- (BOOL) insertOrUpdateObject: (NSManagedObject*)object
                  withContext: (NSManagedObjectContext*)context
                     outError: (NSError**)outError {
    NSDictionary* contents = [self couchbaseLiteRepresentationOfManagedObject: object
                                                          withCouchbaseLiteID: YES];
    CBLDocument* doc = [self.database documentWithID:
                        [object.objectID couchbaseLiteIDRepresentation]];
    CBLUnsavedRevision* revision = [doc newRevision];
    [revision.properties setValuesForKeysWithDictionary: contents];

    // add attachments
    NSDictionary* propertyDesc = [object.entity propertiesByName];

    for (NSString* property in propertyDesc) {
        if ([kCBLISCurrentRevisionAttributeName isEqual: property]) continue;

        NSAttributeDescription* attr = [propertyDesc objectForKey: property];
        if (![attr isKindOfClass: [NSAttributeDescription class]]) continue;

        if ([attr isTransient]) continue;
        if ([attr attributeType] != NSBinaryDataAttributeType) continue;

        NSData* data = [object valueForKey: attr.name];
        if (!data) continue;

        [revision setAttachmentNamed: attr.name
                     withContentType: @"application/binary"
                             content: data];
    }

    BOOL result = [revision save: outError] != nil;
    if (result) {
        [self notifyNewRevisionForManagedObject: object
                                      withRevId: doc.currentRevisionID
                                    withContext: context];
        [self purgeCachedObjectsForEntityName: object.entity.name];
    }
    return result;
}


- (BOOL) deleteObject: (NSManagedObject*)object
          withContext: (NSManagedObjectContext*)context
             outError: (NSError**)outError {
    CBLDocument* doc = [self.database existingDocumentWithID: [object.objectID couchbaseLiteIDRepresentation]];
    if (!doc || doc.isDeleted)
        return YES;
    
    BOOL result = [doc putProperties: [self propertiesForDeletingDocument: doc] error: outError] != nil;
    if (result) {
        [self purgeCachedObjectsForEntityName: object.entity.name];
    }
    return result;
}


- (id) executeSaveRequest: (NSSaveChangesRequest*)request
              withContext: (NSManagedObjectContext*)context
                 outError: (NSError**)outError {
    //
    // TODO: Execute all of the operations in one transaction once and return
    // the outError in a better way once
    // https://github.com/couchbase/couchbase-lite-ios/issues/256 gets resolved.
    //
    for (NSManagedObject* object in [request insertedObjects]) {
        [self insertOrUpdateObject:object withContext:context outError:outError];
    }

    for (NSManagedObject* object in [request updatedObjects]) {
        [self insertOrUpdateObject:object withContext:context outError:outError];
    }

    for (NSManagedObject* object in [request deletedObjects]) {
        [self deleteObject:object withContext:context outError:outError];
    }

    return @[];
}


- (id)executeRequest: (NSPersistentStoreRequest*)request
         withContext: (NSManagedObjectContext*)context
               error: (NSError**)outError {
    if (request.requestType == NSSaveRequestType) {
        NSSaveChangesRequest* saveRequest = (NSSaveChangesRequest*)request;
#ifdef DEBUG_DETAILS
        NSLog(@"[CBLIS] save request: ---------------- \n"
              "[CBLIS]   inserted:%@\n"
              "[CBLIS]   updated:%@\n"
              "[CBLIS]   deleted:%@\n"
              "[CBLIS]   locked:%@\n"
              "[CBLIS]---------------- ", [save insertedObjects], [save updatedObjects],
              [save deletedObjects], [save lockedObjects]);
#endif
        return [self executeSaveRequest: saveRequest withContext: context outError: outError];
    } else if (request.requestType == NSFetchRequestType) {
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();

        NSFetchRequest* fetchRequest = (NSFetchRequest*)request;
        id result = [self executeFetchWithRequest: fetchRequest withContext: context outError: outError];

        CFAbsoluteTime end = CFAbsoluteTimeGetCurrent();
#ifndef PROFILE
        if (end - start > 1) {
#endif
            NSLog(@"[CBLIS] fetch request ---------------- \n"
                  "[CBLIS]   entity-name:%@\n"
                  "[CBLIS]   resultType:%@\n"
                  "[CBLIS]   fetchPredicate: %@\n"
                  "[CBLIS] --> took %f seconds\n"
                  "[CBLIS]---------------- ",
                  fetchRequest.entity.name,
                  CBLISResultTypeName(fetchRequest.resultType),
                  fetchRequest.predicate, end - start);
#ifndef PROFILE
        }
#endif
        return result;
    } else {
        NSString* desc = [NSString stringWithFormat:@"Unsupported requestType: %d", (int)request.requestType];
        if (outError) *outError = [NSError errorWithDomain: kCBLISErrorDomain
                                                      code: CBLIncrementalStoreErrorUnsupportedRequestType
                                                  userInfo: @{ NSLocalizedFailureReasonErrorKey: desc }];
        return nil;
    }
}


- (NSIncrementalStoreNode*) newValuesForObjectWithID: (NSManagedObjectID*)objectID
                                         withContext: (NSManagedObjectContext*)context
                                               error: (NSError**)outError {
    CBLDocument* doc = [self.database documentWithID: [objectID couchbaseLiteIDRepresentation]];
    
    NSEntityDescription* entity = objectID.entity;
    if (![entity.name isEqual: [doc propertyForKey: kCBLISTypeKey]]) {
        entity = [NSEntityDescription entityForName: [doc propertyForKey: kCBLISTypeKey]
                             inManagedObjectContext: context];
    }
    
    NSDictionary* values = [self coreDataPropertiesOfDocumentWithID: doc.documentID
                                                         properties: doc.properties
                                                         withEntity: entity
                                                          inContext: context];
    NSIncrementalStoreNode* node = [[NSIncrementalStoreNode alloc] initWithObjectID: objectID
                                                                         withValues: values
                                                                            version: 1];
    return node;
}

- (id) newValueForRelationship: (NSRelationshipDescription*)relationship
               forObjectWithID: (NSManagedObjectID*)objectID
                   withContext: (NSManagedObjectContext*)context
                         error: (NSError**)outError {
    if ([relationship isToMany]) {
        CBLQueryEnumerator* rows = [self queryToManyRelation: relationship
                                               forParentKeys: @[[objectID couchbaseLiteIDRepresentation]]
                                                    prefetch: NO
                                                    outError: outError];
        if (!rows) return nil;
        NSMutableArray* result = [NSMutableArray arrayWithCapacity: rows.count];
        for (CBLQueryRow* row in rows) {
            [result addObject: [self newObjectIDForEntity: relationship.destinationEntity
                                     managedObjectContext: context
                                                  couchID: row.documentID]];
        }
        return result;
    } else {
        CBLDocument* doc = [self.database documentWithID: [objectID couchbaseLiteIDRepresentation]];
        NSString* destinationID = [doc propertyForKey: relationship.name];
        if (destinationID) {
            return [self newObjectIDForEntity: relationship.destinationEntity referenceObject: destinationID];
        } else {
            return [NSNull null];
        }
    }
}

- (NSArray*) obtainPermanentIDsForObjects: (NSArray*)array error: (NSError**)outError {
    NSMutableArray* result = [NSMutableArray arrayWithCapacity: array.count];
    for (NSManagedObject* object in array) {
        // if you call -[NSManagedObjectContext obtainPermanentIDsForObjects:error:] yourself,
        // this can get called with already permanent ids which leads to mismatch between store.
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

- (NSManagedObjectID*) newObjectIDForEntity: (NSEntityDescription*)entity referenceObject: (id)data {
    NSString* referenceObject = data;
    
    if ([referenceObject hasPrefix: @"p"]) {
        referenceObject = [referenceObject substringFromIndex: 1];
    }
    
    // we need to prefix the refernceObject with a non-numeric prefix, because of a bug where
    // referenceObjects starting with a digit will only use the first digit part. As described here:
    // https://github.com/AFNetworking/AFIncrementalStore/issues/82
    referenceObject = [kCBLISManagedObjectIDPrefix stringByAppendingString: referenceObject];
    NSManagedObjectID* objectID = [super newObjectIDForEntity: entity referenceObject: referenceObject];
    return objectID;
}

- (NSManagedObjectID*) newObjectIDForEntity: (NSEntityDescription*)entity
                       managedObjectContext: (NSManagedObjectContext*)context
                                    couchID: (NSString*)couchID {
    NSManagedObjectID* objectID = [self newObjectIDForEntity: entity referenceObject: couchID];
    return objectID;
}

#pragma mark - Views

/** Initializes the views needed for querying objects by type and for to-many relationships.*/
- (void) initializeViews {
    NSMutableDictionary* subentitiesToSuperentities = [NSMutableDictionary dictionary];

    // Create a view for each to-many relationship
    NSArray* entites = self.persistentStoreCoordinator.managedObjectModel.entities;
    for (NSEntityDescription* entity in entites) {
        NSArray* properties = [entity properties];

        for (NSPropertyDescription* property in properties) {
            if ([property isKindOfClass:[NSRelationshipDescription class]]) {
                NSRelationshipDescription* rel = (NSRelationshipDescription*)property;
                if (rel.isToMany && rel.inverseRelationship) {
                    NSMutableArray* entityNames =
                        [NSMutableArray arrayWithObject: rel.destinationEntity.name];
                    for (NSEntityDescription* subentity in rel.destinationEntity.subentities) {
                        [entityNames addObject: subentity.name];
                    }

                    NSString* viewName = CBLISToManyViewNameForRelationship(rel);
                    NSRelationshipDescription* invRel = rel.inverseRelationship;
                    NSString* invertRelPropName = invRel.name;
                    CBLView* view = [self.database viewNamed: viewName];
                    [view setMapBlock:^(NSDictionary* doc, CBLMapEmitBlock emit) {
                        NSString* type = [doc objectForKey: kCBLISTypeKey];
                        if (type && [entityNames containsObject: type] &&
                            [doc objectForKey: invertRelPropName]) {
                            emit([doc objectForKey: invertRelPropName], nil);
                        }
                    } version: @"1.0"];

                    // Remember view for mapping super-entity and all sub-entities:
                    for (NSString* entityName in entityNames) {
                        [self setViewName: viewName
                      forFetchingProperty: invertRelPropName
                               fromEntity: entityName];
                    }
                }
            }
        }
        
        if (entity.subentities.count > 0) {
            for (NSEntityDescription* subentity in entity.subentities) {
                [subentitiesToSuperentities setObject: entity.name forKey: subentity.name];
            }
        }
    }
}

- (void) defineFetchViewForEntity: (NSString*)entityName byProperty: (NSString*)propertyName {
    // This method is deprecated as we are now using CBLQueryBuilder
    // which dynamically generats the view based on query parameters
    // including predicate and sort descriptors.
}

#pragma mark - Query

- (NSArray*) executeFetchWithRequest: (NSFetchRequest*)request
                         withContext: (NSManagedObjectContext*)context
                            outError: (NSError**)outError {
    NSArray* cachedObjects = [self cachedObjectsForFetchRequest: request];
    if (cachedObjects) {
        NSArray* result = [self fetchResult: cachedObjects
                              forResultType: request.resultType
                      withPropertiesToFetch: request.propertiesToFetch
                                   outError: outError];
        return result;
    }

    BOOL useQueryBuilder = NO;
    NSPredicate* proPredicate = nil;
    NSMutableDictionary* templateVars = [NSMutableDictionary dictionary];
    if (request.predicate) {
        NSError* scanError;
        BOOL hasNonQueryBuilderExp;
        proPredicate = [self scanPredicate: request.predicate
                                withEntity: request.entity
                           outTemplateVars: templateVars
                  outHasNonQueryBuilderExp: &hasNonQueryBuilderExp
                                  outError: &scanError];

        if (proPredicate) {
            useQueryBuilder = !hasNonQueryBuilderExp;
        } else {
            if (outError) *outError = scanError;
            return nil;
        }
    }

    NSArray* objects;
    if (useQueryBuilder) {
        NSError* queryBuilderError;
        objects = [self fetchByUsingQueryBuilderWithPredicate: proPredicate
                                          withOriginalRequest: request
                                             withTemplateVars: templateVars
                                                  withContext: context
                                                     outError: &queryBuilderError];
        if (!objects) {
            useQueryBuilder = NO;
        }
    }

    if (!useQueryBuilder) {
        objects = [self fetchByEntityAndDoPostFilterWithRequest: request
                                                    withContext: context
                                                       outError: outError];
    }

    if (!objects) return nil;

    [self cacheObjects: objects forFetchRequest: request];

    NSArray* result = [self fetchResult: objects
                          forResultType: request.resultType
                  withPropertiesToFetch: request.propertiesToFetch
                               outError: outError];
    return result;
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
            NSDictionary* properties =
            [self couchbaseLiteRepresentationOfManagedObject: object withCouchbaseLiteID: YES];

            if (propertiesToFetch) {
                [result addObject: [properties dictionaryWithValuesForKeys: propertiesToFetch]];
            } else {
                [result addObject: properties];
            }
        }
        return result;
    } else {
        if (outError) {
            NSString* desc = [NSString stringWithFormat: @"Unsupported fetch request result type: %d", (int)type];
            *outError = [NSError errorWithDomain: kCBLISErrorDomain
                                            code: CBLIncrementalStoreErrorUnsupportedFetchRequestResultType
                                        userInfo: @{ NSLocalizedFailureReasonErrorKey: desc }];
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
    NSPredicate* typePredicate = [NSPredicate predicateWithFormat:@"%K == %@", kCBLISTypeKey,
                                  request.entityName];

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
            return nil;

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

    CBLQueryEnumerator* rows = [query run: outError];
    NSMutableArray* result = [NSMutableArray arrayWithCapacity: rows.count];
    for (CBLQueryRow* row in rows) {
        NSManagedObjectID* objectID = [self newObjectIDForEntity: request.entity
                                            managedObjectContext: context
                                                         couchID: row.documentID];
        [result addObject: [context objectWithID: objectID]];
    }
    return result;
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
                        [outTemplateVars setObject: lowerValue forKey: lowerVar];

                        id upperValue = [self scanConstantValue: constantValue[1]];
                        [outTemplateVars setObject: upperValue forKey: uppperVar];
                    } else {
                        NSMutableArray* values = [NSMutableArray array];
                        for (id value in constantValue) {
                            id exValue = [self scanConstantValue: value];
                            [values addObject: exValue];
                        }

                        NSString* varName = [self variableForKeyPath: keyPath
                                                              suffix: @"S"
                                                             current: outTemplateVars];
                        newExpression = [NSExpression expressionForVariable: varName];
                        [outTemplateVars setObject: values forKey: varName];
                    }
                } else {
                    NSString* varName = [self variableForKeyPath: keyPath
                                                          suffix: nil
                                                         current: outTemplateVars];
                    newExpression = [NSExpression expressionForVariable: varName];

                    id exValue = [self scanConstantValue: constantValue];
                    [outTemplateVars setObject: exValue forKey: varName];

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
        }
    }

    if (outHasNonQueryBuilderExp) {
        *outHasNonQueryBuilderExp = hasNonQueryBuilderExp;
    }

    if (!output && (outError && *outError == nil)) {
        NSString* desc = [NSString stringWithFormat:@"Unsupported predicate : %@", predicate];
        *outError = [NSError errorWithDomain: kCBLISErrorDomain
                                        code: CBLIncrementalStoreErrorUnsupportedPredicate
                                    userInfo: @{ NSLocalizedFailureReasonErrorKey: desc }];
        return nil;
    }

    return output;
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

    NSDictionary* properties = [entity propertiesByName];
    id propertyDesc = [properties objectForKey: keyPath];

    BOOL hasDotAccess = NO;
    if (!propertyDesc && [keyPath rangeOfString:@"."].location != NSNotFound) {
        hasDotAccess = YES;
        NSArray* components = [keyPath componentsSeparatedByString: @"."];
        NSArray* keyComponents = [components subarrayWithRange:
                                  NSMakeRange(0, components.count - 1)];
        keyPath = [keyComponents componentsJoinedByString: @"."];
        propertyDesc = [properties objectForKey: keyPath];
    }

    if (propertyDesc) {
        BOOL needJoins = NO;
        if ([propertyDesc isKindOfClass:[NSRelationshipDescription class]]) {
            NSRelationshipDescription* rel = (NSRelationshipDescription*)propertyDesc;
            needJoins = hasDotAccess || rel.toMany;
        }
        if (outNeedJoinsQuery)
            *outNeedJoinsQuery = needJoins;
    } else {
        keyPath = nil;
        if (outError) {
            NSString* desc = [NSString stringWithFormat: @"Predicate Keypath '%@' not found in the entity '%@'.",
                              expression.keyPath, entity.name];
            *outError = [NSError errorWithDomain: kCBLISErrorDomain
                                            code: CBLIncrementalStoreErrorPredicateKeyPathNotFoundInEntity
                                        userInfo: @{ NSLocalizedFailureReasonErrorKey: desc }];
        }
    }

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
        return [value couchbaseLiteIDRepresentation];
    else if ([value isKindOfClass: [NSManagedObject class]])
        return [[value objectID] couchbaseLiteIDRepresentation];
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
    NSPredicate* predicate = [NSPredicate predicateWithFormat: @"%K == %@", kCBLISTypeKey,
                                request.entityName];

    CBLQueryBuilder* builder = [self cachedQueryBuilderForPredicate: predicate
                                                    sortDescriptors: request.sortDescriptors];
    if (!builder) {
        builder = [[CBLQueryBuilder alloc] initWithDatabase: self.database
                                                     select: nil
                                             wherePredicate: predicate
                                                    orderBy: request.sortDescriptors
                                                      error: outError];
    }

    if (!builder)
        return nil;
    
    [self cacheQueryBuilder: builder
               forPredicate: predicate
            sortDescriptors: request.sortDescriptors];

    CBLQuery* query = [builder createQueryWithContext: nil];
    query.prefetch = request.predicate != nil;

    CBLQueryEnumerator* rows = [query run: outError];
    if (!rows) return nil;

    // Post filter:
    NSUInteger offset = 0;
    NSMutableArray* result = [NSMutableArray array];
    for (CBLQueryRow* row in rows) {
        if (!request.predicate ||
            [self evaluatePredicate: request.predicate
                         withEntity: request.entity
                     withProperties: row.documentProperties
                        withContext: context
                           outError: outError]) {
                if (offset >= request.fetchOffset) {
                    NSManagedObjectID* objectID = [self newObjectIDForEntity: request.entity
                                                        managedObjectContext: context
                                                                     couchID: row.documentID];
                    NSManagedObject* object = [context objectWithID: objectID];
                    [result addObject: object];
                }
                if (request.fetchLimit > 0 && result.count == request.fetchLimit) break;
                offset++;
            }
    }
    return result;
}

- (BOOL) evaluatePredicate: (NSPredicate*)predicate
                withEntity: (NSEntityDescription*)entity
            withProperties: (NSDictionary*)properties
               withContext: (NSManagedObjectContext*)context
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
                                      withContext: context
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
        BOOL toManySearch = [self isToManySearchExpression: comparisonPredicate.leftExpression withEntity: entity] ||
        [self isToManySearchExpression: comparisonPredicate.rightExpression withEntity: entity];
        if (toManySearch && !comparisonPredicate.comparisonPredicateModifier) {
            if (outError) {
                NSString* desc = [NSString stringWithFormat:@"Unsupported predicate : "
                                  "%@ (To-many key without ANY or ALL modifier is not allowed here.)", predicate];
                *outError = [NSError errorWithDomain: kCBLISErrorDomain
                                                code: CBLIncrementalStoreErrorUnsupportedPredicate
                                            userInfo: @{ NSLocalizedFailureReasonErrorKey: desc }];
            }
            return NO;
        }

        id leftValue = [self evaluateExpression: comparisonPredicate.leftExpression
                                     withEntity: entity
                                 withProperties: properties
                                    withContext: context];
        id rightValue = [self evaluateExpression: comparisonPredicate.rightExpression
                                      withEntity: entity
                                  withProperties: properties
                                     withContext: context];

        NSExpression* leftExpression = [NSExpression expressionForConstantValue: leftValue];
        NSExpression* rightExpression = [NSExpression expressionForConstantValue: rightValue];
        NSPredicate* comp = [NSComparisonPredicate predicateWithLeftExpression: leftExpression
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
        NSArray* keyProp = [self parseKeyAndPropertyFromKeyPath: expression.keyPath];
        if ([keyProp count] == 2)
            propertyDesc = [entity.propertiesByName objectForKey: keyProp[0]];
    }

    return propertyDesc &&
           [propertyDesc isKindOfClass:[NSRelationshipDescription class]] &&
           ((NSRelationshipDescription*)propertyDesc).isToMany;
}

- (NSArray*) parseKeyAndPropertyFromKeyPath: (NSString*)keyPath {
    if (!keyPath) return nil;

    if ([keyPath rangeOfString:@"."].location != NSNotFound) {
        NSArray* components = [keyPath componentsSeparatedByString: @"."];
        NSString* key = [[components subarrayWithRange: NSMakeRange(0, components.count - 1)]
                         componentsJoinedByString: @"."];
        NSString* property = [components lastObject];
        return @[key, property];
    } else {
        return @[keyPath];
    }
}

- (id) evaluateExpression: (NSExpression*)expression
               withEntity: (NSEntityDescription*)entity
           withProperties: (NSDictionary*)properties
              withContext: (NSManagedObjectContext* )context {
    id value = nil;
    switch (expression.expressionType) {
        case NSConstantValueExpressionType:
            value = [expression constantValue];
            break;
        case NSEvaluatedObjectExpressionType:
            value = properties;
            break;
        case NSKeyPathExpressionType: {
            NSPropertyDescription* propertyDesc = [entity.propertiesByName objectForKey: expression.keyPath];
            if (propertyDesc) {
                value = [properties objectForKey: expression.keyPath];
                if ([propertyDesc isKindOfClass: [NSAttributeDescription class]]) {
                    if (!value) break;

                    NSAttributeDescription* attr = (NSAttributeDescription* )propertyDesc;
                    value =  [self convertCoreDataValue: value toCouchbaseLiteValueOfType: attr.attributeType];
                } else if ([propertyDesc isKindOfClass: [NSRelationshipDescription class]]) {
                    NSRelationshipDescription* relationDesc = (NSRelationshipDescription*)propertyDesc;
                    if (!relationDesc.isToMany) {
                        if (!value) break;

                        NSString* childDocId = value;
                        NSManagedObjectID* objectID = [self newObjectIDForEntity: relationDesc.destinationEntity
                                                                 referenceObject: childDocId];
                        value = objectID ? [context existingObjectWithID: objectID error: nil] : nil;
                    } else {
                        NSString* parentDocId = [properties objectForKey: @"_id"];
                        if (parentDocId) {
                            CBLQueryEnumerator* rows = [self queryToManyRelation: relationDesc
                                                                   forParentKeys: @[parentDocId]
                                                                        prefetch: NO
                                                                        outError: nil];
                            if (rows) {
                                NSMutableArray* objects = [NSMutableArray array];
                                for (CBLQueryRow* row in rows) {
                                    NSManagedObjectID* objectID = [self newObjectIDForEntity: relationDesc.destinationEntity
                                                                             referenceObject: row.documentID];
                                    if (!objectID) continue;
                                    NSManagedObject* object = [context existingObjectWithID: objectID error: nil];
                                    if (object) [objects addObject: object];
                                }
                                value = objects;
                            }
                        }
                    }
                }
            } else if ([expression.keyPath rangeOfString:@"."].location != NSNotFound) {
                NSArray* keyProp = [self parseKeyAndPropertyFromKeyPath: expression.keyPath];
                if ([keyProp count] < 2) break;

                NSString* srcKeyPath = keyProp[0];
                NSString* destKeyPath = keyProp[1];

                propertyDesc = [entity.propertiesByName objectForKey: srcKeyPath];
                if (![propertyDesc isKindOfClass: [NSRelationshipDescription class]])
                    break;

                NSRelationshipDescription* relation = (NSRelationshipDescription*)propertyDesc;
                if (!relation.isToMany) {
                    NSString* childDocId = [properties objectForKey: srcKeyPath];
                    if (childDocId) {
                        CBLDocument* document = [self.database existingDocumentWithID: childDocId];
                        if (document)
                            value = [document.properties objectForKey: destKeyPath];
                    }
                } else {
                    NSString* parentDocId = [properties objectForKey: @"_id"];
                    if (parentDocId) {
                        CBLQueryEnumerator* rows = [self queryToManyRelation: relation
                                                               forParentKeys: @[parentDocId]
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
            break;
        default:
            NSAssert(NO, @"[devel] Expression Type not yet supported: %@", expression);
            break;
    }

    // not supported yet:
    //    NSFunctionExpressionType,
    //    NSAggregateExpressionType,
    //    NSSubqueryExpressionType = 13,
    //    NSUnionSetExpressionType,
    //    NSIntersectSetExpressionType,
    //    NSMinusSetExpressionType,
    //    NSBlockExpressionType = 19
    
    return value;
}

- (CBLQueryEnumerator*) queryToManyRelation: (NSRelationshipDescription*)relation
                              forParentKeys: (NSArray*)parentKeys
                                   prefetch: (BOOL)prefetch
                                   outError: (NSError**)outError {
    CBLView* view = [self.database existingViewNamed: CBLISToManyViewNameForRelationship(relation)];
    if (view) {
        CBLQuery* query = [view createQuery];
        query.keys = parentKeys;
        query.prefetch = prefetch;
        return [self queryEnumeratorForQuery: query error: outError];
    }
    return nil;
}

#pragma mark - Misc

- (id) convertCoreDataValue: (id)value toCouchbaseLiteValueOfType: (NSAttributeType)type {
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
            result = CBLISIsNull(value) ? @(NO) : value;
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

- (id) convertCouchbaseLiteValue: (id)value toCoreDataValueOfType: (NSAttributeType)type {
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

- (id) couchbaseLiteRepresentationOfManagedObject: (NSManagedObject*)object
                              withCouchbaseLiteID: (BOOL)withID {
    NSEntityDescription* desc = object.entity;
    NSDictionary* propertyDesc = [desc propertiesByName];

    NSMutableDictionary* proxy = [NSMutableDictionary dictionary];

    [proxy setObject:desc.name
              forKey:kCBLISTypeKey];

    if ([propertyDesc objectForKey: kCBLISCurrentRevisionAttributeName]) {
        id rev = [object valueForKey: kCBLISCurrentRevisionAttributeName];
        if (!CBLISIsNull(rev)) {
            [proxy setObject: rev forKey: @"_rev"];
        }
    }
    
    if (withID) {
        [proxy setObject: [object.objectID couchbaseLiteIDRepresentation] forKey: @"_id"];
    }
    
    for (NSString* property in propertyDesc) {
        if ([kCBLISCurrentRevisionAttributeName isEqual: property]) continue;
        
        id desc = [propertyDesc objectForKey: property];
        
        if ([desc isKindOfClass: [NSAttributeDescription class]]) {
            NSAttributeDescription* attr = desc;
            
            if ([attr isTransient]) {
                continue;
            }
            
            // skip binary attributes to not load them into memory here. They are added as attachments
            if ([attr attributeType] == NSBinaryDataAttributeType) {
                continue;
            }
            
            id value = [object valueForKey: property];
            
            if (value) {
                NSAttributeType attributeType = [attr attributeType];
                
                if (attr.valueTransformerName) {
                    NSValueTransformer* transformer = [NSValueTransformer valueTransformerForName: attr.valueTransformerName];

                    if (!transformer) {
                        WARN(@"Value transformer for attribute %@ with name %@ not found", attr.name, attr.valueTransformerName);
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
                        WARN(@"Unsupported value transformer transformedValueClass: %@", NSStringFromClass(transformedClass));
                        continue;
                    }
                }
                
                value = [self convertCoreDataValue: value toCouchbaseLiteValueOfType: attributeType];
                if (value) {
                    [proxy setObject: value forKey: property];
                }
            }
        } else if ([desc isKindOfClass: [NSRelationshipDescription class]]) {
            NSRelationshipDescription* rel = desc;
            id relationshipDestination = [object valueForKey: property];
            if (relationshipDestination) {
                if (![rel isToMany]) {
                    NSManagedObjectID* objectID = [relationshipDestination valueForKey: @"objectID"];
                    [proxy setObject: [objectID couchbaseLiteIDRepresentation] forKey: property];
                }
            }
        }
    }
    
    return proxy;
}

- (NSDictionary*) coreDataPropertiesOfDocumentWithID: (NSString*)documentID
                                          properties: (NSDictionary*)properties
                                          withEntity: (NSEntityDescription*)entity
                                           inContext: (NSManagedObjectContext*)context {
    NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity: properties.count];
    
    NSDictionary* propertyDesc = [entity propertiesByName];
    
    for (NSString* property in propertyDesc) {
        id desc = [propertyDesc objectForKey: property];
        
        if ([desc isKindOfClass: [NSAttributeDescription class]]) {
            NSAttributeDescription* attr = desc;
            
            if ([attr isTransient]) {
                continue;
            }
            
            // handle binary attributes specially
            if ([attr attributeType] == NSBinaryDataAttributeType) {
                id value = [self loadDataForAttachmentWithName: property ofDocumentWithID: documentID];
                if (value) {
                    [result setObject: value forKey: property];
                }
                
                continue;
            }
            
            id value = nil;
            if ([kCBLISCurrentRevisionAttributeName isEqual: property]) {
                value = [properties objectForKey: @"_rev"];
            } else {
                value = [properties objectForKey: property];
            }
            
            if (value) {
                NSAttributeType attributeType = [attr attributeType];
                
                if (attr.valueTransformerName) {
                    NSValueTransformer* transformer = [NSValueTransformer valueTransformerForName: attr.valueTransformerName];
                    Class transformedClass = [[transformer class] transformedValueClass];
                    if (transformedClass == [NSString class]) {
                        value = [transformer reverseTransformedValue: value];
                    } else if (transformedClass == [NSData class]) {
                        value = [transformer reverseTransformedValue: [[NSData alloc]initWithBase64EncodedString: value options: 0]];
                    } else {
                        INFO(@"Unsupported value transformer transformedValueClass: %@", NSStringFromClass(transformedClass));
                        continue;
                    }
                }

                value = [self convertCouchbaseLiteValue: value toCoreDataValueOfType: attributeType];

                if (value) {
                    [result setObject: value forKey: property];
                }
            }
        } else if ([desc isKindOfClass: [NSRelationshipDescription class]]) {
            NSRelationshipDescription* rel = desc;
            
            if (![rel isToMany]) { // only handle to-one relationships
                id value = [properties objectForKey: property];
                
                if (!CBLISIsNull(value)) {
                    NSManagedObjectID* destination = [self newObjectIDForEntity: rel.destinationEntity
                                                                referenceObject: value];
                    
                    [result setObject: destination forKey: property];
                }
            }
        }
    }
    
    return result;
}

/** Convenience method to execute a CouchbaseLite query and build a telling NSError if it fails.*/
- (CBLQueryEnumerator*) queryEnumeratorForQuery: (CBLQuery*)query error: (NSError**)outError {
    NSError* error;
    CBLQueryEnumerator* rows = [query run: &error];
    if (!rows) {
        if (outError) *outError = [NSError errorWithDomain: kCBLISErrorDomain
                                                      code: CBLIncrementalStoreErrorQueryingCouchbaseLiteFailed
                                                  userInfo: @{
                                                              NSLocalizedFailureReasonErrorKey: @"Error querying CouchbaseLite",
                                                              NSUnderlyingErrorKey: error
                                                              }];
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

#pragma mark - Views

- (void) setViewName: (NSString*)viewName forFetchingProperty: (NSString*)propertyName fromEntity: (NSString*)entity {
    [_entityAndPropertyToFetchViewName setObject: viewName
                                          forKey: [NSString stringWithFormat:@"%@_%@", entity, propertyName]];
}

#pragma mark - Attachments

- (NSData*) loadDataForAttachmentWithName: (NSString*)name ofDocumentWithID: (NSString*)documentID {
    CBLDocument* document = [self.database documentWithID: documentID];
    CBLAttachment* attachment = [document.currentRevision attachmentNamed: name];
    return attachment.content;
}

#pragma mark - Change Handling

- (void) addObservingManagedObjectContext:(NSManagedObjectContext*)context {
    if (!_observingManagedObjectContexts) {
        _observingManagedObjectContexts = [[NSHashTable alloc] initWithOptions: NSPointerFunctionsWeakMemory capacity:10];
    }
    [_observingManagedObjectContexts addObject:context];
}

- (void) removeObservingManagedObjectContext:(NSManagedObjectContext*)context {
    [_observingManagedObjectContexts removeObject:context];
}

- (void) informManagedObjectContext: (NSManagedObjectContext*)context updatedIDs: (NSArray*)updatedIDs deletedIDs: (NSArray*)deletedIDs {
    NSMutableDictionary* userInfo = [NSMutableDictionary dictionaryWithCapacity: 3];
    NSMutableSet* updatedEntities = [NSMutableSet set];

    if (updatedIDs.count > 0) {
        NSMutableArray* updated = [NSMutableArray arrayWithCapacity: updatedIDs.count];
        NSMutableArray* inserted = [NSMutableArray arrayWithCapacity: updatedIDs.count];
        
        for (NSManagedObjectID* mocid in updatedIDs) {
            NSManagedObject* moc = [context objectRegisteredForID: mocid];
            if (!moc) {
                moc = [context objectWithID: mocid];
                [inserted addObject: moc];
            } else {
                [context refreshObject: moc mergeChanges: YES];
                [updated addObject: moc];
            }

            // Ensure that a fault has been fired:
            [moc willAccessValueForKey: nil];
            [context refreshObject: moc mergeChanges: YES];

            [updatedEntities addObject: moc.entity.name];
        }
        [userInfo setObject: updated forKey: NSUpdatedObjectsKey];
        if (inserted.count > 0) {
            [userInfo setObject: inserted forKey: NSInsertedObjectsKey];
        }
    }
    
    if (deletedIDs.count > 0) {
        NSMutableArray* deleted = [NSMutableArray arrayWithCapacity: deletedIDs.count];
        for (NSManagedObjectID* mocid in deletedIDs) {
            NSManagedObject* moc = [context objectWithID: mocid];
            [context deleteObject: moc];
            // load object again to get a fault
            [deleted addObject: [context objectWithID: mocid]];

            [updatedEntities addObject: moc.entity.name];
        }
        [userInfo setObject: deleted forKey: NSDeletedObjectsKey];
    }

    // Clear cache:
    for (NSString* entity in updatedEntities) {
        [self purgeCachedObjectsForEntityName: entity];
    }

    NSNotification* didUpdateNote = [NSNotification notificationWithName: NSManagedObjectContextObjectsDidChangeNotification
                                                                  object: context
                                                                userInfo: userInfo];
    [context mergeChangesFromContextDidSaveNotification: didUpdateNote];
}

- (void) informObservingManagedObjectContextsAboutUpdatedIDs: (NSArray*)updatedIDs deletedIDs: (NSArray*)deletedIDs {
    for (NSManagedObjectContext* context in self.observingManagedObjectContexts) {
        [self informManagedObjectContext: context updatedIDs: updatedIDs deletedIDs: deletedIDs];
    }
}

- (void) couchDocumentsChanged: (NSArray*)changes {
#if CBLIS_NO_CHANGE_COALESCING
    [_coalescedChanges addObjectsFromArray: changes];
    [self processCouchbaseLiteChanges];
#else
    [NSThread cancelPreviousPerformRequestsWithTarget: self selector: @selector(processCouchbaseLiteChanges) object: nil];
    
    @synchronized(self) {
        [_coalescedChanges addObjectsFromArray: changes];
    }
    
    [self performSelector: @selector(processCouchbaseLiteChanges) withObject: nil afterDelay: 0.1];
#endif
}

- (void) processCouchbaseLiteChanges {
    NSArray* changes = nil;
    @synchronized(self) {
        changes = _coalescedChanges;
        _coalescedChanges = [[NSMutableArray alloc] initWithCapacity: 20];
    }
    
    NSMutableSet* changedEntitites = [NSMutableSet setWithCapacity: changes.count];
    NSMutableArray* deletedObjectIDs = [NSMutableArray array];
    NSMutableArray* updatedObjectIDs = [NSMutableArray array];
    
    for (CBLDatabaseChange* change in changes) {
        if (!change.isCurrentRevision) continue;
        if ([change.documentID hasPrefix: @"CBLIS"]) continue;
        
        CBLDocument* doc = [self.database documentWithID: change.documentID];
        CBLRevision* rev = [doc revisionWithID: change.revisionID];
        
        BOOL deleted = rev.isDeletion;

        NSDictionary* properties = [rev properties];
        
        NSString* type = [properties objectForKey: kCBLISTypeKey];
        NSString* reference = change.documentID;
        
        NSEntityDescription* entity = [self.persistentStoreCoordinator.managedObjectModel.entitiesByName objectForKey: type];
        NSManagedObjectID* objectID = [self newObjectIDForEntity: entity referenceObject: reference];
        
        if (deleted) {
            [deletedObjectIDs addObject: objectID];
        } else {
            [updatedObjectIDs addObject: objectID];
        }

        [changedEntitites addObject: type];
    }
    
    [self informObservingManagedObjectContextsAboutUpdatedIDs: updatedObjectIDs deletedIDs: deletedObjectIDs];
    
    NSDictionary* userInfo = @{
                               NSDeletedObjectsKey: deletedObjectIDs,
                               NSUpdatedObjectsKey: updatedObjectIDs
                               };
    
    [[NSNotificationCenter defaultCenter] postNotificationName: kCBLISObjectHasBeenChangedInStoreNotification
                                                        object: self
                                                      userInfo: userInfo];
}

- (void) stop {
#if !CBLIS_NO_CHANGE_COALESCING
    [NSThread cancelPreviousPerformRequestsWithTarget: self
                                             selector: @selector(processCouchbaseLiteChanges)
                                               object: nil];
    if (_coalescedChanges.count > 0) {
        [self processCouchbaseLiteChanges];
    }
#endif
}

#pragma mark - Conflicts handling

- (void) observeValueForKeyPath: (NSString*)keyPath ofObject: (id)object change: (NSDictionary*)change context: (void*)context {
    if ([@"rows" isEqualToString: keyPath]) {
        CBLLiveQuery* query = object;
        
        NSError* error;
        CBLQueryEnumerator* enumerator = [query run: &error];
        
        if (enumerator.count == 0) return;
        
        [self resolveConflicts: enumerator];
    }
}

- (void) resolveConflicts: (CBLQueryEnumerator*)enumerator {
    // resolve conflicts
    for (CBLQueryRow* row in enumerator) {
        if ([kCBLISMetadataDocumentID isEqual: row.documentID]) {
            // TODO: what to do here?
            continue;
        }
        
        if (self.conflictHandler) self.conflictHandler(row.conflictingRevisions);
    }
}

- (CBLISConflictHandler) defaultConflictHandler {
    CBLISConflictHandler handler = ^(NSArray* conflictingRevisions) {
        // merges changes by
        // - taking the winning revision
        // - adding missing values from other revisions (starting with biggest version)
        CBLRevision* winning = conflictingRevisions[0];
        NSMutableDictionary* properties = [winning.properties mutableCopy];
        
        NSRange otherRevisionsRange = NSMakeRange(1, conflictingRevisions.count - 1);
        NSArray* otherRevisions = [conflictingRevisions subarrayWithRange: otherRevisionsRange];
        
        NSArray* desc = @[[NSSortDescriptor sortDescriptorWithKey: @"revisionID"
                                                        ascending: NO]];
        NSArray* sortedRevisions = [otherRevisions sortedArrayUsingDescriptors: desc];
        
        // this solution merges missing keys from other conflicting revisions to not loose any values
        for (CBLRevision* rev in sortedRevisions) {
            for (NSString* key in rev.properties) {
                if ([key hasPrefix: @"_"]) continue;
                
                if (![properties objectForKey:key]) {
                    [properties setObject:[rev propertyForKey: key] forKey: key];
                }
            }
        }
        
        // TODO: Attachments
        
        CBLUnsavedRevision* newRevision = [winning.document newRevision];
        [newRevision setProperties: properties];
        
        NSError* error;
        [newRevision save: &error];
    };
    return handler;
}

#pragma mark -

/** Returns the properties that are stored for deleting a document. Must contain at least "_rev" and "_deleted" = true for 
 *  CouchbaseLite and kCBLISTypeKey for this store. Can be overridden if you need more for filtered syncing, for example.
 */
- (NSDictionary*) propertiesForDeletingDocument: (CBLDocument*)doc {
    NSDictionary* contents = @{
                               @"_deleted": @YES,
                               @"_rev": [doc propertyForKey:@"_rev"],
                               kCBLISTypeKey: [doc propertyForKey:kCBLISTypeKey]
                               };
    return contents;
}

@end


@implementation NSManagedObjectID (CBLIncrementalStore)

/** Returns an internal representation of this objectID that is used as _id in Couchbase. */
- (NSString*) couchbaseLiteIDRepresentation {
    // +1 because of "p" prefix in managed object IDs
    NSString* uuid = [[self.URIRepresentation lastPathComponent] substringFromIndex: kCBLISManagedObjectIDPrefix.length + 1];
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
    return [NSString stringWithFormat: kCBLISFetchEntityToManyViewNameFormat, entityName, destinationName];
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
