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
    
    CAssertEqual(db.allViews, $array(view));

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
        CAssert([doc objectForKey: @"_id"] != nil, @"Missing _id in %@", doc);
        CAssert([doc objectForKey: @"_rev"] != nil, @"Missing _rev in %@", doc);
        if ([doc objectForKey: @"key"])
            emit([doc objectForKey: @"key"], [doc objectForKey: @"_conflicts"]);
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
    CAssertEqual(dump, $array($dict({@"key", @"\"one\""}, {@"seq", $object(1)}),
                              $dict({@"key", @"\"three\""}, {@"seq", $object(3)}),
                              $dict({@"key", @"\"two\""}, {@"seq", $object(2)}) ));
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
    CAssertEqual(dump, $array($dict({@"key", @"\"3hree\""}, {@"seq", $object(6)}),
                              $dict({@"key", @"\"four\""}, {@"seq", $object(7)}),
                              $dict({@"key", @"\"one\""}, {@"seq", $object(1)}) ));
    
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
    TDRevision* leaf1 = [docs objectAtIndex: 1];
    
    // Create a conflict:
    NSDictionary* props = $dict({@"_id", @"44444"},
                                {@"_rev", @"1-~~~~~"},  // higher revID, will win conflict
                                {@"key", @"40ur"});
    TDRevision* leaf2 = [[[TDRevision alloc] initWithProperties: props] autorelease];
    TDStatus status = [db forceInsert: leaf2 revisionHistory: $array() source: nil];
    CAssert(status < 300);
    CAssertEqual(leaf1.docID, leaf2.docID);
    
    TDView* view = [db viewNamed: @"conflicts"];
    [view setMapBlock: ^(NSDictionary* doc, TDMapEmitBlock emit) {
        NSString* docID = [doc objectForKey: @"_id"];
        NSArray* conflicts = $cast(NSArray, [doc objectForKey: @"_conflicts"]);
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
                                    {@"seq", $object(6)}) ));
}


TestCase(TDView_ConflictWinner) {
    // If a view is re-indexed, and a document in the view has gone into conflict,
    // rows emitted by the earlier 'losing' revision shouldn't appear in the view.
    //TEMP RequireTestCase(TDView_Index);
    TDDatabase *db = createDB();
    NSArray* docs = putDocs(db);
    TDRevision* leaf1 = [docs objectAtIndex: 1];
    
    TDView* view = createView(db);
    CAssertEq([view updateIndex], kTDStatusOK);
    NSArray* dump = [view dump];
    Log(@"View dump: %@", dump);
    CAssertEqual(dump, $array($dict({@"key", @"\"five\""}, {@"seq", $object(5)}),
                              $dict({@"key", @"\"four\""}, {@"seq", $object(2)}),
                              $dict({@"key", @"\"one\""},  {@"seq", $object(3)}),
                              $dict({@"key", @"\"three\""},{@"seq", $object(4)}),
                              $dict({@"key", @"\"two\""},  {@"seq", $object(1)}) ));
    
    // Create a conflict, won by the new revision:
    NSDictionary* props = $dict({@"_id", @"44444"},
                                {@"_rev", @"1-~~~~~"},  // higher revID, will win conflict
                                {@"key", @"40ur"});
    TDRevision* leaf2 = [[[TDRevision alloc] initWithProperties: props] autorelease];
    TDStatus status = [db forceInsert: leaf2 revisionHistory: $array() source: nil];
    CAssert(status < 300);
    CAssertEqual(leaf1.docID, leaf2.docID);
    
    // Update the view -- should contain only the key from the new rev, not the old:
    CAssertEq([view updateIndex], kTDStatusOK);
    dump = [view dump];
    Log(@"View dump: %@", dump);
    CAssertEqual(dump, $array($dict({@"key", @"\"40ur\""}, {@"seq", $object(6)},
                                    {@"value", $sprintf(@"[\"%@\"]", leaf1.revID)}),
                              $dict({@"key", @"\"five\""}, {@"seq", $object(5)}),
                              $dict({@"key", @"\"one\""},  {@"seq", $object(3)}),
                              $dict({@"key", @"\"three\""},{@"seq", $object(4)}),
                              $dict({@"key", @"\"two\""},  {@"seq", $object(1)}) ));
}


