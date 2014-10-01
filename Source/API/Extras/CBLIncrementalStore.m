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

#if !__has_feature(objc_arc)
#  error This class requires ARC!
#endif


NSString * const kCBLISErrorDomain = @"CBLISErrorDomain";
NSString * const kCBLISObjectHasBeenChangedInStoreNotification = @"kCBLISObjectHasBeenChangedInStoreNotification";

static NSString * const kCBLISTypeKey = @"CBLIS_type";
static NSString * const kCBLISCurrentRevisionAttributeName = @"CBLIS_Rev";
static NSString * const kCBLISManagedObjectIDPrefix = @"CBL";
static NSString * const kCBLISMetadataDocumentID = @"CBLIS_metadata";
static NSString * const kCBLISAllByTypeViewName = @"CBLIS/allByType";
static NSString * const kCBLISFetchEntityByPropertyViewNameFormat = @"CBLIS/fetch_%@_by_%@";
static NSString * const kCBLISFetchEntityToManyViewNameFormat = @"CBLIS/%@_tomany_%@";


// utility functions
static BOOL CBLISIsNull(id value);
static NSString *CBLISToManyViewNameForRelationship(NSRelationshipDescription *relationship);
static NSString *CBLISResultTypeName(NSFetchRequestResultType resultType);


@interface NSManagedObjectID (CBLIncrementalStore)
- (NSString*) couchbaseLiteIDRepresentation;
@end


@interface CBLIncrementalStore ()

// TODO: check if there is a better way to not hold strong references on these MOCs
@property (nonatomic, strong) NSHashTable *observingManagedObjectContexts;

@property (nonatomic, strong, readwrite) CBLDatabase *database;
@property (nonatomic, strong)            id changeObserver;

@end

@implementation CBLIncrementalStore
{
    NSMutableArray      *_coalescedChanges;
    NSMutableDictionary *_fetchRequestResultCache;
    NSMutableDictionary *_entityAndPropertyToFetchViewName;
    
    CBLLiveQuery        *_conflictsQuery;
}

@synthesize database = _database;
@synthesize changeObserver = _changeObserver;
@synthesize conflictHandler = _conflictHandler;

@synthesize observingManagedObjectContexts = _observingManagedObjectContexts;


#pragma mark - Convenience Method

+ (NSManagedObjectContext*) createManagedObjectContextWithModel:(NSManagedObjectModel*)managedObjectModel
                                                   databaseName:(NSString*)databaseName
                                                          error:(NSError**)outError
{
    return [self createManagedObjectContextWithModel:managedObjectModel databaseName:databaseName
                              importingDatabaseAtURL:nil importType:nil error:outError];
}
+ (NSManagedObjectContext*) createManagedObjectContextWithModel:(NSManagedObjectModel*)managedObjectModel
                                                   databaseName:(NSString*)databaseName
                                         importingDatabaseAtURL:(NSURL*)importUrl
                                                     importType:(NSString*)importType
                                                          error:(NSError**)outError
{
    NSManagedObjectModel *model = [managedObjectModel mutableCopy];
    
    [self updateManagedObjectModel:model];
    
    NSError *error;
    
    NSPersistentStoreCoordinator *persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    
    NSDictionary *options = @{
                              NSMigratePersistentStoresAutomaticallyOption : @YES,
                              NSInferMappingModelAutomaticallyOption : @YES
                              };
    
    CBLIncrementalStore *store = nil;
    if (importUrl) {
        
        NSPersistentStore *oldStore = [persistentStoreCoordinator addPersistentStoreWithType:importType configuration:nil
                                                                                         URL:importUrl options:options error:&error];
        if (!oldStore) {
            if (outError) *outError = [NSError errorWithDomain:kCBLISErrorDomain
                                                          code:CBLIncrementalStoreErrorMigrationOfStoreFailed
                                                      userInfo:@{
                                                                 NSLocalizedDescriptionKey: @"Couldn't open store to import",
                                                                 NSUnderlyingErrorKey: error
                                                                 }];
            return nil;
        }
        
        store = (CBLIncrementalStore*)[persistentStoreCoordinator migratePersistentStore:oldStore
                                                                                   toURL:[NSURL URLWithString:databaseName] options:options
                                                                                withType:[self type] error:&error];
        
        if (!store) {
            NSString *errorDescription = [NSString stringWithFormat:@"Migration of store at URL %@ failed: %@", importUrl, error.description];
            if (outError) *outError = [NSError errorWithDomain:kCBLISErrorDomain
                                                          code:CBLIncrementalStoreErrorMigrationOfStoreFailed
                                                      userInfo:@{
                                                                 NSLocalizedDescriptionKey: errorDescription,
                                                                 NSUnderlyingErrorKey: error
                                                                 }];
            return nil;
        }
        
    } else {
        store = (CBLIncrementalStore*)[persistentStoreCoordinator addPersistentStoreWithType:[self type]
                                                                               configuration:nil URL:[NSURL URLWithString:databaseName]
                                                                                     options:options error:&error];
        
        if (!store) {
            NSString *errorDescription = [NSString stringWithFormat:@"Initialization of store failed: %@", error.description];
            if (outError) *outError = [NSError errorWithDomain:kCBLISErrorDomain
                                                          code:CBLIncrementalStoreErrorCreatingStoreFailed
                                                      userInfo:@{
                                                                 NSLocalizedDescriptionKey: errorDescription,
                                                                 NSUnderlyingErrorKey: error
                                                                 }];
            return nil;
        }
    }
    
    
    
    NSManagedObjectContext *managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    [managedObjectContext setPersistentStoreCoordinator:persistentStoreCoordinator];
    
    [store addObservingManagedObjectContext:managedObjectContext];
    
    return managedObjectContext;
}

#pragma mark -

+ (void)initialize
{
    if ([[self class] isEqual:[CBLIncrementalStore class]]) {
        [NSPersistentStoreCoordinator registerStoreClass:self
                                            forStoreType:[self type]];
    }
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self.changeObserver];
    
    [_conflictsQuery stop];
    [_conflictsQuery removeObserver:self forKeyPath:@"rows"];
    _conflictsQuery = nil;
    
    self.database = nil;
}

/**
 * This method has to be called once, before the NSManagedObjectModel is used by a NSPersistentStoreCoordinator. This method updates
 * the entities in the managedObjectModel and adds some required properties.
 *
 * @param managedObjectModel the managedObjectModel to use with this store
 */
+ (void) updateManagedObjectModel:(NSManagedObjectModel*)managedObjectModel
{
    NSArray *entites = managedObjectModel.entities;
    for (NSEntityDescription *entity in entites) {
        
        if (entity.superentity) { // only add to super-entities, not the sub-entities
            continue;
        }
        
        NSMutableArray *properties = [entity.properties mutableCopy];
        
        for (NSPropertyDescription *prop in properties) {
            if ([prop.name isEqual:kCBLISCurrentRevisionAttributeName]) {
                return;
            }
        }
        
        NSAttributeDescription *revAttribute = [NSAttributeDescription new];
        revAttribute.name = kCBLISCurrentRevisionAttributeName;
        revAttribute.attributeType = NSStringAttributeType;
        revAttribute.optional = YES;
        revAttribute.indexed = YES;
        
        [properties addObject:revAttribute];
        
        entity.properties = properties;
    }
}

#pragma mark - NSPersistentStore

+ (NSString *)type
{
    return @"CBLIncrementalStore";
}

