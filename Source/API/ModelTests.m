//
//  ModelTests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/11/13.
//  Copyright 2011-2013 Couchbase, Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CouchbaseLitePrivate.h"
#import "CBLModelArray.h"
#import "CBLInternal.h"
#import "Test.h"


#if DEBUG


static CBLDatabase* createEmptyDB(void) {
    CBLManager* dbmgr = [CBLManager sharedInstance];
    CAssert(dbmgr);
    NSError* error;
    CBLDatabase* db = [dbmgr createEmptyDatabaseNamed: @"test_db" error: &error];
    CAssert(db, @"Couldn't create db: %@", error);
    return db;
}


static void closeTestDB(CBLDatabase* db) {
    CAssert(db != nil);
    CAssert([db close]);
}


static CBLDatabase* reopenTestDB(CBLDatabase* db) {
    closeTestDB(db);
    [[CBLManager sharedInstance] _forgetDatabase: db];
    NSError* error;
    CBLDatabase* db2 = [[CBLManager sharedInstance] databaseNamed: @"test_db" error: &error];
    CAssert(db2, @"Couldn't reopen db: %@", error);
    CAssert(db2 != db, @"reopenTestDB couldn't make a new instance");
    return db2;
}


#pragma mark - TEST MODEL:


@interface TestSubModel : NSObject <CBLJSONEncoding>
@property (copy) NSString *firstName, *lastName;
@end


@implementation TestSubModel

@synthesize firstName, lastName;

- (id) initWIthJSON:(id)jsonObject {
    self = [super init];
    if (self) {
        self.firstName = [jsonObject objectForKey: @"first"];
        self.lastName = [jsonObject objectForKey: @"last"];
    }
    return self;
}

- (id) encodeAsJSON {
    return @{@"first": self.firstName, @"last": self.lastName};
}

- (BOOL) isEqual:(id)object {
    return [self.firstName isEqual: [object firstName]] && [self.lastName isEqual: [object lastName]];
}

@end



@interface TestModel : CBLModel
@property int number;
@property unsigned int uInt;
@property NSInteger nsInt;
@property NSUInteger nsUInt;
@property int8_t sInt8;
@property uint8_t uInt8;
@property int16_t sInt16;
@property uint16_t uInt16;
@property int32_t sInt32;
@property uint32_t uInt32;
@property int64_t sInt64;
@property uint64_t uInt64;
@property bool boolean;
@property BOOL boolObjC;
@property float floaty;
@property double doubly;

@property NSString* str;
@property NSData* data;
@property NSDate* date;
@property NSDecimalNumber* decimal;
@property TestModel* other;
@property NSArray* strings;
@property NSArray* dates;
@property NSArray* others;

@property TestSubModel* subModel;
@property NSArray* subModels;

@property int Capitalized;

@property unsigned reloadCount;
@end


@implementation TestModel

@dynamic number, uInt, sInt16, uInt16, sInt8, uInt8, nsInt, nsUInt, sInt32, uInt32;
@dynamic sInt64, uInt64, boolean, boolObjC, floaty, doubly;
@dynamic str, data, date, decimal, other, strings, dates, others, Capitalized;
@dynamic subModel, subModels;
@synthesize reloadCount;

- (void) didLoadFromDocument {
    self.reloadCount++;
    Log(@"reloadCount = %u",self.reloadCount);
}

+ (Class) othersItemClass {
    return [TestModel class];
}

+ (Class) datesItemClass {
    return [NSDate class];
}

+ (Class) subModelsItemClass {
    return [TestSubModel class];
}

@end


#pragma mark - MODELS:


