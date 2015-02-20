//
//  Model_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/22/14.
//
//

#import "CBLTestCase.h"
#import "CBLModelArray.h"


@class TestSubModel, TestMutableSubModel;


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
@property NSURL* url;
@property TestModel* other;
@property NSArray* strings;
@property NSArray* dates;
@property NSArray* others;
@property NSDictionary* dict;

@property TestSubModel* subModel;
@property TestMutableSubModel* mutableSubModel;
@property NSArray* subModels;

@property int Capitalized;

@property unsigned reloadCount;

@property NSArray* otherModels; // inverse of TestOtherModel.model
@end


@interface TestSubModel : NSObject <CBLJSONEncoding>
- (instancetype) initWithFirstName: (NSString*)firstName lastName: (NSString*)lastName;
@property (readonly, copy, nonatomic) NSString *firstName, *lastName;
@end


@interface TestMutableSubModel : TestSubModel
@property (copy, nonatomic) NSString *firstName, *lastName;
@end


@interface CBL_TestAwakeInitModel : CBLModel
@property BOOL didAwake;
@end


@interface TestOtherModel : CBLModel
@property int number;
@property TestModel* model;
@end


#pragma mark - TEST CASES:


#define TEST_PROPERTY(PROPERTY, VALUE) \
    model.PROPERTY = VALUE; \
    AssertEq(model.PROPERTY, VALUE); \
    AssertEqual([model getValueOfProperty: @""#PROPERTY], @(VALUE));


@interface Model_Tests : CBLTestCaseWithDB
@end


@implementation Model_Tests


- (void) test00_DynamicProperties {
    NSArray* strings = @[@"fee", @"fie", @"foe", @"fum"];
    NSData* data = [@"ASCII" dataUsingEncoding: NSUTF8StringEncoding];

    TestModel* model = [TestModel modelForNewDocumentInDatabase: db];

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
    AssertEq([model getValueOfProperty: @"boolean"], (id)kCFBooleanFalse);
    TEST_PROPERTY(boolean, true);
    AssertEq([model getValueOfProperty: @"boolean"], (id)kCFBooleanTrue);

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
    AssertEqual(model.str, @"LEET");
    AssertEqual(model.strings, strings);
    AssertEqual(model.data, data);

    NSURL* url = [NSURL URLWithString: @"http://bogus"];
    model.url = url;
    AssertEqual(model.url, url);

    Log(@"Model: %@", [CBLJSON stringWithJSONObject: model.propertiesToSave options: 0 error: NULL]);
}


- (void) test00_EncodableProperties {
    TestModel* model = [TestModel modelForNewDocumentInDatabase: db];
    TestSubModel* name = [[TestSubModel alloc] initWithFirstName: @"Jens" lastName: @"Alfke"];
    model.subModel = name;
    AssertEq(model.subModel, name);
    AssertEq([model getValueOfProperty: @"subModel"], name);
    NSMutableDictionary* props = [model.propertiesToSave mutableCopy];
    [props removeObjectForKey: @"_id"];
    AssertEqual(props, (@{@"subModel": @{@"first": @"Jens",
                                          @"last": @"Alfke"}}));

    CBLDocument* doc2 = [db createDocument];
    Assert([doc2 putProperties: props error: NULL]);
    TestModel* model2 = [TestModel modelForDocument: doc2];
    AssertEqual(model2.subModel, name);

    // Now test array of encodable objects:
    TestSubModel* name2 = [[TestSubModel alloc] initWithFirstName: @"Naomi" lastName: @"Pearl"];
    model.subModel = nil;
    NSArray* subModels = @[name, name2];
    model.subModels = subModels;
    AssertEqual(model.subModels, subModels);
    AssertEq([model getValueOfProperty: @"subModels"], subModels);

    TestMutableSubModel* name3 = [[TestMutableSubModel alloc] initWithFirstName: @"Jed" lastName: @"Clampett"];
    model.mutableSubModel = name3;
    AssertEq(model.mutableSubModel, name3);
    AssertEq([model getValueOfProperty: @"mutableSubModel"], name3);

    props = [model.propertiesToSave mutableCopy];
    [props removeObjectForKey: @"_id"];
    AssertEqual(props, (@{@"subModels": @[@{@"first": @"Jens", @"last": @"Alfke"},
                                           @{@"first": @"Naomi", @"last": @"Pearl"}],
                           @"mutableSubModel": @{@"first": @"Jed", @"last": @"Clampett"}}));

    CBLDocument* doc3 = [db createDocument];
    Assert([doc3 putProperties: props error: NULL]);
    TestModel* model3 = [TestModel modelForDocument: doc3];
    Assert(!model3.needsSave);
    AssertEqual(model3.subModels, subModels);
    AssertEqual(model3.mutableSubModel, name3);

    // Mutate the submodel in place and make sure the model's serialization changed:
    name3 = model3.mutableSubModel;
    AssertEqual(name3.lastName, @"Clampett");
    Assert(!model3.needsSave);
    name3.lastName = @"Pookie";
    Assert(model3.needsSave);
    props = [model3.propertiesToSave mutableCopy];
    AssertEqual(props, (@{@"subModels": @[@{@"first": @"Jens", @"last": @"Alfke"},
                                           @{@"first": @"Naomi", @"last": @"Pearl"}],
                           @"mutableSubModel": @{@"first": @"Jed", @"last": @"Pookie"},
                           @"_id": doc3.documentID,
                           @"_rev": doc3.currentRevisionID}));
}


- (void) test00_EncodablePropertiesNilValue { // See #247
    RequireTestCase(API_ModelEncodableProperties);

    TestModel* emptyModel = [TestModel modelForNewDocumentInDatabase: db];
    AssertNil(emptyModel.mutableSubModel);
    NSString* documentID = [[emptyModel document] documentID];
    emptyModel = nil;
    CBLDocument *document = [db documentWithID:documentID];
    emptyModel = [TestModel modelForDocument:document];
    AssertNil(emptyModel.mutableSubModel);
}


- (void) test00_TypeProperty {
    TestModel* model = [TestModel modelForNewDocumentInDatabase: db];

    model.type = @"Dummy";
    AssertEqual(model.type, @"Dummy");
    AssertEqual([model getValueOfProperty:@"type"], @"Dummy");
    AssertEqual(model.propertiesToSave, (@{@"_id": model.document.documentID,
                                            @"type": @"Dummy"}));
}

- (void)test00_AutoTypeProperty {
    db.modelFactory = [[CBLModelFactory alloc] init];
    [db.modelFactory registerClass:[TestModel class] forDocumentType:@"Dummy"];

    TestModel *model = [TestModel modelForNewDocumentInDatabase:db];
    AssertEqual(model.type, @"Dummy");
    AssertEqual([model getValueOfProperty:@"type"], @"Dummy");
    AssertEqual(model.propertiesToSave, (@{@"_id": model.document.documentID,
                                           @"type": @"Dummy"}));
}

- (void)test00_AutoTypePropertyByString {
    db.modelFactory = [[CBLModelFactory alloc] init];
    [db.modelFactory registerClass: @"TestModel" forDocumentType:@"Dummy"];

    TestModel *model = [TestModel modelForNewDocumentInDatabase:db];
    AssertEqual(model.type, @"Dummy");
    AssertEqual([model getValueOfProperty:@"type"], @"Dummy");
    AssertEqual(model.propertiesToSave, (@{@"_id": model.document.documentID,
                                           @"type": @"Dummy"}));
}

- (void) test00_DeleteProperty {
    NSArray* strings = @[@"fee", @"fie", @"foe", @"fum"];
    NSData* data = [@"ASCII" dataUsingEncoding: NSUTF8StringEncoding];

    TestModel* model = [TestModel modelForNewDocumentInDatabase: db];
    model.number = 1337;
    model.str = @"LEET";
    model.strings = strings;
    model.data = data;

    AssertEqual(model.str, @"LEET");
    AssertEqual(model.strings, strings);
    AssertEqual(model.data, data);

    model.data = nil;
    AssertEqual(model.data, nil);
    model.data = data;

    NSError* error;
    Assert([model save: &error], @"Failed to save: %@", error);

    AssertEqual(model.data, data);
    model.data = nil;
    AssertEqual(model.data, nil);      // Tests issue CouchCocoa #73
}


- (void) test00_SaveModel {
    NSDate* date = [NSDate dateWithTimeIntervalSinceReferenceDate: 392773252];
    NSArray* dates = @[date, [NSDate dateWithTimeIntervalSinceReferenceDate: 392837521]];
    NSDecimalNumber* decimal = [NSDecimalNumber decimalNumberWithString: @"12345.6789"];
    NSURL* url = [NSURL URLWithString: @"http://bogus"];

    NSString* modelID, *model2ID, *model3ID;
    {
        TestModel* model = [TestModel modelForNewDocumentInDatabase: db];
        Assert(model != nil);
        Assert(model.isNew);
        Assert(!model.needsSave);
        modelID = model.document.documentID;
        AssertEqual(model.propertiesToSave, @{@"_id": modelID});

        // Create and populate a TestModel:
        model.number = 1337;
        model.str = @"LEET";
        model.strings = @[@"fee", @"fie", @"foe", @"fum"];
        model.data = [@"ASCII" dataUsingEncoding: NSUTF8StringEncoding];
        model.date = date;
        model.dates = dates;
        model.decimal = decimal;
        model.url = url;

        Assert(model.isNew);
        Assert(model.needsSave);
        AssertEqual(model.propertiesToSave, (@{@"_id": model.document.documentID,
                                                @"number": @(1337),
                                                @"str": @"LEET",
                                                @"strings": @[@"fee", @"fie", @"foe", @"fum"],
                                                @"data": @"QVNDSUk=",
                                                @"date": @"2013-06-12T23:40:52.000Z",
                                                @"dates": @[@"2013-06-12T23:40:52.000Z",
                                                            @"2013-06-13T17:32:01.000Z"],
                                                @"decimal": @"12345.6789",
                                                @"url": @"http://bogus"}));

        TestModel* model2 = [TestModel modelForNewDocumentInDatabase: db];
        model2ID = model2.document.documentID;
        TestModel* model3 = [TestModel modelForNewDocumentInDatabase: db];
        model3ID = model3.document.documentID;

        model.other = model3;
        model.others = @[model2, model3];

        // Verify the property getters:
        AssertEq(model.number, 1337);
        AssertEqual(model.str, @"LEET");
        AssertEqual(model.strings, (@[@"fee", @"fie", @"foe", @"fum"]));
        AssertEqual(model.data, [@"ASCII" dataUsingEncoding: NSUTF8StringEncoding]);
        AssertEqual(model.date, [NSDate dateWithTimeIntervalSinceReferenceDate: 392773252]);
        AssertEqual(model.dates, dates);
        AssertEqual(model.decimal, decimal);
        AssertEqual(model.url, url);
        AssertEq(model.other, model3);
        AssertEqual(model.others, (@[model2, model3]));

        // Save it and make sure the save didn't trigger a reload:
        AssertEqual(db.unsavedModels, @[model]);
        NSError* error;
        Assert([db saveAllModels: &error]);
        AssertEq(model.reloadCount, 0u);

        // Verify that the document got updated correctly:
        NSMutableDictionary* props = [model.document.properties mutableCopy];
        AssertEqual(props, (@{@"number": @(1337),
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
        Assert([model.document putProperties: props error: &error]);
        AssertEq(model.reloadCount, 1u);
        AssertEq(model.number, 4321);

        // Store the same properties in a different model's document:
        [props removeObjectForKey: @"_id"];
        [props removeObjectForKey: @"_rev"];
        Assert([model2.document putProperties: props error: &error]);
        // ...and verify its properties:
        AssertEq(model2.reloadCount, 1u);
        AssertEq(model2.number, 4321);
        AssertEqual(model2.str, @"LEET");
        AssertEqual(model2.strings, (@[@"fee", @"fie", @"foe", @"fum"]));
        AssertEqual(model2.data, [@"ASCII" dataUsingEncoding: NSUTF8StringEncoding]);
        AssertEqual(model2.date, [NSDate dateWithTimeIntervalSinceReferenceDate: 392773252]);
        AssertEqual(model2.dates, dates);
        AssertEqual(model2.decimal, decimal);
        AssertEq(model2.other, model3);
        AssertEqual(model2.others, (@[model2, model3]));
        AssertEqual(model2.others, model.others);

        AssertEqual($cast(CBLModelArray, model2.others).docIDs, (@[model2.document.documentID,
                                                                    model3.document.documentID]));
    }
    {
        // Close/reopen the database and verify again:
        [self reopenTestDB];
        CBLDocument* doc = [db documentWithID: modelID];
        TestModel* modelAgain = [TestModel modelForDocument: doc];
        AssertEq(modelAgain.number, 4321);
        AssertEqual(modelAgain.str, @"LEET");
        AssertEqual(modelAgain.strings, (@[@"fee", @"fie", @"foe", @"fum"]));
        AssertEqual(modelAgain.data, [@"ASCII" dataUsingEncoding: NSUTF8StringEncoding]);
        AssertEqual(modelAgain.date, [NSDate dateWithTimeIntervalSinceReferenceDate: 392773252]);
        AssertEqual(modelAgain.dates, dates);
        AssertEqual(modelAgain.decimal, decimal);
        AssertEqual(modelAgain.url, url);

        TestModel *other = modelAgain.other;
        AssertEqual(modelAgain.other.document.documentID, model3ID);
        NSArray* others = modelAgain.others;
        AssertEq(others.count, 2u);
        AssertEq(others[1], other);
        AssertEqual(((TestModel*)others[0]).document.documentID, model2ID);
    }
}


- (void) test00_SaveMutatedSubModel {
    NSError* error;
    
    TestModel* model = [TestModel modelForNewDocumentInDatabase: db];
    TestMutableSubModel* submodel = [[TestMutableSubModel alloc] initWithFirstName: @"Jens" lastName: @"Alfke"];
    model.mutableSubModel = submodel;
    NSMutableDictionary* props = [model.propertiesToSave mutableCopy];
    [props removeObjectForKey: @"_id"];
    AssertEqual(props, (@{@"mutableSubModel":@{@"first": @"Jens", @"last": @"Alfke"}}));
    [model save: &error];
    AssertNil(error);
    
    submodel.firstName = @"Pasin";
    submodel.lastName = @"Suri";
    props = [[model propertiesToSave] mutableCopy];
    [props removeObjectForKey: @"_id"];
    [props removeObjectForKey: @"_rev"];
    AssertEqual(props, (@{@"mutableSubModel":@{@"first": @"Pasin", @"last": @"Suri"}}));
    [model save: &error];
    AssertNil(error);
    
    submodel = model.mutableSubModel;
    submodel.firstName = @"Wayne";
    submodel.lastName = @"Carter";
    props = [[model propertiesToSave] mutableCopy];
    [props removeObjectForKey: @"_id"];
    [props removeObjectForKey: @"_rev"];
    AssertEqual(props, (@{@"mutableSubModel":@{@"first": @"Wayne", @"last": @"Carter"}}));
    [model save: &error];
    AssertNil(error);
}


- (void) test00_SaveModelWithNaNProperty {
    TestModel* model = [TestModel modelForNewDocumentInDatabase: db];
    model.doubly = sqrt(-1);
    NSError* error;
    [model save: &error];
    AssertEq(error.code, 400);
    [model revertChanges];
}


- (void) test00_SaveMutableSubmodels {
    NSError *error;
    TestModel* model = [TestModel modelForNewDocumentInDatabase: db];

    TestMutableSubModel* submodel = [[TestMutableSubModel alloc]
                                          initWithFirstName: @"Phasin"
                                          lastName: @"Suri"];
    model.subModels = @[submodel];
    __unused NSMutableDictionary* props = [model.propertiesToSave mutableCopy];
    [props removeObjectForKey: @"_id"];
    AssertEqual(props, (@{@"subModels": @[@{@"first": @"Phasin", @"last": @"Suri"}]}));
    AssertEq(model.needsSave, YES);
    [model save: &error];
    AssertNil(error);

    props = [model.propertiesToSave mutableCopy];
    TestMutableSubModel* subModel = [model.subModels firstObject];
    subModel.firstName = @"Pasin";
    props = [model.propertiesToSave mutableCopy];
    [props removeObjectForKey: @"_id"];
    [props removeObjectForKey: @"_rev"];
    AssertEqual(props, (@{@"subModels": @[@{@"first": @"Pasin", @"last": @"Suri"}]}));
    AssertEq(model.needsSave, YES);
    [model save: &error];
    AssertNil(error);

    NSMutableArray* newSubModels = [NSMutableArray arrayWithArray: model.subModels];
    model.subModels = newSubModels;
    props = [model.propertiesToSave mutableCopy];
    [props removeObjectForKey: @"_id"];
    [props removeObjectForKey: @"_rev"];
    AssertEqual(props, (@{@"subModels": @[@{@"first": @"Pasin", @"last": @"Suri"}]}));
    AssertEq(model.needsSave, NO);

    newSubModels = [NSMutableArray arrayWithArray: model.subModels];
    subModel = [model.subModels firstObject];
    subModel.lastName = @"Suriyen";
    model.subModels = newSubModels;
    props = [model.propertiesToSave mutableCopy];
    [props removeObjectForKey: @"_id"];
    [props removeObjectForKey: @"_rev"];
    AssertEqual(props, (@{@"subModels": @[@{@"first": @"Pasin", @"last": @"Suriyen"}]}));
    AssertEq(model.needsSave, YES);
    [model save: &error];
    AssertNil(error);
}


- (void) test00_Attachments {
    // Attempting to reproduce https://github.com/couchbase/couchbase-lite-ios/issues/63
    NSError* error;

    NSData* attData = [@"Ceci n'est pas une pipe." dataUsingEncoding: NSUTF8StringEncoding];
    CBLDocument* doc;
    {
        TestModel* model = [TestModel modelForNewDocumentInDatabase: db];
        doc = model.document;
        model.number = 1337;
        Assert([model save: &error], @"Initial failed: %@", error);

        [model setAttachmentNamed: @"Caption.txt" withContentType: @"text/plain" content: attData];
        Assert([model save: &error], @"Save after adding attachment failed: %@", error);

        // Ensure that document's attachment metadata doesn't have the "follows" property set [#63]
        NSDictionary* meta = model.document[@"_attachments"][@"Caption.txt"];
        AssertEqual(meta[@"content_type"], @"text/plain");
        AssertEqual(meta[@"length"], @24);
        AssertNil(meta[@"follows"]);

        model.number = 23;
        Assert([model save: &error], @"Save after updating number failed: %@", error);
    }
    {
        TestModel* model = [TestModel modelForDocument: doc];
        AssertEq(model.number, 23);
        CBLAttachment* attachment = [model attachmentNamed: @"Caption.txt"];
        AssertEqual(attachment.content, attData);

        model.number = -1;
        Assert([model save: &error], @"Save of new model object failed: %@", error);

        // Now update the attachment:
        [model removeAttachmentNamed: @"caption.txt"];
        NSData* newAttData = [@"sluggo" dataUsingEncoding: NSUTF8StringEncoding];
        [model setAttachmentNamed: @"Caption.txt" withContentType: @"text/plain" content:newAttData];
        Assert([model save: &error], @"Final save failed: %@", error);
    }
}


- (void) test00_PropertyObservation {
    // For https://github.com/couchbase/couchbase-lite-ios/issues/244
    TestModel* model = [TestModel modelForNewDocumentInDatabase: db];
    id observer = [NSObject new];

    @autoreleasepool {
        model.dict = @{@"name": @"Puddin' Tane"};
        [model addObserver: observer forKeyPath: @"dict.name" options: 0 context: NULL];
        [model save: NULL];
    }
    [model removeObserver: observer forKeyPath: @"dict.name"];
}


- (void) test00_AwakeFromInitializer {
    CBL_TestAwakeInitModel* model = [CBL_TestAwakeInitModel modelForNewDocumentInDatabase: db];
    Assert(model.didAwake);
    NSError *error;
    Assert([model save: &error], @"Save of new model object failed: %@", error);
}


- (void) test00_InverseRelation {
    // Create two TestModels as targets for the 'model' relation:
    [db.modelFactory registerClass: [TestModel class] forDocumentType: @"test"];
    [db.modelFactory registerClass: [TestOtherModel class] forDocumentType: @"other"];
    TestModel* model1 = [TestModel modelForNewDocumentInDatabase: db];
    model1.number = 1;
    TestModel* model2 = [TestModel modelForNewDocumentInDatabase: db];
    model2.number = 2;

    // Create 100 TestOtherModels whose 'model' properties point to the above TestModels:
    for (int i = 0; i < 50; i++) {
        TestOtherModel* other = [TestOtherModel modelForNewDocumentInDatabase: db];
        other.number = i;
        other.model = (i % 2) ? model1 : model2;
    }

    NSError* error;
    Assert([db saveAllModels: &error], @"Save failed: %@", error);

    // Now query:
    NSArray* result1 = model1.otherModels;
    AssertEq(result1.count, 25u);
    for (TestOtherModel* m in result1) {
        AssertEq([m class], [TestOtherModel class]);
        AssertEq(m.number % 2, 1);
    }
    NSArray* result2 = model2.otherModels;
    AssertEq(result2.count, 25u);
    for (TestOtherModel* m in result2) {
        AssertEq([m class], [TestOtherModel class]);
        AssertEq(m.number % 2, 0);
    }
}

@end


@implementation TestModel

@dynamic number, uInt, sInt16, uInt16, sInt8, uInt8, nsInt, nsUInt, sInt32, uInt32;
@dynamic sInt64, uInt64, boolean, boolObjC, floaty, doubly, dict;
@dynamic str, data, date, decimal, url, other, strings, dates, others, Capitalized;
@dynamic subModel, subModels, mutableSubModel, otherModels;
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

+ (Class) otherModelsItemClass {
    return [TestOtherModel class];
}

+ (NSString*) otherModelsInverseRelation {
    return @"model";
}

@end


@implementation TestSubModel
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


@implementation TestMutableSubModel
{
    CBLOnMutateBlock _onMutate;
}

@dynamic firstName, lastName;     // Necessary because this class redeclares them

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

@implementation CBL_TestAwakeInitModel

@dynamic didAwake;

- (void) awakeFromInitializer {
    self.didAwake = YES;
}

@end

@implementation TestOtherModel
@dynamic number, model;
@end