- (id)initWithPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)root
                       configurationName:(NSString *)name
                                     URL:(NSURL *)url options:(NSDictionary *)options
{
    self = [super initWithPersistentStoreCoordinator:root configurationName:name URL:url options:options];
    if (!self) return nil;
    
    _coalescedChanges = [[NSMutableArray alloc] init];
    _fetchRequestResultCache = [[NSMutableDictionary alloc] init];
    _entityAndPropertyToFetchViewName = [[NSMutableDictionary alloc] init];
    
    self.conflictHandler = [self _defaultConflictHandler];
    
    return self;
}

#pragma mark - NSIncrementalStore

-(BOOL)loadMetadata:(NSError **)outError
{
    // check data model if compatible with this store
    NSArray *entites = self.persistentStoreCoordinator.managedObjectModel.entities;
    for (NSEntityDescription *entity in entites) {
        
        NSDictionary *attributesByName = [entity attributesByName];
        
        if (![attributesByName objectForKey:kCBLISCurrentRevisionAttributeName]) {
            if (outError) *outError = [NSError errorWithDomain:kCBLISErrorDomain
                                                          code:CBLIncrementalStoreErrorDatabaseModelIncompatible
                                                      userInfo:@{
                                                                 NSLocalizedFailureReasonErrorKey: @"Database Model not compatible. You need to call +[updateManagedObjectModel:]."
                                                                 }];
            return NO;
        }
    }
    
    
    NSError *error;
    
    NSString *databaseName = [self.URL lastPathComponent];
    
    CBLManager *manager = [CBLManager sharedInstance];
    if (!manager) {
        if (outError) *outError = [NSError errorWithDomain:kCBLISErrorDomain
                                                      code:CBLIncrementalStoreErrorCBLManagerSharedInstanceMissing
                                                  userInfo:@{
                                                             NSLocalizedDescriptionKey: @"No CBLManager shared instance available"
                                                             }];
        return NO;
    }
    
    self.database = [manager databaseNamed:databaseName error:&error];
    if (!self.database) {
        if (outError) *outError = [NSError errorWithDomain:kCBLISErrorDomain
                                                      code:CBLIncrementalStoreErrorCreatingDatabaseFailed
                                                  userInfo:@{
                                                             NSLocalizedDescriptionKey: @"Could not create database",
                                                             NSUnderlyingErrorKey: error
                                                             }];
        return NO;
    }
    
    [self _initializeViews];
    
    
    __weak __typeof(self) _self = self;
    self.changeObserver = [[NSNotificationCenter defaultCenter] addObserverForName:kCBLDatabaseChangeNotification
                                                                            object:self.database queue:nil
                                                                        usingBlock:^(NSNotification *note) {
                                                                            NSArray *changes = note.userInfo[@"changes"];
                                                                            [_self _couchDocumentsChanged:changes];
                                                                        }];
    
    CBLDocument *doc = [self.database documentWithID:kCBLISMetadataDocumentID];
    
    BOOL success = NO;
    
    NSDictionary *metaData = doc.properties;
    if (![metaData objectForKey:NSStoreUUIDKey]) {
        
        metaData = @{
                     NSStoreUUIDKey: [[NSProcessInfo processInfo] globallyUniqueString],
                     NSStoreTypeKey: [[self class] type]
                     };
        [self setMetadata:metaData];
        
        NSError *error;
        success = [doc putProperties:metaData error:&error] != nil;
        if (!success) {
            if (outError) *outError = [NSError errorWithDomain:kCBLISErrorDomain
                                                          code:CBLIncrementalStoreErrorStoringMetadataFailed
                                                      userInfo:@{
                                                                 NSLocalizedDescriptionKey: @"Could not store metadata in database",
                                                                 NSUnderlyingErrorKey: error
                                                                 }];
            return NO;
            
        }
        
    } else {
        
        [self setMetadata:doc.properties];
        
        success = YES;
        
    }
    
    if (success) {
        // create a live-query for conflicting documents
        CBLQuery* query = [self.database createAllDocumentsQuery];
        query.allDocsMode = kCBLOnlyConflicts;
        CBLLiveQuery *liveQuery = query.asLiveQuery;
        [liveQuery addObserver:self forKeyPath:@"rows" options:NSKeyValueObservingOptionNew context:nil];
        [liveQuery start];
        
        _conflictsQuery = liveQuery;
    }
    
    return success;
}

