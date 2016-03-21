//
//  IncrementalStore_Tests.m
//  CouchbaseLite
//
//  Created by Christian Beer on 01.12.13.
//
//

#import "CBLTestCase.h"

#import "CBLInternal.h"  // for -[CBLDatabase close]

#import <CoreData/CoreData.h>
#import "CBLIncrementalStore.h"

#define PERFORMANCE_TEST_ENABLED 0
#define NON_INVERSE_RELATIONSHIP_TEST_ENABLED 0

@interface IncrementalStore_Tests : CBLTestCaseWithDB <CBLIncrementalStoreDelegate>
@property NSUInteger counter; // General purpose counter that can be used with XCTest Async KVO expectation check
@end


@interface CBLIncrementalStore (UnitTest)
@property (nonatomic) BOOL shouldNotifyLocalDatabaseChanges;
@end

@implementation CBLIncrementalStore (UnitTest)
@dynamic shouldNotifyLocalDatabaseChanges;
@end

#pragma mark - Helper Classes / Methods

typedef void(^CBLISAssertionBlock)(NSArray *result, NSFetchRequestResultType resultType);

@class Entry;
@class Subentry;
@class NonInverseSubentry;
@class ManySubentry;
@class File;
@class User;

static NSManagedObjectModel *CBLISTestCoreDataModel(void);
static Entry *CBLISTestInsertEntryWithProperties(NSManagedObjectContext *context, NSDictionary *props);
static NSArray *CBLISTestInsertEntriesWithProperties(NSManagedObjectContext *context, NSArray *entityProps);


@interface Entry : NSManagedObject
@property (nonatomic, retain) NSNumber * check;
@property (nonatomic, retain) NSDate * created_at;
@property (nonatomic, retain) NSString * text;
@property (nonatomic, retain) NSString * text2;
@property (nonatomic, retain) NSNumber * number;
@property (nonatomic, retain) NSDecimalNumber * decimalNumber;
@property (nonatomic, retain) NSNumber * doubleNumber;
@property (nonatomic, retain) NSSet *subEntries;
@property (nonatomic, retain) NSSet *files;
@property (nonatomic, retain) User *user;

#if NON_INVERSE_RELATIONSHIP_TEST_ENABLED
// To-Many relationship without an inverse relationship.
@property (nonatomic, retain) NSSet *nonInverseSubentries;
#endif

// Many-to-Many relationship
@property (nonatomic, retain) NSSet *manySubentries;

@end

@interface Entry (CoreDataGeneratedAccessors)
// subEntries:
- (void)addSubEntriesObject:(Subentry *)value;
- (void)removeSubEntriesObject:(Subentry *)value;
- (void)addSubEntries:(NSSet *)values;
- (void)removeSubEntries:(NSSet *)values;

// files:
- (void)addFilesObject:(File *)value;
- (void)removeFilesObject:(File *)value;
- (void)addFiles:(NSSet *)values;
- (void)removeFiles:(NSSet *)values;

#if NON_INVERSE_RELATIONSHIP_TEST_ENABLED
// non-inverse sub-entries:
- (void)addNonInverseSubentriesObject:(NonInverseSubentry *)value;
- (void)removeNonInverseSubentriesObject:(NonInverseSubentry *)value;
- (void)addNonInverseSubentries:(NSSet *)values;
- (void)removeNonInversesubentries:(NSSet *)values;
#endif

// manySubentries:
- (void)addManySubentriesObject:(ManySubentry *)value;
- (void)removeManySubentriesObject:(ManySubentry *)value;
- (void)addManySubentries:(NSSet *)values;
- (void)removeManySubentries:(NSSet *)values;

@end

@interface Subentry : NSManagedObject
@property (nonatomic, retain) NSString * text;
@property (nonatomic, retain) NSNumber * number;
@property (nonatomic, retain) Entry *entry;
@end

@interface ManySubentry : NSManagedObject
@property (nonatomic, retain) NSString * text;
@property (nonatomic, retain) NSNumber * number;
@property (nonatomic, retain) NSSet *entries;
@end

@interface ManySubentry (CoreDataGeneratedAccessors)
- (void)addEntriesObject:(Entry *)value;
- (void)removeEntriesObject:(Entry *)value;
- (void)addEntries:(NSSet *)values;
- (void)removeEntries:(NSSet *)values;
@end

@interface File : NSManagedObject
@property (nonatomic, retain) NSString * filename;
@property (nonatomic, retain) NSData * data;
@property (nonatomic, retain) Entry *entry;
@end

@interface NonInverseSubentry : NSManagedObject
@property (nonatomic, retain) NSString * name;
@end

@interface User : NSManagedObject
@property (nonatomic, retain) NSString * name;
@property (nonatomic, retain) Entry *entry;
@end

@interface Parent : NSManagedObject
@property (nonatomic, retain) NSString * name;
@end

@interface Child : Parent
@property (nonatomic, retain) NSString * anotherName;
@end

@interface NSManagedObjectID (CBLIncrementalStore)
- (NSString*) documentIDRepresentation;
@end


#pragma mark - Tests


@implementation IncrementalStore_Tests
{
    NSManagedObjectModel *model;
    NSManagedObjectContext *context;
    CBLIncrementalStore *store;
}

@synthesize counter=_counter;

- (void) setUp {
    [super setUp];

    model = CBLISTestCoreDataModel();
    [self reCreateCoreDataContext];
    Assert(store.database != nil);

    self.counter = 0;
}

- (void) tearDown {
    CBLManager *manager = store.database.manager;
    dispatch_sync(manager.dispatchQueue, ^{
        [store.database deleteDatabase:nil];
        [manager close];
    });
    [super tearDown];
}

- (void) reCreateCoreDataContext {
    CBLManager *manager = store.database.manager;
    if (manager) {
        dispatch_sync(manager.dispatchQueue, ^{
            [manager close];
        });
    }

    NSError* error;
    context = [CBLIncrementalStore createManagedObjectContextWithModel:model
                                                          databaseName:db.name
                                                                 error:&error];
    Assert(context, @"Context could not be created: %@", error);

    store = context.persistentStoreCoordinator.persistentStores[0];
    Assert(store, @"Context doesn't have any store?!");
}

- (CBLDocument*) documentWithID:(NSString *)docID {
    Assert(store.database != nil);
    __block CBLDocument *doc;
    [store.database doSync:^{
        doc = [store.database documentWithID:docID];
    }];
    return doc;
}

- (CBLAttachment*) attachmentNamed:(NSString*)name ofDocument:(CBLDocument*)document {
    Assert(store.database != nil);
    __block CBLAttachment *attachment;
    [store.database doSync:^{
        attachment = [document.currentRevision attachmentNamed:name];
    }];
    return attachment;
}

/** Test case that tests create, request, update and delete of Core Data objects. */
- (void) test_CRUD {
    Entry *entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                 inManagedObjectContext:context];

    // cut off seconds as they are not encoded in date values in DB
    NSDate *createdAt = [NSDate dateWithTimeIntervalSince1970:(long)[NSDate new].timeIntervalSince1970];
    NSString *text = @"Test";

    entry.created_at = createdAt;
    entry.text = text;
    entry.check = @NO;

    NSError *error;
    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    CBLDocument *doc = [self documentWithID:[entry.objectID documentIDRepresentation]];
    AssertEqual(entry.text, [doc propertyForKey:@"text"]);

    NSDate *date1 = entry.created_at;
    NSDate *date2 = [CBLJSON dateWithJSONObject:[doc propertyForKey:@"created_at"]];
    int diffInSeconds = (int)floor([date1 timeIntervalSinceDate:date2]);
    AssertEq(diffInSeconds, 0);
    AssertEqual(entry.check, [doc propertyForKey:@"check"]);

    entry.check = @(YES);

    success = [context save:&error];
    Assert(success, @"Could not save context after update: %@", error);

    doc = [self documentWithID:[entry.objectID documentIDRepresentation]];
    AssertEqual(entry.check, [doc propertyForKey:@"check"]);
    AssertEqual(@(YES), [doc propertyForKey:@"check"]);

    NSManagedObjectID *objectID = entry.objectID;

    // tear down context to reload from DB
    [self reCreateCoreDataContext];

    entry = (Entry*)[context existingObjectWithID:objectID error:&error];
    Assert((entry != nil), @"Could not re-load entry (%@)", error);
    AssertEqual(entry.text, text);
    AssertEqual(entry.created_at, createdAt);
    AssertEqual(entry.check, @YES);

    [context deleteObject:entry];
    success = [context save:&error];
    Assert(success, @"Could not save context after deletion: %@", error);

    doc = [self documentWithID:[objectID documentIDRepresentation]];
    Assert([doc isDeleted], @"Document not marked as deleted after deletion");
}


/** Test case that tests the integration between Core Data and CouchbaseLite. */
- (void) test_CBLIntegration {
    // cut off seconds as they are not encoded in date values in DB
    NSString *text = @"Test";
    NSNumber *number = @23;

    // first test creation and storage of Core Data entities
    Entry *entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                 inManagedObjectContext:context];

    entry.text = text;
    entry.check = @NO;
    entry.number = number;

    Subentry *subentry = [NSEntityDescription insertNewObjectForEntityForName:@"Subentry"
                                                       inManagedObjectContext:context];
    subentry.number = @123;
    subentry.text = @"abc";
    [entry addSubEntriesObject:subentry];

    File *file = [NSEntityDescription insertNewObjectForEntityForName:@"File"
                                               inManagedObjectContext:context];
    file.filename = @"abc.png";
    file.data = [text dataUsingEncoding:NSUTF8StringEncoding];
    [entry addFilesObject:file];

    NSError *error;
    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    NSManagedObjectID *entryID = entry.objectID;
    NSManagedObjectID *subentryID = subentry.objectID;
    NSManagedObjectID *fileID = file.objectID;

    // get document from Couchbase to check correctness
    CBLDocument *entryDoc = [self documentWithID:[entryID documentIDRepresentation]];
    NSMutableDictionary *entryProperties = [entryDoc.properties mutableCopy];
    AssertEqual(entry.text, [entryProperties objectForKey:@"text"]);
    AssertEqual(text, [entryProperties objectForKey:@"text"]);
    AssertEqual(entry.check, [entryProperties objectForKey:@"check"]);
    AssertEqual(entry.number, [entryProperties objectForKey:@"number"]);
    AssertEqual(number, [entryProperties objectForKey:@"number"]);

    CBLDocument *subentryDoc = [self documentWithID:[subentryID documentIDRepresentation]];
    NSMutableDictionary *subentryProperties = [subentryDoc.properties mutableCopy];
    AssertEqual(subentry.text, [subentryProperties objectForKey:@"text"]);
    AssertEqual(subentry.number, [subentryProperties objectForKey:@"number"]);

    CBLDocument *fileDoc = [self documentWithID:[fileID documentIDRepresentation]];
    NSMutableDictionary *fileProperties = [fileDoc.properties mutableCopy];
    AssertEqual(file.filename, [fileProperties objectForKey:@"filename"]);

    CBLAttachment *attachment = [self attachmentNamed:@"data" ofDocument:fileDoc];
    Assert(attachment != nil, @"Unable to load attachment");
    AssertEqual(file.data, attachment.content);
}


