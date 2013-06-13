//
//  ModelTests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/11/13.
//  Copyright 2011 Couchbase, Inc.
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
    CBLDatabase* db = dbmgr[@"test_db"];
    if (db)
        CAssert([db deleteDatabase: &error], @"Couldn't delete old test_db: %@", error);
    db = [dbmgr createDatabaseNamed: @"test_db" error: &error];
    CAssert(db, @"Couldn't create db: %@", error);
    return db;
}


static void closeTestDB(CBLDatabase* db) {
    CAssert(db != nil);
    CAssert([db close]);
}


#pragma mark - TEST MODEL:


@interface TestModel : CBLModel
@property int number;
@property NSString* str;
@property NSData* data;
@property NSDate* date;
@property NSDecimalNumber* decimal;
@property TestModel* other;
@property NSArray* strings;
@property NSArray* dates;
@property NSArray* others;

@property unsigned reloadCount;
@end


@implementation TestModel

@dynamic number, str, data, date, decimal, other, strings, dates, others;
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

@end


#pragma mark - MODELS:


TestCase(API_SaveModel) {
    CBLDatabase* db = createEmptyDB();
    TestModel* model = [[TestModel alloc] initWithNewDocumentInDatabase: db];
    CAssert(model != nil);
    CAssert(model.isNew);
    CAssert(!model.needsSave);
    CAssertEq(model.propertiesToSave.count, 0u);

    NSDate* date = [NSDate dateWithTimeIntervalSinceReferenceDate: 392773252];
    NSArray* dates = @[date, [NSDate dateWithTimeIntervalSinceReferenceDate: 392837521]];
    NSDecimalNumber* decimal = [NSDecimalNumber decimalNumberWithString: @"12345.6789"];

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
    TestModel* model3 = [[TestModel alloc] initWithNewDocumentInDatabase: db];

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
    NSError* error;
    CAssert([model save: &error]);
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

    closeTestDB(db);
}


#endif // DEBUG
