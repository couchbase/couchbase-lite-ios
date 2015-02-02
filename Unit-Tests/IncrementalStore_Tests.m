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


@interface CBLIncrementalStore (Internal)
- (void) stop;
@end


@interface IncrementalStore_Tests : CBLTestCaseWithDB
@end


#pragma mark - Helper Classes / Methods

typedef void(^CBLISAssertionBlock)(NSArray *result, NSFetchRequestResultType resultType);

@class Entry;
@class Subentry;
@class File;
@class Article;

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
@property (nonatomic, retain) NSSet *articles;
@end

@interface Entry (CoreDataGeneratedAccessors)
- (void)addSubEntriesObject:(Subentry *)value;
- (void)removeSubEntriesObject:(Subentry *)value;
- (void)addSubEntries:(NSSet *)values;
- (void)removeSubEntries:(NSSet *)values;

- (void)addFilesObject:(File *)value;
- (void)removeFilesObject:(File *)value;
- (void)addFiles:(NSSet *)values;
- (void)removeFiles:(NSSet *)values;

- (void)addArticlesObject:(Article *)value;
- (void)removeArticlesObject:(Article *)value;
- (void)addArticles:(NSSet *)values;
- (void)removeArticles:(NSSet *)values;
@end

@interface Subentry : NSManagedObject
@property (nonatomic, retain) NSString * text;
@property (nonatomic, retain) NSNumber * number;
@property (nonatomic, retain) Entry *entry;
@end

@interface File : NSManagedObject
@property (nonatomic, retain) NSString * filename;
@property (nonatomic, retain) NSData * data;
@property (nonatomic, retain) Entry *entry;
@end

@interface Article : NSManagedObject
@property (nonatomic, retain) NSString * name;
@end

@interface NSManagedObjectID (CBLIncrementalStore)
- (NSString*) couchbaseLiteIDRepresentation;
@end


#pragma mark - Tests


@implementation IncrementalStore_Tests
{
    NSManagedObjectModel *model;
    NSManagedObjectContext *context;
    CBLIncrementalStore *store;
}


- (void) setUp {
    [super setUp];

    NSError* error;
    [CBLIncrementalStore setCBLManager: dbmgr];
    model = CBLISTestCoreDataModel();
    context = [CBLIncrementalStore createManagedObjectContextWithModel:model
                                                          databaseName:db.name
                                                                 error:&error];
    Assert(context, @"Context could not be created: %@", error);

    store = context.persistentStoreCoordinator.persistentStores[0];
    Assert(store, @"Context doesn't have any store?!");

    AssertEq(store.database, db);
}

- (void) tearDown {
    [store stop];
    [super tearDown];
}


/** Test case that tests create, request, update and delete of Core Data objects. */
- (void) test_CRUD
{
    RequireTestCase(API);
    NSError *error;
    
    CBLDatabase *database = store.database;
    
    Entry *entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                 inManagedObjectContext:context];
    
    // cut off seconds as they are not encoded in date values in DB
    NSDate *createdAt = [NSDate dateWithTimeIntervalSince1970:(long)[NSDate new].timeIntervalSince1970];
    NSString *text = @"Test";
    
    entry.created_at = createdAt;
    entry.text = text;
    entry.check = @NO;
    
    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);
    
    CBLDocument *doc = [database documentWithID:[entry.objectID couchbaseLiteIDRepresentation]];
    AssertEqual(entry.text, [doc propertyForKey:@"text"]);
    
    NSDate *date1 = entry.created_at;
    NSDate *date2 = [CBLJSON dateWithJSONObject:[doc propertyForKey:@"created_at"]];
    int diffInSeconds = (int)floor([date1 timeIntervalSinceDate:date2]);
    AssertEq(diffInSeconds, 0);
    AssertEqual(entry.check, [doc propertyForKey:@"check"]);

    entry.check = @(YES);

    success = [context save:&error];
    Assert(success, @"Could not save context after update: %@", error);
    
    doc = [database documentWithID:[entry.objectID couchbaseLiteIDRepresentation]];
    AssertEqual(entry.check, [doc propertyForKey:@"check"]);
    AssertEqual(@(YES), [doc propertyForKey:@"check"]);

    NSManagedObjectID *objectID = entry.objectID;
    
    // tear down context to reload from DB
    context = [CBLIncrementalStore createManagedObjectContextWithModel:model
                                                          databaseName:database.name error:&error];
    database = store.database;
    
    entry = (Entry*)[context existingObjectWithID:objectID error:&error];
    Assert((entry != nil), @"Could not re-load entry (%@)", error);
    AssertEqual(entry.text, text);
    AssertEqual(entry.created_at, createdAt);
    AssertEqual(entry.check, @YES);
    
    [context deleteObject:entry];
    success = [context save:&error];
    Assert(success, @"Could not save context after deletion: %@", error);
    
    doc = [database documentWithID:[objectID couchbaseLiteIDRepresentation]];
    Assert([doc isDeleted], @"Document not marked as deleted after deletion");
}


