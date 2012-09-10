//
//  TDView_Tests.m
//  TouchDB
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

#import "TDView.h"
#import "TDDatabase+Insertion.h"
#import "TDInternal.h"
#import "Test.h"


#if DEBUG

static TDDatabase* createDB(void) {
    return [TDDatabase createEmptyDBAtPath: [NSTemporaryDirectory() stringByAppendingPathComponent: @"TouchDB_ViewTest.touchdb"]];
}

TestCase(TDView_Create) {
    RequireTestCase(TDDatabase);
    TDDatabase *db = createDB();
    
    CAssertNil([db existingViewNamed: @"aview"]);
    
    TDView* view = [db viewNamed: @"aview"];
    CAssert(view);
    CAssertEq(view.database, db);
    CAssertEqual(view.name, @"aview");
    CAssertNull(view.mapBlock);
    CAssertEq([db existingViewNamed: @"aview"], view);

    
    BOOL changed = [view setMapBlock: ^(NSDictionary* doc, TDMapEmitBlock emit) { }
                         reduceBlock: NULL version: @"1"];
    CAssert(changed);
    
    CAssertEqual(db.allViews, @[view]);

    changed = [view setMapBlock: ^(NSDictionary* doc, TDMapEmitBlock emit) { }
                    reduceBlock: NULL version: @"1"];
    CAssert(!changed);
    
    changed = [view setMapBlock: ^(NSDictionary* doc, TDMapEmitBlock emit) { }
                    reduceBlock: NULL version: @"2"];
    CAssert(changed);
    
    [db close];
}


static TDRevision* putDoc(TDDatabase* db, NSDictionary* props) {
    TDRevision* rev = [[[TDRevision alloc] initWithProperties: props] autorelease];
    TDStatus status;
    TDRevision* result = [db putRevision: rev prevRevisionID: nil allowConflict: NO status: &status];
    CAssert(status < 300);
    return result;
}


static NSArray* putDocs(TDDatabase* db) {
    NSMutableArray* docs = $marray();
    [docs addObject: putDoc(db, $dict({@"_id", @"22222"}, {@"key", @"two"}))];
    [docs addObject: putDoc(db, $dict({@"_id", @"44444"}, {@"key", @"four"}))];
    [docs addObject: putDoc(db, $dict({@"_id", @"11111"}, {@"key", @"one"}))];
    [docs addObject: putDoc(db, $dict({@"_id", @"33333"}, {@"key", @"three"}))];
    [docs addObject: putDoc(db, $dict({@"_id", @"55555"}, {@"key", @"five"}))];
    return docs;
}


static TDView* createView(TDDatabase* db) {
    TDView* view = [db viewNamed: @"aview"];
    [view setMapBlock: ^(NSDictionary* doc, TDMapEmitBlock emit) {
        CAssert(doc[@"_id"] != nil, @"Missing _id in %@", doc);
        CAssert(doc[@"_rev"] != nil, @"Missing _rev in %@", doc);
        if (doc[@"key"])
            emit(doc[@"key"], doc[@"_conflicts"]);
    } reduceBlock: NULL version: @"1"];
    return view;
}