- (void) test_CreateAndUpdate {
    Entry *entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                 inManagedObjectContext:context];
    entry.created_at = [NSDate new];
    entry.text = @"Test";
    NSError *error;
    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    entry.check = @(YES);
    success = [context save:&error];
    Assert(success, @"Could not save context after update 1: %@", error);

    Subentry *subentry = [NSEntityDescription insertNewObjectForEntityForName:@"Subentry"
                                                       inManagedObjectContext:context];
    subentry.text = @"Subentry abc";
    [entry addSubEntriesObject:subentry];
    success = [context save:&error];
    Assert(success, @"Could not save context after update 2: %@", error);

    subentry.number = @123;
    success = [context save:&error];
    Assert(success, @"Could not save context after update 3: %@", error);

    NSManagedObjectID *objectID = entry.objectID;
    // tear down and re-init for checking that data got saved
    [self reCreateCoreDataContext];

    entry = (Entry*)[context existingObjectWithID:objectID error:&error];
    Assert(entry, @"Entry could not be loaded: %@", error);
    AssertEq(entry.subEntries.count, 1u);
    AssertEqual([entry.subEntries valueForKeyPath:@"text"], [NSSet setWithObject:@"Subentry abc"]);
    AssertEqual([entry.subEntries valueForKeyPath:@"number"], [NSSet setWithObject:@123]);
}

- (void) test_ToMany {
    // To-Many with inverse relationship:
    Entry *entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                 inManagedObjectContext:context];
    entry.created_at = [NSDate new];
    entry.text = @"Test";
    entry.check = @NO;
    NSError *error;
    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    for (NSUInteger i = 0; i < 3; i++) {
        Subentry *sub = [NSEntityDescription insertNewObjectForEntityForName:@"Subentry"
                                                      inManagedObjectContext:context];
        sub.text = [NSString stringWithFormat:@"Sub%lu", (unsigned long)i];
        [entry addSubEntriesObject:sub];
    }

    success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

#if NON_INVERSE_RELATIONSHIP_TEST_ENABLED
    // To-Many without inverse relationship:
    for (NSUInteger i = 0; i < 3; i++) {
        NonInverseSubentry *sub = [NSEntityDescription insertNewObjectForEntityForName:@"NonInverseSubentry"
                                                                inManagedObjectContext:context];
        sub.name = [NSString stringWithFormat:@"NonInverseSub%lu", (unsigned long)i];
        [entry addNonInverseSubentriesObject:sub];
    }
    success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);
#endif

    NSManagedObjectID *objectID = entry.objectID;

    // tear down and re-init for checking that data got saved:
    [self reCreateCoreDataContext];

    entry = (Entry*)[context existingObjectWithID:objectID error:&error];
    Assert(entry, @"Entry could not be loaded: %@", error);
    AssertEq(entry.subEntries.count, 3u);


#if NON_INVERSE_RELATIONSHIP_TEST_ENABLED
    // We do not support to-many-non-inverse-relationship.
    AssertEq(entry.nonInverseSubentries.count, 0u);
#endif

    // Tear down and re-init and test with fetch request:
    [self reCreateCoreDataContext];

    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] initWithEntityName:@"Entry"];
    NSArray *result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, 1u);
    entry = result.firstObject;
    AssertEq(entry.subEntries.count, 3u);


#if NON_INVERSE_RELATIONSHIP_TEST_ENABLED
    // We do not support to-many-non-inverse-relationship.
    AssertEq(entry.nonInverseSubentries.count, 0u);
#endif
}

- (void) test_ToManyDeletion {
    Entry *entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                 inManagedObjectContext:context];
    entry.created_at = [NSDate new];
    entry.text = @"Test";
    entry.check = @NO;
    NSError *error;
    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    for (NSUInteger i = 0; i < 3; i++) {
        Subentry *sub = [NSEntityDescription insertNewObjectForEntityForName:@"Subentry"
                                                      inManagedObjectContext:context];
        sub.text = [NSString stringWithFormat:@"Sub%lu", (unsigned long)i];
        [entry addSubEntriesObject:sub];
    }

    success = [context save: &error];
    Assert(success, @"Could not save context: %@", error);

    // Delete one sub entry:
    Subentry* aSubentry = [entry.subEntries anyObject];
    [context deleteObject: aSubentry];
    success = [context save: &error];
    Assert(success, @"Could not save context: %@", error);

    // Check the result:
    NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] initWithEntityName:@"Subentry"];
    NSArray* result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, 2u);

    fetchRequest = [[NSFetchRequest alloc] initWithEntityName:@"Entry"];
    result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, 1u);
    entry = result.firstObject;
    AssertEq(entry.subEntries.count, 2u);

    // Delete entry (cascading):
    [context deleteObject: entry];
    success = [context save: &error];
    Assert(success, @"Could not save context: %@", error);

    // Check the result:
    fetchRequest = [[NSFetchRequest alloc] initWithEntityName:@"Subentry"];
    result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, 0u);

    fetchRequest = [[NSFetchRequest alloc] initWithEntityName:@"Entry"];
    result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, 0u);

    // Tear down and re-init and test with fetch request:
    [self reCreateCoreDataContext];

    // Recheck the result:
    fetchRequest = [[NSFetchRequest alloc] initWithEntityName:@"Subentry"];
    result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, 0u);

    fetchRequest = [[NSFetchRequest alloc] initWithEntityName:@"Entry"];
    result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, 0u);
}

- (void) test_ManyToMany {
    NSMutableSet *entries = [NSMutableSet set];
    for (NSUInteger i = 0; i < 3; i++) {
        Entry *entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                     inManagedObjectContext:context];
        entry.text = [NSString stringWithFormat:@"Entry%lu", (unsigned long)i];
        [entries addObject:entry];
    }

    for (NSUInteger i = 0; i < 3; i++) {
        ManySubentry *subentry = [NSEntityDescription insertNewObjectForEntityForName:@"ManySubentry"
                                                               inManagedObjectContext:context];
        subentry.text = [NSString stringWithFormat:@"Subentry%lu", (unsigned long)i];
        [subentry addEntries:entries];
    }

    NSError *error;
    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    // Tear down and re-init and test with fetch request:
    [self reCreateCoreDataContext];

    // Check the result:
    NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] initWithEntityName:@"Entry"];
    NSArray* result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, 3u);
    for (Entry *entry in result) {
        AssertEq(entry.manySubentries.count, 3u);
        NSMutableArray *expected = [NSMutableArray arrayWithArray:
                                    @[@"Subentry0", @"Subentry1", @"Subentry2"]];
        for (ManySubentry *subentry in entry.manySubentries) {
            NSString *text = subentry.text;
            Assert([expected containsObject:text]);
            [expected removeObject:text];
        }
    }

    fetchRequest = [[NSFetchRequest alloc] initWithEntityName:@"ManySubentry"];
    result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, 3u);
    for (ManySubentry *subentry in result) {
        AssertEq(subentry.entries.count, 3u);
        NSMutableArray *expected = [NSMutableArray arrayWithArray:
                                    @[@"Entry0", @"Entry1", @"Entry2"]];
        for (Entry *entry in subentry.entries) {
            NSString *text = entry.text;
            Assert([expected containsObject:text]);
            [expected removeObject:text];
        }
    }
}

- (void) test_FetchRequest {
    NSUInteger count;
    NSArray *result;

    Entry *entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                 inManagedObjectContext:context];
    entry.created_at = [NSDate new];
    entry.text = @"Test";
    entry.check = @(YES);

    NSError *error;
    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] initWithEntityName:@"Entry"];

    fetchRequest.resultType = NSCountResultType;
    result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, 1u);
    Assert([result[0] intValue] > 0, @"Database should contain more than zero entries (if the testCreateAndUpdate was run)");
    count = [result[0] intValue];

    fetchRequest.resultType = NSDictionaryResultType;
    result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, count);
    Assert([result[0] isKindOfClass:[NSDictionary class]], @"Results are not NSDictionaries");

    fetchRequest.resultType = NSManagedObjectIDResultType;
    result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, 1u);
    Assert([result[0] isKindOfClass:[NSManagedObjectID class]], @"Results are not NSManagedObjectIDs");

    fetchRequest.resultType = NSManagedObjectResultType;
    result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, 1u);
    Assert([result[0] isKindOfClass:[NSManagedObject class]], @"Results are not NSManagedObjects");

    //// Predicate
    entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                          inManagedObjectContext:context];
    entry.created_at = [NSDate new];
    entry.text = @"Test2";
    success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, 2u);
    Assert([result[0] isKindOfClass:[NSManagedObject class]], @"Results are not NSManagedObjects");
    Assert([result[1] isKindOfClass:[NSManagedObject class]], @"Results are not NSManagedObjects");

    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"text == 'Test2'"];
    fetchRequest.resultType = NSCountResultType;
    result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, 1u);
    Assert([result[0] intValue] > 0, @"Database should contain more than zero entries (if the testCreateAndUpdate was run)");
    count = [result[0] intValue];

    fetchRequest.resultType = NSDictionaryResultType;
    result = [context executeFetchRequest:fetchRequest error:&error];
    Assert(result.count == count, @"Fetch request should return same result count as number fetch");
    Assert([result[0] isKindOfClass:[NSDictionary class]], @"Results are not NSDictionaries");

    fetchRequest.resultType = NSManagedObjectIDResultType;
    result = [context executeFetchRequest:fetchRequest error:&error];
    Assert(result.count == count, @"Fetch request should return same result count as number fetch");
    Assert([result[0] isKindOfClass:[NSManagedObjectID class]], @"Results are not NSManagedObjectIDs");

    fetchRequest.resultType = NSManagedObjectResultType;
    result = [context executeFetchRequest:fetchRequest error:&error];
    Assert(result.count == count, @"Fetch request should return same result count as number fetch");
    Assert([result[0] isKindOfClass:[NSManagedObject class]], @"Results are not NSManagedObjects");
}