- (id)executeRequest:(NSPersistentStoreRequest *)request withContext:(NSManagedObjectContext*)context error:(NSError **)outError
{
    if (request.requestType == NSSaveRequestType) {
        
        NSSaveChangesRequest *save = (NSSaveChangesRequest*)request;
        
#ifdef DEBUG_DETAILS
        NSLog(@"[tdis] save request: ---------------- \n"
              "[tdis]   inserted:%@\n"
              "[tdis]   updated:%@\n"
              "[tdis]   deleted:%@\n"
              "[tdis]   locked:%@\n"
              "[tids]---------------- ", [save insertedObjects], [save updatedObjects], [save deletedObjects], [save lockedObjects]);
#endif
        
        // TODO: Check if using the CouchbaseLite transaction mechanism makes sense here.
        
        NSError *error;
        
        NSMutableSet *changedEntities = [NSMutableSet setWithCapacity:[save insertedObjects].count];
        
        // Objects that were inserted...
        for (NSManagedObject *object in [save insertedObjects]) {
            NSDictionary *contents = [self _couchbaseLiteRepresentationOfManagedObject:object withCouchbaseLiteID:YES];
            
            CBLDocument *doc = [self.database documentWithID:[object.objectID couchbaseLiteIDRepresentation]];
            CBLUnsavedRevision *revision = [doc newRevision];
            [revision.properties setValuesForKeysWithDictionary:contents];
            
            
            // add attachments
            NSDictionary *propertyDesc = [object.entity propertiesByName];

            for (NSString *property in propertyDesc) {
                if ([kCBLISCurrentRevisionAttributeName isEqual:property]) continue;
                
                NSAttributeDescription *attr = [propertyDesc objectForKey:property];
                if (![attr isKindOfClass:[NSAttributeDescription class]]) continue;
                
                if ([attr isTransient]) continue;
                if ([attr attributeType] != NSBinaryDataAttributeType) continue;
                
                NSData *data = [object valueForKey:attr.name];
                if (!data) continue;
                
                [revision setAttachmentNamed:attr.name withContentType:@"application/binary"
                                     content:data];
            }
            
            
            if ([revision save:&error]) {
                [changedEntities addObject:object.entity.name];
                
                [object willChangeValueForKey:kCBLISCurrentRevisionAttributeName];
                [object setPrimitiveValue:doc.currentRevisionID forKey:kCBLISCurrentRevisionAttributeName];
                [object didChangeValueForKey:kCBLISCurrentRevisionAttributeName];
                
                [object willChangeValueForKey:@"objectID"];
                [context obtainPermanentIDsForObjects:@[object] error:nil];
                [object didChangeValueForKey:@"objectID"];
                
                [context refreshObject:object mergeChanges:YES];
            } else {
                if (outError) *outError = [NSError errorWithDomain:kCBLISErrorDomain
                                                              code:CBLIncrementalStoreErrorPersistingInsertedObjectsFailed
                                                          userInfo:@{
                                                                     NSLocalizedFailureReasonErrorKey: @"Error persisting inserted objects",
                                                                     NSUnderlyingErrorKey:error
                                                                     }];
            }
        }
        
        // Objects that were updated...
        for (NSManagedObject *object in [save updatedObjects]) {
            NSDictionary *contents = [self _couchbaseLiteRepresentationOfManagedObject:object withCouchbaseLiteID:YES];
            
            CBLDocument *doc = [self.database documentWithID:[object.objectID couchbaseLiteIDRepresentation]];
            CBLUnsavedRevision *revision = [doc newRevision];
            [revision.properties setValuesForKeysWithDictionary:contents];
            
            
            // update attachments
            NSDictionary *propertyDesc = [object.entity propertiesByName];
            
            for (NSString *property in [[object changedValues] allKeys]) {
                if ([kCBLISCurrentRevisionAttributeName isEqual:property]) continue;
                
                NSAttributeDescription *attr = [propertyDesc objectForKey:property];
                if (![attr isKindOfClass:[NSAttributeDescription class]]) continue;
                
                if ([attr isTransient]) continue;
                if ([attr attributeType] != NSBinaryDataAttributeType) continue;
                
                NSData *data = [object valueForKey:attr.name];
                
                if (data) {
                    [revision setAttachmentNamed:attr.name withContentType:@"application/binary"
                                         content:data];
                } else {
                    [revision removeAttachmentNamed:attr.name];
                }
            }
            
            
            if ([revision save:&error]) {
                [changedEntities addObject:object.entity.name];
                
                [object willChangeValueForKey:kCBLISCurrentRevisionAttributeName];
                [object setPrimitiveValue:doc.currentRevisionID forKey:kCBLISCurrentRevisionAttributeName];
                [object didChangeValueForKey:kCBLISCurrentRevisionAttributeName];
                
                [context refreshObject:object mergeChanges:YES];
            } else {
                if (outError) *outError = [NSError errorWithDomain:kCBLISErrorDomain
                                                              code:CBLIncrementalStoreErrorPersistingUpdatedObjectsFailed
                                                          userInfo:@{
                                                                     NSLocalizedFailureReasonErrorKey: @"Error persisting updated object",
                                                                     NSUnderlyingErrorKey:error
                                                                     }];
            }
        }
        
        
        // Objects that were deleted from the calling context...
        for (NSManagedObject *object in [save deletedObjects]) {
            // doesn't delete the document the normal way, but marks it as deleted to keep the type field needed for notifying Core Data.
            CBLDocument *doc = [self.database documentWithID:[object.objectID couchbaseLiteIDRepresentation]];
            NSDictionary *contents = [self _propertiesForDeletingDocument:doc];
            if (![doc putProperties:contents error:&error]) {
                if (outError) *outError = [NSError errorWithDomain:kCBLISErrorDomain
                                                              code:CBLIncrementalStoreErrorPersistingDeletedObjectsFailed
                                                          userInfo:@{
                                                                     NSLocalizedFailureReasonErrorKey: @"Error deleting object",
                                                                     NSUnderlyingErrorKey:error
                                                                     }];
            }
        }
        
        // clear cache for entities to get changes
        for (NSString *entityName in changedEntities) {
            [self _purgeCacheForEntityName:entityName];
        }
        
        return @[];
        
        
    } else if (request.requestType == NSFetchRequestType) {
        
        NSFetchRequest *fetch = (NSFetchRequest*)request;
        
        NSFetchRequestResultType resultType = fetch.resultType;
        
        id result = nil;
        
        NSEntityDescription *entity = fetch.entity;
        NSString *entityName = entity.name;
        
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        
        // Docs: "note that it is not necessary to populate the managed object with attribute or relationship values at this point"
        // -> you'll need them for predicates, though ;)
        
        switch (resultType) {
            case NSManagedObjectResultType:
            case NSManagedObjectIDResultType: {
                result = [self _queryObjectsOfEntity:entity byFetchRequest:fetch inContext:context error:outError];
                if (!result) return nil;
                
                if (fetch.sortDescriptors) {
                    result = [result sortedArrayUsingDescriptors:fetch.sortDescriptors];
                }
                if (resultType == NSManagedObjectIDResultType) {
                    NSMutableArray *objectIDs = [NSMutableArray arrayWithCapacity:[result count]];
                    for (NSManagedObject *obj in result) {
                        [objectIDs addObject:[obj objectID]];
                    }
                    result = objectIDs;
                }
            }
                break;
                
            case NSDictionaryResultType: {
                CBLView *view = [self.database existingViewNamed:kCBLISAllByTypeViewName];
                CBLQuery* query = [view createQuery];
                query.keys = @[ entityName ];
                query.prefetch = YES;
                
                CBLQueryEnumerator *rows = [self _queryEnumeratorForQuery:query error:outError];
                if (!rows) return nil;
                
                NSMutableArray *array = [NSMutableArray arrayWithCapacity:rows.count];
                for (CBLQueryRow *row in rows) {
                    NSDictionary *properties = row.documentProperties;
                    
                    if (!fetch.predicate || [fetch.predicate evaluateWithObject:properties]) {
                        
                        if (fetch.propertiesToFetch) {
                            [array addObject:[properties dictionaryWithValuesForKeys:fetch.propertiesToFetch]];
                        } else {
                            [array addObject:properties];
                        }
                    }
                }
                result = array;
            }
                break;
                
            case NSCountResultType: {
                NSUInteger count = 0;
                if (fetch.predicate) {
                    NSArray *array = [self _queryObjectsOfEntity:entity byFetchRequest:fetch inContext:context error:outError];
                    if (!array) return nil;
                    
                    count = array.count;
                } else {
                    CBLView *view = [self.database existingViewNamed:kCBLISAllByTypeViewName];
                    CBLQuery* query = [view createQuery];
                    query.keys = @[ entityName ];
                    query.prefetch = NO;
                    
                    CBLQueryEnumerator *rows = [self _queryEnumeratorForQuery:query error:outError];
                    if (!rows) return nil;
                    
                    count = rows.count;
                }
                
                result = @[@(count)];
            }
                break;
            default:
                break;
        }
        
        CFAbsoluteTime end = CFAbsoluteTimeGetCurrent();
#ifndef PROFILE
        if (end - start > 1) {
#endif
            NSLog(@"[tdis] fetch request ---------------- \n"
                  "[tdis]   entity-name:%@\n"
                  "[tdis]   resultType:%@\n"
                  "[tdis]   fetchPredicate: %@\n"
                  "[tdis] --> took %f seconds\n"
                  "[tids]---------------- ",
                  entityName, CBLISResultTypeName(resultType), fetch.predicate, end - start);
#ifndef PROFILE
        }
#endif
        
        
        return result;
    } else {
        if (outError) *outError = [NSError errorWithDomain:kCBLISErrorDomain
                                                      code:CBLIncrementalStoreErrorUnsupportedRequestType
                                                  userInfo:@{
                                                             NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"Unsupported requestType: %d", (int)request.requestType]
                                                             }];
        return nil;
    }
}

- (NSIncrementalStoreNode *)newValuesForObjectWithID:(NSManagedObjectID*)objectID withContext:(NSManagedObjectContext*)context error:(NSError**)outError
{
    CBLDocument* doc = [self.database documentWithID:[objectID couchbaseLiteIDRepresentation]];
    
    NSEntityDescription *entity = objectID.entity;
    if (![entity.name isEqual:[doc propertyForKey:kCBLISTypeKey]]) {
        entity = [NSEntityDescription entityForName:[doc propertyForKey:kCBLISTypeKey]
                             inManagedObjectContext:context];
    }
    
    NSDictionary *values = [self _coreDataPropertiesOfDocumentWithID:doc.documentID properties:doc.properties withEntity:entity inContext:context];
    NSIncrementalStoreNode *node = [[NSIncrementalStoreNode alloc] initWithObjectID:objectID
                                                                         withValues:values
                                                                            version:1];
    
    return node;
}