TestCase(TDView_ConflictLoser) {
    // Like the ConflictWinner test, except the newer revision is the loser,
    // so it shouldn't be indexed at all. Instead, the older still-winning revision
    // should be indexed again, this time with a '_conflicts' property.
    TDDatabase *db = createDB();
    NSArray* docs = putDocs(db);
    TDRevision* leaf1 = [docs objectAtIndex: 1];
    
    TDView* view = createView(db);
    CAssertEq([view updateIndex], kTDStatusOK);
    NSArray* dump = [view dump];
    Log(@"View dump: %@", dump);
    CAssertEqual(dump, $array($dict({@"key", @"\"five\""}, {@"seq", $object(5)}),
                              $dict({@"key", @"\"four\""}, {@"seq", $object(2)}),
                              $dict({@"key", @"\"one\""},  {@"seq", $object(3)}),
                              $dict({@"key", @"\"three\""},{@"seq", $object(4)}),
                              $dict({@"key", @"\"two\""},  {@"seq", $object(1)}) ));
    
    // Create a conflict, won by the new revision:
    NSDictionary* props = $dict({@"_id", @"44444"},
                                {@"_rev", @"1-...."},  // lower revID, will lose conflict
                                {@"key", @"40ur"});
    TDRevision* leaf2 = [[[TDRevision alloc] initWithProperties: props] autorelease];
    TDStatus status = [db forceInsert: leaf2 revisionHistory: $array() source: nil];
    CAssert(status < 300);
    CAssertEqual(leaf1.docID, leaf2.docID);
    
    // Update the view -- should contain only the key from the new rev, not the old:
    CAssertEq([view updateIndex], kTDStatusOK);
    dump = [view dump];
    Log(@"View dump: %@", dump);
    CAssertEqual(dump, $array($dict({@"key", @"\"five\""}, {@"seq", $object(5)}),
                              $dict({@"key", @"\"four\""}, {@"seq", $object(2)},
                                    {@"value", @"[\"1-....\"]"}),
                              $dict({@"key", @"\"one\""},  {@"seq", $object(3)}),
                              $dict({@"key", @"\"three\""},{@"seq", $object(4)}),
                              $dict({@"key", @"\"two\""},  {@"seq", $object(1)}) ));
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
    options.keys = $array(@"two", @"four");
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
                              {@"total_rows", $object(5)},
                              {@"offset", $object(0)}));

    // Start/end key query:
    options = kDefaultTDQueryOptions;
    options.startKey = @"2";
    options.endKey = @"44444";
    query = [db getAllDocs: &options];
    expectedRows = $array(expectedRow[0], expectedRow[3], expectedRow[1]);
    CAssertEqual(query, $dict({@"rows", expectedRows},
                              {@"total_rows", $object(3)},
                              {@"offset", $object(0)}));

    // Start/end query without inclusive end:
    options.inclusiveEnd = NO;
    query = [db getAllDocs: &options];
    expectedRows = $array(expectedRow[0], expectedRow[3]);
    CAssertEqual(query, $dict({@"rows", expectedRows},
                              {@"total_rows", $object(2)},
                              {@"offset", $object(0)}));

    // Get specific documents:
    options = kDefaultTDQueryOptions;
    query = [db getDocsWithIDs: $array() options: &options];
    CAssertEqual(query, $dict({@"rows", $array()},
                              {@"total_rows", $object(0)},
                              {@"offset", $object(0)}));
    
    // Get specific documents:
    options = kDefaultTDQueryOptions;
    query = [db getDocsWithIDs: $array([expectedRow[2] objectForKey: @"id"]) options: &options];
    CAssertEqual(query, $dict({@"rows", $array(expectedRow[2])},
                              {@"total_rows", $object(1)},
                              {@"offset", $object(0)}));
}


TestCase(TDView_Reduce) {
    RequireTestCase(TDView_Query);
    TDDatabase *db = createDB();
    putDoc(db, $dict({@"_id", @"CD"},      {@"cost", $object(8.99)}));
    putDoc(db, $dict({@"_id", @"App"},     {@"cost", $object(1.95)}));
    putDoc(db, $dict({@"_id", @"Dessert"}, {@"cost", $object(6.50)}));
    
    TDView* view = [db viewNamed: @"totaler"];
    [view setMapBlock: ^(NSDictionary* doc, TDMapEmitBlock emit) {
        CAssert([doc objectForKey: @"_id"] != nil, @"Missing _id in %@", doc);
        CAssert([doc objectForKey: @"_rev"] != nil, @"Missing _rev in %@", doc);
        id cost = [doc objectForKey: @"cost"];
        if (cost)
            emit([doc objectForKey: @"_id"], cost);
    } reduceBlock: ^(NSArray* keys, NSArray* values, BOOL rereduce) {
        return [TDView totalValues: values];
    } version: @"1"];

    CAssertEq([view updateIndex], kTDStatusOK);
    NSArray* dump = [view dump];
    Log(@"View dump: %@", dump);
    CAssertEqual(dump, $array($dict({@"key", @"\"App\""}, {@"value", @"1.95"}, {@"seq", $object(2)}),
                              $dict({@"key", @"\"CD\""}, {@"value", @"8.99"}, {@"seq", $object(1)}),
                              $dict({@"key", @"\"Dessert\""}, {@"value", @"6.5"}, {@"seq", $object(3)}) ));

    TDQueryOptions options = kDefaultTDQueryOptions;
    options.reduce = YES;
    TDStatus status;
    NSArray* reduced = [view queryWithOptions: &options status: &status];
    CAssertEq(status, kTDStatusOK);
    CAssertEq(reduced.count, 1u);
    double result = [[[reduced objectAtIndex: 0] objectForKey: @"value"] doubleValue];
    CAssert(fabs(result - 17.44) < 0.001, @"Unexpected reduced value %@", reduced);
}