- (void)test_FetchLimit {
    for (NSUInteger i = 0; i < 100; i++) {
        Entry *entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                     inManagedObjectContext:context];
        entry.created_at = [NSDate new];
        entry.text = [NSString stringWithFormat:@"Entry%lu", (unsigned long)i];
        entry.number = @(i);
    }

    NSError *error;
    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    NSArray *result;
    NSUInteger number = 0;
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] initWithEntityName:@"Entry"];

    // Without predicates
    fetchRequest.fetchLimit = 20;
    result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, 20u);

    // Without predicates ascending sort
    fetchRequest.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"number" ascending:YES]];
    result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, 20u);
    number = 0;
    for (NSManagedObject *obj in result) {
        AssertEqual([obj valueForKey:@"number"], @(number++));
    }

    fetchRequest.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"number" ascending:NO]];
    result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, 20u);
    number = 99;
    for (NSManagedObject *obj in result) {
        AssertEqual([obj valueForKey:@"number"], @(number--));
    }

    // With a predicate, ascending sort
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"number > 20"];
    fetchRequest.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"number" ascending:YES]];
    fetchRequest.fetchLimit = 20;
    result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, 20u);
    number = 21;
    for (NSManagedObject *obj in result) {
        AssertEqual([obj valueForKey:@"number"], @(number++));
    }

    // With a predicate, descending sort
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"number > 20"];
    fetchRequest.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"number" ascending:NO]];
    fetchRequest.fetchLimit = 20;
    result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, 20u);
    number = 99;
    for (NSManagedObject *obj in result) {
        AssertEqual([obj valueForKey:@"number"], @(number--));
    }
}

- (void) test_FetchOffset {
    NSError *error;
    for (NSUInteger i = 0; i < 100; i++) {
        Entry *entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                     inManagedObjectContext:context];
        entry.created_at = [NSDate new];
        entry.text = [NSString stringWithFormat:@"Entry%lu", (unsigned long)i];
        entry.number = @(i);
    }

    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    NSArray *result;
    NSUInteger number = 0;
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] initWithEntityName:@"Entry"];

    // Without predicates
    fetchRequest.fetchOffset = 20;
    result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, 80u);

    // With a predicate
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"number > 19"];
    fetchRequest.fetchOffset = 20;
    result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, 60u);
    number = 40;
    for (NSManagedObject *obj in result) {
        AssertEqual([obj valueForKey:@"number"], @(number++));
    }
}

- (void) test_Attachments {
    NSError *error;
    File *file = [NSEntityDescription insertNewObjectForEntityForName:@"File"
                                               inManagedObjectContext:context];
    file.filename = @"test.txt";

    NSData *data = [@"Test. Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    file.data = data;

    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    CBLDocument *doc = [self documentWithID:[file.objectID documentIDRepresentation]];
    Assert(doc != nil, @"Document should not be nil");
    AssertEqual(file.filename, [doc propertyForKey:@"filename"]);

    CBLAttachment *att = [self attachmentNamed:@"data" ofDocument:doc];
    Assert(att != nil, @"Attachmant should be created");

    NSData *content = att.content;
    Assert(content != nil, @"Content should be loaded");
    AssertEq(content.length, data.length);
    AssertEqual(content, data);

    NSManagedObjectID *fileID = file.objectID;

    // tear down the context to reload from disk
    file = nil;
    [self reCreateCoreDataContext];

    file = (File*)[context existingObjectWithID:fileID error:&error];
    Assert(file != nil, @"File should not be nil (%@)", error);
    AssertEqual(file.data, data);


    // update attachment

    data = [@"Updated. Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    file.data = data;

    success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    doc = [self documentWithID:[file.objectID documentIDRepresentation]];
    Assert(doc != nil, @"Document should not be nil");
    AssertEqual(file.filename, [doc propertyForKey:@"filename"]);

    att = [self attachmentNamed:@"data" ofDocument:doc];
    Assert(att != nil, @"Attachmant should be created");

    content = att.content;
    Assert(content != nil, @"Content should be loaded");
    AssertEq(content.length, data.length);
    AssertEqual(content, data);

    NSString *stringFromContent = [[NSString alloc] initWithData:content encoding:NSUTF8StringEncoding];
    Assert([stringFromContent hasPrefix:@"Updated."], @"Not updated");

    // nullify attachment

    data = nil;
    file.data = data;

    success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    doc = [self documentWithID:[file.objectID documentIDRepresentation]];
    Assert(doc != nil, @"Document should not be nil");
    AssertEqual(file.filename, [doc propertyForKey:@"filename"]);

    att = [self attachmentNamed:@"data" ofDocument:doc];
    AssertNil(att);
}

- (void) test_NullifyProperty {
    NSError *error;

    Entry *entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                 inManagedObjectContext:context];

    NSString *text = @"Test";

    entry.text = text;
    entry.check = @NO;

    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    CBLDocument *doc = [self documentWithID:[entry.objectID documentIDRepresentation]];
    AssertEqual(text, entry.text);
    AssertEqual(text, [doc propertyForKey:@"text"]);

    text = nil;

    entry.text = text;

    success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    doc = [self documentWithID:[entry.objectID documentIDRepresentation]];
    AssertEqual(text, entry.text);
    AssertEqual(text, [doc propertyForKey:@"text"]);
}

- (void) test_NullifyRelationship {
    NSError *error;

    Entry *entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                 inManagedObjectContext:context];

    Subentry *subentry = [NSEntityDescription insertNewObjectForEntityForName:@"Subentry"
                                                       inManagedObjectContext:context];

    BOOL success = [context save:&error];

    CBLDocument *docEntry = [self documentWithID:[entry.objectID documentIDRepresentation]];
    CBLDocument *docSubentry = [self documentWithID:[subentry.objectID documentIDRepresentation]];

    AssertEqual(nil, [docSubentry propertyForKey:@"entry"]);

    subentry.entry = entry;

    success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    docEntry = [self documentWithID:[entry.objectID documentIDRepresentation]];
    docSubentry = [self documentWithID:[subentry.objectID documentIDRepresentation]];

    AssertEqual(docEntry.documentID, [docSubentry propertyForKey:@"entry"]);

    subentry.entry = nil;

    success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    docEntry = [self documentWithID:[entry.objectID documentIDRepresentation]];
    docSubentry = [self documentWithID:[subentry.objectID documentIDRepresentation]];

    AssertEqual(nil, [docSubentry propertyForKey:@"entry"]);
}

