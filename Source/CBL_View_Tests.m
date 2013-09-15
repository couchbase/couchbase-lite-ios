//
//  CBL_View_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/8/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLView+Internal.h"
#import "CBLDatabase+Insertion.h"
#import "CBLInternal.h"
#import "CouchbaseLitePrivate.h"
#import "Test.h"


#if DEBUG

static CBLDatabase* createDB(void) {
    return [CBLDatabase createEmptyDBAtPath: [NSTemporaryDirectory() stringByAppendingPathComponent: @"CouchbaseLite_ViewTest.touchdb"]];
}

TestCase(CBL_View_Create) {
    RequireTestCase(CBLDatabase);
    CBLDatabase *db = createDB();
    
    CAssertNil([db existingViewNamed: @"aview"]);
    
    CBLView* view = [db viewNamed: @"aview"];
    CAssert(view);
    CAssertEqual(view.name, @"aview");
    CAssert(view.mapBlock == nil, nil);
    CAssertEq([db existingViewNamed: @"aview"], view);

    
    BOOL changed = [view setMapBlock: MAPBLOCK({})
                         reduceBlock: NULL version: @"1"];
    CAssert(changed);
    
    CAssertEqual(db.allViews, @[view]);

    changed = [view setMapBlock: MAPBLOCK({})
                    reduceBlock: NULL version: @"1"];
    CAssert(!changed);
    
    changed = [view setMapBlock: MAPBLOCK({})
                    reduceBlock: NULL version: @"2"];
    CAssert(changed);
    
    [db close];
}


static CBL_Revision* putDoc(CBLDatabase* db, NSDictionary* props) {
    CBL_Revision* rev = [[CBL_Revision alloc] initWithProperties: props];
    CBLStatus status;
    CBL_Revision* result = [db putRevision: rev prevRevisionID: nil allowConflict: NO status: &status];
    CAssert(status < 300);
    return result;
}


static NSArray* putDocs(CBLDatabase* db) {
    NSMutableArray* docs = $marray();
    [docs addObject: putDoc(db, $dict({@"_id", @"22222"}, {@"key", @"two"}))];
    [docs addObject: putDoc(db, $dict({@"_id", @"44444"}, {@"key", @"four"}))];
    [docs addObject: putDoc(db, $dict({@"_id", @"11111"}, {@"key", @"one"}))];
    [docs addObject: putDoc(db, $dict({@"_id", @"33333"}, {@"key", @"three"}))];
    [docs addObject: putDoc(db, $dict({@"_id", @"55555"}, {@"key", @"five"}))];
    return docs;
}

static NSArray* putGeoDocs(CBLDatabase* db) {
    NSMutableArray* docs = $marray();
    [docs addObject: putDoc(db, $dict({@"_id", @"22222"}, {@"key", @"two"}))];
    [docs addObject: putDoc(db, $dict({@"_id", @"44444"}, {@"key", @"four"}))];
    [docs addObject: putDoc(db, $dict({@"_id", @"11111"}, {@"key", @"one"}))];
    [docs addObject: putDoc(db, $dict({@"_id", @"33333"}, {@"key", @"three"}))];
    [docs addObject: putDoc(db, $dict({@"_id", @"55555"}, {@"key", @"five"}))];
    [docs addObject: putDoc(db, $dict({@"_id", @"55555"}, {@"key", @"Portland"}, {@"geoJSON", $dict({@"type", @"Point"}, {@"coordinates", $array(@122.68, @45.52)})}))];
    [docs addObject: putDoc(db, $dict({@"_id", @"55555"}, {@"key", @"Austin"}, {@"geoJSON", $dict({@"type", @"Point"}, {@"coordinates", $array(@97.75, @30.25)})}))];
    [docs addObject: putDoc(db, $dict({@"_id", @"55555"}, {@"key", @"Mountain View"}, {@"geoJSON", $dict({@"type", @"Point"}, {@"coordinates", $array(@122.08, @37.39)})}))];
    return docs;
}


static CBLView* createView(CBLDatabase* db) {
    CBLView* view = [db viewNamed: @"aview"];
    [view setMapBlock: MAPBLOCK({
        CAssert(doc[@"_id"] != nil, @"Missing _id in %@", doc);
        CAssert(doc[@"_rev"] != nil, @"Missing _rev in %@", doc);
        if (doc[@"key"])
            emit(doc[@"key"], doc[@"_conflicts"]);
        if (doc[@"geoJSON"])
            geoemit(doc[@"geoJSON"], doc[@"_conflicts"]);
    }) reduceBlock: NULL version: @"1"];
    return view;
}


static NSArray* rowsToDicts(NSArray* rows) {
    return [rows my_map:^(CBLQueryRow* row) {return row.asJSONDictionary;}];
}