- (id)newValueForRelationship:(NSRelationshipDescription*)relationship forObjectWithID:(NSManagedObjectID*)objectID withContext:(NSManagedObjectContext *)context error:(NSError **)outError
{
    if ([relationship isToMany]) {
        CBLView *view = [self.database existingViewNamed:CBLISToManyViewNameForRelationship(relationship)];
        CBLQuery* query = [view createQuery];
        
        query.keys = @[ [objectID couchbaseLiteIDRepresentation] ];
        
        CBLQueryEnumerator *rows = [self _queryEnumeratorForQuery:query error:outError];
        if (!rows) return nil;
        
        NSMutableArray *result = [NSMutableArray arrayWithCapacity:rows.count];
        for (CBLQueryRow* row in rows) {
            [result addObject:[self _newObjectIDForEntity:relationship.destinationEntity
                                     managedObjectContext:context couchID:row.documentID]];
        }
        
        return result;
    } else {
        CBLDocument* doc = [self.database documentWithID:[objectID couchbaseLiteIDRepresentation]];
        NSString *destinationID = [doc propertyForKey:relationship.name];
        if (destinationID) {
            return [self newObjectIDForEntity:relationship.destinationEntity referenceObject:destinationID];
        } else {
            return [NSNull null];
        }
    }
}

- (NSArray *)obtainPermanentIDsForObjects:(NSArray *)array error:(NSError **)outError
{
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:array.count];
    for (NSManagedObject *object in array) {
        // if you call -[NSManagedObjectContext obtainPermanentIDsForObjects:error:] yourself,
        // this can get called with already permanent ids which leads to mismatch between store.
        if (![object.objectID isTemporaryID]) {
            
            [result addObject:object.objectID];
            
        } else {
            
            NSString *uuid = [[NSProcessInfo processInfo] globallyUniqueString];
            NSManagedObjectID *objectID = [self newObjectIDForEntity:object.entity
                                                     referenceObject:uuid];
            [result addObject:objectID];
            
        }
    }
    return result;
}

- (NSManagedObjectID *)newObjectIDForEntity:(NSEntityDescription *)entity referenceObject:(id)data
{
    NSString *referenceObject = data;
    
    if ([referenceObject hasPrefix:@"p"]) {
        referenceObject = [referenceObject substringFromIndex:1];
    }
    
    // we need to prefix the refernceObject with a non-numeric prefix, because of a bug where
    // referenceObjects starting with a digit will only use the first digit part. As described here:
    // https://github.com/AFNetworking/AFIncrementalStore/issues/82
    referenceObject = [kCBLISManagedObjectIDPrefix stringByAppendingString:referenceObject];
    NSManagedObjectID *objectID = [super newObjectIDForEntity:entity referenceObject:referenceObject];
    return objectID;
}

#pragma mark - Views

/** Initializes the views needed for querying objects by type and for to-many relationships. */
- (void) _initializeViews
{
    NSMutableDictionary *subentitiesToSuperentities = [NSMutableDictionary dictionary];
    
    // Create a view for each to-many relationship
    NSArray *entites = self.persistentStoreCoordinator.managedObjectModel.entities;
    for (NSEntityDescription *entity in entites) {
        
        NSArray *properties = [entity properties];
        
        for (NSPropertyDescription *property in properties) {
            
            if ([property isKindOfClass:[NSRelationshipDescription class]]) {
                NSRelationshipDescription *rel = (NSRelationshipDescription*)property;
                
                if (rel.isToMany) {
                    
                    NSMutableArray *entityNames = nil;
                    if (rel.destinationEntity.subentities.count > 0) {
                        entityNames = [NSMutableArray arrayWithCapacity:3];
                        for (NSEntityDescription *subentity in rel.destinationEntity.subentities) {
                            [entityNames addObject:subentity.name];
                        }
                    }
                    
                    NSString *viewName = CBLISToManyViewNameForRelationship(rel);
                    NSString *destEntityName = rel.destinationEntity.name;
                    NSString *inverseRelNameLower = [rel.inverseRelationship.name lowercaseString];
                    if (entityNames.count == 0) {
                        CBLView *view = [self.database viewNamed:viewName];
                        [view setMapBlock:^(NSDictionary *doc, CBLMapEmitBlock emit) {
                            if ([[doc objectForKey:kCBLISTypeKey] isEqual:destEntityName] && [doc objectForKey:inverseRelNameLower]) {
                                emit([doc objectForKey:inverseRelNameLower], nil);
                            }
                        }
                                  version:@"1.0"];
                        
                        [self _setViewName:viewName forFetchingProperty:inverseRelNameLower fromEntity:destEntityName];
                        
                    } else {
                        CBLView *view = [self.database viewNamed:viewName];
                        [view setMapBlock:^(NSDictionary *doc, CBLMapEmitBlock emit) {
                            if ([entityNames containsObject:[doc objectForKey:kCBLISTypeKey]] && [doc objectForKey:inverseRelNameLower]) {
                                emit([doc objectForKey:inverseRelNameLower], nil);
                            }
                        }
                                  version:@"1.0"];
                        
                        // remember view for mapping super-entity and all sub-entities
                        [self _setViewName:viewName forFetchingProperty:inverseRelNameLower fromEntity:rel.destinationEntity.name];
                        for (NSString *entityName in entityNames) {
                            [self _setViewName:viewName forFetchingProperty:inverseRelNameLower fromEntity:entityName];
                        }
                        
                    }
                    
                }
                
            }
            
        }
        
        if (entity.subentities.count > 0) {
            for (NSEntityDescription *subentity in entity.subentities) {
                [subentitiesToSuperentities setObject:entity.name forKey:subentity.name];
            }
        }
    }
    
    // Create a view that maps entity names to instances
    CBLView *view = [self.database viewNamed:kCBLISAllByTypeViewName];
    [view setMapBlock:^(NSDictionary *doc, CBLMapEmitBlock emit) {
        NSString *ident = [doc valueForKey:@"_id"];
        if ([ident hasPrefix:@"cblis_"]) return;
        
        NSString* type = [doc objectForKey: kCBLISTypeKey];
        if (type) emit(type, nil);
        
        NSString *superentity = [subentitiesToSuperentities objectForKey:type];
        if (superentity) {
            emit(superentity, nil);
        }
    }
              version:@"1.0"];
}

/** Creates a view for fetching entities by a property name. Can speed up fetching this entity by this property. */
- (void) defineFetchViewForEntity:(NSString*)entityName
                       byProperty:(NSString*)propertyName
{
    NSString *viewName = [self _createViewNameForFetchingFromEntity:entityName byProperty:propertyName];
    
    CBLView *view = [self.database viewNamed:viewName];
    [view setMapBlock:^(NSDictionary *doc, CBLMapEmitBlock emit) {
        NSString* type = [doc objectForKey:kCBLISTypeKey];
        if ([type isEqual:entityName] && [doc objectForKey:propertyName]) {
            emit([doc objectForKey:propertyName], nil);
        }
    }
              version:@"1.0"];
    
    [self _setViewName:viewName forFetchingProperty:propertyName fromEntity:entityName];
}

#pragma mark - Querying

/** Queries the database by a given fetch request. Checks the cache for the result first. */
- (NSArray*) _queryObjectsOfEntity:(NSEntityDescription*)entity byFetchRequest:(NSFetchRequest*)fetch inContext:(NSManagedObjectContext*)context error:(NSError**)outError
{
    id cached = [self _cachedQueryResultsForEntity:entity.name predicate:fetch.predicate];
    if (cached) {
        return cached;
    }
    
    CBLQuery* query = [self _queryForFetchRequest:fetch onEntity:entity error:nil];
    if (!query) {
        CBLView *view = [self.database existingViewNamed:kCBLISAllByTypeViewName];
        query = [view createQuery];
        query.keys = @[ entity.name ];
        query.prefetch = fetch.predicate != nil;
    }
    
    NSArray *result = [self _filterObjectsOfEntity:entity fromQuery:query byFetchRequest:fetch
                                         inContext:context error:outError];
    
    return result;
}