- (void) test_FetchWithPredicates {
    NSError *error;

    NSDictionary *entry1 = @{
                             @"created_at": [NSDate new],
                             @"check": @YES,
                             @"text": @"This is a test for predicates. Möhre.",
                             @"text2": @"This is text2.",
                             @"number": [NSNumber numberWithInt:10],
                             @"decimalNumber": [NSDecimalNumber decimalNumberWithString:@"10.10"],
                             @"doubleNumber": [NSNumber numberWithDouble:42.23]
                             };
    NSDictionary *entry2 = @{
                             @"created_at": [[NSDate new] dateByAddingTimeInterval:-60],
                             @"check": @YES,
                             @"text": @"Entry number 2. touché.",
                             @"text2": @"Text 2 by Entry number 2",
                             @"number": [NSNumber numberWithInt:20],
                             @"decimalNumber": [NSDecimalNumber decimalNumberWithString:@"20.20"],
                             @"doubleNumber": [NSNumber numberWithDouble:12.45]
                             };
    NSDictionary *entry3 = @{
                             @"created_at": [[NSDate new] dateByAddingTimeInterval:60],
                             @"check": @NO,
                             @"text": @"Entry number 3",
                             @"text2": @"Text 2 by Entry number 3",
                             @"number": [NSNumber numberWithInt:30],
                             @"decimalNumber": [NSDecimalNumber decimalNumberWithString:@"30.30"],
                             @"doubleNumber": [NSNumber numberWithDouble:98.76]
                             };

    CBLISTestInsertEntriesWithProperties(context, @[entry1, entry2, entry3]);

    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Entry"];

    //// ==
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"text == %@", entry1[@"text"]];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 1);
        if (result.count != 1) return;
        AssertEqual([result[0] valueForKey:@"text"], entry1[@"text"]);
    }];

    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"number == %@", entry1[@"number"]];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 1);
        if (result.count != 1) return;
        AssertEqual([result[0] valueForKey:@"number"], entry1[@"number"]);
    }];

    //// >=
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"number >= %@", entry2[@"number"]];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 2);
        if (result.count != 2) return;
        NSArray *numbers = [[result valueForKey:@"number"] sortedArrayUsingSelector:@selector(compare:)];
        AssertEqual(numbers[0], entry2[@"number"]);
        AssertEqual(numbers[1], entry3[@"number"]);
    }];

    //// <=
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"number <= %@", entry2[@"number"]];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 2);
        if (result.count != 2) return;
        NSArray *numbers = [[result valueForKey:@"number"] sortedArrayUsingSelector:@selector(compare:)];
        AssertEqual(numbers[0], entry1[@"number"]);
        AssertEqual(numbers[1], entry2[@"number"]);
    }];

    //// >
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"number > %@", entry2[@"number"]];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 1);
        if (result.count != 1) return;
        NSArray *numbers = [[result valueForKey:@"number"] sortedArrayUsingSelector:@selector(compare:)];
        AssertEqual(numbers[0], entry3[@"number"]);
    }];

    //// <
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"number < %@", entry2[@"number"]];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 1);
        if (result.count != 1) return;
        NSArray *numbers = [[result valueForKey:@"number"] sortedArrayUsingSelector:@selector(compare:)];
        AssertEqual(numbers[0], entry1[@"number"]);
    }];

    //// !=
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"number != %@", entry2[@"number"]];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 2);
        if (result.count != 2) return;
        NSArray *numbers = [[result valueForKey:@"number"] sortedArrayUsingSelector:@selector(compare:)];
        AssertEqual(numbers[0], entry1[@"number"]);
        AssertEqual(numbers[1], entry3[@"number"]);
    }];

    //// BETWEEN
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"number BETWEEN %@", @[entry1[@"number"], entry2[@"number"]]];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 2);
        if (result.count != 2) return;
        NSArray *numbers = [[result valueForKey:@"number"] sortedArrayUsingSelector:@selector(compare:)];
        AssertEqual(numbers[0], entry1[@"number"]);
        AssertEqual(numbers[1], entry2[@"number"]);
    }];

    //// BEGINSWITH
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"text BEGINSWITH 'Entry'"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 2);
        if (result.count != 2) return;
        AssertEq((int)[[result[0] valueForKey:@"text"] rangeOfString:@"Entry"].location, 0);
        AssertEq((int)[[result[1] valueForKey:@"text"] rangeOfString:@"Entry"].location, 0);
    }];

    //// CONTAINS
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"text CONTAINS 'test'"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 1);
        Assert([[result[0] valueForKey:@"text"] rangeOfString:@"test"].location != NSNotFound);
    }];

    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"text CONTAINS[c] 'This'"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 1);
        Assert([[result[0] valueForKey:@"text"] rangeOfString:@"test"].location != NSNotFound);
    }];

    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"text CONTAINS[c] 'this'"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 1);
        Assert([[result[0] valueForKey:@"text"] rangeOfString:@"test"].location != NSNotFound);
    }];

    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"text CONTAINS 'this'"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 0);
    }];

    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"text CONTAINS 'touche'"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 0);
    }];

    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"text CONTAINS[d] 'touche'"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 1);
    }];

    //// ENDSWITH
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"text ENDSWITH 'touché.'"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 1);
        Assert([[result[0] valueForKey:@"text"] rangeOfString:@"touché."].location != NSNotFound);
    }];

    //// LIKE
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"text LIKE '*number ?*'"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 2);
    }];

    //// MATCH
    // this test fails, although I think it should be correctly filter the second and third entries...: Need to investigate more
    //    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"text MATCHES %@", @"^Entry"];
    //    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
    //        AssertEq((int)result.count, 2);
    //    }];

    //// IN
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"number IN %@", @[@(10), @(30)]];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 2);
        if (result.count != 2) return;
        NSArray *numbers = [[result valueForKey:@"number"] sortedArrayUsingSelector:@selector(compare:)];
        AssertEqual(numbers[0], entry1[@"number"]);
        AssertEqual(numbers[1], entry3[@"number"]);
    }];

    //// AND
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"number == 10 AND decimalNumber == 10.10"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 1);
        if (result.count != 1) return;
        AssertEqual([result[0] valueForKey:@"number"], entry1[@"number"]);
        AssertEqual([result[0] valueForKey:@"decimalNumber"], entry1[@"decimalNumber"]);
    }];

    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"number == 10 AND decimalNumber == 20.10"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 0);
    }];

    //// OR
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"number == 10 OR number == 20"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 2);
        if (result.count != 2) return;
        NSArray *numbers = [[result valueForKey:@"number"] sortedArrayUsingSelector:@selector(compare:)];
        AssertEqual(numbers[0], entry1[@"number"]);
        AssertEqual(numbers[1], entry2[@"number"]);
    }];

    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"number == 11 OR number == 20"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 1);
        NSArray *numbers = [[result valueForKey:@"number"] sortedArrayUsingSelector:@selector(compare:)];
        AssertEqual(numbers[0], entry2[@"number"]);
    }];
}

- (void) test_FetchWithDate {
    NSError *error;

    NSDictionary *entry1 = @{
                             @"created_at": [NSDate new],
                             @"text": @"This is a test for predicates. Möhre.",
                             @"text2": @"This is text2.",
                             @"number": [NSNumber numberWithInt:10],
                             @"decimalNumber": [NSDecimalNumber decimalNumberWithString:@"10.10"],
                             @"doubleNumber": [NSNumber numberWithDouble:42.23]
                             };
    NSDictionary *entry2 = @{
                             @"created_at": [[NSDate new] dateByAddingTimeInterval:-60],
                             @"text": @"Entry number 2. touché.",
                             @"text2": @"Text 2 by Entry number 2",
                             @"number": [NSNumber numberWithInt:20],
                             @"decimalNumber": [NSDecimalNumber decimalNumberWithString:@"20.20"],
                             @"doubleNumber": [NSNumber numberWithDouble:12.45]
                             };
    NSDictionary *entry3 = @{
                             @"created_at": [[NSDate new] dateByAddingTimeInterval:60],
                             @"text": @"Entry number 3",
                             @"text2": @"Text 2 by Entry number 3",
                             @"number": [NSNumber numberWithInt:30],
                             @"decimalNumber": [NSDecimalNumber decimalNumberWithString:@"30.30"],
                             @"doubleNumber": [NSNumber numberWithDouble:98.76]
                             };

    CBLISTestInsertEntriesWithProperties(context, @[entry1, entry2, entry3]);

    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Entry"];

    //// DATE
    NSDate *startDate = [entry1[@"created_at"] dateByAddingTimeInterval:-30];
    NSDate *endDate = [entry1[@"created_at"] dateByAddingTimeInterval:30];
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"%@ <= created_at AND %@ >= created_at", startDate, endDate];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 1);
        if (result.count != 1) return;
        AssertEqual([result[0] valueForKey:@"text"], entry1[@"text"]);
    }];

    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"created_at = %@ ", entry2[@"created_at"]];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 1);
        if (result.count != 1) return;
        AssertEqual([result[0] valueForKey:@"text"], entry2[@"text"]);
    }];
}

- (void)test_FetchBooleanValue {
    NSError *error;

    NSDictionary *entry1 = @{
                             @"created_at": [NSDate new],
                             @"check": @YES,
                             @"text": @"This is a test for predicates. Möhre.",
                             @"text2": @"This is text2.",
                             @"number": [NSNumber numberWithInt:10],
                             @"decimalNumber": [NSDecimalNumber decimalNumberWithString:@"10.10"],
                             @"doubleNumber": [NSNumber numberWithDouble:42.23]
                             };
    NSDictionary *entry2 = @{
                             @"created_at": [[NSDate new] dateByAddingTimeInterval:-60],
                             @"check": @YES,
                             @"text": @"Entry number 2. touché.",
                             @"text2": @"Text 2 by Entry number 2",
                             @"number": [NSNumber numberWithInt:20],
                             @"decimalNumber": [NSDecimalNumber decimalNumberWithString:@"20.20"],
                             @"doubleNumber": [NSNumber numberWithDouble:12.45]
                             };
    NSDictionary *entry3 = @{
                             @"created_at": [[NSDate new] dateByAddingTimeInterval:60],
                             @"check": @NO,
                             @"text": @"Entry number 3",
                             @"text2": @"Text 2 by Entry number 3",
                             @"number": [NSNumber numberWithInt:30],
                             @"decimalNumber": [NSDecimalNumber decimalNumberWithString:@"30.30"],
                             @"doubleNumber": [NSNumber numberWithDouble:98.76]
                             };

    CBLISTestInsertEntriesWithProperties(context, @[entry1, entry2, entry3]);

    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Entry"];

    //// ==
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"check == YES"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 2);
    }];

    //// ==
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"check == NO"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 1);
    }];

    //// !=
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"check != YES"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 1);
    }];

    //// !=
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"check != NO"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 2);
    }];

    [store setCustomProperties:@{kCBLISCustomPropertyQueryBooleanWithNumber: @(YES)}];

    //// ==
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"check == YES"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 2);
    }];

    //// ==
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"check == NO"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 1);
    }];

    //// !=
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"check != YES"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 1);
    }];

    //// !=
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"check != NO"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 2);
    }];
}