TestCase(CBL_View_Index) {
    RequireTestCase(CBL_View_Create);
    CBLDatabase *db = createDB();
    CBL_Revision* rev1 = putDoc(db, $dict({@"key", @"one"}));
    CBL_Revision* rev2 = putDoc(db, $dict({@"key", @"two"}));
    CBL_Revision* rev3 = putDoc(db, $dict({@"key", @"three"}));
    putDoc(db, $dict({@"_id", @"_design/foo"}));
    putDoc(db, $dict({@"clef", @"quatre"}));
    
    CBLView* view = createView(db);
    CAssertEq(view.viewID, 1);
    
    CAssert(view.stale);
    CAssertEq([view updateIndex], kCBLStatusOK);
    
    NSArray* dump = [view dump];
    Log(@"View dump: %@", dump);
    CAssertEqual(dump, $array($dict({@"key", @"\"one\""}, {@"seq", @1}),
                              $dict({@"key", @"\"three\""}, {@"seq", @3}),
                              $dict({@"key", @"\"two\""}, {@"seq", @2}) ));
    // No-op reindex:
    CAssert(!view.stale);
    CAssertEq([view updateIndex], kCBLStatusNotModified);
    
    // Now add a doc and update a doc:
    CBL_MutableRevision* threeUpdated = [[CBL_MutableRevision alloc] initWithDocID: rev3.docID revID: nil deleted:NO];
    threeUpdated.properties = $dict({@"key", @"3hree"});
    CBLStatus status;
    rev3 = [db putRevision: threeUpdated prevRevisionID: rev3.revID allowConflict: NO status: &status];
    CAssert(status < 300);

    CBL_Revision* rev4 = putDoc(db, $dict({@"key", @"four"}));
    
    CBL_Revision* twoDeleted = [[CBL_Revision alloc] initWithDocID: rev2.docID revID: nil deleted:YES];
    [db putRevision: twoDeleted prevRevisionID: rev2.revID allowConflict: NO status: &status];
    CAssert(status < 300);

    // Reindex again:
    CAssert(view.stale);
    CAssertEq([view updateIndex], kCBLStatusOK);

    dump = [view dump];
    Log(@"View dump: %@", dump);
    CAssertEqual(dump, $array($dict({@"key", @"\"3hree\""}, {@"seq", @6}),
                              $dict({@"key", @"\"four\""}, {@"seq", @7}),
                              $dict({@"key", @"\"one\""}, {@"seq", @1}) ));
    
    // Now do a real query:
    NSArray* rows = rowsToDicts([view _queryWithOptions: NULL status: &status]);
    CAssertEq(status, kCBLStatusOK);
    CAssertEqual(rows, $array( $dict({@"key", @"3hree"}, {@"id", rev3.docID}),
                               $dict({@"key", @"four"}, {@"id", rev4.docID}),
                               $dict({@"key", @"one"}, {@"id", rev1.docID}) ));
    
    [view removeIndex];
    
    [db close];
}


TestCase(CBL_View_MapConflicts) {
    RequireTestCase(CBL_View_Index);
    CBLDatabase *db = createDB();
    NSArray* docs = putDocs(db);
    CBL_Revision* leaf1 = docs[1];
    
    // Create a conflict:
    NSDictionary* props = $dict({@"_id", @"44444"},
                                {@"_rev", @"1-~~~~~"},  // higher revID, will win conflict
                                {@"key", @"40ur"});
    CBL_Revision* leaf2 = [[CBL_Revision alloc] initWithProperties: props];
    CBLStatus status = [db forceInsert: leaf2 revisionHistory: @[] source: nil];
    CAssert(status < 300);
    CAssertEqual(leaf1.docID, leaf2.docID);
    
    CBLView* view = [db viewNamed: @"conflicts"];
    [view setMapBlock: MAPBLOCK({
        NSString* docID = doc[@"_id"];
        NSArray* conflicts = $cast(NSArray, doc[@"_conflicts"]);
        if (conflicts) {
            Log(@"Doc %@, _conflicts = %@", docID, conflicts);
            emit(docID, conflicts);
        }
    }) reduceBlock: NULL version: @"1"];
    
    CAssertEq([view updateIndex], kCBLStatusOK);
    NSArray* dump = [view dump];
    Log(@"View dump: %@", dump);
    CAssertEqual(dump, $array($dict({@"key", @"\"44444\""},
                                    {@"value", $sprintf(@"[\"%@\"]", leaf1.revID)},
                                    {@"seq", @6}) ));
    [db close];
}