TestCase(TDView_Index) {
    RequireTestCase(TDView_Create);
    TDDatabase *db = createDB();
    TDRevision* rev1 = putDoc(db, $dict({@"key", @"one"}));
    TDRevision* rev2 = putDoc(db, $dict({@"key", @"two"}));
    TDRevision* rev3 = putDoc(db, $dict({@"key", @"three"}));
    putDoc(db, $dict({@"_id", @"_design/foo"}));
    putDoc(db, $dict({@"clef", @"quatre"}));
    
    TDView* view = createView(db);
    CAssertEq(view.viewID, 1);
    
    CAssert(view.stale);
    CAssertEq([view updateIndex], kTDStatusOK);
    
    NSArray* dump = [view dump];
    Log(@"View dump: %@", dump);
    CAssertEqual(dump, $array($dict({@"key", @"\"one\""}, {@"seq", @1}),
                              $dict({@"key", @"\"three\""}, {@"seq", @3}),
                              $dict({@"key", @"\"two\""}, {@"seq", @2}) ));
    // No-op reindex:
    CAssert(!view.stale);
    CAssertEq([view updateIndex], kTDStatusNotModified);
    
    // Now add a doc and update a doc:
    TDRevision* threeUpdated = [[[TDRevision alloc] initWithDocID: rev3.docID revID: nil deleted:NO] autorelease];
    threeUpdated.properties = $dict({@"key", @"3hree"});
    TDStatus status;
    rev3 = [db putRevision: threeUpdated prevRevisionID: rev3.revID allowConflict: NO status: &status];
    CAssert(status < 300);

    TDRevision* rev4 = putDoc(db, $dict({@"key", @"four"}));
    
    TDRevision* twoDeleted = [[[TDRevision alloc] initWithDocID: rev2.docID revID: nil deleted:YES] autorelease];
    [db putRevision: twoDeleted prevRevisionID: rev2.revID allowConflict: NO status: &status];
    CAssert(status < 300);

    // Reindex again:
    CAssert(view.stale);
    CAssertEq([view updateIndex], kTDStatusOK);

    dump = [view dump];
    Log(@"View dump: %@", dump);
    CAssertEqual(dump, $array($dict({@"key", @"\"3hree\""}, {@"seq", @6}),
                              $dict({@"key", @"\"four\""}, {@"seq", @7}),
                              $dict({@"key", @"\"one\""}, {@"seq", @1}) ));
    
    // Now do a real query:
    NSArray* rows = [view queryWithOptions: NULL status: &status];
    CAssertEq(status, kTDStatusOK);
    CAssertEqual(rows, $array( $dict({@"key", @"3hree"}, {@"id", rev3.docID}),
                               $dict({@"key", @"four"}, {@"id", rev4.docID}),
                               $dict({@"key", @"one"}, {@"id", rev1.docID}) ));
    
    [view removeIndex];
    
    [db close];
}


TestCase(TDView_MapConflicts) {
    RequireTestCase(TDView_Index);
    TDDatabase *db = createDB();
    NSArray* docs = putDocs(db);
    TDRevision* leaf1 = docs[1];
    
    // Create a conflict:
    NSDictionary* props = $dict({@"_id", @"44444"},
                                {@"_rev", @"1-~~~~~"},  // higher revID, will win conflict
                                {@"key", @"40ur"});
    TDRevision* leaf2 = [[[TDRevision alloc] initWithProperties: props] autorelease];
    TDStatus status = [db forceInsert: leaf2 revisionHistory: @[] source: nil];
    CAssert(status < 300);
    CAssertEqual(leaf1.docID, leaf2.docID);
    
    TDView* view = [db viewNamed: @"conflicts"];
    [view setMapBlock: ^(NSDictionary* doc, TDMapEmitBlock emit) {
        NSString* docID = doc[@"_id"];
        NSArray* conflicts = $cast(NSArray, doc[@"_conflicts"]);
        if (conflicts) {
            Log(@"Doc %@, _conflicts = %@", docID, conflicts);
            emit(docID, conflicts);
        }
    } reduceBlock: NULL version: @"1"];
    
    CAssertEq([view updateIndex], kTDStatusOK);
    NSArray* dump = [view dump];
    Log(@"View dump: %@", dump);
    CAssertEqual(dump, $array($dict({@"key", @"\"44444\""},
                                    {@"value", $sprintf(@"[\"%@\"]", leaf1.revID)},
                                    {@"seq", @6}) ));
}


TestCase(TDView_ConflictWinner) {
    // If a view is re-indexed, and a document in the view has gone into conflict,
    // rows emitted by the earlier 'losing' revision shouldn't appear in the view.
    RequireTestCase(TDView_Index);
    TDDatabase *db = createDB();
    NSArray* docs = putDocs(db);
    TDRevision* leaf1 = docs[1];
    
    TDView* view = createView(db);
    CAssertEq([view updateIndex], kTDStatusOK);
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
    TDRevision* leaf2 = [[[TDRevision alloc] initWithProperties: props] autorelease];
    TDStatus status = [db forceInsert: leaf2 revisionHistory: @[] source: nil];
    CAssert(status < 300);
    CAssertEqual(leaf1.docID, leaf2.docID);
    
    // Update the view -- should contain only the key from the new rev, not the old:
    CAssertEq([view updateIndex], kTDStatusOK);
    dump = [view dump];
    Log(@"View dump: %@", dump);
    CAssertEqual(dump, $array($dict({@"key", @"\"40ur\""}, {@"seq", @6},
                                    {@"value", $sprintf(@"[\"%@\"]", leaf1.revID)}),
                              $dict({@"key", @"\"five\""}, {@"seq", @5}),
                              $dict({@"key", @"\"one\""},  {@"seq", @3}),
                              $dict({@"key", @"\"three\""},{@"seq", @4}),
                              $dict({@"key", @"\"two\""},  {@"seq", @1}) ));
}