- (void)test_FetchWithRelationship {
    User *user1 = [NSEntityDescription insertNewObjectForEntityForName:@"User"
                                                inManagedObjectContext:context];
    user1.name = @"User1";

    User *user2 = [NSEntityDescription insertNewObjectForEntityForName:@"User"
                                                inManagedObjectContext:context];
    user2.name = @"User2";

    // Entry1:
    Entry *entry1 = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                  inManagedObjectContext:context];
    entry1.created_at = [NSDate new];
    entry1.text = @"This is an entry 1.";
    entry1.number = @(10);
    entry1.user = user1;

    for (NSUInteger i = 0; i < 3; i++) {
        Subentry *sub = [NSEntityDescription insertNewObjectForEntityForName:@"Subentry"
                                                      inManagedObjectContext:context];
        sub.text = [NSString stringWithFormat:@"Entry1-Sub%lu", (unsigned long)i];
        sub.number = @(10 + i);
        [entry1 addSubEntriesObject:sub];
    }

    // Entry2:
    Entry *entry2 = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                  inManagedObjectContext:context];
    entry2.created_at = [entry1.created_at dateByAddingTimeInterval:60];
    entry2.text = @"This is an entry 2.";
    entry2.number = @(20);
    entry2.user = user2;

    for (NSUInteger i = 0; i < 3; i++) {
        Subentry *sub = [NSEntityDescription insertNewObjectForEntityForName:@"Subentry"
                                                      inManagedObjectContext:context];
        sub.text = [NSString stringWithFormat:@"Entry2-Sub%lu", (unsigned long)i];
        sub.number = @(20 + i);
        [entry2 addSubEntriesObject:sub];
    }

    // Entry3:
    Entry *entry3 = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                  inManagedObjectContext:context];
    entry3.created_at = [entry2.created_at dateByAddingTimeInterval:60];
    entry3.text = @"This is an entry 3.";
    entry3.number = @(30);
    entry3.user = user1;


    // ManySubentry:
    for (NSUInteger i = 0; i < 4; i++) {
        ManySubentry *subentry = [NSEntityDescription insertNewObjectForEntityForName:@"ManySubentry"
                                                               inManagedObjectContext:context];
        subentry.text = [NSString stringWithFormat:@"ManySubentry%lu", (unsigned long)i];
        subentry.number = @(30 + i);

        if (i < 2) {
            [subentry addEntriesObject:entry1];
            [subentry addEntriesObject:entry2];
        } else {
            [subentry addEntriesObject:entry2];
            [subentry addEntriesObject:entry3];
        }
    }

    NSError *error;
    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    // Reset context and cache:
    [self reCreateCoreDataContext];

    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Entry"];

    // one-to-one
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"user == %@", user1];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 2);
        if (result.count != 2) return;
        NSArray *numbers = [[result valueForKey:@"number"] sortedArrayUsingSelector:@selector(compare:)];
        AssertEqual(numbers[0], entry1.number);
        AssertEqual(numbers[1], entry3.number);
    }];

    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"user.name like %@", user1.name];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 2);
        if (result.count != 2) return;
        NSArray *numbers = [[result valueForKey:@"number"] sortedArrayUsingSelector:@selector(compare:)];
        AssertEqual(numbers[0], entry1.number);
        AssertEqual(numbers[1], entry3.number);
    }];

    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"user.name == %@", user2.name];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 1);
        if (result.count != 1) return;
        AssertEqual([result[0] valueForKey:@"number"], entry2.number);
    }];

    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"user.name beginswith 'User'"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 3);
        if (result.count != 3) return;
        NSArray *numbers = [[result valueForKey:@"number"] sortedArrayUsingSelector:@selector(compare:)];
        AssertEqual(numbers[0], entry1.number);
        AssertEqual(numbers[1], entry2.number);
        AssertEqual(numbers[2], entry3.number);
    }];

    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"user.name beginswith 'User' and created_at == %@", entry3.created_at];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 1);
        if (result.count != 1) return;
        AssertEqual([result[0] valueForKey:@"number"], entry3.number);
    }];

    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"user.name beginswith 'User' and created_at < %@", entry3.created_at];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 2);
        if (result.count != 2) return;
        NSArray *numbers = [[result valueForKey:@"number"] sortedArrayUsingSelector:@selector(compare:)];
        AssertEqual(numbers[0], entry1.number);
        AssertEqual(numbers[1], entry2.number);
    }];

    // one-to-many
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"ANY subEntries.number < 20"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 1);
        if (result.count != 1) return;
        AssertEqual([result[0] valueForKey:@"number"], entry1.number);
    }];

    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"number < 20 AND ANY subEntries.number < 100"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 1);
        if (result.count != 1) return;
        AssertEqual([result[0] valueForKey:@"number"], entry1.number);
    }];

    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"user.name like %@ AND ANY subEntries.number < 100", user2.name];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 1);
        if (result.count != 1) return;
        AssertEqual([result[0] valueForKey:@"number"], entry2.number);
    }];

    // many-to-many
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"ANY manySubentries.number < 32"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 2);
        NSArray *numbers = [[result valueForKey:@"number"] sortedArrayUsingSelector:@selector(compare:)];
        AssertEqual(numbers[0], entry1.number);
        AssertEqual(numbers[1], entry2.number);
    }];

    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"ANY manySubentries.number > 32"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 2);
        NSArray *numbers = [[result valueForKey:@"number"] sortedArrayUsingSelector:@selector(compare:)];
        AssertEqual(numbers[0], entry2.number);
        AssertEqual(numbers[1], entry3.number);
    }];

    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"ANY manySubentries.number > 40"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 0);
    }];

    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"number < 40 AND ANY manySubentries.number < 32"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 2);
        NSArray *numbers = [[result valueForKey:@"number"] sortedArrayUsingSelector:@selector(compare:)];
        AssertEqual(numbers[0], entry1.number);
        AssertEqual(numbers[1], entry2.number);
    }];
}

- (void)test_FetchWithNestedRelationship {
    NSError *error;

    User *user1 = [NSEntityDescription insertNewObjectForEntityForName:@"User"
                                                inManagedObjectContext:context];
    user1.name = @"User1";

    // Entry1:
    Entry *entry1 = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                  inManagedObjectContext:context];
    entry1.created_at = [NSDate new];
    entry1.text = @"This is an entry 1.";
    entry1.number = @(10);
    entry1.user = user1;

    for (NSUInteger i = 0; i < 3; i++) {
        Subentry *sub = [NSEntityDescription insertNewObjectForEntityForName:@"Subentry"
                                                      inManagedObjectContext:context];
        sub.text = [NSString stringWithFormat:@"Entry1-Sub%lu", (unsigned long)i];
        sub.number = @(10 + i);
        [entry1 addSubEntriesObject:sub];
    }

    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    // Reset context and cache:
    [self reCreateCoreDataContext];

    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Subentry"];

    // Simple Many
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"entry == %@", entry1];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 3);
    }];

    // Deep Many
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"entry.user == %@", user1];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 3);
    }];

    // Deep Many with an object id
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"entry.user == %@", [user1 objectID]];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 3);
    }];

    fetchRequest.predicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[[NSPredicate predicateWithFormat:@"entry == %@", entry1], [NSPredicate predicateWithFormat:@"number == 10"]]];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 1);
    }];

    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"entry.user.name like %@", user1.name];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 3);
    }];

    [self reCreateCoreDataContext];

    // Set the max depth to 1:
    store.customProperties = @{kCBLISCustomPropertyMaxRelationshipLoadDepth: @(1)};

    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"entry == %@", entry1];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 3);
    }];

    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"entry.user == %@", user1];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 3);
    }];

    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"entry.user.name like %@", user1];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 0);
    }];
}

- (void)test_FetchWithNestedRelationshipAndSort {
    NSError *error;

    User *user1 = [NSEntityDescription insertNewObjectForEntityForName:@"User"
                                                inManagedObjectContext:context];
    user1.name = @"User1";

    User *user2 = [NSEntityDescription insertNewObjectForEntityForName:@"User"
                                                inManagedObjectContext:context];
    user2.name = @"User2";

    // Entry1:
    Entry *entry1 = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                  inManagedObjectContext:context];
    entry1.created_at = [NSDate new];
    entry1.text = @"This is an entry 1.";
    entry1.number = @(10);
    entry1.user = user1;

    Entry *entry2 = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                  inManagedObjectContext:context];
    entry2.created_at = [NSDate new];
    entry2.text = @"This is an entry 2.";
    entry2.number = @(20);
    entry2.user = user2;

    for (NSUInteger i = 0; i < 3; i++) {
        Subentry *sub = [NSEntityDescription insertNewObjectForEntityForName:@"Subentry"
                                                      inManagedObjectContext:context];
        sub.text = [NSString stringWithFormat:@"Entry1-Sub%lu", (unsigned long)i];
        sub.number = @(10 + i);
        [entry1 addSubEntriesObject:sub];
    }

    for (NSUInteger i = 0; i < 4; i++) {
        Subentry *sub = [NSEntityDescription insertNewObjectForEntityForName:@"Subentry"
                                                      inManagedObjectContext:context];
        sub.text = [NSString stringWithFormat:@"Entry2-Sub%lu", (unsigned long)i];
        sub.number = @(10 + i);
        [entry2 addSubEntriesObject:sub];
    }

    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    // Reset context and cache:
    [self reCreateCoreDataContext];

    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Subentry"];

    // Simple Sort
    fetchRequest.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"text" ascending:NO]];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        NSArray *texts = [result valueForKey:@"text"];
        NSArray *expected = @[@"Entry2-Sub3", @"Entry2-Sub2", @"Entry2-Sub1", @"Entry2-Sub0",
                              @"Entry1-Sub2", @"Entry1-Sub1", @"Entry1-Sub0"];
        AssertEqual (texts, expected);
    }];

    // Simple Sort 2
    fetchRequest.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"text" ascending:YES]];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        NSArray *texts = [result valueForKey:@"text"];
        NSArray *expected = @[@"Entry1-Sub0", @"Entry1-Sub1", @"Entry1-Sub2",
                              @"Entry2-Sub0", @"Entry2-Sub1", @"Entry2-Sub2", @"Entry2-Sub3"];
        AssertEqual (texts, expected);
    }];

    // Deep Sort
    fetchRequest.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"entry.text" ascending:NO],
                                     [NSSortDescriptor sortDescriptorWithKey:@"text" ascending:YES]];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        NSArray *texts = [result valueForKey:@"text"];
        NSArray *expected = @[@"Entry2-Sub0", @"Entry2-Sub1", @"Entry2-Sub2", @"Entry2-Sub3",
                              @"Entry1-Sub0", @"Entry1-Sub1", @"Entry1-Sub2"];
        AssertEqual (texts, expected);
    }];

    // Deep Sort 2
    fetchRequest.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"entry.text" ascending:YES],
                                     [NSSortDescriptor sortDescriptorWithKey:@"text" ascending:YES]];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        NSArray *texts = [result valueForKey:@"text"];
        NSArray *expected = @[@"Entry1-Sub0", @"Entry1-Sub1", @"Entry1-Sub2",
                              @"Entry2-Sub0", @"Entry2-Sub1", @"Entry2-Sub2", @"Entry2-Sub3"];
        AssertEqual (texts, expected);
    }];

    // Deeper Sort
    fetchRequest.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"entry.user.name" ascending:NO],
                                     [NSSortDescriptor sortDescriptorWithKey:@"text" ascending:YES]];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        NSArray *texts = [result valueForKey:@"text"];
        NSArray *expected = @[@"Entry2-Sub0", @"Entry2-Sub1", @"Entry2-Sub2", @"Entry2-Sub3",
                              @"Entry1-Sub0", @"Entry1-Sub1", @"Entry1-Sub2"];
        AssertEqual (texts, expected);
    }];

    // Deeper Sort 2
    fetchRequest.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"entry.user.name" ascending:YES],
                                     [NSSortDescriptor sortDescriptorWithKey:@"text" ascending:YES]];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        NSArray *texts = [result valueForKey:@"text"];
        NSArray *expected = @[@"Entry1-Sub0", @"Entry1-Sub1", @"Entry1-Sub2",
                              @"Entry2-Sub0", @"Entry2-Sub1", @"Entry2-Sub2", @"Entry2-Sub3"];
        AssertEqual (texts, expected);
    }];
}