TestCase(CBL_View_ConflictWinner) {
    // If a view is re-indexed, and a document in the view has gone into conflict,
    // rows emitted by the earlier 'losing' revision shouldn't appear in the view.
    RequireTestCase(CBL_View_Index);
    CBLDatabase *db = createDB();
    NSArray* docs = putDocs(db);
    CBL_Revision* leaf1 = docs[1];
    
    CBLView* view = createView(db);
    CAssertEq([view updateIndex], kCBLStatusOK);
    NSArray* dump = [view dump];
    Log(@"View dump: %@", dump);
    CAssertEqual(dump, $array($dict({@"key", @"\"five\""}, {@"seq", @5}),
                              $dict({@"key", @"\"four\""}, {@"seq", @2}),
                              $dict({@"key", @"\"one\""},  {@"seq", @3}),
                              $dict({@"key", @"\"three\""},{@"seq", @4}),
                              $dict({@"key", @"\"two\""},  {@"seq", @1}) ));
    
    // Create a conflict, won by the new revision:
    NSDictionary* props = $dict({@"_id", @"44444"},
                                {@"_rev", @"1-~~~~~"},  // higher revID, will win conflict
                                {@"key", @"40ur"});
    CBL_Revision* leaf2 = [[CBL_Revision alloc] initWithProperties: props];
    CBLStatus status = [db forceInsert: leaf2 revisionHistory: @[] source: nil];
    CAssert(status < 300);
    CAssertEqual(leaf1.docID, leaf2.docID);
    
    // Update the view -- should contain only the key from the new rev, not the old:
    CAssertEq([view updateIndex], kCBLStatusOK);
    dump = [view dump];
    Log(@"View dump: %@", dump);
    CAssertEqual(dump, $array($dict({@"key", @"\"40ur\""}, {@"seq", @6},
                                    {@"value", $sprintf(@"[\"%@\"]", leaf1.revID)}),
                              $dict({@"key", @"\"five\""}, {@"seq", @5}),
                              $dict({@"key", @"\"one\""},  {@"seq", @3}),
                              $dict({@"key", @"\"three\""},{@"seq", @4}),
                              $dict({@"key", @"\"two\""},  {@"seq", @1}) ));
    [db close];
}


TestCase(CBL_View_ConflictLoser) {
    // Like the ConflictWinner test, except the newer revision is the loser,
    // so it shouldn't be indexed at all. Instead, the older still-winning revision
    // should be indexed again, this time with a '_conflicts' property.
    CBLDatabase *db = createDB();
    NSArray* docs = putDocs(db);
    CBL_Revision* leaf1 = docs[1];
    
    CBLView* view = createView(db);
    CAssertEq([view updateIndex], kCBLStatusOK);
    NSArray* dump = [view dump];
    Log(@"View dump: %@", dump);
    CAssertEqual(dump, $array($dict({@"key", @"\"five\""}, {@"seq", @5}),
                              $dict({@"key", @"\"four\""}, {@"seq", @2}),
                              $dict({@"key", @"\"one\""},  {@"seq", @3}),
                              $dict({@"key", @"\"three\""},{@"seq", @4}),
                              $dict({@"key", @"\"two\""},  {@"seq", @1}) ));
    
    // Create a conflict, won by the new revision:
    NSDictionary* props = $dict({@"_id", @"44444"},
                                {@"_rev", @"1-...."},  // lower revID, will lose conflict
                                {@"key", @"40ur"});
    CBL_Revision* leaf2 = [[CBL_Revision alloc] initWithProperties: props];
    CBLStatus status = [db forceInsert: leaf2 revisionHistory: @[] source: nil];
    CAssert(status < 300);
    CAssertEqual(leaf1.docID, leaf2.docID);
    
    // Update the view -- should contain only the key from the new rev, not the old:
    CAssertEq([view updateIndex], kCBLStatusOK);
    dump = [view dump];
    Log(@"View dump: %@", dump);
    CAssertEqual(dump, $array($dict({@"key", @"\"five\""}, {@"seq", @5}),
                              $dict({@"key", @"\"four\""}, {@"seq", @2},
                                    {@"value", @"[\"1-....\"]"}),
                              $dict({@"key", @"\"one\""},  {@"seq", @3}),
                              $dict({@"key", @"\"three\""},{@"seq", @4}),
                              $dict({@"key", @"\"two\""},  {@"seq", @1}) ));
    [db close];
}


