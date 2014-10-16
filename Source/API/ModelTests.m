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

#if DEBUG
#import "APITestUtils.h"
#import "CBLModelArray.h"


#pragma mark - TEST MODEL:


@interface CBL_TestSubModel : NSObject <CBLJSONEncoding>
- (instancetype) initWithFirstName: (NSString*)firstName lastName: (NSString*)lastName;
@property (readonly, copy, nonatomic) NSString *firstName, *lastName;
@end


@interface CBL_TTestMutableSubModel : CBL_TestSubModel
@property (copy, nonatomic) NSString *firstName, *lastName;
@end


@implementation CBL_TestSubModel
{
    @protected
    NSString* _firstName, *_lastName;
}

@synthesize firstName=_firstName, lastName=_lastName;

- (instancetype) initWithFirstName: (NSString*)first lastName: (NSString*)last {
    self = [super init];
    if (self) {
        _firstName = first;
        _lastName = last;
    }
    return self;
}

- (id) initWithJSON:(id)jsonObject {
    return [self initWithFirstName: jsonObject[@"first"]
                          lastName: jsonObject[@"last"]];
}

- (id) encodeAsJSON {
    return @{@"first": self.firstName, @"last": self.lastName};
}

- (BOOL) isEqual:(id)object {
    return [self.firstName isEqual: [object firstName]] && [self.lastName isEqual: [object lastName]];
}

@end


@implementation CBL_TTestMutableSubModel
{
    CBLOnMutateBlock _onMutate;
}

- (void) setOnMutate:(CBLOnMutateBlock)onMutate {
    _onMutate = onMutate;
}

- (void) setFirstName:(NSString *)firstName {
    _firstName = [firstName copy];
    if (_onMutate) _onMutate();
}

- (void) setLastName:(NSString *)lastName {
    _lastName = [lastName copy];
    if (_onMutate) _onMutate();
}

@end



@interface CBL_TestModel : CBLModel
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
@property NSURL* url;
@property CBL_TestModel* other;
@property NSArray* strings;
@property NSArray* dates;
@property NSArray* others;
@property NSDictionary* dict;

@property CBL_TestSubModel* subModel;
@property CBL_TTestMutableSubModel* mutableSubModel;
@property NSArray* subModels;

@property int Capitalized;

@property unsigned reloadCount;
@end


@implementation CBL_TestModel

@dynamic number, uInt, sInt16, uInt16, sInt8, uInt8, nsInt, nsUInt, sInt32, uInt32;
@dynamic sInt64, uInt64, boolean, boolObjC, floaty, doubly, dict;
@dynamic str, data, date, decimal, url, other, strings, dates, others, Capitalized;
@dynamic subModel, subModels, mutableSubModel;
@synthesize reloadCount;

- (void) didLoadFromDocument {
    self.reloadCount++;
    Log(@"reloadCount = %u",self.reloadCount);
}

+ (Class) othersItemClass {
    return [CBL_TestModel class];
}

+ (Class) datesItemClass {
    return [NSDate class];
}

+ (Class) subModelsItemClass {
    return [CBL_TestSubModel class];
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
    CBL_TestModel* model = [[CBL_TestModel alloc] initWithNewDocumentInDatabase: db];

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

    NSURL* url = [NSURL URLWithString: @"http://bogus"];
    model.url = url;
    CAssertEqual(model.url, url);

    Log(@"Model: %@", [CBLJSON stringWithJSONObject: model.propertiesToSave options: 0 error: NULL]);
}


TestCase(API_ModelEncodableProperties) {
    CBLDatabase* db = createEmptyDB();
    CBL_TestModel* model = [[CBL_TestModel alloc] initWithNewDocumentInDatabase: db];

    CBL_TestSubModel* name = [[CBL_TestSubModel alloc] initWithFirstName: @"Jens" lastName: @"Alfke"];
    model.subModel = name;
    AssertEq(model.subModel, name);
    AssertEq([model getValueOfProperty: @"subModel"], name);
    NSMutableDictionary* props = [model.propertiesToSave mutableCopy];
    [props removeObjectForKey: @"_id"];
    CAssertEqual(props, (@{@"subModel": @{@"first": @"Jens",
                                          @"last": @"Alfke"}}));

    CBLDocument* doc2 = [db createDocument];
    CAssert([doc2 putProperties: props error: NULL]);
    CBL_TestModel* model2 = [[CBL_TestModel alloc] initWithDocument: doc2];
    CAssertEqual(model2.subModel, name);

    // Now test array of encodable objects:
    CBL_TestSubModel* name2 = [[CBL_TestSubModel alloc] initWithFirstName: @"Naomi" lastName: @"Pearl"];
    model.subModel = nil;
    NSArray* subModels = @[name, name2];
    model.subModels = subModels;
    AssertEqual(model.subModels, subModels);
    AssertEq([model getValueOfProperty: @"subModels"], subModels);

    CBL_TTestMutableSubModel* name3 = [[CBL_TTestMutableSubModel alloc] initWithFirstName: @"Jed" lastName: @"Clampett"];
    model.mutableSubModel = name3;
    AssertEq(model.mutableSubModel, name3);
    AssertEq([model getValueOfProperty: @"mutableSubModel"], name3);

    props = [model.propertiesToSave mutableCopy];
    [props removeObjectForKey: @"_id"];
    CAssertEqual(props, (@{@"subModels": @[@{@"first": @"Jens", @"last": @"Alfke"},
                                           @{@"first": @"Naomi", @"last": @"Pearl"}],
                           @"mutableSubModel": @{@"first": @"Jed", @"last": @"Clampett"}}));

    CBLDocument* doc3 = [db createDocument];
    CAssert([doc3 putProperties: props error: NULL]);
    CBL_TestModel* model3 = [[CBL_TestModel alloc] initWithDocument: doc3];
    Assert(!model3.needsSave);
    CAssertEqual(model3.subModels, subModels);
    CAssertEqual(model3.mutableSubModel, name3);

    // Mutate the submodel in place and make sure the model's serialization changed:
    name3 = model3.mutableSubModel;
    AssertEqual(name3.lastName, @"Clampett");
    Assert(!model3.needsSave);
    name3.lastName = @"Pookie";
    Assert(model3.needsSave);
    props = [model3.propertiesToSave mutableCopy];
    CAssertEqual(props, (@{@"subModels": @[@{@"first": @"Jens", @"last": @"Alfke"},
                                           @{@"first": @"Naomi", @"last": @"Pearl"}],
                           @"mutableSubModel": @{@"first": @"Jed", @"last": @"Pookie"},
                           @"_id": doc3.documentID,
                           @"_rev": doc3.currentRevisionID}));
}