/** Test case that tests the integration between Core Data and CouchbaseLite. */
- (void) test_CBLIntegration
{
    RequireTestCase(CBLIncrementalStoreCRUD);
    NSError *error;
    
    CBLDatabase *database = store.database;
    
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

    Article *article = [NSEntityDescription insertNewObjectForEntityForName:@"Article"
                                                     inManagedObjectContext:context];
    article.name = @"An Article";
    [entry addArticlesObject:article];
    
    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);
    
    NSManagedObjectID *entryID = entry.objectID;
    NSManagedObjectID *subentryID = subentry.objectID;
    NSManagedObjectID *fileID = file.objectID;
    NSManagedObjectID *articleID = article.objectID;
    
    // get document from Couchbase to check correctness
    CBLDocument *entryDoc = [database documentWithID:[entryID couchbaseLiteIDRepresentation]];
    NSMutableDictionary *entryProperties = [entryDoc.properties mutableCopy];
    AssertEqual(entry.text, [entryProperties objectForKey:@"text"]);
    AssertEqual(text, [entryProperties objectForKey:@"text"]);
    AssertEqual(entry.check, [entryProperties objectForKey:@"check"]);
    AssertEqual(entry.number, [entryProperties objectForKey:@"number"]);
    AssertEqual(number, [entryProperties objectForKey:@"number"]);
    
    CBLDocument *subentryDoc = [database documentWithID:[subentryID couchbaseLiteIDRepresentation]];
    NSMutableDictionary *subentryProperties = [subentryDoc.properties mutableCopy];
    AssertEqual(subentry.text, [subentryProperties objectForKey:@"text"]);
    AssertEqual(subentry.number, [subentryProperties objectForKey:@"number"]);
    
    CBLDocument *fileDoc = [database documentWithID:[fileID couchbaseLiteIDRepresentation]];
    NSMutableDictionary *fileProperties = [fileDoc.properties mutableCopy];
    AssertEqual(file.filename, [fileProperties objectForKey:@"filename"]);

    CBLDocument *articleDoc = [database documentWithID:[articleID couchbaseLiteIDRepresentation]];
    NSMutableDictionary *articleProperties = [articleDoc.properties mutableCopy];
    AssertEqual(article.name, [articleProperties objectForKey:@"name"]);
    
    CBLAttachment *attachment = [fileDoc.currentRevision attachmentNamed:@"data"];
    Assert(attachment != nil, @"Unable to load attachment");
    AssertEqual(file.data, attachment.content);
    
    // now change the properties in CouchbaseLite and check if those are available in Core Data
    [entryProperties setObject:@"different text" forKey:@"text"];
    [entryProperties setObject:@NO forKey:@"check"];
    [entryProperties setObject:@42 forKey:@"number"];
    id revisions = [entryDoc putProperties:entryProperties error:&error];
    Assert(revisions != nil, @"Couldn't persist changed properties in CBL: %@", error);
    Assert(error == nil, @"Couldn't persist changed properties in CBL: %@", error);

    // wait for changes to be notified
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
    
    entry = (Entry*)[context existingObjectWithID:entryID error:&error];
    Assert(entry != nil, @"Couldn load entry: %@", error);
    
    // if one of the following fails, make sure you compiled the CBLIncrementalStore with CBLIS_NO_CHANGE_COALESCING=1
    AssertEqual(entry.text, [entryProperties objectForKey:@"text"]);
    AssertEqual(entry.check, [entryProperties objectForKey:@"check"]);
    AssertEqual(entry.number, [entryProperties objectForKey:@"number"]);
}