TestCase(CBL_View_Query) {
    RequireTestCase(CBL_View_Index);
    CBLDatabase *db = createDB();
    putDocs(db);
    CBLView* view = createView(db);
    CAssertEq([view updateIndex], kCBLStatusOK);
    
    // Query all rows:
    CBLQueryOptions options = kDefaultCBLQueryOptions;
    CBLStatus status;
    NSArray* rows = rowsToDicts([view _queryWithOptions: &options status: &status]);
    NSArray* expectedRows = $array($dict({@"id",  @"55555"}, {@"key", @"five"}),
                                   $dict({@"id",  @"44444"}, {@"key", @"four"}),
                                   $dict({@"id",  @"11111"}, {@"key", @"one"}),
                                   $dict({@"id",  @"33333"}, {@"key", @"three"}),
                                   $dict({@"id",  @"22222"}, {@"key", @"two"}));
    CAssertEqual(rows, expectedRows);

    return;
    
    // Start/end key query:
    options = kDefaultCBLQueryOptions;
    options.startKey = @"a";
    options.endKey = @"one";
    rows = rowsToDicts([view _queryWithOptions: &options status: &status]);
    expectedRows = $array($dict({@"id",  @"55555"}, {@"key", @"five"}),
                          $dict({@"id",  @"44444"}, {@"key", @"four"}),
                          $dict({@"id",  @"11111"}, {@"key", @"one"}));
    CAssertEqual(rows, expectedRows);

    // Start/end query without inclusive end:
    options.inclusiveEnd = NO;
    rows = rowsToDicts([view _queryWithOptions: &options status: &status]);
    expectedRows = $array($dict({@"id",  @"55555"}, {@"key", @"five"}),
                          $dict({@"id",  @"44444"}, {@"key", @"four"}));
    CAssertEqual(rows, expectedRows);

    // Reversed:
    options.descending = YES;
    options.startKey = @"o";
    options.endKey = @"five";
    options.inclusiveEnd = YES;
    rows = rowsToDicts([view _queryWithOptions: &options status: &status]);
    expectedRows = $array($dict({@"id",  @"44444"}, {@"key", @"four"}),
                          $dict({@"id",  @"55555"}, {@"key", @"five"}));
    CAssertEqual(rows, expectedRows);

    // Reversed, no inclusive end:
    options.inclusiveEnd = NO;
    rows = rowsToDicts([view _queryWithOptions: &options status: &status]);
    expectedRows = $array($dict({@"id",  @"44444"}, {@"key", @"four"}));
    CAssertEqual(rows, expectedRows);
    
    // Limit:
    options = kDefaultCBLQueryOptions;
    options.limit = 2;
    rows = rowsToDicts([view _queryWithOptions: &options status: &status]);
    expectedRows = $array($dict({@"id",  @"55555"}, {@"key", @"five"}),
                          $dict({@"id",  @"44444"}, {@"key", @"four"}));
    CAssertEqual(rows, expectedRows);

    // Skip rows:
    options = kDefaultCBLQueryOptions;
    options.skip = 2;
    rows = rowsToDicts([view _queryWithOptions: &options status: &status]);
    expectedRows = $array($dict({@"id",  @"11111"}, {@"key", @"one"}),
                          $dict({@"id",  @"33333"}, {@"key", @"three"}),
                          $dict({@"id",  @"22222"}, {@"key", @"two"}));
    CAssertEqual(rows, expectedRows);

    // Skip + limit:
    options.limit = 1;
    rows = rowsToDicts([view _queryWithOptions: &options status: &status]);
    expectedRows = $array($dict({@"id",  @"11111"}, {@"key", @"one"}));
    CAssertEqual(rows, expectedRows);

    // Specific keys:
    options = kDefaultCBLQueryOptions;
    NSArray* keys = @[@"two", @"four"];
    options.keys = keys;
    rows = rowsToDicts([view _queryWithOptions: &options status: &status]);
    expectedRows = $array($dict({@"id",  @"44444"}, {@"key", @"four"}),
                          $dict({@"id",  @"22222"}, {@"key", @"two"}));
    CAssertEqual(rows, expectedRows);

    [db close];
}