TestCase(API_ModelEncodablePropertiesNilValue) { // See #247
    RequireTestCase(API_ModelEncodableProperties);
    CBLDatabase* db = createEmptyDB();

    CBL_TestModel* emptyModel = [[CBL_TestModel alloc] initWithNewDocumentInDatabase: db];
    AssertNil(emptyModel.mutableSubModel);
    NSString* documentID = [[emptyModel document] documentID];
    emptyModel = nil;
    CBLDocument *document = [db documentWithID:documentID];
    emptyModel = [[CBL_TestModel alloc] initWithDocument:document];
    AssertNil(emptyModel.mutableSubModel);
}


TestCase(API_ModelTypeProperty) {
    CBLDatabase* db = createEmptyDB();
    CBL_TestModel* model = [[CBL_TestModel alloc] initWithNewDocumentInDatabase: db];

    model.type = @"Dummy";
    CAssertEqual(model.type, @"Dummy");
    CAssertEqual([model getValueOfProperty:@"type"], @"Dummy");
    CAssertEqual(model.propertiesToSave, (@{@"_id": model.document.documentID,
                                            @"type": @"Dummy"}));
}


TestCase(API_ModelDeleteProperty) {
    NSArray* strings = @[@"fee", @"fie", @"foe", @"fum"];
    NSData* data = [@"ASCII" dataUsingEncoding: NSUTF8StringEncoding];

    CBLDatabase* db = createEmptyDB();
    CBL_TestModel* model = [[CBL_TestModel alloc] initWithNewDocumentInDatabase: db];
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
}


TestCase(API_SaveModel) {
    NSDate* date = [NSDate dateWithTimeIntervalSinceReferenceDate: 392773252];
    NSArray* dates = @[date, [NSDate dateWithTimeIntervalSinceReferenceDate: 392837521]];
    NSDecimalNumber* decimal = [NSDecimalNumber decimalNumberWithString: @"12345.6789"];
    NSURL* url = [NSURL URLWithString: @"http://bogus"];

    CBLDatabase* db = createEmptyDB();
    NSString* modelID, *model2ID, *model3ID;
    {
        CBL_TestModel* model = [[CBL_TestModel alloc] initWithNewDocumentInDatabase: db];
        CAssert(model != nil);
        CAssert(model.isNew);
        CAssert(!model.needsSave);
        modelID = model.document.documentID;
        CAssertEqual(model.propertiesToSave, @{@"_id": modelID});

        // Create and populate a TestModel:
        model.number = 1337;
        model.str = @"LEET";
        model.strings = @[@"fee", @"fie", @"foe", @"fum"];
        model.data = [@"ASCII" dataUsingEncoding: NSUTF8StringEncoding];
        model.date = date;
        model.dates = dates;
        model.decimal = decimal;
        model.url = url;

        CAssert(model.isNew);
        CAssert(model.needsSave);
        CAssertEqual(model.propertiesToSave, (@{@"_id": model.document.documentID,
                                                @"number": @(1337),
                                                @"str": @"LEET",
                                                @"strings": @[@"fee", @"fie", @"foe", @"fum"],
                                                @"data": @"QVNDSUk=",
                                                @"date": @"2013-06-12T23:40:52.000Z",
                                                @"dates": @[@"2013-06-12T23:40:52.000Z",
                                                            @"2013-06-13T17:32:01.000Z"],
                                                @"decimal": @"12345.6789",
                                                @"url": @"http://bogus"}));

        CBL_TestModel* model2 = [[CBL_TestModel alloc] initWithNewDocumentInDatabase: db];
        model2ID = model2.document.documentID;
        CBL_TestModel* model3 = [[CBL_TestModel alloc] initWithNewDocumentInDatabase: db];
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
        CAssertEqual(model.url, url);
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
                               @"url": @"http://bogus",
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
        CBL_TestModel* modelAgain = [CBL_TestModel modelForDocument: doc];
        CAssertEq(modelAgain.number, 4321);
        CAssertEqual(modelAgain.str, @"LEET");
        CAssertEqual(modelAgain.strings, (@[@"fee", @"fie", @"foe", @"fum"]));
        CAssertEqual(modelAgain.data, [@"ASCII" dataUsingEncoding: NSUTF8StringEncoding]);
        CAssertEqual(modelAgain.date, [NSDate dateWithTimeIntervalSinceReferenceDate: 392773252]);
        CAssertEqual(modelAgain.dates, dates);
        CAssertEqual(modelAgain.decimal, decimal);
        CAssertEqual(modelAgain.url, url);

        CBL_TestModel *other = modelAgain.other;
        CAssertEqual(modelAgain.other.document.documentID, model3ID);
        NSArray* others = modelAgain.others;
        CAssertEq(others.count, 2u);
        CAssertEq(others[1], other);
        CAssertEqual(((CBL_TestModel*)others[0]).document.documentID, model2ID);
    }
}