TestCase(TDView_ConflictLoser) {
    // Like the ConflictWinner test, except the newer revision is the loser,
    // so it shouldn't be indexed at all. Instead, the older still-winning revision
    // should be indexed again, this time with a '_conflicts' property.
    TDDatabase *db = createDB();
    NSArray* docs = putDocs(db);
    TDRevision* leaf1 = docs[1];
    
    TDView* view = createView(db);
    CAssertEq([view updateIndex], kTDStatusOK);
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
    TDRevision* leaf2 = [[[TDRevision alloc] initWithProperties: props] autorelease];
    TDStatus status = [db forceInsert: leaf2 revisionHistory: @[] source: nil];
    CAssert(status < 300);
    CAssertEqual(leaf1.docID, leaf2.docID);
    
    // Update the view -- should contain only the key from the new rev, not the old:
    CAssertEq([view updateIndex], kTDStatusOK);
    dump = [view dump];
    Log(@"View dump: %@", dump);
    CAssertEqual(dump, $array($dict({@"key", @"\"five\""}, {@"seq", @5}),
                              $dict({@"key", @"\"four\""}, {@"seq", @2},
                                    {@"value", @"[\"1-....\"]"}),
                              $dict({@"key", @"\"one\""},  {@"seq", @3}),
                              $dict({@"key", @"\"three\""},{@"seq", @4}),
                              $dict({@"key", @"\"two\""},  {@"seq", @1}) ));
}


TestCase(TDView_Query) {
    RequireTestCase(TDView_Index);
    TDDatabase *db = createDB();
    putDocs(db);
    TDView* view = createView(db);
    CAssertEq([view updateIndex], kTDStatusOK);
    
    // Query all rows:
    TDQueryOptions options = kDefaultTDQueryOptions;
    TDStatus status;
    NSArray* rows = [view queryWithOptions: &options status: &status];
    NSArray* expectedRows = $array($dict({@"id",  @"55555"}, {@"key", @"five"}),
                                   $dict({@"id",  @"44444"}, {@"key", @"four"}),
                                   $dict({@"id",  @"11111"}, {@"key", @"one"}),
                                   $dict({@"id",  @"33333"}, {@"key", @"three"}),
                                   $dict({@"id",  @"22222"}, {@"key", @"two"}));
    CAssertEqual(rows, expectedRows);

    // Start/end key query:
    options = kDefaultTDQueryOptions;
    options.startKey = @"a";
    options.endKey = @"one";
    rows = [view queryWithOptions: &options status: &status];
    expectedRows = $array($dict({@"id",  @"55555"}, {@"key", @"five"}),
                          $dict({@"id",  @"44444"}, {@"key", @"four"}),
                          $dict({@"id",  @"11111"}, {@"key", @"one"}));
    CAssertEqual(rows, expectedRows);

    // Start/end query without inclusive end:
    options.inclusiveEnd = NO;
    rows = [view queryWithOptions: &options status: &status];
    expectedRows = $array($dict({@"id",  @"55555"}, {@"key", @"five"}),
                          $dict({@"id",  @"44444"}, {@"key", @"four"}));
    CAssertEqual(rows, expectedRows);

    // Reversed:
    options.descending = YES;
    options.startKey = @"o";
    options.endKey = @"five";
    options.inclusiveEnd = YES;
    rows = [view queryWithOptions: &options status: &status];
    expectedRows = $array($dict({@"id",  @"44444"}, {@"key", @"four"}),
                          $dict({@"id",  @"55555"}, {@"key", @"five"}));
    CAssertEqual(rows, expectedRows);

    // Reversed, no inclusive end:
    options.inclusiveEnd = NO;
    rows = [view queryWithOptions: &options status: &status];
    expectedRows = $array($dict({@"id",  @"44444"}, {@"key", @"four"}));
    CAssertEqual(rows, expectedRows);
    
    // Specific keys:
    options = kDefaultTDQueryOptions;
    options.keys = @[@"two", @"four"];
    rows = [view queryWithOptions: &options status: &status];
    expectedRows = $array($dict({@"id",  @"44444"}, {@"key", @"four"}),
                          $dict({@"id",  @"22222"}, {@"key", @"two"}));
    CAssertEqual(rows, expectedRows);
}