TestCase(CBL_View_GeoQuery) {
    RequireTestCase(CBL_View_Index);
    CBLDatabase *db = createDB();
    putGeoDocs(db);
    CBLView* view = createView(db);
    CAssertEq([view updateIndex], kCBLStatusOK);
    
    // Query all rows:
    CBLQueryOptions options = kDefaultCBLQueryOptions;
    CBLStatus status;
    NSArray* rows = rowsToDicts([view _queryWithOptions: &options status: &status]);
    NSArray* expectedRows = $array($dict({@"id",  @"55555"}, {@"key", @"five"}),
                                   $dict({@"id",  @"44444"}, {@"key", @"four"}),
                                   $dict({@"id",  @"11111"}, {@"key", @"one"}),
                                   $dict({@"id",  @"33333"}, {@"key", @"three"}),
                                   $dict({@"id",  @"22222"}, {@"key", @"two"}));
    CAssertEqual(rows, expectedRows);
    
    // Start/end key query:
    options = kDefaultCBLQueryOptions;
    options.startKey = @"a";
    options.endKey = @"one";
    rows = rowsToDicts([view _queryWithOptions: &options status: &status]);
    expectedRows = $array($dict({@"id",  @"55555"}, {@"key", @"five"}),
                          $dict({@"id",  @"44444"}, {@"key", @"four"}),
                          $dict({@"id",  @"11111"}, {@"key", @"one"}));
    CAssertEqual(rows, expectedRows);
    
    // Start/end query without inclusive end:
    options.inclusiveEnd = NO;
    rows = rowsToDicts([view _queryWithOptions: &options status: &status]);
    expectedRows = $array($dict({@"id",  @"55555"}, {@"key", @"five"}),
                          $dict({@"id",  @"44444"}, {@"key", @"four"}));
    CAssertEqual(rows, expectedRows);
    
    // Reversed:
    options.descending = YES;
    options.startKey = @"o";
    options.endKey = @"five";
    options.inclusiveEnd = YES;
    rows = rowsToDicts([view _queryWithOptions: &options status: &status]);
    expectedRows = $array($dict({@"id",  @"44444"}, {@"key", @"four"}),
                          $dict({@"id",  @"55555"}, {@"key", @"five"}));
    CAssertEqual(rows, expectedRows);
    
    // Reversed, no inclusive end:
    options.inclusiveEnd = NO;
    rows = rowsToDicts([view _queryWithOptions: &options status: &status]);
    expectedRows = $array($dict({@"id",  @"44444"}, {@"key", @"four"}));
    CAssertEqual(rows, expectedRows);
    
    // Limit:
    options = kDefaultCBLQueryOptions;
    options.limit = 2;
    rows = rowsToDicts([view _queryWithOptions: &options status: &status]);
    expectedRows = $array($dict({@"id",  @"55555"}, {@"key", @"five"}),
                          $dict({@"id",  @"44444"}, {@"key", @"four"}));
    CAssertEqual(rows, expectedRows);
    
    // Skip rows:
    options = kDefaultCBLQueryOptions;
    options.skip = 2;
    rows = rowsToDicts([view _queryWithOptions: &options status: &status]);
    expectedRows = $array($dict({@"id",  @"11111"}, {@"key", @"one"}),
                          $dict({@"id",  @"33333"}, {@"key", @"three"}),
                          $dict({@"id",  @"22222"}, {@"key", @"two"}));
    CAssertEqual(rows, expectedRows);
    
    // Skip + limit:
    options.limit = 1;
    rows = rowsToDicts([view _queryWithOptions: &options status: &status]);
    expectedRows = $array($dict({@"id",  @"11111"}, {@"key", @"one"}));
    CAssertEqual(rows, expectedRows);
    
    // Specific keys:
    options = kDefaultCBLQueryOptions;
    NSArray* keys = @[@"two", @"four"];
    options.keys = keys;
    rows = rowsToDicts([view _queryWithOptions: &options status: &status]);
    expectedRows = $array($dict({@"id",  @"44444"}, {@"key", @"four"}),
                          $dict({@"id",  @"22222"}, {@"key", @"two"}));
    CAssertEqual(rows, expectedRows);
    
    [db close];
}

TestCase(CBL_View_AllDocsQuery) {
    CBLDatabase *db = createDB();
    NSArray* docs = putDocs(db);
    NSDictionary* expectedRow[docs.count];
    memset(&expectedRow, 0, sizeof(expectedRow));
    int i = 0;
    for (CBL_Revision* rev in docs) {
        expectedRow[i++] = $dict({@"id",  rev.docID},
                                 {@"key", rev.docID},
                                 {@"value", $dict({@"rev", rev.revID})});
    }
    
    // Query all rows:
    CBLQueryOptions options = kDefaultCBLQueryOptions;
    NSArray* query = [db getAllDocs: &options];
    NSArray* expectedRows = $array(expectedRow[2], expectedRow[0], expectedRow[3], expectedRow[1],
                                   expectedRow[4]);
    CAssertEqual(rowsToDicts(query), expectedRows);

    // Start/end key query:
    options = kDefaultCBLQueryOptions;
    options.startKey = @"2";
    options.endKey = @"44444";
    query = [db getAllDocs: &options];
    expectedRows = @[expectedRow[0], expectedRow[3], expectedRow[1]];
    CAssertEqual(rowsToDicts(query), expectedRows);

    // Start/end query without inclusive end:
    options.inclusiveEnd = NO;
    query = [db getAllDocs: &options];
    expectedRows = @[expectedRow[0], expectedRow[3]];
    CAssertEqual(rowsToDicts(query), expectedRows);

    // Get zero specific documents:
    options = kDefaultCBLQueryOptions;
    options.keys = @[];
    query = [db getAllDocs: &options];
    CAssertEq(query.count, 0u);
    
    // Get specific documents:
    options = kDefaultCBLQueryOptions;
    __unused NSArray* keys = @[(expectedRow[2])[@"id"], expectedRow[3][@"id"]];
    options.keys = keys;
    query = [db getAllDocs: &options];
    CAssertEqual(rowsToDicts(query), (@[expectedRow[2], expectedRow[3]]));

    // Delete a document:
    CBL_Revision* del = docs[0];
    del = [[CBL_Revision alloc] initWithDocID: del.docID revID: del.revID deleted: YES];
    CBLStatus status;
    del = [db putRevision: del prevRevisionID: del.revID allowConflict: NO status: &status];
    CAssertEq(status, kCBLStatusOK);

    // Get deleted doc, and one bogus one:
    options = kDefaultCBLQueryOptions;
    keys = options.keys = @[@"BOGUS", expectedRow[0][@"id"]];
    query = [db getAllDocs: &options];
    CAssertEqual(rowsToDicts(query), (@[$dict({@"key",  @"BOGUS"},
                                              {@"error", @"not_found"}),
                                      $dict({@"id",  del.docID},
                                            {@"key", del.docID},
                                            {@"value", $dict({@"rev", del.revID},
                                                             {@"deleted", $true})}) ]));
    [db close];
}


