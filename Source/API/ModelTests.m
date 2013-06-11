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
@property unsigned reloadCount;
@end


@implementation TestModel

@dynamic number, str;
@synthesize reloadCount;

- (void) didLoadFromDocument {
    self.reloadCount++;
    Log(@"reloadCount = %u",self.reloadCount);
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

    model.number = 1337;
    model.str = @"LEET";

    CAssert(model.isNew);
    CAssert(model.needsSave);
    CAssertEqual(model.propertiesToSave, (@{@"number": @(1337), @"str": @"LEET"}));

    NSError* error;
    CAssert([model save: &error]);

    CAssertEq(model.reloadCount, 0u);

    NSMutableDictionary* props = [model.document.properties mutableCopy];
    props[@"number"] = @4321;
    CAssert([model.document putProperties: props error: &error]);

    CAssertEq(model.reloadCount, 1u);
    CAssertEq(model.number, 4321);

    closeTestDB(db);
}


#endif // DEBUG