/** Filters a query by a given fetch request. Checks the cache for the result first. */
- (NSArray*) _filterObjectsOfEntity:(NSEntityDescription*)entity fromQuery:(CBLQuery*)query byFetchRequest:(NSFetchRequest*)fetch inContext:(NSManagedObjectContext*)context error:(NSError**)outError
{
    id cached = [self _cachedQueryResultsForEntity:entity.name predicate:fetch.predicate];
    if (cached) {
        return cached;
    }
    
    CBLQueryEnumerator *rows = [self _queryEnumeratorForQuery:query error:outError];
    if (!rows) return nil;
    
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:rows.count];
    for (CBLQueryRow *row in rows) {
        if (!fetch.predicate || [self _evaluatePredicate:fetch.predicate withEntity:entity properties:row.documentProperties]) {
            NSManagedObjectID *objectID = [self _newObjectIDForEntity:entity managedObjectContext:context
                                                              couchID:row.documentID];
            NSManagedObject *object = [context objectWithID:objectID];
            [array addObject:object];
        }
    }
    
    [self _setCacheResults:array forEntity:entity.name predicate:fetch.predicate];
    
    return array;
}

/** Creates a query for fetching the data for an entity filtered by a NSFetchRequest. Only takes a NSComparisonPredicate that references 
 * the requested entity into account.
 */
- (CBLQuery*) _queryForFetchRequest:(NSFetchRequest*)fetch onEntity:(NSEntityDescription*)entity error:(NSError**)outError
{
    NSPredicate *predicate = fetch.predicate;
    
    if (!predicate) return nil;
    
    // Check if the query is a compound query.
    if ([predicate isKindOfClass:[NSCompoundPredicate class]]) {
        if (((NSCompoundPredicate*)predicate).subpredicates.count == 1 ||
            ((NSCompoundPredicate*)predicate).compoundPredicateType == NSAndPredicateType) {
            predicate = ((NSCompoundPredicate*)predicate).subpredicates[0];
        } else {
            if (outError) *outError = [NSError errorWithDomain:kCBLISErrorDomain
                                                          code:CBLIncrementalStoreErrorCreatingQueryFailed
                                                      userInfo:@{
                                                                 NSLocalizedFailureReasonErrorKey: @"Error creating query: unsupported NSCompoundPredicate."
                                                                 }];
            return nil;
        }
    }
    
    if (![predicate isKindOfClass:[NSComparisonPredicate class]]) {
        if (outError) *outError = [NSError errorWithDomain:kCBLISErrorDomain
                                                      code:CBLIncrementalStoreErrorCreatingQueryFailed
                                                  userInfo:@{
                                                             NSLocalizedFailureReasonErrorKey: @"Error creating query: unsupported predicate: only comparison predicate supported"
                                                             }];
        return nil;
    }
    
    NSComparisonPredicate *comparisonPredicate = (NSComparisonPredicate*)predicate;
    
    if (comparisonPredicate.predicateOperatorType != NSEqualToPredicateOperatorType &&
        comparisonPredicate.predicateOperatorType != NSNotEqualToPredicateOperatorType &&
        comparisonPredicate.predicateOperatorType != NSInPredicateOperatorType) {
        if (outError) *outError = [NSError errorWithDomain:kCBLISErrorDomain
                                                      code:CBLIncrementalStoreErrorCreatingQueryFailed
                                                  userInfo:@{
                                                             NSLocalizedFailureReasonErrorKey: @"Error creating query: unsupported predicate: only equal, not equal or IN supported"
                                                             }];
        return nil;
    }
    
    if (comparisonPredicate.leftExpression.expressionType != NSKeyPathExpressionType) {
        if (outError) *outError = [NSError errorWithDomain:kCBLISErrorDomain
                                                      code:CBLIncrementalStoreErrorCreatingQueryFailed
                                                  userInfo:@{
                                                             NSLocalizedFailureReasonErrorKey: @"Error creating query: unsupported predicate: left expression invalid"
                                                             }];
        return nil;
    }
    
    if (comparisonPredicate.rightExpression.expressionType != NSConstantValueExpressionType) {
        if (outError) *outError = [NSError errorWithDomain:kCBLISErrorDomain
                                                      code:CBLIncrementalStoreErrorCreatingQueryFailed
                                                  userInfo:@{
                                                             NSLocalizedFailureReasonErrorKey: @"Error creating query: unsupported predicate: right expression invalid"
                                                             }];
        return nil;
    }
    
    if (![self _hasViewForFetchingFromEntity:entity.name byProperty:comparisonPredicate.leftExpression.keyPath]) {
        if (outError) *outError = [NSError errorWithDomain:kCBLISErrorDomain
                                                      code:CBLIncrementalStoreErrorCreatingQueryFailed
                                                  userInfo:@{
                                                             NSLocalizedFailureReasonErrorKey: @"Error creating query: no view for that entity found"
                                                             }];
        return nil;
    }
    
    NSString *viewName = [self _viewNameForFetchingFromEntity:entity.name byProperty:comparisonPredicate.leftExpression.keyPath];
    if (!viewName) {
        return nil;
    }
    
    CBLView *view = [self.database existingViewNamed:viewName];
    CBLQuery *query = [view createQuery];
    if (comparisonPredicate.predicateOperatorType == NSEqualToPredicateOperatorType) {
        id rightValue = [comparisonPredicate.rightExpression constantValue];
        if ([rightValue isKindOfClass:[NSManagedObjectID class]]) {
            rightValue = [rightValue couchbaseLiteIDRepresentation];
        } else if ([rightValue isKindOfClass:[NSManagedObject class]]) {
            rightValue = [[rightValue objectID] couchbaseLiteIDRepresentation];
        }
        query.keys = @[ rightValue ];
        
    } else if (comparisonPredicate.predicateOperatorType == NSInPredicateOperatorType) {
        id rightValue = [comparisonPredicate.rightExpression constantValue];
        if ([rightValue isKindOfClass:[NSSet class]]) {
            rightValue = [[self _replaceManagedObjectsWithCouchIDInSet:rightValue] allObjects];
        } else if ([rightValue isKindOfClass:[NSArray class]]) {
            rightValue = [self _replaceManagedObjectsWithCouchIDInArray:rightValue];
        } else if (rightValue != nil) {
            NSAssert(NO, @"Wrong value in IN predicate rhv");
        }
        query.keys = rightValue;
    }
    query.prefetch = YES;
    
    return query;
}
- (NSArray*) _replaceManagedObjectsWithCouchIDInArray:(NSArray*)array
{
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:array.count];
    for (id value in array) {
        if ([value isKindOfClass:[NSManagedObject class]]) {
            [result addObject:[[value objectID] couchbaseLiteIDRepresentation]];
        } else if ([value isKindOfClass:[NSManagedObjectID class]]) {
            [result addObject:[value couchbaseLiteIDRepresentation]];
        } else {
            [result addObject:value];
        }
    }
    return result;
}
- (NSSet*) _replaceManagedObjectsWithCouchIDInSet:(NSSet*)set
{
    NSMutableSet *result = [NSMutableSet setWithCapacity:set.count];
    for (id value in set) {
        if ([value isKindOfClass:[NSManagedObject class]]) {
            [result addObject:[[value objectID] couchbaseLiteIDRepresentation]];
        } else if ([value isKindOfClass:[NSManagedObjectID class]]) {
            [result addObject:[value couchbaseLiteIDRepresentation]];
        } else {
            [result addObject:value];
        }
    }
    return result;
}