TestCase(CBL_View_Reduce) {
    RequireTestCase(CBL_View_Query);
    CBLDatabase *db = createDB();
    putDoc(db, $dict({@"_id", @"CD"},      {@"cost", @(8.99)}));
    putDoc(db, $dict({@"_id", @"App"},     {@"cost", @(1.95)}));
    putDoc(db, $dict({@"_id", @"Dessert"}, {@"cost", @(6.50)}));
    
    CBLView* view = [db viewNamed: @"totaler"];
    [view setMapBlock: MAPBLOCK({
        CAssert(doc[@"_id"] != nil, @"Missing _id in %@", doc);
        CAssert(doc[@"_rev"] != nil, @"Missing _rev in %@", doc);
        id cost = doc[@"cost"];
        if (cost)
            emit(doc[@"_id"], cost);
    }) reduceBlock: ^(NSArray* keys, NSArray* values, BOOL rereduce) {
        return [CBLView totalValues: values];
    } version: @"1"];

    CAssertEq([view updateIndex], kCBLStatusOK);
    NSArray* dump = [view dump];
    Log(@"View dump: %@", dump);
    CAssertEqual(dump, $array($dict({@"key", @"\"App\""}, {@"value", @"1.95"}, {@"seq", @2}),
                              $dict({@"key", @"\"CD\""}, {@"value", @"8.99"}, {@"seq", @1}),
                              $dict({@"key", @"\"Dessert\""}, {@"value", @"6.5"}, {@"seq", @3}) ));

    CBLQueryOptions options = kDefaultCBLQueryOptions;
    CBLStatus status;
    NSArray* reduced = rowsToDicts([view _queryWithOptions: &options status: &status]);
    CAssertEq(status, kCBLStatusOK);
    CAssertEq(reduced.count, 1u);
    double result = [reduced[0][@"value"] doubleValue];
    CAssert(fabs(result - 17.44) < 0.001, @"Unexpected reduced value %@", reduced);
    [db close];
}