TestCase(API_SaveMutatedSubModel) {
    NSError* error;
    
    CBLDatabase* db = createEmptyDB();
    CBL_TestModel* model = [[CBL_TestModel alloc] initWithNewDocumentInDatabase: db];
    CBL_TTestMutableSubModel* submodel = [[CBL_TTestMutableSubModel alloc] initWithFirstName: @"Jens" lastName: @"Alfke"];
    model.mutableSubModel = submodel;
    NSMutableDictionary* props = [model.propertiesToSave mutableCopy];
    [props removeObjectForKey: @"_id"];
    CAssertEqual(props, (@{@"mutableSubModel":@{@"first": @"Jens", @"last": @"Alfke"}}));
    [model save: &error];
    CAssertNil(error);
    
    submodel.firstName = @"Pasin";
    submodel.lastName = @"Suri";
    props = [[model propertiesToSave] mutableCopy];
    [props removeObjectForKey: @"_id"];
    [props removeObjectForKey: @"_rev"];
    CAssertEqual(props, (@{@"mutableSubModel":@{@"first": @"Pasin", @"last": @"Suri"}}));
    [model save: &error];
    CAssertNil(error);
    
    submodel = model.mutableSubModel;
    submodel.firstName = @"Wayne";
    submodel.lastName = @"Carter";
    props = [[model propertiesToSave] mutableCopy];
    [props removeObjectForKey: @"_id"];
    [props removeObjectForKey: @"_rev"];
    CAssertEqual(props, (@{@"mutableSubModel":@{@"first": @"Wayne", @"last": @"Carter"}}));
    [model save: &error];
    CAssertNil(error);
}


TestCase(API_SaveModelWithNaNProperty) {
    CBLDatabase* db = createEmptyDB();
    CBL_TestModel* model = [[CBL_TestModel alloc] initWithNewDocumentInDatabase: db];
    model.doubly = sqrt(-1);
    NSError* error;
    [model save: &error];
    CAssertEq(error.code, 400);
}


TestCase(API_ModelAttachments) {
    // Attempting to reproduce https://github.com/couchbase/couchbase-lite-ios/issues/63
    CBLDatabase* db = createEmptyDB();
    NSError* error;

    NSData* attData = [@"Ceci n'est pas une pipe." dataUsingEncoding: NSUTF8StringEncoding];
    CBLDocument* doc;
    {
        CBL_TestModel* model = [[CBL_TestModel alloc] initWithNewDocumentInDatabase: db];
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
        CBL_TestModel* model = [CBL_TestModel modelForDocument: doc];
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
}


TestCase(API_ModelPropertyObservation) {
    // For https://github.com/couchbase/couchbase-lite-ios/issues/244
    CBLDatabase* db = createEmptyDB();
    CBL_TestModel* model = [[CBL_TestModel alloc] initWithNewDocumentInDatabase: db];
    id observer = [NSObject new];

    @autoreleasepool {
        model.dict = @{@"name": @"Puddin' Tane"};
        [model addObserver: observer forKeyPath: @"dict.name" options: 0 context: NULL];
        [model save: NULL];
    }
    [model removeObserver: observer forKeyPath: @"dict.name"];
}


TestCase(API_Model) {
    RequireTestCase(API_ModelDynamicProperties);
    RequireTestCase(API_ModelEncodableProperties);
    RequireTestCase(API_ModelEncodablePropertiesNilValue);
    RequireTestCase(API_ModelTypeProperty);
    RequireTestCase(API_SaveModel);
    RequireTestCase(API_SaveMutatedSubModel);
    RequireTestCase(API_SaveModelWithNaNProperty);
    RequireTestCase(API_ModelDeleteProperty);
    RequireTestCase(API_ModelAttachments);
}


#endif // DEBUG