- (void)test_FetchWithRelationshipNil {
    NSError *error;

    // Entry1:
    Entry *entry1 = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                  inManagedObjectContext:context];
    entry1.created_at = [NSDate new];
    entry1.text = @"This is an entry 1.";
    entry1.number = @(10);

    for (NSUInteger i = 0; i < 3; i++) {
        Subentry *sub = [NSEntityDescription insertNewObjectForEntityForName:@"Subentry"
                                                      inManagedObjectContext:context];
        sub.text = [NSString stringWithFormat:@"Entry1-Sub%lu", (unsigned long)i];
        sub.number = @(10 + i);
        [entry1 addSubEntriesObject:sub];
    }

    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    // Reset context and cache:
    [self reCreateCoreDataContext];

    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Subentry"];

    // Simple Many
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"entry == %@", nil];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 0);
    }];

    // Nil Many
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"entry.user == %@", nil];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        AssertEq((int)result.count, 3);
    }];
}

- (void)test_FetchParentChildEntities {
    Parent *p1 = [NSEntityDescription insertNewObjectForEntityForName:@"Parent"
                                               inManagedObjectContext:context];
    p1.name = @"Parent1";

    Child *c1 = [NSEntityDescription insertNewObjectForEntityForName:@"Child"
                                              inManagedObjectContext:context];
    c1.name = @"Child1";
    c1.anotherName = @"One";

    Child *c2 = [NSEntityDescription insertNewObjectForEntityForName:@"Child"
                                              inManagedObjectContext:context];

    c2.name = @"Child2";
    c2.anotherName = @"Two";

    Parent *p2 = [NSEntityDescription insertNewObjectForEntityForName:@"Parent"
                                               inManagedObjectContext:context];
    p2.name = @"Parent2";

    Child *c3 = [NSEntityDescription insertNewObjectForEntityForName:@"Child"
                                              inManagedObjectContext:context];
    c3.name = @"Child3";
    c3.anotherName = @"Three";

    Child *c4 = [NSEntityDescription insertNewObjectForEntityForName:@"Child"
                                              inManagedObjectContext:context];
    c4.name = @"Child4";
    c4.anotherName = @"Four";

    NSError *error;
    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    NSFetchRequest *fetchRequest;

    fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        NSArray *expected = @[@"Parent1", @"Parent2", @"Child1", @"Child2", @"Child3", @"Child4"];
        [self assertFetchResult:result key:@"name" expected:expected ordered:NO];
    }];

    fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    fetchRequest.includesSubentities = YES;
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        NSArray *expected = @[@"Parent1", @"Parent2", @"Child1", @"Child2", @"Child3", @"Child4"];
        [self assertFetchResult:result key:@"name" expected:expected ordered:NO];
    }];

    fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"name == 'Child3'"];
    fetchRequest.includesSubentities = YES;
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        NSArray *expected = @[@"Child3"];
        [self assertFetchResult:result key:@"name" expected:expected ordered:NO];
    }];

    fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    fetchRequest.includesSubentities = NO;
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        NSArray *expected = @[@"Parent1", @"Parent2"];
        [self assertFetchResult:result key:@"name" expected:expected ordered:NO];
    }];

    fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"name == 'Child3'"];
    fetchRequest.includesSubentities = NO;
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        NSArray *expected = @[];
        [self assertFetchResult:result key:@"name" expected:expected ordered:NO];
    }];

    fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Parent"];
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"anotherName == 'Four'"];
    NSArray *result = [context executeFetchRequest:fetchRequest error:&error];
    Assert(result == nil);
    AssertEq(error.code, CBLIncrementalStoreErrorPredicateKeyPathNotFoundInEntity);

    fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Child"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        NSArray *expected = @[@"Child1", @"Child2", @"Child3", @"Child4"];
        [self assertFetchResult:result key:@"name" expected:expected ordered:NO];
    }];

    fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Child"];
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"anotherName == 'Four'"];
    [self assertFetchRequest: fetchRequest block: ^(NSArray *result, NSFetchRequestResultType resultType) {
        NSArray *expected = @[@"Child4"];
        [self assertFetchResult:result key:@"name" expected:expected ordered:NO];
    }];
}

- (void)test_DocTypeKey {
    Entry *entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                 inManagedObjectContext:context];
    NSString *text = @"Test";
    entry.text = text;

    NSError *error;
    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    CBLDocument *doc = [self documentWithID:[entry.objectID documentIDRepresentation]];
    AssertEqual(entry.text, [doc propertyForKey:@"text"]);
    Assert([[doc.properties allKeys] containsObject:@"type"]);
    AssertEqual(doc.properties[@"type"], @"Entry");
}

- (void)test_DocTypeKeyBackwardCompat {
    // Simulate old version (v.1.0.4 and below).
    __block NSDictionary *metadata;
    [store.database doSync:^{
        metadata = [store.database existingLocalDocumentWithID:@"CBLIS_metadata"];
    }];

    Assert(metadata != nil, @"Cannot find CBLIS_metadata local document");
    __block NSError* error;
    [store.database doSync:^{
        [store.database deleteLocalDocumentWithID:@"CBLIS_metadata" error: &error];
    }];
    Assert(!error, @"Cannot delete CBLIS_metadata local document");

    // Old version of CBLIncrementalStore stores metadata in a document
    CBLDocument *metadataDoc = [self documentWithID: @"CBLIS_metadata"];
    [metadataDoc putProperties:@{metadata[NSStoreUUIDKey]: metadata[NSStoreUUIDKey],
                                 metadata[NSStoreTypeKey]: metadata[NSStoreTypeKey]
                                 } error:&error];
    Assert(!error, @"Cannot create CBLIS_metadata document");

    // Tear down and re-init
    [self reCreateCoreDataContext];

    // The document type key should be 'CBLIS_Type'.
    Entry *entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                 inManagedObjectContext:context];
    NSString *text = @"Test";
    entry.text = text;

    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    CBLDocument *doc = [self documentWithID:[entry.objectID documentIDRepresentation]];
    AssertEqual(entry.text, [doc propertyForKey:@"text"]);
    Assert([[doc.properties allKeys] containsObject:@"CBLIS_type"]);
    AssertEqual(doc.properties[@"CBLIS_type"], @"Entry");
}

- (void)test_ConflictHandler {
    __block NSArray *conflictRevs = nil;
    XCTestExpectation *expectation = [self expectationWithDescription:@"CBLIS Conflict Handler"];
    store.conflictHandler = ^(NSArray* conflictingRevisions) {
        conflictRevs = conflictingRevisions;
        [expectation fulfill];
    };

    NSError *error;
    Entry *entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                 inManagedObjectContext:context];
    entry.text = @"1";

    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    CBLDocument *doc = [self documentWithID:[entry.objectID documentIDRepresentation]];
    AssertEqual(entry.text, [doc propertyForKey:@"text"]);

    CBLSavedRevision* rev1 = doc.currentRevision;

    // Create rev2a:
    NSMutableDictionary* properties = doc.properties.mutableCopy;
    properties[@"text"] = @"2a";
    CBLSavedRevision* rev2a = [doc putProperties: properties error: &error];
    Assert(rev2a, @"Failed to create a new revision: %@", error);

    // Create rev2b:
    properties = rev1.properties.mutableCopy;
    properties[@"text"] = @"2b";
    CBLUnsavedRevision* newRev = [rev1 createRevision];
    newRev.properties = properties;
    CBLSavedRevision* rev2b = [newRev saveAllowingConflict: &error];
    Assert(rev2b, @"Failed to create a conflict revision: %@", error);

    [self waitForExpectationsWithTimeout:5.0 handler:^(NSError *error) {
        Assert(error == nil, "Timeout error: %@", error);
    }];

    AssertEq(conflictRevs.count, 2u);
    AssertEqual(conflictRevs[0], rev2a);
    AssertEqual(conflictRevs[1], rev2b);
}

- (void)test_DefaultConflictHandler {
    [self keyValueObservingExpectationForObject: self keyPath: @"counter" expectedValue: @(1)];

    CBLISConflictHandler defaultHandler = [store.conflictHandler copy];
    __weak IncrementalStore_Tests* weakSelf = self;
    store.conflictHandler = ^(NSArray* conflictingRevisions) {
        defaultHandler(conflictingRevisions);
        weakSelf.counter = 1;
    };

    __block NSError* error;
    Entry* entry = [NSEntityDescription insertNewObjectForEntityForName: @"Entry"
                                                 inManagedObjectContext: context];
    entry.text = @"test";
    BOOL success = [context save: &error];
    Assert(success, @"Could not save context: %@", error);

    NSString* date = [CBLJSON JSONObjectWithDate: [NSDate date]];
    [store.database doSync: ^{
        CBLDocument *doc = [store.database documentWithID: [entry.objectID documentIDRepresentation]];
        AssertEqual(entry.text, [doc propertyForKey: @"text"]);
        CBLSavedRevision* rev1 = doc.currentRevision;

        // Create rev2a:
        NSMutableDictionary* properties = doc.properties.mutableCopy;
        properties[@"check"] = @(YES);
        CBLSavedRevision* rev2a = [doc putProperties: properties error: &error];
        Assert(rev2a, @"Failed to create a new revision: %@", error);

        // Create rev2b:
        properties = rev1.properties.mutableCopy;
        properties[@"created_at"] = date;
        CBLUnsavedRevision* newRev = [rev1 createRevision];
        newRev.properties = properties;
        CBLSavedRevision* rev2b = [newRev saveAllowingConflict: &error];
        Assert(rev2b, @"Failed to create a conflict revision: %@", error);
    }];

    [self waitForExpectationsWithTimeout: 2.0 handler: ^(NSError *error) {
        Assert(error == nil, "Timeout error: %@ (counter = %lu)", error, (unsigned long)self.counter);
    }];

    __block NSDictionary *properties;
    [store.database doSync: ^{
        CBLDocument *doc = [store.database documentWithID: [entry.objectID documentIDRepresentation]];
        CBLSavedRevision* mergedRev = doc.currentRevision;
        Assert([mergedRev.revisionID hasPrefix:@"3-"]);
        AssertEq([[doc getConflictingRevisions: &error] count], 1u);
        properties = mergedRev.properties;
    }];

    AssertEqual(properties[@"text"], @"test");
    AssertEqual(properties[@"check"], @(YES));
    AssertEqual(properties[@"created_at"], date);
}