TestCase(TDView_AllDocsQuery) {
    TDDatabase *db = createDB();
    NSArray* docs = putDocs(db);
    NSDictionary* expectedRow[docs.count];
    memset(&expectedRow, 0, sizeof(expectedRow));
    int i = 0;
    for (TDRevision* rev in docs) {
        expectedRow[i++] = $dict({@"id",  rev.docID},
                                 {@"key", rev.docID},
                                 {@"value", $dict({@"rev", rev.revID})});
    }
    
    // Query all rows:
    TDQueryOptions options = kDefaultTDQueryOptions;
    NSDictionary* query = [db getAllDocs: &options];
    NSArray* expectedRows = $array(expectedRow[2], expectedRow[0], expectedRow[3], expectedRow[1],
                                   expectedRow[4]);
    CAssertEqual(query, $dict({@"rows", expectedRows},
                              {@"total_rows", @5},
                              {@"offset", @0}));

    // Start/end key query:
    options = kDefaultTDQueryOptions;
    options.startKey = @"2";
    options.endKey = @"44444";
    query = [db getAllDocs: &options];
    expectedRows = @[expectedRow[0], expectedRow[3], expectedRow[1]];
    CAssertEqual(query, $dict({@"rows", expectedRows},
                              {@"total_rows", @3},
                              {@"offset", @0}));

    // Start/end query without inclusive end:
    options.inclusiveEnd = NO;
    query = [db getAllDocs: &options];
    expectedRows = @[expectedRow[0], expectedRow[3]];
    CAssertEqual(query, $dict({@"rows", expectedRows},
                              {@"total_rows", @2},
                              {@"offset", @0}));

    // Get zero specific documents:
    options = kDefaultTDQueryOptions;
    query = [db getDocsWithIDs: @[] options: &options];
    CAssertEqual(query, $dict({@"rows", @[]},
                              {@"total_rows", @0},
                              {@"offset", @0}));
    
    // Get specific documents:
    options = kDefaultTDQueryOptions;
    query = [db getDocsWithIDs: @[expectedRow[2][@"id"], expectedRow[3][@"id"]] options: &options];
    CAssertEqual(query, $dict({@"rows", @[expectedRow[2], expectedRow[3]]},
                              {@"total_rows", @2},
                              {@"offset", @0}));
    // Make sure the order reflects the order of the input array:
    query = [db getDocsWithIDs: @[expectedRow[3][@"id"], expectedRow[2][@"id"]] options: &options];
    CAssertEqual(query, $dict({@"rows", @[expectedRow[3], expectedRow[2]]},
                              {@"total_rows", @2},
                              {@"offset", @0}));

    // Delete a document:
    TDRevision* del = docs[0];
    del = [[[TDRevision alloc] initWithDocID: del.docID revID: del.revID deleted: YES] autorelease];
    TDStatus status;
    del = [db putRevision: del prevRevisionID: del.revID allowConflict: NO status: &status];
    CAssertEq(status, kTDStatusOK);

    // Get deleted doc, and one bogus one:
    options = kDefaultTDQueryOptions;
    query = [db getDocsWithIDs: @[@"BOGUS", expectedRow[0][@"id"]] options: &options];
    CAssertEqual(query, $dict({@"rows", @[$dict({@"key",  @"BOGUS"},
                                                {@"error", @"not_found"}),
                                          $dict({@"id",  del.docID},
                                                {@"key", del.docID},
                                                {@"value", $dict({@"rev", del.revID},
                                                                 {@"deleted", $true})}) ]},
                              {@"total_rows", @2},
                              {@"offset", @0}));
}