- (NSManagedObjectID *)_newObjectIDForEntity:(NSEntityDescription *)entity managedObjectContext:(NSManagedObjectContext*)context
                                     couchID:(NSString*)couchID
{
    NSManagedObjectID *objectID = [self newObjectIDForEntity:entity referenceObject:couchID];
    return objectID;
}

- (id) _couchbaseLiteRepresentationOfManagedObject:(NSManagedObject*)object withCouchbaseLiteID:(BOOL)withID
{
    NSEntityDescription *desc = object.entity;
    NSDictionary *propertyDesc = [desc propertiesByName];
    
    NSMutableDictionary *proxy = [NSMutableDictionary dictionary];
    
    [proxy setObject:desc.name
              forKey:kCBLISTypeKey];
    
    if ([propertyDesc objectForKey:kCBLISCurrentRevisionAttributeName]) {
        id rev = [object valueForKey:kCBLISCurrentRevisionAttributeName];
        if (!CBLISIsNull(rev)) {
            [proxy setObject:rev forKey:@"_rev"];
        }
    }
    
    if (withID) {
        [proxy setObject:[object.objectID couchbaseLiteIDRepresentation] forKey:@"_id"];
    }
    
    for (NSString *property in propertyDesc) {
        if ([kCBLISCurrentRevisionAttributeName isEqual:property]) continue;
        
        id desc = [propertyDesc objectForKey:property];
        
        if ([desc isKindOfClass:[NSAttributeDescription class]]) {
            NSAttributeDescription *attr = desc;
            
            if ([attr isTransient]) {
                continue;
            }
            
            // skip binary attributes to not load them into memory here. They are added as attachments
            if ([attr attributeType] == NSBinaryDataAttributeType) {
                continue;
            }
            
            id value = [object valueForKey:property];
            
            if (value) {
                
                NSAttributeType attributeType = [attr attributeType];
                
                if (attr.valueTransformerName) {
                    NSValueTransformer *transformer = [NSValueTransformer valueTransformerForName:attr.valueTransformerName];
                    
                    if (!transformer) {
                        NSLog(@"[info] value transformer for attribute %@ with name %@ not found", attr.name, attr.valueTransformerName);
                        continue;
                    }
                    
                    value = [transformer transformedValue:value];
                    
                    Class transformedClass = [[transformer class] transformedValueClass];
                    if (transformedClass == [NSString class]) {
                        attributeType = NSStringAttributeType;
                    } else if (transformedClass == [NSData class]) {
                        value = [value base64EncodedStringWithOptions:0];
                        attributeType = NSStringAttributeType;
                    } else {
                        NSLog(@"[info] unsupported value transformer transformedValueClass: %@", NSStringFromClass(transformedClass));
                        continue;
                    }
                }
                
                switch (attributeType) {
                    case NSInteger16AttributeType:
                    case NSInteger32AttributeType:
                    case NSInteger64AttributeType:
                        value = [NSNumber numberWithLong:CBLISIsNull(value) ? 0 : [value longValue]];
                        break;
                    case NSDecimalAttributeType:
                    case NSDoubleAttributeType:
                    case NSFloatAttributeType:
                        value = [NSNumber numberWithDouble:CBLISIsNull(value) ? 0.0 : [value doubleValue]];
                        break;
                    case NSStringAttributeType:
                        value = CBLISIsNull(value) ? @"" : value;
                        break;
                    case NSBooleanAttributeType:
                        value = [NSNumber numberWithBool:CBLISIsNull(value) ? NO : [value boolValue]];
                        break;
                    case NSDateAttributeType:
                        value = CBLISIsNull(value) ? nil : [CBLJSON JSONObjectWithDate:value];
                        break;
                        //                    case NSBinaryDataAttributeType: // handled above
                    case NSUndefinedAttributeType:
                        // intentionally do nothing
                        break;
                    default:
                        NSLog(@"[info] unsupported attribute %@, type: %@ (%d)", attr.name, attr, (int)[attr attributeType]);
                        break;
                }
                
                if (value) {
                    [proxy setObject:value forKey:property];
                }
                
            }
        } else if ([desc isKindOfClass:[NSRelationshipDescription class]]) {
            NSRelationshipDescription *rel = desc;
            
            id relationshipDestination = [object valueForKey:property];
            
            if (relationshipDestination) {
                if (![rel isToMany]) {
                    NSManagedObjectID *objectID = [relationshipDestination valueForKey:@"objectID"];
                    [proxy setObject:[objectID couchbaseLiteIDRepresentation] forKey:property];
                }
            }
            
        }
    }
    
    return proxy;
}

- (NSDictionary*) _coreDataPropertiesOfDocumentWithID:(NSString*)documentID properties:(NSDictionary*)properties withEntity:(NSEntityDescription*)entity inContext:(NSManagedObjectContext*)context
{
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:properties.count];
    
    NSDictionary *propertyDesc = [entity propertiesByName];
    
    for (NSString *property in propertyDesc) {
        id desc = [propertyDesc objectForKey:property];
        
        if ([desc isKindOfClass:[NSAttributeDescription class]]) {
            NSAttributeDescription *attr = desc;
            
            if ([attr isTransient]) {
                continue;
            }
            
            // handle binary attributes specially
            if ([attr attributeType] == NSBinaryDataAttributeType) {
                id value = [self _loadDataForAttachmentWithName:property ofDocumentWithID:documentID];
                if (value) {
                    [result setObject:value forKey:property];
                }
                
                continue;
            }
            
            id value = nil;
            if ([kCBLISCurrentRevisionAttributeName isEqual:property]) {
                value = [properties objectForKey:@"_rev"];
            } else {
                value = [properties objectForKey:property];
            }
            
            if (value) {
                
                NSAttributeType attributeType = [attr attributeType];
                
                if (attr.valueTransformerName) {
                    NSValueTransformer *transformer = [NSValueTransformer valueTransformerForName:attr.valueTransformerName];
                    
                    Class transformedClass = [[transformer class] transformedValueClass];
                    if (transformedClass == [NSString class]) {
                        value = [transformer reverseTransformedValue:value];
                    } else if (transformedClass == [NSData class]) {
                        value = [transformer reverseTransformedValue:[[NSData alloc]initWithBase64EncodedString:value options:0]];
                    } else {
                        NSLog(@"[info] unsupported value transformer transformedValueClass: %@", NSStringFromClass(transformedClass));
                        continue;
                    }
                }
                
                switch (attributeType) {
                    case NSInteger16AttributeType:
                    case NSInteger32AttributeType:
                    case NSInteger64AttributeType:
                        value = [NSNumber numberWithLong:CBLISIsNull(value) ? 0 : [value longValue]];
                        break;
                    case NSDecimalAttributeType:
                        value = [NSDecimalNumber numberWithDouble:CBLISIsNull(value) ? 0.0 : [value doubleValue]];
                        break;
                    case NSDoubleAttributeType:
                    case NSFloatAttributeType:
                        value = [NSNumber numberWithDouble:CBLISIsNull(value) ? 0.0 : [value doubleValue]];
                        break;
                    case NSStringAttributeType:
                        value = CBLISIsNull(value) ? @"" : value;
                        break;
                    case NSBooleanAttributeType:
                        value = [NSNumber numberWithBool:CBLISIsNull(value) ? NO : [value boolValue]];
                        break;
                    case NSDateAttributeType:
                        value = CBLISIsNull(value) ? nil : [CBLJSON dateWithJSONObject:value];
                        break;
                    case NSTransformableAttributeType:
                        // intentionally do nothing
                        break;
                    default:
                        //NSAssert(NO, @"Unsupported attribute type");
                        //break;
                        NSLog(@"CBLIncrementalStore: unsupported attribute %@, type: %lu",  attr, (unsigned long)attributeType);
                }
                
                if (value) {
                    [result setObject:value forKey:property];
                }
                
            }
        } else if ([desc isKindOfClass:[NSRelationshipDescription class]]) {
            NSRelationshipDescription *rel = desc;
            
            if (![rel isToMany]) { // only handle to-one relationships
                id value = [properties objectForKey:property];
                
                if (!CBLISIsNull(value)) {
                    NSManagedObjectID *destination = [self newObjectIDForEntity:rel.destinationEntity
                                                                referenceObject:value];
                    
                    [result setObject:destination forKey:property];
                }
            }
        }
    }
    
    return result;
}