- (void)test_StoreWillSaveDocument {
    NSError *error;
    Entry *entry1 = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                  inManagedObjectContext:context];
    Assert([context save:&error]);

    CBLDocument *doc1 = [self documentWithID:[entry1.objectID documentIDRepresentation]];
    AssertNil([doc1 propertyForKey:@"code"]);

    // Set delegate:
    store.delegate = self;

    // Update entry1 and create entry2 and user1:
    entry1.text = @"entry1";
    Entry *entry2 = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                  inManagedObjectContext:context];
    User *user1 = [NSEntityDescription insertNewObjectForEntityForName:@"User"
                                                inManagedObjectContext:context];
    Assert([context save:&error]);

    CBLDocument *doc2 = [self documentWithID:[entry2.objectID documentIDRepresentation]];
    CBLDocument *doc3 = [self documentWithID:[user1.objectID documentIDRepresentation]];

    AssertEqual([doc1 propertyForKey:@"code"], @"1234");
    AssertEqual([doc2 propertyForKey:@"code"], @"1234");
    AssertNil([doc3 propertyForKey:@"code"]);

    // Delete (ensure no error):
    [context deleteObject: entry2];
    Assert([context save:&error]);

    // Reset delegate:
    store.delegate = nil;
}

- (void) test_FetchWithGroupBy {
    // Not support GroupBy fetch yet.
    NSError *error;

    NSDictionary *entry1 = @{
                             @"text": @"Name 1",
                             @"check": @YES,
                             };
    NSDictionary *entry2 = @{
                             @"text": @"Name 1",
                             @"check": @YES,
                             };
    NSDictionary *entry3 = @{
                             @"text": @"Name 2",
                             @"check": @YES,
                             };

    CBLISTestInsertEntriesWithProperties(context, @[entry1, entry2, entry3]);

    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Entry"];

    NSEntityDescription *entity = [NSEntityDescription entityForName:@"Entry"
                                              inManagedObjectContext:context];
    NSString *checkPropertyName = @"check";
    NSString *textPropertyName = @"text";
    NSAttributeDescription *checkPropertyDescription = [entity.attributesByName objectForKey:checkPropertyName];
    NSAttributeDescription *textPropertyDescription = [entity.attributesByName objectForKey:textPropertyName];

    [fetchRequest setPropertiesToFetch:[NSArray arrayWithObjects:checkPropertyDescription, textPropertyDescription, nil]];
    [fetchRequest setPropertiesToGroupBy:[NSArray arrayWithObjects:checkPropertyDescription, textPropertyDescription, nil]];
    [fetchRequest setResultType:NSDictionaryResultType];
    [fetchRequest setSortDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:checkPropertyName ascending:YES]]];
    [fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"check == %@", @YES]];

    NSArray *result = [context executeFetchRequest:fetchRequest error:&error];
    Assert(error);
    AssertEq(CBLIncrementalStoreErrorUnsupportedFetchRequest, error.code);
    AssertEq((int)result.count, 0);
}

- (void) test_PurgeObject {
    NSError *error;

    Entry *entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                 inManagedObjectContext:context];
    entry.text = @"Test";
    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    NSString *docID = [entry.objectID documentIDRepresentation];
    __block CBLDocument *doc;
    [store.database doSync:^{
        doc = [store.database existingDocumentWithID: docID];
    }];
    Assert(doc != nil);
    Assert(!entry.isDeleted);

    success = [store purgeObject: entry error: &error];

    Assert(success, @"Could not purge object: %@", error);

    __block CBLDocument *cachedDoc;
    [store.database doSync:^{
        cachedDoc = [store.database _cachedDocumentWithID: docID];
    }];
    AssertNil(cachedDoc);
}

#pragma mark - Performance

#if PERFORMANCE_TEST_ENABLED

- (void) test_PerformanceSave {
    if (!self.isSQLiteDB)
        return;

    NSArray *metrics = [[self class] defaultPerformanceMetrics];
    [self measureMetrics:metrics automaticallyStartMeasuring:NO forBlock:^{
        for (NSInteger i = 1; i < 1000; i++) {
            Entry *entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                         inManagedObjectContext:context];
            entry.created_at = [NSDate new];
            entry.text = [NSString stringWithFormat:@"Test %@", @(i)];
            entry.check = @(YES);

            Subentry *subentry = [NSEntityDescription insertNewObjectForEntityForName:@"Subentry"
                                                               inManagedObjectContext:context];
            subentry.text = @"Subentry abc";
            subentry.number = @123;
            [entry addSubEntriesObject:subentry];
        }

        [self startMeasuring];

        NSError *error;
        BOOL success = [context save:&error];
        Assert(success, @"Could not save context: %@", error);

        [self stopMeasuring];
    }];
}

- (void) test_PerformanceFetchWithContextReset {
    if (!self.isSQLiteDB)
        return;

    for (NSInteger i = 1; i < 1000; i++) {
        Entry *entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                     inManagedObjectContext:context];
        entry.created_at = [NSDate new];
        entry.text = [NSString stringWithFormat:@"Test %@", @(i)];
        entry.check = (i%3) ? @(YES) : @(NO);

        Subentry *subentry = [NSEntityDescription insertNewObjectForEntityForName:@"Subentry"
                                                           inManagedObjectContext:context];
        subentry.text = @"Subentry abc";
        subentry.number = @123;
        [entry addSubEntriesObject:subentry];
    }

    NSError *error;
    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    NSArray *metrics = [[self class] defaultPerformanceMetrics];
    [self measureMetrics:metrics automaticallyStartMeasuring:NO forBlock:^{
        // This will make all the Core Data and CBLIS cache gone:
        [self reCreateCoreDataContext];

        [self startMeasuring];

        NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Entry"];
        request.fetchLimit = 1;
        request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"created_at" ascending:YES]];

        NSError *error;
        [context executeFetchRequest:request error:&error];
        AssertNil(error);

        [self stopMeasuring];
    }];
}

- (void) test_PerformanceFetchWithoutContextReset {
    // Note: Wihtout resetting the context, the fetch result cache will be used:
    if (!self.isSQLiteDB)
        return;

    for (NSInteger i = 1; i < 1000; i++) {
        Entry *entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                     inManagedObjectContext:context];
        entry.created_at = [NSDate new];
        entry.text = [NSString stringWithFormat:@"Test %@", @(i)];
        entry.check = (i%3) ? @(YES) : @(NO);

        Subentry *subentry = [NSEntityDescription insertNewObjectForEntityForName:@"Subentry"
                                                           inManagedObjectContext:context];
        subentry.text = @"Subentry abc";
        subentry.number = @123;
        [entry addSubEntriesObject:subentry];
    }

    NSError *error;
    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    NSArray *metrics = [[self class] defaultPerformanceMetrics];
    [self measureMetrics:metrics automaticallyStartMeasuring:NO forBlock:^{
        [self startMeasuring];

        NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Entry"];
        request.fetchLimit = 1;
        request.sortDescriptors =
        @[[NSSortDescriptor sortDescriptorWithKey:@"created_at" ascending:YES]];

        NSError *error;
        [context executeFetchRequest:request error:&error];
        AssertNil(error);

        [self stopMeasuring];
    }];
}

- (void) test_PerformanceFetchWithIncreasingData {
    if (!self.isSQLiteDB)
        return;

    NSArray *metrics = [[self class] defaultPerformanceMetrics];
    [self measureMetrics:metrics automaticallyStartMeasuring:NO forBlock:^{
        for (NSInteger i = 1; i < 1000; i++) {
            Entry *entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                         inManagedObjectContext:context];
            entry.created_at = [NSDate new];
            entry.text = [NSString stringWithFormat:@"Test %@", @(i)];

            entry.check = (i%3) ? @(YES) : @(NO);

            Subentry *subentry = [NSEntityDescription insertNewObjectForEntityForName:@"Subentry"
                                                               inManagedObjectContext:context];
            subentry.text = @"Subentry abc";
            subentry.number = @123;
            [entry addSubEntriesObject:subentry];
        }

        NSError *error;
        BOOL success = [context save:&error];
        Assert(success, @"Could not save context: %@", error);

        [self reCreateCoreDataContext];

        [self startMeasuring];

        NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Entry"];
        request.predicate = [NSPredicate predicateWithFormat:@"%K == %@", @"check", @(YES)];
        request.sortDescriptors =
        @[[NSSortDescriptor sortDescriptorWithKey:@"created_at" ascending:YES]];

        [context executeFetchRequest:request error:&error];

        [self stopMeasuring];

        [self reCreateCoreDataContext];
    }];
}

- (void) test_PerformanceCBLDatabaseChanged {
    if (!self.isSQLiteDB)
        return;

    static NSUInteger docCount = 1000;

    NSArray *metrics = [[self class] defaultPerformanceMetrics];
    [self measureMetrics:metrics automaticallyStartMeasuring:NO forBlock:^{
        store.shouldNotifyLocalDatabaseChanges = YES;

        XCTestExpectation *expectation = [self expectationWithDescription:@"CBLIS Changed Notification"];

        [self startMeasuring];

        __block NSUInteger count = 0;

        [[NSNotificationCenter defaultCenter] addObserverForName:kCBLISObjectHasBeenChangedInStoreNotification
                                                          object:store
                                                           queue:nil
                                                      usingBlock:^(NSNotification *note) {
                                                          if (++count == docCount) {
                                                              NSError *error;
                                                              NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Entry"];
                                                              request.sortDescriptors =
                                                              @[[NSSortDescriptor sortDescriptorWithKey:@"created_at" ascending:YES]];

                                                              NSArray *result = [context executeFetchRequest:request error:&error];
                                                              Assert(docCount == result.count);
                                                              [expectation fulfill];
                                                          }
                                                      }];

        [store.database doSync:^{
            for (NSUInteger i = 0; i < docCount; i++) {
                NSDictionary *properties = @{@"created_at": [CBLJSON JSONObjectWithDate: [NSDate new]],
                                             @"text": [NSString stringWithFormat: @"Test %@", @(i)],
                                             @"type": @"Entry",
                                             @"check": (i%3) ? @(YES) : @(NO)};
                CBLDocument *doc = [self createDocumentWithProperties: properties];
                NSString *docID = doc.documentID;
                AssertEqual(doc.userProperties, properties);
                AssertEq([self documentWithID: docID], doc);

                [store.database _clearDocumentCache]; // so we can load fresh copies

                CBLDocument *doc2 = [db existingDocumentWithID: docID];
                AssertEqual(doc2.documentID, docID);
            }
        }];

        [self waitForExpectationsWithTimeout:30.0 handler:^(NSError *error) {
            [self stopMeasuring];
            Assert(error == nil, "Timeout error: %@", error);
        }];

        [store.database doSync:^{
            [store.database deleteDatabase:nil];
        }];
        [self reCreateCoreDataContext];
    }];

    store.shouldNotifyLocalDatabaseChanges = NO;
}