TestCase(TDView_Reduce) {
    RequireTestCase(TDView_Query);
    TDDatabase *db = createDB();
    putDoc(db, $dict({@"_id", @"CD"},      {@"cost", @(8.99)}));
    putDoc(db, $dict({@"_id", @"App"},     {@"cost", @(1.95)}));
    putDoc(db, $dict({@"_id", @"Dessert"}, {@"cost", @(6.50)}));
    
    TDView* view = [db viewNamed: @"totaler"];
    [view setMapBlock: ^(NSDictionary* doc, TDMapEmitBlock emit) {
        CAssert(doc[@"_id"] != nil, @"Missing _id in %@", doc);
        CAssert(doc[@"_rev"] != nil, @"Missing _rev in %@", doc);
        id cost = doc[@"cost"];
        if (cost)
            emit(doc[@"_id"], cost);
    } reduceBlock: ^(NSArray* keys, NSArray* values, BOOL rereduce) {
        return [TDView totalValues: values];
    } version: @"1"];

    CAssertEq([view updateIndex], kTDStatusOK);
    NSArray* dump = [view dump];
    Log(@"View dump: %@", dump);
    CAssertEqual(dump, $array($dict({@"key", @"\"App\""}, {@"value", @"1.95"}, {@"seq", @2}),
                              $dict({@"key", @"\"CD\""}, {@"value", @"8.99"}, {@"seq", @1}),
                              $dict({@"key", @"\"Dessert\""}, {@"value", @"6.5"}, {@"seq", @3}) ));

    TDQueryOptions options = kDefaultTDQueryOptions;
    options.reduce = YES;
    TDStatus status;
    NSArray* reduced = [view queryWithOptions: &options status: &status];
    CAssertEq(status, kTDStatusOK);
    CAssertEq(reduced.count, 1u);
    double result = [reduced[0][@"value"] doubleValue];
    CAssert(fabs(result - 17.44) < 0.001, @"Unexpected reduced value %@", reduced);
}


TestCase(TDView_Grouped) {
    RequireTestCase(TDView_Reduce);
    TDDatabase *db = createDB();
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
    
    TDView* view = [db viewNamed: @"grouper"];
    [view setMapBlock: ^(NSDictionary* doc, TDMapEmitBlock emit) {
        emit($array(doc[@"artist"],
                    doc[@"album"], 
                    doc[@"track"]),
             doc[@"time"]);
    } reduceBlock:^id(NSArray *keys, NSArray *values, BOOL rereduce) {
        return [TDView totalValues: values];
    } version: @"1"];
    
    CAssertEq([view updateIndex], kTDStatusOK);

    TDQueryOptions options = kDefaultTDQueryOptions;
    options.reduce = YES;
    TDStatus status;
    NSArray* rows = [view queryWithOptions: &options status: &status];
    CAssertEq(status, kTDStatusOK);
    CAssertEqual(rows, $array($dict({@"key", $null}, {@"value", @(1162)})));

    options.group = YES;
    rows = [view queryWithOptions: &options status: &status];
    CAssertEq(status, kTDStatusOK);
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
    rows = [view queryWithOptions: &options status: &status];
    CAssertEq(status, kTDStatusOK);
    CAssertEqual(rows, $array($dict({@"key", @[@"Gang Of Four"]}, {@"value", @(853)}),
                              $dict({@"key", @[@"PiL"]}, {@"value", @(309)})));
    
    options.groupLevel = 2;
    rows = [view queryWithOptions: &options status: &status];
    CAssertEq(status, kTDStatusOK);
    CAssertEqual(rows, $array($dict({@"key", @[@"Gang Of Four", @"Entertainment!"]},
                                    {@"value", @(605)}),
                              $dict({@"key", @[@"Gang Of Four", @"Songs Of The Free"]},
                                    {@"value", @(248)}),
                              $dict({@"key", @[@"PiL", @"Metal Box"]}, 
                                    {@"value", @(309)})));
}