- (void) test_CreateAndUpdate
{
    RequireTestCase(CBLIncrementalStoreCRUD);
    NSError *error;
    
    Entry *entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                 inManagedObjectContext:context];
    entry.created_at = [NSDate new];
    entry.text = @"Test";
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

    Article *article = [NSEntityDescription insertNewObjectForEntityForName:@"Article"
                                                     inManagedObjectContext:context];
    article.name = @"An Article";
    [entry addArticlesObject:article];
    success = [context save:&error];
    Assert(success, @"Could not save context after update 4: %@", error);
    
    NSManagedObjectID *objectID = entry.objectID;
    // tear down and re-init for checking that data got saved
    context = [CBLIncrementalStore createManagedObjectContextWithModel:model
                                                          databaseName:db.name error:&error];
    
    entry = (Entry*)[context existingObjectWithID:objectID error:&error];
    Assert(entry, @"Entry could not be loaded: %@", error);
    AssertEq(entry.subEntries.count, (unsigned int)1);
    AssertEqual([entry.subEntries valueForKeyPath:@"text"], [NSSet setWithObject:@"Subentry abc"]);
    AssertEqual([entry.subEntries valueForKeyPath:@"number"], [NSSet setWithObject:@123]);
    AssertEqual([entry.articles valueForKeyPath:@"name"], [NSSet setWithObject:@"An Article"]);
    Assert([entry.decimalNumber isKindOfClass:[NSDecimalNumber class]], @"decimalNumber must be with type NSDecimalNumber");
}


- (void) test_ToManyRelationship
{
    RequireTestCase(CBLIncrementalStoreCRUD);
    NSError *error;

    // To-Many with inverse relationship
    Entry *entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                 inManagedObjectContext:context];
    entry.created_at = [NSDate new];
    entry.text = @"Test";
    entry.check = @NO;
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

    // To-Many without inverse relationship
    for (NSUInteger i = 0; i < 3; i++) {
        Article *article = [NSEntityDescription insertNewObjectForEntityForName:@"Article"
                                                         inManagedObjectContext:context];
        article.name = [NSString stringWithFormat:@"Article%lu", (unsigned long)i];
        [entry addArticlesObject:article];
    }

    success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);

    NSManagedObjectID *objectID = entry.objectID;

    // tear down and re-init for checking that data got saved
    context = [CBLIncrementalStore createManagedObjectContextWithModel:model
                                                          databaseName:db.name error:&error];

    entry = (Entry*)[context existingObjectWithID:objectID error:&error];
    Assert(entry, @"Entry could not be loaded: %@", error);
    AssertEq(entry.subEntries.count, 3u);
    AssertEq(entry.articles.count, 3u);

    // tear down and re-init and test with fetch request
    context = [CBLIncrementalStore createManagedObjectContextWithModel:model
                                                          databaseName:db.name error:&error];

    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] initWithEntityName:@"Entry"];
    NSArray *result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, 1u);
    entry = result.firstObject;
    AssertEq(entry.subEntries.count, 3u);
    AssertEq(entry.articles.count, 3u);
}


- (void) test_FetchRequest
{
    RequireTestCase(CBLIncrementalStoreCRUD);
    NSError *error;

    Entry *entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                 inManagedObjectContext:context];
    entry.created_at = [NSDate new];
    entry.text = @"Test";
    entry.check = @(YES);
    
    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);
    
    
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] initWithEntityName:@"Entry"];
    
    fetchRequest.resultType = NSCountResultType;
    
    NSArray *result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, (NSUInteger)1);
    Assert([result[0] intValue] > 0, @"Database should contain more than zero entries (if the testCreateAndUpdate was run)");
    
    NSUInteger count = [result[0] intValue];
    
    fetchRequest.resultType = NSDictionaryResultType;
    
    result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, count);
    Assert([result[0] isKindOfClass:[NSDictionary class]], @"Results are not NSDictionaries");
    
    
    fetchRequest.resultType = NSManagedObjectIDResultType;
    
    result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, count);
    Assert([result[0] isKindOfClass:[NSManagedObjectID class]], @"Results are not NSManagedObjectIDs");
    
    
    fetchRequest.resultType = NSManagedObjectResultType;
    
    result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, count);
    Assert([result[0] isKindOfClass:[NSManagedObject class]], @"Results are not NSManagedObjects");
    
    //// Predicate
    
    entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                          inManagedObjectContext:context];
    entry.created_at = [NSDate new];
    entry.text = @"Test2";
    
    success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);
    
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"text == 'Test2'"];
    
    fetchRequest.resultType = NSCountResultType;
    
    result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, (NSUInteger)1);
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


