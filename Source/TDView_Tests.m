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
#import "TDInternal.h"
#import "Test.h"


#if DEBUG

TestCase(TDView_Create) {
    RequireTestCase(TDDatabase);
    TDDatabase *db = [TDDatabase createEmptyDBAtPath: @"/tmp/TouchDB_ViewTest.touchdb"];
    
    TDView* view = [db viewNamed: @"aview"];
    CAssert(view);
    CAssertEq(view.database, db);
    CAssertEqual(view.name, @"aview");
    CAssertNull(view.mapBlock);
    
    BOOL changed = [view setMapBlock: ^(NSDictionary* doc, TDMapEmitBlock emit) { } version: @"1"];
    CAssert(changed);
    
    CAssertEqual(db.allViews, $array(view));

    changed = [view setMapBlock: ^(NSDictionary* doc, TDMapEmitBlock emit) { } version: @"1"];
    CAssert(!changed);
    
    changed = [view setMapBlock: ^(NSDictionary* doc, TDMapEmitBlock emit) { } version: @"2"];
    CAssert(changed);
    
    [db close];
}


static TDRevision* putDoc(TDDatabase* db, NSDictionary* props) {
    TDRevision* rev = [[[TDRevision alloc] initWithProperties: props] autorelease];
    TDStatus status;
    TDRevision* result = [db putRevision: rev prevRevisionID: nil status: &status];
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
        emit([doc objectForKey: @"key"], nil);
    } version: @"1"];
    return view;
}


TestCase(TDView_Index) {
    RequireTestCase(TDView_Create);
    TDDatabase *db = [TDDatabase createEmptyDBAtPath: @"/tmp/TouchDB_ViewTest.touchdb"];
    TDRevision* rev1 = putDoc(db, $dict({@"key", @"one"}));
    TDRevision* rev2 = putDoc(db, $dict({@"key", @"two"}));
    TDRevision* rev3 = putDoc(db, $dict({@"key", @"three"}));
    putDoc(db, $dict({@"clef", @"quatre"}));
    
    TDView* view = createView(db);
    CAssertEq(view.viewID, 1);
    
    CAssertEq([view updateIndex], 200);
    
    NSArray* dump = [view dump];
    Log(@"View dump: %@", dump);
    CAssertEqual(dump, $array($dict({@"key", @"\"one\""}, {@"seq", $object(1)}),
                              $dict({@"key", @"\"three\""}, {@"seq", $object(3)}),
                              $dict({@"key", @"\"two\""}, {@"seq", $object(2)}) ));
    // No-op reindex:
    CAssertEq([view updateIndex], 200);
    
    // Now add a doc and update a doc:
    TDRevision* threeUpdated = [[[TDRevision alloc] initWithDocID: rev3.docID revID: nil deleted:NO] autorelease];
    threeUpdated.properties = $dict({@"key", @"3hree"});
    int status;
    rev3 = [db putRevision: threeUpdated prevRevisionID: rev3.revID status: &status];
    CAssert(status < 300);

    TDRevision* rev4 = putDoc(db, $dict({@"key", @"four"}));
    
    TDRevision* twoDeleted = [[[TDRevision alloc] initWithDocID: rev2.docID revID: nil deleted:YES] autorelease];
    [db putRevision: twoDeleted prevRevisionID: rev2.revID status: &status];
    CAssert(status < 300);

    // Reindex again:
    CAssertEq([view updateIndex], 200);

    dump = [view dump];
    Log(@"View dump: %@", dump);
    CAssertEqual(dump, $array($dict({@"key", @"\"3hree\""}, {@"seq", $object(5)}),
                              $dict({@"key", @"\"four\""}, {@"seq", $object(6)}),
                              $dict({@"key", @"\"one\""}, {@"seq", $object(1)}) ));
    
    // Now do a real query:
    NSDictionary* query = [view queryWithOptions: NULL status: &status];
    CAssertEq(status, 200);
    CAssertEqual([query objectForKey: @"rows"], $array(
                               $dict({@"key", @"3hree"}, {@"id", rev3.docID}),
                               $dict({@"key", @"four"}, {@"id", rev4.docID}),
                               $dict({@"key", @"one"}, {@"id", rev1.docID}) ));
    CAssertEqual([query objectForKey: @"total_rows"], $object(3));
    CAssertEqual([query objectForKey: @"offset"], $object(0));
    
    [view removeIndex];
    
    [db close];
}


TestCase(TDView_Query) {
    RequireTestCase(TDView_Index);
    TDDatabase *db = [TDDatabase createEmptyDBAtPath: @"/tmp/TouchDB_ViewTest.touchdb"];
    putDocs(db);
    TDView* view = createView(db);
    CAssertEq([view updateIndex], 200);
    
    // Query all rows:
    TDQueryOptions options = kDefaultTDQueryOptions;
    TDStatus status;
    NSDictionary* query = [view queryWithOptions: &options status: &status];
    NSArray* expectedRows = $array($dict({@"id",  @"55555"}, {@"key", @"five"}),
                                   $dict({@"id",  @"44444"}, {@"key", @"four"}),
                                   $dict({@"id",  @"11111"}, {@"key", @"one"}),
                                   $dict({@"id",  @"33333"}, {@"key", @"three"}),
                                   $dict({@"id",  @"22222"}, {@"key", @"two"}));
    CAssertEqual(query, $dict({@"rows", expectedRows},
                              {@"total_rows", $object(5)},
                              {@"offset", $object(0)}));

    // Start/end key query:
    options = kDefaultTDQueryOptions;
    options.startKey = @"a";
    options.endKey = @"one";
    query = [view queryWithOptions: &options status: &status];
    expectedRows = $array($dict({@"id",  @"55555"}, {@"key", @"five"}),
                          $dict({@"id",  @"44444"}, {@"key", @"four"}),
                          $dict({@"id",  @"11111"}, {@"key", @"one"}));
    CAssertEqual(query, $dict({@"rows", expectedRows},
                              {@"total_rows", $object(3)},
                              {@"offset", $object(0)}));

    // Start/end query without inclusive end:
    options.inclusiveEnd = NO;
    query = [view queryWithOptions: &options status: &status];
    expectedRows = $array($dict({@"id",  @"55555"}, {@"key", @"five"}),
                          $dict({@"id",  @"44444"}, {@"key", @"four"}));
    CAssertEqual(query, $dict({@"rows", expectedRows},
                              {@"total_rows", $object(2)},
                              {@"offset", $object(0)}));

    // Reversed:
    options.descending = YES;
    options.startKey = @"o";
    options.endKey = @"five";
    options.inclusiveEnd = YES;
    query = [view queryWithOptions: &options status: &status];
    expectedRows = $array($dict({@"id",  @"44444"}, {@"key", @"four"}),
                          $dict({@"id",  @"55555"}, {@"key", @"five"}));
    CAssertEqual(query, $dict({@"rows", expectedRows},
                              {@"total_rows", $object(2)},
                              {@"offset", $object(0)}));

    // Reversed, no inclusive end:
    options.inclusiveEnd = NO;
    query = [view queryWithOptions: &options status: &status];
    expectedRows = $array($dict({@"id",  @"44444"}, {@"key", @"four"}));
    CAssertEqual(query, $dict({@"rows", expectedRows},
                              {@"total_rows", $object(1)},
                              {@"offset", $object(0)}));
}    


TestCase(TDView_AllDocsQuery) {
    TDDatabase *db = [TDDatabase createEmptyDBAtPath: @"/tmp/TouchDB_ViewTest.touchdb"];
    NSArray* docs = putDocs(db);
    NSDictionary* expectedRow[docs.count];
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
}    

#endif