TestCase(TDView_GroupedStrings) {
    RequireTestCase(TDView_Grouped);
    TDDatabase *db = createDB();
    putDoc(db, $dict({@"name", @"Alice"}));
    putDoc(db, $dict({@"name", @"Albert"}));
    putDoc(db, $dict({@"name", @"Naomi"}));
    putDoc(db, $dict({@"name", @"Jens"}));
    putDoc(db, $dict({@"name", @"Jed"}));
    
    TDView* view = [db viewNamed: @"default/names"];
    [view setMapBlock: ^(NSDictionary* doc, TDMapEmitBlock emit) {
         NSString *name = doc[@"name"];
         if (name)
             emit([name substringToIndex:1], @1);
     } reduceBlock:^id(NSArray *keys, NSArray *values, BOOL rereduce) {
         return @([values count]);
     } version:@"1.0"];
   
    CAssertEq([view updateIndex], kTDStatusOK);

    TDQueryOptions options = kDefaultTDQueryOptions;
    options.groupLevel = 1;
    TDStatus status;
    NSArray* rows = [view queryWithOptions: &options status: &status];
    CAssertEq(status, kTDStatusOK);
    CAssertEqual(rows, $array($dict({@"key", @"A"}, {@"value", @2}),
                              $dict({@"key", @"J"}, {@"value", @2}),
                              $dict({@"key", @"N"}, {@"value", @1})));
}


TestCase(TDView_Collation) {
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
    RequireTestCase(TDView_Query);
    TDDatabase *db = createDB();
    int i = 0;
    for (id key in testKeys)
        putDoc(db, $dict({@"_id", $sprintf(@"%d", i++)}, {@"name", key}));

    TDView* view = [db viewNamed: @"default/names"];
    [view setMapBlock: ^(NSDictionary* doc, TDMapEmitBlock emit) {
        emit(doc[@"name"], nil);
    } reduceBlock: NULL version:@"1.0"];
    
    TDQueryOptions options = kDefaultTDQueryOptions;
    TDStatus status;
    NSArray* rows = [view queryWithOptions: &options status: &status];
    CAssertEq(status, kTDStatusOK);
    i = 0;
    for (NSDictionary* row in rows)
        CAssertEqual(row[@"key"], testKeys[i++]);
}


TestCase(TDView_CollationRaw) {
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
    RequireTestCase(TDView_Query);
    TDDatabase *db = createDB();
    int i = 0;
    for (id key in testKeys)
        putDoc(db, $dict({@"_id", $sprintf(@"%d", i++)}, {@"name", key}));

    TDView* view = [db viewNamed: @"default/names"];
    [view setMapBlock: ^(NSDictionary* doc, TDMapEmitBlock emit) {
        emit(doc[@"name"], nil);
    } reduceBlock: NULL version:@"1.0"];
    view.collation = kTDViewCollationRaw;
    
    TDQueryOptions options = kDefaultTDQueryOptions;
    TDStatus status;
    NSArray* rows = [view queryWithOptions: &options status: &status];
    CAssertEq(status, kTDStatusOK);
    i = 0;
    for (NSDictionary* row in rows)
        CAssertEqual(row[@"key"], testKeys[i++]);
}


TestCase(TDView_LinkedDocs) {
    RequireTestCase(TDView_Query);
    TDDatabase *db = createDB();
    NSArray* revs = putDocs(db);
    
    NSDictionary* docs[5];
    int i = 0;
    for (TDRevision* rev in revs) {
        docs[i++] = [db getDocumentWithID: rev.docID revisionID: rev.revID].properties;
    }

    TDView* view = [db viewNamed: @"linkview"];
    [view setMapBlock: ^(NSDictionary* doc, TDMapEmitBlock emit) {
        NSString* key = doc[@"key"];
        NSDictionary* value = nil;
        int linkedID = [doc[@"_id"] intValue] - 11111;
        if (linkedID > 0)
            value = $dict({@"_id", $sprintf(@"%d", linkedID)});
        emit(key, value);
    } reduceBlock: NULL version: @"1"];

    CAssertEq([view updateIndex], kTDStatusOK);
    
    // Query all rows:
    TDQueryOptions options = kDefaultTDQueryOptions;
    options.includeDocs = YES;
    TDStatus status;
    NSArray* rows = [view queryWithOptions: &options status: &status];
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
    
}


#endif