- (void) test_Attachments
{
    RequireTestCase(CBLIncrementalStoreCRUD);
    NSError *error;
    CBLDatabase *database = store.database;
    
    File *file = [NSEntityDescription insertNewObjectForEntityForName:@"File"
                                               inManagedObjectContext:context];
    file.filename = @"test.txt";
    
    NSData *data = [@"Test. Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    file.data = data;
    
    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);
    
    CBLDocument *doc = [database documentWithID:[file.objectID couchbaseLiteIDRepresentation]];
    Assert(doc != nil, @"Document should not be nil");
    AssertEqual(file.filename, [doc propertyForKey:@"filename"]);
    
    CBLAttachment *att = [doc.currentRevision attachmentNamed:@"data"];
    Assert(att != nil, @"Attachmant should be created");
    
    NSData *content = att.content;
    Assert(content != nil, @"Content should be loaded");
    AssertEq(content.length, data.length);
    AssertEqual(content, data);
    
    NSManagedObjectID *fileID = file.objectID;
    
    // tear down the context to reload from disk
    file = nil;
    context = [CBLIncrementalStore createManagedObjectContextWithModel:model
                                                          databaseName:db.name error:&error];
    
    file = (File*)[context existingObjectWithID:fileID error:&error];
    Assert(file != nil, @"File should not be nil (%@)", error);
    AssertEqual(file.data, data);
    
    
    // update attachment
    
    data = [@"Updated. Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    file.data = data;
    
    success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);
    
    doc = [database documentWithID:[file.objectID couchbaseLiteIDRepresentation]];
    Assert(doc != nil, @"Document should not be nil");
    AssertEqual(file.filename, [doc propertyForKey:@"filename"]);
    
    att = [doc.currentRevision attachmentNamed:@"data"];
    Assert(att != nil, @"Attachmant should be created");
    
    content = att.content;
    Assert(content != nil, @"Content should be loaded");
    AssertEq(content.length, data.length);
    AssertEqual(content, data);

    NSString *stringFromContent = [[NSString alloc] initWithData:content encoding:NSUTF8StringEncoding];
    Assert([stringFromContent hasPrefix:@"Updated."], @"Not updated");
}


- (void) test_FetchWithPredicates
{
    RequireTestCase(CBLIncrementalStoreCRUD);
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


#pragma mark - UTILITIES


- (void) assertFetchRequest: (NSFetchRequest *)fetchRequest
                      block: (CBLISAssertionBlock)assertionBlock
{
    NSFetchRequestResultType resultTypes[] = {NSManagedObjectResultType, NSDictionaryResultType};
    for (int index = 0; index < 2; index++) {
        fetchRequest.resultType = resultTypes[index];
        NSError *error;
        NSArray *result = [context executeFetchRequest:fetchRequest error:&error];
        Assert(result != nil, @"Could not execute fetch request: %@", error);
        assertionBlock(result, fetchRequest.resultType);
    }
}


@end


#pragma mark -
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

    NSEntityDescription *article = [NSEntityDescription new];
    [article setName:@"Article"];
    [article setManagedObjectClassName:@"Article"];

    NSRelationshipDescription *entryFiles = CBLISRelationshipDescription(@"files", YES, YES, NSCascadeDeleteRule, file);
    NSRelationshipDescription *entrySubentries = CBLISRelationshipDescription(@"subEntries", YES, YES, NSCascadeDeleteRule, subentry);
    NSRelationshipDescription *fileEntry = CBLISRelationshipDescription(@"entry", YES, NO, NSNullifyDeleteRule, entry);
    NSRelationshipDescription *subentryEntry = CBLISRelationshipDescription(@"entry", YES, NO, NSNullifyDeleteRule, entry);
    NSRelationshipDescription *articles = CBLISRelationshipDescription(@"articles", YES, YES, NSCascadeDeleteRule, article);

    [entryFiles setInverseRelationship:fileEntry];
    [entrySubentries setInverseRelationship:subentryEntry];
    [fileEntry setInverseRelationship:entryFiles];
    [subentryEntry setInverseRelationship:entrySubentries];
    
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
                           articles
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

    [article setProperties:@[
                             CBLISAttributeDescription(@"name", YES, NSStringAttributeType, nil),
                             ]];
    
    [model setEntities:@[entry, file, subentry, article]];
    
    return model;
}

@implementation Entry
@dynamic check, created_at, text, text2, number, decimalNumber, doubleNumber, subEntries, files, articles;
@end

@implementation Subentry
@dynamic text, number, entry;
@end

@implementation File
@dynamic filename, data, entry;
@end

@implementation Article
@dynamic name;
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