TestCase(CBL_View_Grouped) {
    RequireTestCase(CBL_View_Reduce);
    CBLDatabase *db = createDB();
    putDoc(db, $dict({@"_id", @"1"}, {@"artist", @"Gang Of Four"}, {@"album", @"Entertainment!"},
                     {@"track", @"Ether"}, {@"time", @(231)}));
    putDoc(db, $dict({@"_id", @"2"}, {@"artist", @"Gang Of Four"}, {@"album", @"Songs Of The Free"},
                     {@"track", @"I Love A Man In Uniform"}, {@"time", @(248)}));
    putDoc(db, $dict({@"_id", @"3"}, {@"artist", @"Gang Of Four"}, {@"album", @"Entertainment!"},
                     {@"track", @"Natural's Not In It"}, {@"time", @(187)}));
    putDoc(db, $dict({@"_id", @"4"}, {@"artist", @"PiL"}, {@"album", @"Metal Box"},
                     {@"track", @"Memories"}, {@"time", @(309)}));
    putDoc(db, $dict({@"_id", @"5"}, {@"artist", @"Gang Of Four"}, {@"album", @"Entertainment!"},
                     {@"track", @"Not Great Men"}, {@"time", @(187)}));
    
    CBLView* view = [db viewNamed: @"grouper"];
    [view setMapBlock: MAPBLOCK({
        emit($array(doc[@"artist"],
                    doc[@"album"], 
                    doc[@"track"]),
             doc[@"time"]);
    }) reduceBlock:^id(NSArray *keys, NSArray *values, BOOL rereduce) {
        return [CBLView totalValues: values];
    } version: @"1"];
    
    CAssertEq([view updateIndex], kCBLStatusOK);

    CBLQueryOptions options = kDefaultCBLQueryOptions;
    CBLStatus status;
    NSArray* rows = rowsToDicts([view _queryWithOptions: &options status: &status]);
    CAssertEq(status, kCBLStatusOK);
    CAssertEqual(rows, $array($dict({@"key", $null}, {@"value", @(1162)})));

    options.group = YES;
    rows = rowsToDicts([view _queryWithOptions: &options status: &status]);
    CAssertEq(status, kCBLStatusOK);
    CAssertEqual(rows, $array($dict({@"key", $array(@"Gang Of Four", @"Entertainment!",
                                                    @"Ether")},
                                    {@"value", @(231)}),
                              $dict({@"key", $array(@"Gang Of Four", @"Entertainment!",
                                                    @"Natural's Not In It")},
                                    {@"value", @(187)}),
                              $dict({@"key", $array(@"Gang Of Four", @"Entertainment!",
                                                    @"Not Great Men")},
                                    {@"value", @(187)}),
                              $dict({@"key", $array(@"Gang Of Four", @"Songs Of The Free",
                                                    @"I Love A Man In Uniform")},
                                    {@"value", @(248)}),
                              $dict({@"key", $array(@"PiL", @"Metal Box",
                                                    @"Memories")}, 
                                    {@"value", @(309)})));

    options.groupLevel = 1;
    rows = rowsToDicts([view _queryWithOptions: &options status: &status]);
    CAssertEq(status, kCBLStatusOK);
    CAssertEqual(rows, $array($dict({@"key", @[@"Gang Of Four"]}, {@"value", @(853)}),
                              $dict({@"key", @[@"PiL"]}, {@"value", @(309)})));
    
    options.groupLevel = 2;
    rows = rowsToDicts([view _queryWithOptions: &options status: &status]);
    CAssertEq(status, kCBLStatusOK);
    CAssertEqual(rows, $array($dict({@"key", @[@"Gang Of Four", @"Entertainment!"]},
                                    {@"value", @(605)}),
                              $dict({@"key", @[@"Gang Of Four", @"Songs Of The Free"]},
                                    {@"value", @(248)}),
                              $dict({@"key", @[@"PiL", @"Metal Box"]}, 
                                    {@"value", @(309)})));
    [db close];
}


TestCase(CBL_View_GroupedStrings) {
    RequireTestCase(CBL_View_Grouped);
    CBLDatabase *db = createDB();
    putDoc(db, $dict({@"name", @"Alice"}));
    putDoc(db, $dict({@"name", @"Albert"}));
    putDoc(db, $dict({@"name", @"Naomi"}));
    putDoc(db, $dict({@"name", @"Jens"}));
    putDoc(db, $dict({@"name", @"Jed"}));
    
    CBLView* view = [db viewNamed: @"default/names"];
    [view setMapBlock: MAPBLOCK({
         NSString *name = doc[@"name"];
         if (name)
             emit([name substringToIndex:1], @1);
     }) reduceBlock:^id(NSArray *keys, NSArray *values, BOOL rereduce) {
         return @([values count]);
     } version:@"1.0"];
   
    CAssertEq([view updateIndex], kCBLStatusOK);

    CBLQueryOptions options = kDefaultCBLQueryOptions;
    options.groupLevel = 1;
    CBLStatus status;
    NSArray* rows = rowsToDicts([view _queryWithOptions: &options status: &status]);
    CAssertEq(status, kCBLStatusOK);
    CAssertEqual(rows, $array($dict({@"key", @"A"}, {@"value", @2}),
                              $dict({@"key", @"J"}, {@"value", @2}),
                              $dict({@"key", @"N"}, {@"value", @1})));
    [db close];
}


TestCase(CBL_View_Collation) {
    // Based on CouchDB's "view_collation.js" test
    NSArray* testKeys = @[$null,
                                                   $false,
                                                   $true,
                                                   @0,
                                                   @(2.5),
                                                   @(10),
                                                   @" ", @"_", @"~", 
                                                   @"a",
                                                   @"A",
                                                   @"aa",
                                                   @"b",
                                                   @"B",
                                                   @"ba",
                                                   @"bb",
                                                   @[@"a"],
                                                   @[@"b"],
                                                   @[@"b", @"c"],
                                                   @[@"b", @"c", @"a"],
                                                   @[@"b", @"d"],
                                                   @[@"b", @"d", @"e"]];
    RequireTestCase(CBL_View_Query);
    CBLDatabase *db = createDB();
    int i = 0;
    for (id key in testKeys)
        putDoc(db, $dict({@"_id", $sprintf(@"%d", i++)}, {@"name", key}));

    CBLView* view = [db viewNamed: @"default/names"];
    [view setMapBlock:  MAPBLOCK({
        emit(doc[@"name"], nil);
    }) reduceBlock: NULL version:@"1.0"];
    
    CBLQueryOptions options = kDefaultCBLQueryOptions;
    CBLStatus status;
    NSArray* rows = rowsToDicts([view _queryWithOptions: &options status: &status]);
    CAssertEq(status, kCBLStatusOK);
    i = 0;
    for (NSDictionary* row in rows)
        CAssertEqual(row[@"key"], testKeys[i++]);
    [db close];
}