TestCase(TDView_Grouped) {
    RequireTestCase(TDView_Reduce);
    TDDatabase *db = createDB();
    putDoc(db, $dict({@"_id", @"1"}, {@"artist", @"Gang Of Four"}, {@"album", @"Entertainment!"},
                     {@"track", @"Ether"}, {@"time", $object(231)}));
    putDoc(db, $dict({@"_id", @"2"}, {@"artist", @"Gang Of Four"}, {@"album", @"Songs Of The Free"},
                     {@"track", @"I Love A Man In Uniform"}, {@"time", $object(248)}));
    putDoc(db, $dict({@"_id", @"3"}, {@"artist", @"Gang Of Four"}, {@"album", @"Entertainment!"},
                     {@"track", @"Natural's Not In It"}, {@"time", $object(187)}));
    putDoc(db, $dict({@"_id", @"4"}, {@"artist", @"PiL"}, {@"album", @"Metal Box"},
                     {@"track", @"Memories"}, {@"time", $object(309)}));
    putDoc(db, $dict({@"_id", @"5"}, {@"artist", @"Gang Of Four"}, {@"album", @"Entertainment!"},
                     {@"track", @"Not Great Men"}, {@"time", $object(187)}));
    
    TDView* view = [db viewNamed: @"grouper"];
    [view setMapBlock: ^(NSDictionary* doc, TDMapEmitBlock emit) {
        emit($array([doc objectForKey: @"artist"],
                    [doc objectForKey: @"album"], 
                    [doc objectForKey: @"track"]),
             [doc objectForKey: @"time"]);
    } reduceBlock:^id(NSArray *keys, NSArray *values, BOOL rereduce) {
        return [TDView totalValues: values];
    } version: @"1"];
    
    CAssertEq([view updateIndex], kTDStatusOK);

    TDQueryOptions options = kDefaultTDQueryOptions;
    options.reduce = YES;
    TDStatus status;
    NSArray* rows = [view queryWithOptions: &options status: &status];
    CAssertEq(status, kTDStatusOK);
    CAssertEqual(rows, $array($dict({@"key", $null}, {@"value", $object(1162)})));

    options.group = YES;
    rows = [view queryWithOptions: &options status: &status];
    CAssertEq(status, kTDStatusOK);
    CAssertEqual(rows, $array($dict({@"key", $array(@"Gang Of Four", @"Entertainment!",
                                                    @"Ether")},
                                    {@"value", $object(231)}),
                              $dict({@"key", $array(@"Gang Of Four", @"Entertainment!",
                                                    @"Natural's Not In It")},
                                    {@"value", $object(187)}),
                              $dict({@"key", $array(@"Gang Of Four", @"Entertainment!",
                                                    @"Not Great Men")},
                                    {@"value", $object(187)}),
                              $dict({@"key", $array(@"Gang Of Four", @"Songs Of The Free",
                                                    @"I Love A Man In Uniform")},
                                    {@"value", $object(248)}),
                              $dict({@"key", $array(@"PiL", @"Metal Box",
                                                    @"Memories")}, 
                                    {@"value", $object(309)})));

    options.groupLevel = 1;
    rows = [view queryWithOptions: &options status: &status];
    CAssertEq(status, kTDStatusOK);
    CAssertEqual(rows, $array($dict({@"key", $array(@"Gang Of Four")}, {@"value", $object(853)}),
                              $dict({@"key", $array(@"PiL")}, {@"value", $object(309)})));
    
    options.groupLevel = 2;
    rows = [view queryWithOptions: &options status: &status];
    CAssertEq(status, kTDStatusOK);
    CAssertEqual(rows, $array($dict({@"key", $array(@"Gang Of Four", @"Entertainment!")},
                                    {@"value", $object(605)}),
                              $dict({@"key", $array(@"Gang Of Four", @"Songs Of The Free")},
                                    {@"value", $object(248)}),
                              $dict({@"key", $array(@"PiL", @"Metal Box")}, 
                                    {@"value", $object(309)})));
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
         NSString *name = [doc objectForKey: @"name"];
         if (name)
             emit([name substringToIndex:1], [NSNumber numberWithInt:1]);
     } reduceBlock:^id(NSArray *keys, NSArray *values, BOOL rereduce) {
         return [NSNumber numberWithUnsignedInteger:[values count]];
     } version:@"1.0"];
   
    CAssertEq([view updateIndex], kTDStatusOK);

    TDQueryOptions options = kDefaultTDQueryOptions;
    options.groupLevel = 1;
    TDStatus status;
    NSArray* rows = [view queryWithOptions: &options status: &status];
    CAssertEq(status, kTDStatusOK);
    CAssertEqual(rows, $array($dict({@"key", @"A"}, {@"value", $object(2)}),
                              $dict({@"key", @"J"}, {@"value", $object(2)}),
                              $dict({@"key", @"N"}, {@"value", $object(1)})));
}