/** Convenience method to execute a CouchbaseLite query and build a telling NSError if it fails. */
- (CBLQueryEnumerator*) _queryEnumeratorForQuery:(CBLQuery*)query error:(NSError**)outError
{
    NSError *error;
    CBLQueryEnumerator *rows = [query run:&error];
    if (!rows) {
        if (outError) *outError = [NSError errorWithDomain:kCBLISErrorDomain
                                                      code:CBLIncrementalStoreErrorQueryingCouchbaseLiteFailed
                                                  userInfo:@{
                                                             NSLocalizedFailureReasonErrorKey: @"Error querying CouchbaseLite",
                                                             NSUnderlyingErrorKey: error
                                                             }];
        return nil;
    }
    
    return rows;
}

#pragma mark - Caching

- (void) _setCacheResults:(NSArray*)array forEntity:(NSString*)entityName predicate:(NSPredicate*)predicate
{
    NSString *cacheKey = [NSString stringWithFormat:@"%@_%@", entityName, predicate];
    [_fetchRequestResultCache setObject:array forKey:cacheKey];
}

- (NSArray*) _cachedQueryResultsForEntity:(NSString*)entityName predicate:(NSPredicate*)predicate
{
    NSString *cacheKey = [NSString stringWithFormat:@"%@_%@", entityName, predicate];
    return [_fetchRequestResultCache objectForKey:cacheKey];
}

- (void) _purgeCacheForEntityName:(NSString*)type
{
    for (NSString *key in [_fetchRequestResultCache allKeys]) {
        if ([key hasPrefix:type]) {
            [_fetchRequestResultCache removeObjectForKey:key];
        }
    }
}

#pragma mark - NSPredicate