TestCase(CBL_View_CollationRaw) {
    NSArray* testKeys = @[@0,
                                                   @(2.5),
                                                   @(10),
                                                   $false,
                                                   $null,
                                                   $true,
                                                   @[@"a"],
                                                   @[@"b"],
                                                   @[@"b", @"c"],
                                                   @[@"b", @"c", @"a"],
                                                   @[@"b", @"d"],
                                                   @[@"b", @"d", @"e"],
                                                   @" ",
                                                   @"A",
                                                   @"B",
                                                   @"_",
                                                   @"a",
                                                   @"aa",
                                                   @"b",
                                                   @"ba",
                                                   @"bb",
                                                   @"~"];
    RequireTestCase(CBL_View_Query);
    CBLDatabase *db = createDB();
    int i = 0;
    for (id key in testKeys)
        putDoc(db, $dict({@"_id", $sprintf(@"%d", i++)}, {@"name", key}));

    CBLView* view = [db viewNamed: @"default/names"];
    [view setMapBlock: MAPBLOCK({
        emit(doc[@"name"], nil);
    }) reduceBlock: NULL version:@"1.0"];
    view.collation = kCBLViewCollationRaw;
    
    CBLQueryOptions options = kDefaultCBLQueryOptions;
    CBLStatus status;
    NSArray* rows = rowsToDicts([view _queryWithOptions: &options status: &status]);
    CAssertEq(status, kCBLStatusOK);
    i = 0;
    for (NSDictionary* row in rows)
        CAssertEqual(row[@"key"], testKeys[i++]);
    [db close];
}


TestCase(CBL_View_LinkedDocs) {
    RequireTestCase(CBL_View_Query);
    CBLDatabase *db = createDB();
    NSArray* revs = putDocs(db);
    
    NSDictionary* docs[5];
    int i = 0;
    for (CBL_Revision* rev in revs) {
        docs[i++] = [db getDocumentWithID: rev.docID revisionID: rev.revID].properties;
    }

    CBLView* view = [db viewNamed: @"linkview"];
    [view setMapBlock:  MAPBLOCK({
        NSString* key = doc[@"key"];
        NSDictionary* value = nil;
        int linkedID = [doc[@"_id"] intValue] - 11111;
        if (linkedID > 0)
            value = $dict({@"_id", $sprintf(@"%d", linkedID)});
        emit(key, value);
    }) reduceBlock: NULL version: @"1"];

    CAssertEq([view updateIndex], kCBLStatusOK);
    
    // Query all rows:
    CBLQueryOptions options = kDefaultCBLQueryOptions;
    options.includeDocs = YES;
    CBLStatus status;
    NSArray* rows = rowsToDicts([view _queryWithOptions: &options status: &status]);
    NSArray* expectedRows = $array($dict({@"id",  @"55555"}, {@"key", @"five"},
                                         {@"value", $dict({@"_id", @"44444"})},
                                         {@"doc", docs[1]}),
                                   $dict({@"id",  @"44444"}, {@"key", @"four"},
                                         {@"value", $dict({@"_id", @"33333"})},
                                         {@"doc", docs[3]}),
                                   $dict({@"id",  @"11111"}, {@"key", @"one"},
                                         {@"doc", docs[2]}),
                                   $dict({@"id",  @"33333"}, {@"key", @"three"},
                                         {@"value", $dict({@"_id", @"22222"})},
                                         {@"doc", docs[0]}),
                                   $dict({@"id",  @"22222"}, {@"key", @"two"},
                                         {@"value", $dict({@"_id", @"11111"})},
                                         {@"doc", docs[2]}));
    CAssertEqual(rows, expectedRows);
    [db close];
}


TestCase(CBLView) {
    RequireTestCase(CBL_View_MapConflicts);
    RequireTestCase(CBL_View_ConflictWinner);
    RequireTestCase(CBL_View_ConflictLoser);
    RequireTestCase(CBL_View_LinkedDocs);
    RequireTestCase(CBL_View_Collation);
    RequireTestCase(CBL_View_CollationRaw);
}


#endif