#endif


#pragma mark - CBLIncrementalStoreDelegate

- (NSDictionary *)storeWillSaveDocument:(NSDictionary *)props {
    if ([props[@"type"] isEqualToString:@"Entry"]) {
        NSMutableDictionary* newProps = [props mutableCopy];
        newProps[@"code"] = @"1234";
        return newProps;
    }
    return props;
}

#pragma mark - UTILITIES

- (void)assertFetchRequest:(NSFetchRequest *)fetchRequest
                     block:(CBLISAssertionBlock)assertionBlock {
    NSFetchRequestResultType resultTypes[] = {NSManagedObjectResultType, NSDictionaryResultType};
    for (int index = 0; index < 1; index++) {
        fetchRequest.resultType = resultTypes[index];
        NSError *error;
        NSArray *result = [context executeFetchRequest:fetchRequest error:&error];
        Assert(result != nil, @"Could not execute fetch request: %@", error);
        assertionBlock(result, fetchRequest.resultType);
    }
}

- (void)assertFetchResult:(NSArray *)result key:(NSString *)key
                 expected:(NSArray *)values ordered:(BOOL)ordered {
    AssertEq(result.count, values.count);
    NSMutableArray *valueList = [NSMutableArray arrayWithArray:values];
    NSInteger i = 0;
    for (NSManagedObject *obj in result) {
        NSString *value = [obj valueForKey:key];
        if (ordered)
            AssertEqual(valueList[i], value);
        else {
            Assert([valueList containsObject:value]);
            [valueList removeObject:value];
        }
        i++;
    }
}

@end

#pragma mark - Test Core Data Model

static NSAttributeDescription *CBLISAttributeDescription(NSString *name, BOOL optional, NSAttributeType type, id defaultValue)
{
    NSAttributeDescription *attribute = [NSAttributeDescription new];
    [attribute setName:name];
    [attribute setOptional:optional];
    [attribute setAttributeType:type];
    if (defaultValue) {
        [attribute setDefaultValue:defaultValue];
    }
    return attribute;
}


static NSRelationshipDescription *CBLISRelationshipDescription(NSString *name, BOOL optional, BOOL toMany, NSDeleteRule deletionRule, NSEntityDescription *destinationEntity)
{
    NSRelationshipDescription *relationship = [NSRelationshipDescription new];
    [relationship setName:name];
    [relationship setOptional:optional];
    [relationship setMinCount:optional ? 0 : 1];
    [relationship setMaxCount:toMany ? 0 : 1];
    [relationship setDeleteRule:deletionRule];
    [relationship setDestinationEntity:destinationEntity];
    return relationship;
}


static NSManagedObjectModel *CBLISTestCoreDataModel(void)
{
    NSManagedObjectModel *model = [NSManagedObjectModel new];

    NSEntityDescription *entry = [NSEntityDescription new];
    [entry setName:@"Entry"];
    [entry setManagedObjectClassName:@"Entry"];

    NSEntityDescription *file = [NSEntityDescription new];
    [file setName:@"File"];
    [file setManagedObjectClassName:@"File"];

    NSEntityDescription *subentry = [NSEntityDescription new];
    [subentry setName:@"Subentry"];
    [subentry setManagedObjectClassName:@"Subentry"];

    NSEntityDescription *manySubentry = [NSEntityDescription new];
    [manySubentry setName:@"ManySubentry"];
    [manySubentry setManagedObjectClassName:@"ManySubentry"];

    NSEntityDescription *user = [NSEntityDescription new];
    [user setName:@"User"];
    [user setManagedObjectClassName:@"User"];

    NSEntityDescription *parent = [NSEntityDescription new];
    [parent setName:@"Parent"];
    [parent setManagedObjectClassName:@"Parent"];

    NSEntityDescription *child = [NSEntityDescription new];
    [child setName:@"Child"];
    [child setManagedObjectClassName:@"Child"];
    [parent setSubentities:@[child]];

    NSRelationshipDescription *entrySubentries = CBLISRelationshipDescription(@"subEntries", YES, YES, NSCascadeDeleteRule, subentry);
    NSRelationshipDescription *entryFiles = CBLISRelationshipDescription(@"files", YES, YES, NSCascadeDeleteRule, file);
    NSRelationshipDescription *entryUser = CBLISRelationshipDescription(@"user", YES, NO, NSCascadeDeleteRule, user);
    NSRelationshipDescription *entryManySubentries = CBLISRelationshipDescription(@"manySubentries", YES, YES, NSNullifyDeleteRule, manySubentry);

    NSRelationshipDescription *subentryEntry = CBLISRelationshipDescription(@"entry", YES, NO, NSNullifyDeleteRule, entry);
    NSRelationshipDescription *fileEntry = CBLISRelationshipDescription(@"entry", YES, NO, NSNullifyDeleteRule, entry);
    NSRelationshipDescription *manySubentryEntries = CBLISRelationshipDescription(@"entries", YES, YES, NSNullifyDeleteRule, entry);
    NSRelationshipDescription *userEntry = CBLISRelationshipDescription(@"entry", YES, NO, NSNullifyDeleteRule, entry);

    [entrySubentries setInverseRelationship:subentryEntry];
    [entryFiles setInverseRelationship:fileEntry];
    [entryManySubentries setInverseRelationship:manySubentryEntries];

    [fileEntry setInverseRelationship:entryFiles];
    [subentryEntry setInverseRelationship:entrySubentries];
    [manySubentryEntries setInverseRelationship:entryManySubentries];
    [userEntry setInverseRelationship:entryUser];

    [entry setProperties:@[
                           CBLISAttributeDescription(@"check", YES, NSBooleanAttributeType, nil),
                           CBLISAttributeDescription(@"created_at", YES, NSDateAttributeType, nil),
                           CBLISAttributeDescription(@"decimalNumber", YES, NSDecimalAttributeType, @(0.0)),
                           CBLISAttributeDescription(@"doubleNumber", YES, NSDoubleAttributeType, @(0.0)),
                           CBLISAttributeDescription(@"number", YES, NSInteger16AttributeType, @(0)),
                           CBLISAttributeDescription(@"text", YES, NSStringAttributeType, nil),
                           CBLISAttributeDescription(@"text2", YES, NSStringAttributeType, nil),
                           entryFiles,
                           entrySubentries,
                           entryManySubentries,
                           entryUser
                           ]];

    [file setProperties:@[
                          CBLISAttributeDescription(@"data", YES, NSBinaryDataAttributeType, nil),
                          CBLISAttributeDescription(@"filename", YES, NSStringAttributeType, nil),
                          fileEntry
                          ]];

    [subentry setProperties:@[
                              CBLISAttributeDescription(@"number", YES, NSInteger32AttributeType, @(0)),
                              CBLISAttributeDescription(@"text", YES, NSStringAttributeType, nil),
                              subentryEntry
                              ]];

    [manySubentry setProperties:@[
                                  CBLISAttributeDescription(@"number", YES, NSInteger32AttributeType, @(0)),
                                  CBLISAttributeDescription(@"text", YES, NSStringAttributeType, nil),
                                  manySubentryEntries
                                  ]];

    [user setProperties:@[
                          CBLISAttributeDescription(@"name", YES, NSStringAttributeType, nil),
                          userEntry
                          ]];

    [parent setProperties:@[
                            CBLISAttributeDescription(@"name", YES, NSStringAttributeType, nil)
                            ]];

    [child setProperties:@[
                           CBLISAttributeDescription(@"anotherName", YES, NSStringAttributeType, nil)
                           ]];

    [model setEntities:@[entry, file, subentry, manySubentry, user, parent, child]];


#if NON_INVERSE_RELATIONSHIP_TEST_ENABLED
    NSEntityDescription *nonInverseSubentry = [NSEntityDescription new];
    [nonInverseSubentry setName:@"NonInverseSubentry"];
    [nonInverseSubentry setManagedObjectClassName:@"NonInverseSubentry"];
    [nonInverseSubentry setProperties:@[ CBLISAttributeDescription(@"name", YES, NSStringAttributeType, nil)]];

    NSRelationshipDescription *entryNonInverseSubentries =
    CBLISRelationshipDescription(@"nonInverseSubentries", YES, YES, NSCascadeDeleteRule, nonInverseSubentry);
    
    NSMutableArray *entryProperties = [NSMutableArray arrayWithArray:entry.properties];
    [entryProperties addObject:entryNonInverseSubentries];
    [entry setProperties:entryProperties];
    
    
    NSMutableArray *modelEntities = [NSMutableArray arrayWithArray:model.entities];
    [modelEntities addObject:nonInverseSubentry];
    [model setEntities:modelEntities];
#endif
    
    return model;
}

@implementation Entry
@dynamic check, created_at, text, text2, number, decimalNumber, doubleNumber;
@dynamic subEntries, files, manySubentries;
@dynamic user;

#if NON_INVERSE_RELATIONSHIP_TEST_ENABLED
@dynamic nonInverseSubentries;
#endif

@end

@implementation Subentry
@dynamic text, number, entry;
@end

@implementation ManySubentry
@dynamic text, number, entries;
@end

@implementation File
@dynamic filename, data, entry;
@end

@implementation NonInverseSubentry
@dynamic name;
@end

@implementation User
@dynamic name, entry;
@end

@implementation Parent
@dynamic name;
@end

@implementation Child
@dynamic anotherName;
@end

static Entry *CBLISTestInsertEntryWithProperties(NSManagedObjectContext *context, NSDictionary *props)
{
    Entry *entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                 inManagedObjectContext:context];
    [entry setValuesForKeysWithDictionary:props];
    return  entry;
}


static NSArray *CBLISTestInsertEntriesWithProperties(NSManagedObjectContext *context, NSArray *entityProps)
{
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:entityProps.count];
    for (NSDictionary *props in entityProps) {
        [result addObject:CBLISTestInsertEntryWithProperties(context, props)];
    }
    return result;
}