TestCase(TDView_Collation) {
    // Based on CouchDB's "view_collation.js" test
    NSArray* testKeys = [NSArray arrayWithObjects: $null,
                                                   $false,
                                                   $true,
                                                   $object(0),
                                                   $object(2.5),
                                                   $object(10),
                                                   @" ", @"_", @"~", 
                                                   @"a",
                                                   @"A",
                                                   @"aa",
                                                   @"b",
                                                   @"B",
                                                   @"ba",
                                                   @"bb",
                                                   $array(@"a"),
                                                   $array(@"b"),
                                                   $array(@"b", @"c"),
                                                   $array(@"b", @"c", @"a"),
                                                   $array(@"b", @"d"),
                                                   $array(@"b", @"d", @"e"), nil];
    RequireTestCase(TDView_Query);
    TDDatabase *db = createDB();
    int i = 0;
    for (id key in testKeys)
        putDoc(db, $dict({@"_id", $sprintf(@"%d", i++)}, {@"name", key}));

    TDView* view = [db viewNamed: @"default/names"];
    [view setMapBlock: ^(NSDictionary* doc, TDMapEmitBlock emit) {
        emit([doc objectForKey: @"name"], nil);
    } reduceBlock: NULL version:@"1.0"];
    
    TDQueryOptions options = kDefaultTDQueryOptions;
    TDStatus status;
    NSArray* rows = [view queryWithOptions: &options status: &status];
    CAssertEq(status, kTDStatusOK);
    i = 0;
    for (NSDictionary* row in rows)
        CAssertEqual([row objectForKey: @"key"], [testKeys objectAtIndex: i++]);
}


TestCase(TDView_CollationRaw) {
    NSArray* testKeys = [NSArray arrayWithObjects: $object(0),
                                                   $object(2.5),
                                                   $object(10),
                                                   $false,
                                                   $null,
                                                   $true,
                                                   $array(@"a"),
                                                   $array(@"b"),
                                                   $array(@"b", @"c"),
                                                   $array(@"b", @"c", @"a"),
                                                   $array(@"b", @"d"),
                                                   $array(@"b", @"d", @"e"),
                                                   @" ",
                                                   @"A",
                                                   @"B",
                                                   @"_",
                                                   @"a",
                                                   @"aa",
                                                   @"b",
                                                   @"ba",
                                                   @"bb",
                                                   @"~", nil];
    RequireTestCase(TDView_Query);
    TDDatabase *db = createDB();
    int i = 0;
    for (id key in testKeys)
        putDoc(db, $dict({@"_id", $sprintf(@"%d", i++)}, {@"name", key}));

    TDView* view = [db viewNamed: @"default/names"];
    [view setMapBlock: ^(NSDictionary* doc, TDMapEmitBlock emit) {
        emit([doc objectForKey: @"name"], nil);
    } reduceBlock: NULL version:@"1.0"];
    view.collation = kTDViewCollationRaw;
    
    TDQueryOptions options = kDefaultTDQueryOptions;
    TDStatus status;
    NSArray* rows = [view queryWithOptions: &options status: &status];
    CAssertEq(status, kTDStatusOK);
    i = 0;
    for (NSDictionary* row in rows)
        CAssertEqual([row objectForKey: @"key"], [testKeys objectAtIndex: i++]);
}


#endif