#define TEST_PROPERTY(PROPERTY, VALUE) \
    model.PROPERTY = VALUE; \
    CAssertEq(model.PROPERTY, VALUE); \
    CAssertEqual([model getValueOfProperty: @""#PROPERTY], @(VALUE));


TestCase(API_ModelDynamicProperties) {
    NSArray* strings = @[@"fee", @"fie", @"foe", @"fum"];
    NSData* data = [@"ASCII" dataUsingEncoding: NSUTF8StringEncoding];

    CBLDatabase* db = createEmptyDB();
    TestModel* model = [[TestModel alloc] initWithNewDocumentInDatabase: db];

    TEST_PROPERTY(number, 1337);
    TEST_PROPERTY(number, INT_MAX);
    TEST_PROPERTY(number, INT_MIN);
    TEST_PROPERTY(uInt, UINT_MAX);
    TEST_PROPERTY(uInt, 0u);
    TEST_PROPERTY(sInt64, INT64_MAX);
    TEST_PROPERTY(sInt64, INT64_MIN);
    TEST_PROPERTY(uInt64, UINT64_MAX);
    TEST_PROPERTY(uInt64, 0u);
    TEST_PROPERTY(sInt32, INT32_MAX);
    TEST_PROPERTY(sInt32, INT32_MIN);
    TEST_PROPERTY(uInt32, UINT32_MAX);
    TEST_PROPERTY(uInt32, 0u);
    TEST_PROPERTY(sInt16, INT16_MAX);
    TEST_PROPERTY(sInt16, INT16_MIN);
    TEST_PROPERTY(uInt16, USHRT_MAX);
    TEST_PROPERTY(uInt16, 0u);
    TEST_PROPERTY(sInt8, INT8_MAX);
    TEST_PROPERTY(sInt8, INT8_MIN);
    TEST_PROPERTY(uInt8, UCHAR_MAX);
    TEST_PROPERTY(uInt8, 0u);

    TEST_PROPERTY(nsInt, NSIntegerMax);
    TEST_PROPERTY(nsInt, NSIntegerMin);
    TEST_PROPERTY(nsUInt, NSUIntegerMax);
    TEST_PROPERTY(nsUInt, 0u);

    TEST_PROPERTY(boolean, false);
    CAssertEq([model getValueOfProperty: @"boolean"], (id)kCFBooleanFalse);
    TEST_PROPERTY(boolean, true);
    CAssertEq([model getValueOfProperty: @"boolean"], (id)kCFBooleanTrue);

    TEST_PROPERTY(boolObjC, NO);
    TEST_PROPERTY(boolObjC, YES);

    TEST_PROPERTY(floaty, 0.0f);
    TEST_PROPERTY(floaty, (float)M_PI);
    TEST_PROPERTY(doubly, 0.0f);
    TEST_PROPERTY(doubly, M_PI);

    TEST_PROPERTY(Capitalized, 12345);

    model.str = @"LEET";
    model.strings = strings;
    model.data = data;
    CAssertEqual(model.str, @"LEET");
    CAssertEqual(model.strings, strings);
    CAssertEqual(model.data, data);

    Log(@"Model: %@", [CBLJSON stringWithJSONObject: model.propertiesToSave options: 0 error: NULL]);
}


TestCase(API_ModelEncodableProperties) {
    CBLDatabase* db = createEmptyDB();
    TestModel* model = [[TestModel alloc] initWithNewDocumentInDatabase: db];

    TestSubModel* name = [[TestSubModel alloc] init];
    name.firstName = @"Jens";
    name.lastName = @"Alfke";
    model.subModel = name;
    AssertEq(model.subModel, name);
    AssertEq([model getValueOfProperty: @"subModel"], name);
    NSDictionary* props = model.propertiesToSave;
    CAssertEqual(props, (@{@"subModel": @{@"first": @"Jens", @"last": @"Alfke"}}));

    CBLDocument* doc2 = [db createDocument];
    CAssert([doc2 putProperties: props error: NULL]);
    TestModel* model2 = [[TestModel alloc] initWithDocument: doc2];
    CAssertEqual(model2.subModel, name);

    // Now test array of encodable objects:
    TestSubModel* name2 = [[TestSubModel alloc] init];
    name2.firstName = @"Naomi";
    name2.lastName = @"Pearl";
    model.subModel = nil;
    NSArray* subModels = @[name, name2];
    model.subModels = subModels;
    AssertEqual(model.subModels, subModels);
    AssertEq([model getValueOfProperty: @"subModels"], subModels);
    props = model.propertiesToSave;
    CAssertEqual(props, (@{@"subModels": @[@{@"first": @"Jens", @"last": @"Alfke"},
                                           @{@"first": @"Naomi", @"last": @"Pearl"}]}));

    CBLDocument* doc3 = [db createDocument];
    CAssert([doc3 putProperties: props error: NULL]);
    TestModel* model3 = [[TestModel alloc] initWithDocument: doc3];
    CAssertEqual(model3.subModels, subModels);
}


TestCase(API_ModelDeleteProperty) {
    NSArray* strings = @[@"fee", @"fie", @"foe", @"fum"];
    NSData* data = [@"ASCII" dataUsingEncoding: NSUTF8StringEncoding];

    CBLDatabase* db = createEmptyDB();
    TestModel* model = [[TestModel alloc] initWithNewDocumentInDatabase: db];
    model.number = 1337;
    model.str = @"LEET";
    model.strings = strings;
    model.data = data;

    CAssertEqual(model.str, @"LEET");
    CAssertEqual(model.strings, strings);
    CAssertEqual(model.data, data);

    model.data = nil;
    CAssertEqual(model.data, nil);
    model.data = data;

    NSError* error;
    CAssert([model save: &error], @"Failed to save: %@", error);

    CAssertEqual(model.data, data);
    model.data = nil;
    CAssertEqual(model.data, nil);      // Tests issue CouchCocoa #73

    [db close];
}


TestCase(API_SaveModel) {
    NSDate* date = [NSDate dateWithTimeIntervalSinceReferenceDate: 392773252];
    NSArray* dates = @[date, [NSDate dateWithTimeIntervalSinceReferenceDate: 392837521]];
    NSDecimalNumber* decimal = [NSDecimalNumber decimalNumberWithString: @"12345.6789"];

    CBLDatabase* db = createEmptyDB();
    NSString* modelID, *model2ID, *model3ID;
    {
        TestModel* model = [[TestModel alloc] initWithNewDocumentInDatabase: db];
        CAssert(model != nil);
        CAssert(model.isNew);
        CAssert(!model.needsSave);
        CAssertEq(model.propertiesToSave.count, 0u);
        modelID = model.document.documentID;

        // Create and populate a TestModel:
        model.number = 1337;
        model.str = @"LEET";
        model.strings = @[@"fee", @"fie", @"foe", @"fum"];
        model.data = [@"ASCII" dataUsingEncoding: NSUTF8StringEncoding];
        model.date = date;
        model.dates = dates;
        model.decimal = decimal;

        CAssert(model.isNew);
        CAssert(model.needsSave);
        CAssertEqual(model.propertiesToSave, (@{@"number": @(1337),
                                                @"str": @"LEET",
                                                @"strings": @[@"fee", @"fie", @"foe", @"fum"],
                                                @"data": @"QVNDSUk=",
                                                @"date": @"2013-06-12T23:40:52.000Z",
                                                @"dates": @[@"2013-06-12T23:40:52.000Z",
                                                            @"2013-06-13T17:32:01.000Z"],
                                                @"decimal": @"12345.6789"}));

        TestModel* model2 = [[TestModel alloc] initWithNewDocumentInDatabase: db];
        model2ID = model2.document.documentID;
        TestModel* model3 = [[TestModel alloc] initWithNewDocumentInDatabase: db];
        model3ID = model3.document.documentID;

        model.other = model3;
        model.others = @[model2, model3];

        // Verify the property getters:
        CAssertEq(model.number, 1337);
        CAssertEqual(model.str, @"LEET");
        CAssertEqual(model.strings, (@[@"fee", @"fie", @"foe", @"fum"]));
        CAssertEqual(model.data, [@"ASCII" dataUsingEncoding: NSUTF8StringEncoding]);
        CAssertEqual(model.date, [NSDate dateWithTimeIntervalSinceReferenceDate: 392773252]);
        CAssertEqual(model.dates, dates);
        CAssertEqual(model.decimal, decimal);
        CAssertEq(model.other, model3);
        CAssertEqual(model.others, (@[model2, model3]));

        // Save it and make sure the save didn't trigger a reload:
        CAssertEqual(db.unsavedModels, @[model]);
        NSError* error;
        CAssert([db saveAllModels: &error]);
        CAssertEq(model.reloadCount, 0u);

        // Verify that the document got updated correctly:
        NSMutableDictionary* props = [model.document.properties mutableCopy];
        CAssertEqual(props, (@{@"number": @(1337),
                               @"str": @"LEET",
                               @"strings": @[@"fee", @"fie", @"foe", @"fum"],
                               @"data": @"QVNDSUk=",
                               @"date": @"2013-06-12T23:40:52.000Z",
                               @"dates": @[@"2013-06-12T23:40:52.000Z", @"2013-06-13T17:32:01.000Z"],
                               @"decimal": @"12345.6789",
                               @"other": model3.document.documentID,
                               @"others": @[model2.document.documentID, model3.document.documentID],
                               @"_id": props[@"_id"],
                               @"_rev": props[@"_rev"]}));

        // Update the document directly and make sure the model updates:
        props[@"number"] = @4321;
        CAssert([model.document putProperties: props error: &error]);
        CAssertEq(model.reloadCount, 1u);
        CAssertEq(model.number, 4321);

        // Store the same properties in a different model's document:
        [props removeObjectForKey: @"_id"];
        [props removeObjectForKey: @"_rev"];
        CAssert([model2.document putProperties: props error: &error]);
        // ...and verify its properties:
        CAssertEq(model2.reloadCount, 1u);
        CAssertEq(model2.number, 4321);
        CAssertEqual(model2.str, @"LEET");
        CAssertEqual(model2.strings, (@[@"fee", @"fie", @"foe", @"fum"]));
        CAssertEqual(model2.data, [@"ASCII" dataUsingEncoding: NSUTF8StringEncoding]);
        CAssertEqual(model2.date, [NSDate dateWithTimeIntervalSinceReferenceDate: 392773252]);
        CAssertEqual(model2.dates, dates);
        CAssertEqual(model2.decimal, decimal);
        CAssertEq(model2.other, model3);
        CAssertEqual(model2.others, (@[model2, model3]));
        CAssertEqual(model2.others, model.others);

        CAssertEqual($cast(CBLModelArray, model2.others).docIDs, (@[model2.document.documentID,
                                                                    model3.document.documentID]));
    }
    {
        // Close/reopen the database and verify again:
        db = reopenTestDB(db);
        CBLDocument* doc = [db documentWithID: modelID];
        TestModel* modelAgain = [TestModel modelForDocument: doc];
        CAssertEq(modelAgain.number, 4321);
        CAssertEqual(modelAgain.str, @"LEET");
        CAssertEqual(modelAgain.strings, (@[@"fee", @"fie", @"foe", @"fum"]));
        CAssertEqual(modelAgain.data, [@"ASCII" dataUsingEncoding: NSUTF8StringEncoding]);
        CAssertEqual(modelAgain.date, [NSDate dateWithTimeIntervalSinceReferenceDate: 392773252]);
        CAssertEqual(modelAgain.dates, dates);
        CAssertEqual(modelAgain.decimal, decimal);

        TestModel *other = modelAgain.other;
        CAssertEqual(modelAgain.other.document.documentID, model3ID);
        NSArray* others = modelAgain.others;
        CAssertEq(others.count, 2u);
        CAssertEq(others[1], other);
        CAssertEqual(((TestModel*)others[0]).document.documentID, model2ID);
    }
    [db close];
}


TestCase(API_ModelAttachments) {
    // Attempting to reproduce https://github.com/couchbase/couchbase-lite-ios/issues/63
    CBLDatabase* db = createEmptyDB();
    NSError* error;

    NSData* attData = [@"Ceci n'est pas une pipe." dataUsingEncoding: NSUTF8StringEncoding];
    CBLDocument* doc;
    {
        TestModel* model = [[TestModel alloc] initWithNewDocumentInDatabase: db];
        doc = model.document;
        model.number = 1337;
        CAssert([model save: &error], @"Initial failed: %@", error);

        [model setAttachmentNamed: @"Caption.txt" withContentType: @"text/plain" content: attData];
        CAssert([model save: &error], @"Save after adding attachment failed: %@", error);

        // Ensure that document's attachment metadata doesn't have the "follows" property set [#63]
        NSDictionary* meta = model.document[@"_attachments"][@"Caption.txt"];
        CAssertEqual(meta[@"content_type"], @"text/plain");
        CAssertEqual(meta[@"length"], @24);
        CAssertNil(meta[@"follows"]);

        model.number = 23;
        CAssert([model save: &error], @"Save after updating number failed: %@", error);
    }
    {
        TestModel* model = [TestModel modelForDocument: doc];
        CAssertEq(model.number, 23);
        CBLAttachment* attachment = [model attachmentNamed: @"Caption.txt"];
        CAssertEqual(attachment.content, attData);

        model.number = -1;
        CAssert([model save: &error], @"Save of new model object failed: %@", error);

        // Now update the attachment:
        [model removeAttachmentNamed: @"caption.txt"];
        NSData* newAttData = [@"sluggo" dataUsingEncoding: NSUTF8StringEncoding];
        [model setAttachmentNamed: @"Caption.txt" withContentType: @"text/plain" content:newAttData];
        CAssert([model save: &error], @"Final save failed: %@", error);
    }
    [db close];
}


TestCase(API_Model) {
    RequireTestCase(API_ModelDynamicProperties);
    RequireTestCase(API_SaveModel);
    RequireTestCase(API_ModelDeleteProperty);
    RequireTestCase(API_ModelAttachments);
}


#endif // DEBUG