- (BOOL) _evaluatePredicate:(NSPredicate*)predicate withEntity:(NSEntityDescription*)entity properties:(NSDictionary*)properties
{
    if ([predicate isKindOfClass:[NSCompoundPredicate class]]) {
        NSCompoundPredicate *compoundPredicate = (NSCompoundPredicate*)predicate;
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
        for (NSPredicate *subpredicate in compoundPredicate.subpredicates) {
            BOOL result = [self _evaluatePredicate:subpredicate withEntity:entity properties:properties];
            
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
        NSComparisonPredicate *comparisonPredicate = (NSComparisonPredicate*)predicate;
        id leftValue = [self _evaluateExpression:comparisonPredicate.leftExpression withEntity:entity properties:properties];
        id rightValue = [self _evaluateExpression:comparisonPredicate.rightExpression withEntity:entity properties:properties];
        
        NSExpression *leftExpression = [NSExpression expressionForConstantValue:leftValue];
        NSExpression *rightExpression = [NSExpression expressionForConstantValue:rightValue];
        NSPredicate *comp = [NSComparisonPredicate predicateWithLeftExpression:leftExpression rightExpression:rightExpression
                                                                      modifier:comparisonPredicate.comparisonPredicateModifier
                                                                          type:comparisonPredicate.predicateOperatorType
                                                                       options:comparisonPredicate.options];
        
        BOOL result = [comp evaluateWithObject:nil];
        return result;
    }
    
    return NO;
}
- (id) _evaluateExpression:(NSExpression*)expression withEntity:(NSEntityDescription*)entity properties:(NSDictionary*)properties
{
    id value = nil;
    switch (expression.expressionType) {
        case NSConstantValueExpressionType:
            value = [expression constantValue];
            break;
        case NSEvaluatedObjectExpressionType:
            value = properties;
            break;
        case NSKeyPathExpressionType: {
            value = [properties objectForKey:expression.keyPath];
            if (!value) return nil;
            NSPropertyDescription *property = [entity.propertiesByName objectForKey:expression.keyPath];
            if ([property isKindOfClass:[NSRelationshipDescription class]]) {
                // if it's a relationship it should be a MOCID
                NSRelationshipDescription *rel = (NSRelationshipDescription*)property;
                value = [self newObjectIDForEntity:rel.destinationEntity referenceObject:value];
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

#pragma mark - Views

- (NSString*) _createViewNameForFetchingFromEntity:(NSString*)entityName
                                        byProperty:(NSString*)propertyName
{
    NSString *viewName = [NSString stringWithFormat:kCBLISFetchEntityByPropertyViewNameFormat, [entityName lowercaseString], propertyName];
    return viewName;
}

- (BOOL) _hasViewForFetchingFromEntity:(NSString*)entityName
                            byProperty:(NSString*)propertyName
{
    return [self _viewNameForFetchingFromEntity:entityName byProperty:propertyName] != nil;
}
- (NSString*) _viewNameForFetchingFromEntity:(NSString*)entityName
                                  byProperty:(NSString*)propertyName
{
    return [_entityAndPropertyToFetchViewName objectForKey:[NSString stringWithFormat:@"%@_%@", entityName, propertyName]];
}
- (void) _setViewName:(NSString*)viewName forFetchingProperty:(NSString*)propertyName fromEntity:(NSString*)entity
{
    [_entityAndPropertyToFetchViewName setObject:viewName
                                          forKey:[NSString stringWithFormat:@"%@_%@", entity, propertyName]];
}

#pragma mark - Attachments

- (NSData*) _loadDataForAttachmentWithName:(NSString*)name ofDocumentWithID:(NSString*)documentID
{
    CBLDocument *document = [self.database documentWithID:documentID];
    CBLAttachment *attachment = [document.currentRevision attachmentNamed:name];
    return attachment.content;
}

#pragma mark - Change Handling

- (void) addObservingManagedObjectContext:(NSManagedObjectContext*)context
{
    if (!_observingManagedObjectContexts) {
        _observingManagedObjectContexts = [[NSHashTable alloc] initWithOptions:NSPointerFunctionsWeakMemory capacity:10];
    }
    [_observingManagedObjectContexts addObject:context];
}
- (void) removeObservingManagedObjectContext:(NSManagedObjectContext*)context
{
    [_observingManagedObjectContexts removeObject:context];
}
- (void) _informManagedObjectContext:(NSManagedObjectContext*)context updatedIDs:(NSArray*)updatedIDs deletedIDs:(NSArray*)deletedIDs
{
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:3];
    
    if (updatedIDs.count > 0) {
        NSMutableArray *updated = [NSMutableArray arrayWithCapacity:updatedIDs.count];
        NSMutableArray *inserted = [NSMutableArray arrayWithCapacity:updatedIDs.count];
        
        for (NSManagedObjectID *mocid in updatedIDs) {
            NSManagedObject *moc = [context objectRegisteredForID:mocid];
            if (!moc) {
                moc = [context objectWithID:mocid];
                [inserted addObject:moc];
            } else {
                [context refreshObject:moc mergeChanges:YES];
                [updated addObject:moc];
            }
        }
        [userInfo setObject:updated forKey:NSUpdatedObjectsKey];
        if (inserted.count > 0) {
            [userInfo setObject:inserted forKey:NSInsertedObjectsKey];
        }
    }
    
    if (deletedIDs.count > 0) {
        NSMutableArray *deleted = [NSMutableArray arrayWithCapacity:deletedIDs.count];
        for (NSManagedObjectID *mocid in deletedIDs) {
            NSManagedObject *moc = [context objectWithID:mocid];
            [context deleteObject:moc];
            // load object again to get a fault
            [deleted addObject:[context objectWithID:mocid]];
        }
        [userInfo setObject:deleted forKey:NSDeletedObjectsKey];
    }
    
    NSNotification *didUpdateNote = [NSNotification notificationWithName:NSManagedObjectContextObjectsDidChangeNotification
                                                                  object:context userInfo:userInfo];
    [context mergeChangesFromContextDidSaveNotification:didUpdateNote];
}
- (void) _informObservingManagedObjectContextsAboutUpdatedIDs:(NSArray*)updatedIDs deletedIDs:(NSArray*)deletedIDs
{
    for (NSManagedObjectContext *context in self.observingManagedObjectContexts) {
        [self _informManagedObjectContext:context updatedIDs:updatedIDs deletedIDs:deletedIDs];
    }
}

- (void) _couchDocumentsChanged:(NSArray*)changes
{
#if CBLIS_NO_CHANGE_COALESCING
    [_coalescedChanges addObjectsFromArray:changes];
    [self _processCouchbaseLiteChanges];
#else
    [NSThread cancelPreviousPerformRequestsWithTarget:self selector:@selector(_processCouchbaseLiteChanges) object:nil];
    
    @synchronized(self) {
        [_coalescedChanges addObjectsFromArray:changes];
    }
    
    [self performSelector:@selector(_processCouchbaseLiteChanges) withObject:nil afterDelay:0.1];
#endif
}
- (void) _processCouchbaseLiteChanges
{
    NSArray *changes = nil;
    @synchronized(self) {
        changes = _coalescedChanges;
        _coalescedChanges = [[NSMutableArray alloc] initWithCapacity:20];
    }
    
    NSMutableSet *changedEntitites = [NSMutableSet setWithCapacity:changes.count];
    
    NSMutableArray *deletedObjectIDs = [NSMutableArray array];
    NSMutableArray *updatedObjectIDs = [NSMutableArray array];
    
    for (CBLDatabaseChange *change in changes) {
        if (!change.isCurrentRevision) continue;
        if ([change.documentID hasPrefix:@"CBLIS"]) continue;
        
        CBLDocument *doc = [self.database documentWithID:change.documentID];
        CBLRevision *rev = [doc revisionWithID:change.revisionID];
        
        BOOL deleted = rev.isDeletion;

        NSDictionary *properties = [rev properties];
        
        NSString *type = [properties objectForKey:kCBLISTypeKey];
        NSString *reference = change.documentID;
        
        NSEntityDescription *entity = [self.persistentStoreCoordinator.managedObjectModel.entitiesByName objectForKey:type];
        NSManagedObjectID *objectID = [self newObjectIDForEntity:entity referenceObject:reference];
        
        if (deleted) {
            [deletedObjectIDs addObject:objectID];
        } else {
            [updatedObjectIDs addObject:objectID];
        }

        [changedEntitites addObject:type];
    }
    
    [self _informObservingManagedObjectContextsAboutUpdatedIDs:updatedObjectIDs deletedIDs:deletedObjectIDs];
    
    NSDictionary *userInfo = @{
                               NSDeletedObjectsKey: deletedObjectIDs,
                               NSUpdatedObjectsKey: updatedObjectIDs
                               };
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kCBLISObjectHasBeenChangedInStoreNotification
                                                        object:self userInfo:userInfo];
    
}

#pragma mark - Conflicts handling

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([@"rows" isEqualToString:keyPath]) {
        CBLLiveQuery *query = object;
        
        NSError *error;
        CBLQueryEnumerator *enumerator = [query run:&error];
        
        if (enumerator.count == 0) return;
        
        [self _resolveConflicts:enumerator];
    }
}

- (void) _resolveConflicts:(CBLQueryEnumerator*)enumerator
{
    // resolve conflicts
    for (CBLQueryRow *row in enumerator) {
        if ([kCBLISMetadataDocumentID isEqual:row.documentID]) {
            // TODO: what to do here?
            continue;
        }
        
        if (self.conflictHandler) self.conflictHandler(row.conflictingRevisions);
    }
}

- (CBLISConflictHandler) _defaultConflictHandler
{
    CBLISConflictHandler handler = ^(NSArray *conflictingRevisions) {
        // merges changes by
        // - taking the winning revision
        // - adding missing values from other revisions (starting with biggest version)
        CBLRevision *winning = conflictingRevisions[0];
        NSMutableDictionary *properties = [winning.properties mutableCopy];
        
        NSRange otherRevisionsRange = NSMakeRange(1, conflictingRevisions.count - 1);
        NSArray *otherRevisions = [conflictingRevisions subarrayWithRange:otherRevisionsRange];
        
        NSArray *desc = @[[NSSortDescriptor sortDescriptorWithKey:@"revisionID"
                                                        ascending:NO]];
        NSArray *sortedRevisions = [otherRevisions sortedArrayUsingDescriptors:desc];
        
        // this solution merges missing keys from other conflicting revisions to not loose any values
        for (CBLRevision *rev in sortedRevisions) {
            for (NSString *key in rev.properties) {
                if ([key hasPrefix:@"_"]) continue;
                
                if (![properties objectForKey:key]) {
                    [properties setObject:[rev propertyForKey:key] forKey:key];
                }
            }
        }
        
        // TODO: Attachments
        
        CBLUnsavedRevision *newRevision = [winning.document newRevision];
        [newRevision setProperties:properties];
        
        NSError *error;
        [newRevision save:&error];
    };
    return handler;
}

#pragma mark -

/** Returns the properties that are stored for deleting a document. Must contain at least "_rev" and "_deleted" = true for 
 * CouchbaseLite and kCBLISTypeKey for this store. Can be overridden if you need more for filtered syncing, for example.
 */
- (NSDictionary*) _propertiesForDeletingDocument:(CBLDocument*)doc
{
    NSDictionary *contents = @{
                               @"_deleted": @YES,
                               @"_rev": [doc propertyForKey:@"_rev"],
                               kCBLISTypeKey: [doc propertyForKey:kCBLISTypeKey]
                               };
    return contents;
}

@end


@implementation NSManagedObjectID (CBLIncrementalStore)

/** Returns an internal representation of this objectID that is used as _id in Couchbase. */
- (NSString*) couchbaseLiteIDRepresentation
{
    // +1 because of "p" prefix in managed object IDs
    NSString *uuid = [[self.URIRepresentation lastPathComponent] substringFromIndex:kCBLISManagedObjectIDPrefix.length + 1];
    return uuid;
}

@end


//// utility methods

/** Checks if value is nil or NSNull. */
BOOL CBLISIsNull(id value)
{
    return value == nil || [value isKindOfClass:[NSNull class]];
}

/** returns name of a view that returns objectIDs for all destination entities of a to-many relationship. */
NSString *CBLISToManyViewNameForRelationship(NSRelationshipDescription *relationship)
{
    NSString *entityName = relationship.entity.name;
    NSString *destinationName = relationship.destinationEntity.name;
    return [NSString stringWithFormat:kCBLISFetchEntityToManyViewNameFormat, entityName, destinationName];
}

/** Returns a readable name for a NSFetchRequestResultType */
NSString *CBLISResultTypeName(NSFetchRequestResultType resultType)
{
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
