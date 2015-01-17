//
//  ViewInternal_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/22/14.
//
//

#import "CBLTestCase.h"
#import "CouchbaseLitePrivate.h"
#import "CBLView+Internal.h"
#import "CBLQuery+Geo.h"
#import "CBLDatabase+Insertion.h"
#import "CBLInternal.h"


@interface ViewInternal_Tests : CBLTestCaseWithDB
@end


@implementation ViewInternal_Tests


- (void) test_Create {
    RequireTestCase(CBLDatabase);

    AssertNil([db existingViewNamed: @"aview"]);
    
    CBLView* view = [db viewNamed: @"aview"];
    Assert(view);
    AssertEqual(view.name, @"aview");
    Assert(view.mapBlock == nil);
    AssertEq([db existingViewNamed: @"aview"], view);

    
    BOOL changed = [view setMapBlock: MAPBLOCK({})
                         reduceBlock: NULL version: @"1"];
    Assert(changed);
    
    AssertEqual(db.allViews, @[view]);

    changed = [view setMapBlock: MAPBLOCK({})
                    reduceBlock: NULL version: @"1"];
    Assert(!changed);
    
    changed = [view setMapBlock: MAPBLOCK({})
                    reduceBlock: NULL version: @"2"];
    Assert(changed);
}


- (CBL_Revision*) putDoc: (NSDictionary*)props {
    CBL_Revision* rev = [[CBL_Revision alloc] initWithProperties: props];
    CBLStatus status;
    CBL_Revision* result = [db putRevision: rev prevRevisionID: nil allowConflict: NO status: &status];
    Assert(status < 300);
    return result;
}


- (NSArray*) putDocs {
    NSMutableArray* docs = $marray();
    [docs addObject: [self putDoc: $dict({@"_id", @"22222"}, {@"key", @"two"})]];
    [docs addObject: [self putDoc: $dict({@"_id", @"44444"}, {@"key", @"four"})]];
    [docs addObject: [self putDoc: $dict({@"_id", @"11111"}, {@"key", @"one"})]];
    [docs addObject: [self putDoc: $dict({@"_id", @"33333"}, {@"key", @"three"})]];
    [docs addObject: [self putDoc: $dict({@"_id", @"55555"}, {@"key", @"five"})]];
    return docs;
}

static NSDictionary* mkGeoPoint(double x, double y) {
    return CBLGeoPointToJSON((CBLGeoPoint){x,y});
}

static NSDictionary* mkGeoRect(double x0, double y0, double x1, double y1) {
    return CBLGeoRectToJSON((CBLGeoRect){{x0,y0}, {x1,y1}});
}

- (NSArray*) putGeoDocs {
    NSMutableArray* docs = $marray();
    [docs addObject: [self putDoc: $dict({@"_id", @"22222"}, {@"key", @"two"})]];
    [docs addObject: [self putDoc: $dict({@"_id", @"44444"}, {@"key", @"four"})]];
    [docs addObject: [self putDoc: $dict({@"_id", @"11111"}, {@"key", @"one"})]];
    [docs addObject: [self putDoc: $dict({@"_id", @"33333"}, {@"key", @"three"})]];
    [docs addObject: [self putDoc: $dict({@"_id", @"55555"}, {@"key", @"five"})]];
    [docs addObject: [self putDoc: $dict({@"_id", @"pdx"},   {@"key", @"Portland"},
                                      {@"geoJSON", mkGeoPoint(-122.68, 45.52)})]];
    [docs addObject: [self putDoc: $dict({@"_id", @"aus"},   {@"key", @"Austin"},
                                      {@"geoJSON", mkGeoPoint(-97.75, 30.25)})]];
    [docs addObject: [self putDoc: $dict({@"_id", @"mv"},    {@"key", @"Mountain View"},
                                      {@"geoJSON", mkGeoPoint(-122.08, 37.39)})]];
    [docs addObject: [self putDoc: $dict({@"_id", @"hkg"}, {@"geoJSON", mkGeoPoint(-113.91, 45.52)})]];
    [docs addObject: [self putDoc: $dict({@"_id", @"diy"}, {@"geoJSON", mkGeoPoint(40.12, 37.53)})]];
    [docs addObject: [self putDoc: $dict({@"_id", @"snc"}, {@"geoJSON", mkGeoPoint(-2.205, -80.98)})]];

    [docs addObject: [self putDoc: $dict({@"_id", @"xxx"}, {@"geoJSON",
                                        mkGeoRect(-115,-10, -90, 12)})]];
    return docs;
}


- (CBLView*) createViewNamed: (NSString*)name {
    CBLView* view = [db viewNamed: name];
    [view setMapBlock: MAPBLOCK({
        Assert(doc[@"_id"] != nil, @"Missing _id in %@", doc);
        Assert(doc[@"_rev"] != nil, @"Missing _rev in %@", doc);
        Assert([doc[@"_local_seq"] isKindOfClass: [NSNumber class]], @"Invalid _local_seq in %@", doc);
        if (doc[@"key"])
            emit(doc[@"key"], nil);
        if (doc[@"geoJSON"])
            emit(CBLGeoJSONKey(doc[@"geoJSON"]), nil);
    }) reduceBlock: NULL version: @"1"];
    return view;
}

- (CBLView*) createView {
    return [self createViewNamed: @"aview"];
}


static NSArray* rowsToDicts(NSArray* rows) {
    return [rows my_map:^(CBLQueryRow* row) {return row.asJSONDictionary;}];
}


- (void) test_Index {
    RequireTestCase(Create);
    CBL_Revision* rev1 = [self putDoc: $dict({@"key", @"one"})];
    CBL_Revision* rev2 = [self putDoc: $dict({@"key", @"two"})];
    CBL_Revision* rev3 = [self putDoc: $dict({@"key", @"three"})];
    [self putDoc: $dict({@"_id", @"_design/foo"})];
    [self putDoc: $dict({@"clef", @"quatre"})];
    
    CBLView* view = [self createView];
    AssertEq(view.viewID, 1);
    
    Assert(view.stale);
    AssertEq([view updateIndex], kCBLStatusOK);
    
    NSArray* dump = [view dump];
    Log(@"View dump: %@", dump);
    AssertEqual(dump, $array($dict({@"key", @"\"one\""}, {@"seq", @1}),
                              $dict({@"key", @"\"three\""}, {@"seq", @3}),
                              $dict({@"key", @"\"two\""}, {@"seq", @2}) ));
    // No-op reindex:
    Assert(!view.stale);
    AssertEq([view updateIndex], kCBLStatusNotModified);
    
    // Now add a doc and update a doc:
    CBL_MutableRevision* threeUpdated = [[CBL_MutableRevision alloc] initWithDocID: rev3.docID revID: nil deleted:NO];
    threeUpdated.properties = $dict({@"key", @"3hree"});
    CBLStatus status;
    rev3 = [db putRevision: threeUpdated prevRevisionID: rev3.revID allowConflict: NO status: &status];
    Assert(status < 300);

    CBL_Revision* rev4 = [self putDoc: $dict({@"key", @"four"})];
    
    CBL_Revision* twoDeleted = [[CBL_Revision alloc] initWithDocID: rev2.docID revID: nil deleted:YES];
    [db putRevision: twoDeleted prevRevisionID: rev2.revID allowConflict: NO status: &status];
    Assert(status < 300);

    // Reindex again:
    Assert(view.stale);
    AssertEq([view updateIndex], kCBLStatusOK);

    dump = [view dump];
    Log(@"View dump: %@", dump);
    AssertEqual(dump, $array($dict({@"key", @"\"3hree\""}, {@"seq", @6}),
                              $dict({@"key", @"\"four\""}, {@"seq", @7}),
                              $dict({@"key", @"\"one\""}, {@"seq", @1}) ));
    
    // Now do a real query:
    NSArray* rows = rowsToDicts([view _queryWithOptions: NULL status: &status]);
    AssertEq(status, kCBLStatusOK);
    AssertEqual(rows, $array( $dict({@"key", @"3hree"}, {@"id", rev3.docID}),
                               $dict({@"key", @"four"}, {@"id", rev4.docID}),
                               $dict({@"key", @"one"}, {@"id", rev1.docID}) ));
    
    [view deleteIndex];
}


- (void) test_IndexMultiple {
    RequireTestCase(Index);

    CBLView* v1 = [self createViewNamed: @"agroup/view1"];
    CBLView* v2 = [self createViewNamed: @"other/view2"];
    CBLView* v3 = [self createViewNamed: @"other/view3"];
    CBLView* vX = [self createViewNamed: @"other/viewX"];
    CBLView* v4 = [self createViewNamed: @"view4"];
    CBLView* v5 = [self createViewNamed: @"view5"];

    [vX forgetMapBlock]; // To reproduce #438

    AssertEqual(v1.viewsInGroup, (@[v1]));
    AssertEqual(v2.viewsInGroup, (@[v2, v3, vX]));
    AssertEqual(v3.viewsInGroup, (@[v2, v3, vX]));
    AssertEqual(vX.viewsInGroup, (@[v2, v3, vX]));
    AssertEqual(v4.viewsInGroup, (@[v4])); // because GROUP_VIEWS_BY_DEFAULT isn't enabled
    AssertEqual(v5.viewsInGroup, (@[v5]));

    const int kNDocs = 10;
    for (int i=0; i<kNDocs; i++) {
        [self putDoc: @{@"key": @(i)}];
        if (i == kNDocs/2) {
            CBLStatus status = [v1 updateIndex];
            Assert(status < 300);
        }
    }

    CBLStatus status = [v2 updateIndexAlone];
    Assert(status < 300);

    status = [v2 updateIndex];
    AssertEq(status, kCBLStatusNotModified); // should not update v3

    status = [v3 updateIndex];
    Assert(status < 300);

    for (CBLView* view in @[v2, v3])
        AssertEq(view.lastSequenceIndexed, kNDocs);
}


- (void) test_ConflictWinner {
    // If a view is re-indexed, and a document in the view has gone into conflict,
    // rows emitted by the earlier 'losing' revision shouldn't appear in the view.
    RequireTestCase(Index);
    NSArray* docs = [self putDocs];
    CBL_Revision* leaf1 = docs[1];
    
    CBLView* view = [self createView];
    AssertEq([view updateIndex], kCBLStatusOK);
    NSArray* dump = [view dump];
    Log(@"View dump: %@", dump);
    AssertEqual(dump, $array($dict({@"key", @"\"five\""}, {@"seq", @5}),
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
    Assert(status < 300);
    AssertEqual(leaf1.docID, leaf2.docID);
    
    // Update the view -- should contain only the key from the new rev, not the old:
    AssertEq([view updateIndex], kCBLStatusOK);
    dump = [view dump];
    Log(@"View dump: %@", dump);
    AssertEqual(dump, $array($dict({@"key", @"\"40ur\""}, {@"seq", @6}),
                              $dict({@"key", @"\"five\""}, {@"seq", @5}),
                              $dict({@"key", @"\"one\""},  {@"seq", @3}),
                              $dict({@"key", @"\"three\""},{@"seq", @4}),
                              $dict({@"key", @"\"two\""},  {@"seq", @1}) ));
}


- (void) test_ConflictLoser {
    // Like the ConflictWinner test, except the newer revision is the loser,
    // so it shouldn't be indexed at all. Instead, the older still-winning revision
    // should be indexed again.
    NSArray* docs = [self putDocs];
    CBL_Revision* leaf1 = docs[1];
    
    CBLView* view = [self createView];
    AssertEq([view updateIndex], kCBLStatusOK);
    NSArray* dump = [view dump];
    Log(@"View dump: %@", dump);
    AssertEqual(dump, $array($dict({@"key", @"\"five\""}, {@"seq", @5}),
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
    Assert(status < 300);
    AssertEqual(leaf1.docID, leaf2.docID);
    
    // Update the view -- should contain only the key from the new rev, not the old:
    AssertEq([view updateIndex], kCBLStatusOK);
    dump = [view dump];
    Log(@"View dump: %@", dump);
    AssertEqual(dump, $array($dict({@"key", @"\"five\""}, {@"seq", @5}),
                              $dict({@"key", @"\"four\""}, {@"seq", @2}),
                              $dict({@"key", @"\"one\""},  {@"seq", @3}),
                              $dict({@"key", @"\"three\""},{@"seq", @4}),
                              $dict({@"key", @"\"two\""},  {@"seq", @1}) ));
}


- (void) test_Query {
    RequireTestCase(Index);
    [self putDocs];
    CBLView* view = [self createView];
    AssertEq([view updateIndex], kCBLStatusOK);
    
    // Query all rows:
    CBLQueryOptions* options = [CBLQueryOptions new];
    CBLStatus status;
    NSArray* rows = rowsToDicts([view _queryWithOptions: options status: &status]);
    NSArray* expectedRows = $array($dict({@"id",  @"55555"}, {@"key", @"five"}),
                                   $dict({@"id",  @"44444"}, {@"key", @"four"}),
                                   $dict({@"id",  @"11111"}, {@"key", @"one"}),
                                   $dict({@"id",  @"33333"}, {@"key", @"three"}),
                                   $dict({@"id",  @"22222"}, {@"key", @"two"}));
    AssertEqual(rows, expectedRows);

    // Start/end key query:
    options = [CBLQueryOptions new];
    options.startKey = @"a";
    options.endKey = @"one";
    rows = rowsToDicts([view _queryWithOptions: options status: &status]);
    expectedRows = $array($dict({@"id",  @"55555"}, {@"key", @"five"}),
                          $dict({@"id",  @"44444"}, {@"key", @"four"}),
                          $dict({@"id",  @"11111"}, {@"key", @"one"}));
    AssertEqual(rows, expectedRows);

    // Start/end query without inclusive start:
    options->inclusiveStart = NO;
    options.startKey = @"five";
    rows = rowsToDicts([view _queryWithOptions: options status: &status]);
    expectedRows = $array($dict({@"id",  @"44444"}, {@"key", @"four"}),
                          $dict({@"id",  @"11111"}, {@"key", @"one"}));
    AssertEqual(rows, expectedRows);

    // Start/end query without inclusive end:
    options->inclusiveStart = YES;
    options.startKey = @"a";
    options->inclusiveEnd = NO;
    rows = rowsToDicts([view _queryWithOptions: options status: &status]);
    expectedRows = $array($dict({@"id",  @"55555"}, {@"key", @"five"}),
                          $dict({@"id",  @"44444"}, {@"key", @"four"}));
    AssertEqual(rows, expectedRows);

    // Reversed:
    options->descending = YES;
    options.startKey = @"o";
    options.endKey = @"five";
    options->inclusiveEnd = YES;
    rows = rowsToDicts([view _queryWithOptions: options status: &status]);
    expectedRows = $array($dict({@"id",  @"44444"}, {@"key", @"four"}),
                          $dict({@"id",  @"55555"}, {@"key", @"five"}));
    AssertEqual(rows, expectedRows);

    // Reversed, no inclusive end:
    options->inclusiveEnd = NO;
    rows = rowsToDicts([view _queryWithOptions: options status: &status]);
    expectedRows = $array($dict({@"id",  @"44444"}, {@"key", @"four"}));
    AssertEqual(rows, expectedRows);
    
    // Limit:
    options = [CBLQueryOptions new];
    options->limit = 2;
    rows = rowsToDicts([view _queryWithOptions: options status: &status]);
    expectedRows = $array($dict({@"id",  @"55555"}, {@"key", @"five"}),
                          $dict({@"id",  @"44444"}, {@"key", @"four"}));
    AssertEqual(rows, expectedRows);

    // Skip rows:
    options = [CBLQueryOptions new];
    options->skip = 2;
    rows = rowsToDicts([view _queryWithOptions: options status: &status]);
    expectedRows = $array($dict({@"id",  @"11111"}, {@"key", @"one"}),
                          $dict({@"id",  @"33333"}, {@"key", @"three"}),
                          $dict({@"id",  @"22222"}, {@"key", @"two"}));
    AssertEqual(rows, expectedRows);

    // Skip + limit:
    options->limit = 1;
    rows = rowsToDicts([view _queryWithOptions: options status: &status]);
    expectedRows = $array($dict({@"id",  @"11111"}, {@"key", @"one"}));
    AssertEqual(rows, expectedRows);

    // Specific keys:
    options = [CBLQueryOptions new];
    NSArray* keys = @[@"two", @"four"];
    options.keys = keys;
    rows = rowsToDicts([view _queryWithOptions: options status: &status]);
    expectedRows = $array($dict({@"id",  @"44444"}, {@"key", @"four"}),
                          $dict({@"id",  @"22222"}, {@"key", @"two"}));
    AssertEqual(rows, expectedRows);
}

- (void) test_QueryStartKeyDocID {
    RequireTestCase(Query);
    [self putDocs];
    [self putDoc: $dict({@"_id", @"11112"}, {@"key", @"one"})];

    CBLView* view = [self createView];
    AssertEq([view updateIndex], kCBLStatusOK);

    CBLQueryOptions* options = [CBLQueryOptions new];
    options.startKey = @"one";
    options.startKeyDocID = @"11112";
    options.endKey = @"three";
    CBLStatus status;
    NSArray* rows = rowsToDicts([view _queryWithOptions: options status: &status]);
    NSArray* expectedRows = $array($dict({@"id",  @"11112"}, {@"key", @"one"}),
                                   $dict({@"id",  @"33333"}, {@"key", @"three"}));
    AssertEqual(rows, expectedRows);

    options = [CBLQueryOptions new];
    options.endKey = @"one";
    options.endKeyDocID = @"11111";
    rows = rowsToDicts([view _queryWithOptions: options status: &status]);
    expectedRows = $array($dict({@"id",  @"55555"}, {@"key", @"five"}),
                          $dict({@"id",  @"44444"}, {@"key", @"four"}),
                          $dict({@"id",  @"11111"}, {@"key", @"one"}));
    AssertEqual(rows, expectedRows);

    options.startKey = @"one";
    options.startKeyDocID = @"11111";
    rows = rowsToDicts([view _queryWithOptions: options status: &status]);
    expectedRows = $array($dict({@"id",  @"11111"}, {@"key", @"one"}));
    AssertEqual(rows, expectedRows);
}

- (void) test_PrefixMatch {
    RequireTestCase(Query);
    [self putDocs];
    CBLView* view = [self createView];
    AssertEq([view updateIndex], kCBLStatusOK);

    // Query all rows:
    CBLQueryOptions* options = [CBLQueryOptions new];
    CBLStatus status;
    options.endKey = @"f";
    options->prefixMatchLevel = 1;
    NSArray* rows = rowsToDicts([view _queryWithOptions: options status: &status]);
    NSArray* expectedRows = $array($dict({@"id",  @"55555"}, {@"key", @"five"}),
                                   $dict({@"id",  @"44444"}, {@"key", @"four"}));
    AssertEqual(rows, expectedRows);
    // TODO: Test prefixMatchLevel > 1
}

- (void) test_EmitDocAsValue {
    RequireTestCase(Query);
    NSArray* docs = [self putDocs];

    CBLView* view = [db viewNamed: @"wholedoc"];
    [view setMapBlock: MAPBLOCK({
        emit(doc[@"key"], doc);
    }) reduceBlock: ^(NSArray* keys, NSArray* values, BOOL rereduce) {
        NSMutableString* result = [NSMutableString string];
        // Make sure values have been expanded to the full docs:
        for (NSDictionary* value in values) {
            Assert([value isKindOfClass: [NSDictionary class]]);
            Assert(value[@"key"]);
            Assert(value[@"_id"]);
            Assert(value[@"_rev"]);
            [result appendString: value[@"key"]];
        }
        return result;
    } version: @"1"];

    AssertEq([view updateIndex], kCBLStatusOK);

    // Query all rows:
    CBLQueryOptions* options = [CBLQueryOptions new];
    options->reduceSpecified = YES;
    options->reduce = NO;
    CBLStatus status;
    NSArray* rows = [view _queryWithOptions: options status: &status];
    for (CBLQueryRow* row in rows)
        row.database = db; // it doesn't get set initially, but the .value accessor will need it
    rows = rowsToDicts(rows);
    NSArray* expectedRows = $array($dict({@"id",  @"55555"}, {@"key", @"five"},
                                         {@"value", [docs[4] properties]}),
                                   $dict({@"id",  @"44444"}, {@"key", @"four"},
                                         {@"value", [docs[1] properties]}),
                                   $dict({@"id",  @"11111"}, {@"key", @"one"},
                                         {@"value", [docs[2] properties]}),
                                   $dict({@"id",  @"33333"}, {@"key", @"three"},
                                         {@"value", [docs[3] properties]}),
                                   $dict({@"id",  @"22222"}, {@"key", @"two"},
                                         {@"value", [docs[0] properties]}));
    AssertEqual(rows, expectedRows);

    // Now test reducing
    options->reduce = YES;
    NSArray* reduced = [view _queryWithOptions: options status: &status];
    AssertEq(status, kCBLStatusOK);
    AssertEq(reduced.count, 1u);
    AssertEqual([(CBLQueryRow*)reduced[0] value], @"fivefouronethreetwo");
}

- (void) test_NumericKeys {
    [self putDoc: $dict({@"_id", @"22222"},
                     {@"refrenceNumber", @(33547239)},
                     {@"title", @"this is the title"})];

    CBLView* view = [db viewNamed: @"things_byRefNumber"];
    [view setMapBlock: MAPBLOCK({
        NSNumber *refrenceNumber = doc[@"refrenceNumber"];
        if (refrenceNumber) {
            emit(refrenceNumber, doc);
        };
    }) version: @"0.3"];

    CBLQuery* query = [[db viewNamed:@"things_byRefNumber"] createQuery];
    query.startKey = @(33547239);
    query.endKey = @(33547239);
    NSError* error;
    NSArray* rows = [[query run: &error] allObjects];
    AssertEq(rows.count, 1u);
    AssertEqual([rows[0] key], @(33547239));
}

- (void) test_GeoQuery {
    RequireTestCase(CBLGeometry);
    RequireTestCase(Index);
    [self putGeoDocs];
    CBLView* view = [self createView];
    AssertEq([view updateIndex], kCBLStatusOK);
    
    // Bounding-box query:
    CBLQueryOptions* options = [CBLQueryOptions new];
    CBLGeoRect bbox = {{-100, 0}, {180, 90}};
    options->bbox = &bbox;
    CBLStatus status;
    NSArray* rows = [view _queryWithOptions: options status: &status];
    NSArray* expectedRows = @[$dict({@"id", @"xxx"},
                                    {@"geometry", mkGeoRect(-115, -10, -90, 12)},
                                    {@"bbox", @[@-115, @-10, @-90, @12]}),
                               $dict({@"id", @"aus"},
                                     {@"geometry", mkGeoPoint(-97.75, 30.25)},
                                     {@"bbox", @[@-97.75, @30.25, @-97.75, @30.25]}),
                               $dict({@"id", @"diy"},
                                     {@"geometry", mkGeoPoint(40.12, 37.53)},
                                     {@"bbox", @[@40.12, @37.53, @40.12, @37.53]})];
    AssertEqualish(rowsToDicts(rows), expectedRows);

    // Now try again using the public API:
    CBLQuery* query = [view createQuery];
    query.boundingBox = bbox;
    rows = [[query run: NULL] allObjects];
    AssertEqualish(rowsToDicts(rows), expectedRows);

    CBLGeoQueryRow* row = rows[0];
    AssertEq(row.boundingBox.min.x, -115);
    AssertEq(row.boundingBox.min.y,  -10);
    AssertEq(row.boundingBox.max.x,  -90);
    AssertEq(row.boundingBox.max.y,   12);
    AssertEqual(row.geometryType, @"Polygon");
    AssertEqual(row.geometry, mkGeoRect(-115, -10, -90, 12));

    row = rows[1];
    AssertEq(row.boundingBox.min.x, -97.75);
    AssertEq(row.boundingBox.min.y,  30.25);
    AssertEqual(row.geometryType, @"Point");
    AssertEqual(row.geometry, mkGeoPoint(-97.75, 30.25));
}

- (void) test_AllDocsQuery {
    NSArray* docs = [self putDocs];
    NSDictionary* expectedRow[docs.count];
    memset(&expectedRow, 0, sizeof(expectedRow));
    int i = 0;
    for (CBL_Revision* rev in docs) {
        expectedRow[i++] = $dict({@"id",  rev.docID},
                                 {@"key", rev.docID},
                                 {@"value", $dict({@"rev", rev.revID})});
    }

    // Create a conflict, won by the old revision:
    NSDictionary* props = $dict({@"_id", @"44444"},
                                {@"_rev", @"1-...."},  // lower revID, will lose conflict
                                {@"key", @"40ur"});
    CBL_Revision* leaf2 = [[CBL_Revision alloc] initWithProperties: props];
    CBLStatus status = [db forceInsert: leaf2 revisionHistory: @[] source: nil];
    Assert(status < 300);

    // Query all rows:
    CBLQueryOptions* options = [CBLQueryOptions new];
    NSArray* query = [db getAllDocs: options];
    NSArray* expectedRows = $array(expectedRow[2], expectedRow[0], expectedRow[3], expectedRow[1],
                                   expectedRow[4]);
    AssertEqual(rowsToDicts(query), expectedRows);

    // Start/end key query:
    options = [CBLQueryOptions new];
    options.startKey = @"2";
    options.endKey = @"44444";
    query = [db getAllDocs: options];
    expectedRows = @[expectedRow[0], expectedRow[3], expectedRow[1]];
    AssertEqual(rowsToDicts(query), expectedRows);

    // Start/end query without inclusive end:
    options->inclusiveEnd = NO;
    query = [db getAllDocs: options];
    expectedRows = @[expectedRow[0], expectedRow[3]];
    AssertEqual(rowsToDicts(query), expectedRows);

    // Get zero specific documents:
    options = [CBLQueryOptions new];
    options.keys = @[];
    query = [db getAllDocs: options];
    AssertEq(query.count, 0u);
    
    // Get specific documents:
    options = [CBLQueryOptions new];
    __unused NSArray* keys = @[(expectedRow[2])[@"id"], expectedRow[3][@"id"]];
    options.keys = keys;
    query = [db getAllDocs: options];
    AssertEqual(rowsToDicts(query), (@[expectedRow[2], expectedRow[3]]));

    // Delete a document:
    CBL_Revision* del = docs[0];
    del = [[CBL_Revision alloc] initWithDocID: del.docID revID: del.revID deleted: YES];
    del = [db putRevision: del prevRevisionID: del.revID allowConflict: NO status: &status];
    AssertEq(status, kCBLStatusOK);

    // Get deleted doc, and one bogus one:
    options = [CBLQueryOptions new];
    keys = options.keys = @[@"BOGUS", expectedRow[0][@"id"]];
    query = [db getAllDocs: options];
    AssertEqual(rowsToDicts(query), (@[$dict({@"key",  @"BOGUS"},
                                              {@"error", @"not_found"}),
                                      $dict({@"id",  del.docID},
                                            {@"key", del.docID},
                                            {@"value", $dict({@"rev", del.revID},
                                                             {@"deleted", $true})}) ]));
    // Get conflicts:
    options = [CBLQueryOptions new];
    options->allDocsMode = kCBLIncludeConflicts;
    query = [db getAllDocs: options];
    NSString* curRevID = [docs[1] revID];
    NSDictionary* expectedConflict1 = $dict({@"id",  @"44444"},
                                            {@"key", @"44444"},
                                            {@"value", $dict({@"rev", [docs[1] revID]},
                                                             {@"_conflicts", @[curRevID, @"1-...."]})} );
    expectedRows = $array(expectedRow[2], expectedRow[3], expectedConflict1, expectedRow[4]);
    AssertEqual(rowsToDicts(query), expectedRows);

    // Get _only_ conflicts:
    options->allDocsMode = kCBLOnlyConflicts;
    query = [db getAllDocs: options];
    expectedRows = $array(expectedConflict1);
    AssertEqual(rowsToDicts(query), expectedRows);
}


- (void) test_Reduce {
    RequireTestCase(Query);
    [self putDoc: $dict({@"_id", @"CD"},      {@"cost", @(8.99)})];
    [self putDoc: $dict({@"_id", @"App"},     {@"cost", @(1.95)})];
    [self putDoc: $dict({@"_id", @"Dessert"}, {@"cost", @(6.50)})];
    
    CBLView* view = [db viewNamed: @"totaler"];
    [view setMapBlock: MAPBLOCK({
        Assert(doc[@"_id"] != nil, @"Missing _id in %@", doc);
        Assert(doc[@"_rev"] != nil, @"Missing _rev in %@", doc);
        id cost = doc[@"cost"];
        if (cost)
            emit(doc[@"_id"], cost);
    }) reduceBlock: ^(NSArray* keys, NSArray* values, BOOL rereduce) {
        return [CBLView totalValues: values];
    } version: @"1"];

    AssertEq([view updateIndex], kCBLStatusOK);
    NSArray* dump = [view dump];
    Log(@"View dump: %@", dump);
    AssertEqual(dump, $array($dict({@"key", @"\"App\""}, {@"value", @"1.95"}, {@"seq", @2}),
                              $dict({@"key", @"\"CD\""}, {@"value", @"8.99"}, {@"seq", @1}),
                              $dict({@"key", @"\"Dessert\""}, {@"value", @"6.5"}, {@"seq", @3}) ));

    CBLQueryOptions* options = [CBLQueryOptions new];
    CBLStatus status;
    NSArray* reduced = rowsToDicts([view _queryWithOptions: options status: &status]);
    AssertEq(status, kCBLStatusOK);
    AssertEq(reduced.count, 1u);
    double result = [reduced[0][@"value"] doubleValue];
    Assert(fabs(result - 17.44) < 0.001, @"Unexpected reduced value %@", reduced);
}


- (void) test_Grouped {
    RequireTestCase(Reduce);
    [self putDoc: $dict({@"_id", @"1"}, {@"artist", @"Gang Of Four"}, {@"album", @"Entertainment!"},
                     {@"track", @"Ether"}, {@"time", @(231)})];
    [self putDoc: $dict({@"_id", @"2"}, {@"artist", @"Gang Of Four"}, {@"album", @"Songs Of The Free"},
                     {@"track", @"I Love A Man In Uniform"}, {@"time", @(248)})];
    [self putDoc: $dict({@"_id", @"3"}, {@"artist", @"Gang Of Four"}, {@"album", @"Entertainment!"},
                     {@"track", @"Natural's Not In It"}, {@"time", @(187)})];
    [self putDoc: $dict({@"_id", @"4"}, {@"artist", @"PiL"}, {@"album", @"Metal Box"},
                     {@"track", @"Memories"}, {@"time", @(309)})];
    [self putDoc: $dict({@"_id", @"5"}, {@"artist", @"Gang Of Four"}, {@"album", @"Entertainment!"},
                     {@"track", @"Not Great Men"}, {@"time", @(187)})];
    
    CBLView* view = [db viewNamed: @"grouper"];
    [view setMapBlock: MAPBLOCK({
        emit($array(doc[@"artist"],
                    doc[@"album"], 
                    doc[@"track"]),
             doc[@"time"]);
    }) reduceBlock:^id(NSArray *keys, NSArray *values, BOOL rereduce) {
        return [CBLView totalValues: values];
    } version: @"1"];
    
    AssertEq([view updateIndex], kCBLStatusOK);

    CBLQueryOptions* options = [CBLQueryOptions new];
    CBLStatus status;
    NSArray* rows = rowsToDicts([view _queryWithOptions: options status: &status]);
    AssertEq(status, kCBLStatusOK);
    AssertEqual(rows, $array($dict({@"key", $null}, {@"value", @(1162)})));

    options->group = YES;
    rows = rowsToDicts([view _queryWithOptions: options status: &status]);
    AssertEq(status, kCBLStatusOK);
    AssertEqual(rows, $array($dict({@"key", $array(@"Gang Of Four", @"Entertainment!",
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

    options->groupLevel = 1;
    rows = rowsToDicts([view _queryWithOptions: options status: &status]);
    AssertEq(status, kCBLStatusOK);
    AssertEqual(rows, $array($dict({@"key", @[@"Gang Of Four"]}, {@"value", @(853)}),
                              $dict({@"key", @[@"PiL"]}, {@"value", @(309)})));
    
    options->groupLevel = 2;
    rows = rowsToDicts([view _queryWithOptions: options status: &status]);
    AssertEq(status, kCBLStatusOK);
    AssertEqual(rows, $array($dict({@"key", @[@"Gang Of Four", @"Entertainment!"]},
                                    {@"value", @(605)}),
                              $dict({@"key", @[@"Gang Of Four", @"Songs Of The Free"]},
                                    {@"value", @(248)}),
                              $dict({@"key", @[@"PiL", @"Metal Box"]}, 
                                    {@"value", @(309)})));
}


- (void) test_GroupedStrings {
    RequireTestCase(Grouped);
    [self putDoc: $dict({@"name", @"Alice"})];
    [self putDoc: $dict({@"name", @"Albert"})];
    [self putDoc: $dict({@"name", @"Naomi"})];
    [self putDoc: $dict({@"name", @"Jens"})];
    [self putDoc: $dict({@"name", @"Jed"})];
    
    CBLView* view = [db viewNamed: @"default/names"];
    [view setMapBlock: MAPBLOCK({
         NSString *name = doc[@"name"];
         if (name)
             emit([name substringToIndex:1], @1);
     }) reduceBlock:^id(NSArray *keys, NSArray *values, BOOL rereduce) {
         return @([values count]);
     } version:@"1.0"];
   
    AssertEq([view updateIndex], kCBLStatusOK);

    CBLQueryOptions* options = [CBLQueryOptions new];
    options->groupLevel = 1;
    CBLStatus status;
    NSArray* rows = rowsToDicts([view _queryWithOptions: options status: &status]);
    AssertEq(status, kCBLStatusOK);
    AssertEqual(rows, $array($dict({@"key", @"A"}, {@"value", @2}),
                              $dict({@"key", @"J"}, {@"value", @2}),
                              $dict({@"key", @"N"}, {@"value", @1})));
}

- (void) test_Grouped_NoReduce {
    RequireTestCase(Grouped);
    [self putDoc: $dict({@"_id", @"1"}, {@"type", @"A"})];
    [self putDoc: $dict({@"_id", @"2"}, {@"type", @"A"})];
    [self putDoc: $dict({@"_id", @"3"}, {@"type", @"B"})];
    [self putDoc: $dict({@"_id", @"4"}, {@"type", @"B"})];
    [self putDoc: $dict({@"_id", @"5"}, {@"type", @"C"})];
    [self putDoc: $dict({@"_id", @"6"}, {@"type", @"C"})];
    
    CBLView* view = [db viewNamed: @"GroupByType"];
    [view setMapBlock: MAPBLOCK({
        NSString *type = doc[@"type"];
        if (type)
            emit(type, nil);
    }) version:@"1.0"];
    
    AssertEq([view updateIndex], kCBLStatusOK);
    CBLQueryOptions *options = [CBLQueryOptions new];
    options->groupLevel = 1;
    CBLStatus status;
    NSArray* rows = rowsToDicts([view _queryWithOptions: options status: &status]);
    AssertEq(status, kCBLStatusOK);
    AssertEqual(rows, $array($dict({@"key", @"A"}, {@"error", @"not_found"}),
                              $dict({@"key", @"B"}, {@"error", @"not_found"}),
                              $dict({@"key", @"C"}, {@"error", @"not_found"})));
}


- (void) test_Collation {
    // Based on CouchDB's "view_collation.js" test
    RequireTestCase(Query);
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
    int i = 0;
    for (id key in testKeys)
        [self putDoc: $dict({@"_id", $sprintf(@"%d", i++)}, {@"name", key})];

    CBLView* view = [db viewNamed: @"default/names"];
    [view setMapBlock:  MAPBLOCK({
        emit(doc[@"name"], nil);
    }) reduceBlock: NULL version:@"1.0"];
    [view updateIndex];
    
    CBLQueryOptions* options = [CBLQueryOptions new];
    CBLStatus status;
    NSArray* rows = rowsToDicts([view _queryWithOptions: options status: &status]);
    AssertEq(status, kCBLStatusOK);
    AssertEq(rows.count, testKeys.count);
    i = 0;
    for (NSDictionary* row in rows)
        AssertEqual(row[@"key"], testKeys[i++]);
}


- (void) test_CollationRaw {
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
    RequireTestCase(Query);
    int i = 0;
    for (id key in testKeys)
        [self putDoc: $dict({@"_id", $sprintf(@"%d", i++)}, {@"name", key})];

    CBLView* view = [db viewNamed: @"default/names"];
    [view setMapBlock: MAPBLOCK({
        emit(doc[@"name"], nil);
    }) reduceBlock: NULL version:@"1.0"];
    view.collation = kCBLViewCollationRaw;
    
    CBLQueryOptions* options = [CBLQueryOptions new];
    CBLStatus status;
    NSArray* rows = rowsToDicts([view _queryWithOptions: options status: &status]);
    AssertEq(status, kCBLStatusOK);
    i = 0;
    for (NSDictionary* row in rows)
        AssertEqual(row[@"key"], testKeys[i++]);
}


- (void) test_LinkedDocs {
    RequireTestCase(Query);
    NSArray* revs = [self putDocs];
    
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

    AssertEq([view updateIndex], kCBLStatusOK);
    
    // Query all rows:
    CBLQueryOptions* options = [CBLQueryOptions new];
    options->includeDocs = YES;
    CBLStatus status;
    NSArray* rows = rowsToDicts([view _queryWithOptions: options status: &status]);
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
    AssertEqual(rows, expectedRows);
}


- (void) test_FullTextQuery {
    RequireTestCase(Query);

    NSMutableArray* docs = $marray();
    [docs addObject: [self putDoc: $dict({@"_id", @"22222"}, {@"text", @"it was a dark"})]];
    [docs addObject: [self putDoc: $dict({@"_id", @"44444"}, {@"text", @"and STöRMy night."})]];
    [docs addObject: [self putDoc: $dict({@"_id", @"11111"}, {@"text", @"outside somewhere"})]];
    [docs addObject: [self putDoc: $dict({@"_id", @"33333"}, {@"text", @"a dog whøse ñame was “Dog”"})]];
    [docs addObject: [self putDoc: $dict({@"_id", @"55555"}, {@"text", @"was barking."})]];

    CBLView* view = [db viewNamed: @"fts"];
    [view setMapBlock: MAPBLOCK({
        if (doc[@"text"])
            emit(CBLTextKey(doc[@"text"]), doc[@"_id"]);
    }) reduceBlock: NULL version: @"1"];

    AssertEq([view updateIndex], kCBLStatusOK);

    // Create another view that outputs similar-but-different text, to make sure the results
    // don't get mixed up
    CBLView* otherView = [db viewNamed: @"fts_other"];
    [otherView setMapBlock: MAPBLOCK({
        if (doc[@"text"])
            emit(CBLTextKey(@"dog stormy"), doc[@"_id"]);
    }) reduceBlock: NULL version: @"1"];
    AssertEq([otherView updateIndex], kCBLStatusOK);
    
    CBLQueryOptions* options = [CBLQueryOptions new];
    __unused NSString* fullTextQuery = @"stormy OR dog";
    options.fullTextQuery = fullTextQuery;
    options->fullTextRanking = NO;
    options->fullTextSnippets = YES;
    CBLStatus status;
    NSArray* rows = [view _queryWithOptions: options status: &status];
    Assert(rows, @"_queryFullText failed: %d", status);
    Log(@"rows = %@", rows);
    NSArray* expectedRows = $array($dict({@"id",  @"44444"},
                                         {@"matches", @[@{@"range": @[@4, @7], @"term": @0}]},
                                         {@"snippet", @"and [STöRMy] night."},
                                         {@"value", @"44444"}),
                                   $dict({@"id",  @"33333"},
                                         {@"matches", @[@{@"range": @[@2,  @3], @"term": @1},
                                                        @{@"range": @[@26, @3], @"term": @1}]},
                                         {@"snippet", @"a [dog] whøse ñame was “[Dog]”"},
                                         {@"value", @"33333"}));
    AssertEqual(rowsToDicts(rows), expectedRows);

    // Try a query with the public API:
    CBLQuery* query = [view createQuery];
    query.fullTextQuery = @"(was NOT barking) OR dog";
    query.fullTextSnippets = YES;
    rows = [[query run: NULL] allObjects];
    AssertEq(rows.count, 2u);

    CBLFullTextQueryRow* row = rows[0];
    AssertEqual(row.fullText, @"a dog whøse ñame was “Dog”");
    AssertEqual(row.documentID, @"33333");
    AssertEqual(row.snippet, @"a \001dog\002 whøse ñame \001was\002 “\001Dog\002”");
    AssertEq(row.matchCount, 3u);
    AssertEq([row termIndexOfMatch: 0], 1u);
    AssertEq([row textRangeOfMatch: 0].location, 2u);
    AssertEq([row textRangeOfMatch: 0].length, 3u);
    AssertEq([row termIndexOfMatch: 1], 0u);
    AssertEq([row textRangeOfMatch: 1].location, 17u);
    AssertEq([row textRangeOfMatch: 1].length, 3u);
    AssertEq([row termIndexOfMatch: 2], 1u);
    AssertEq([row textRangeOfMatch: 2].location, 22u);
    AssertEq([row textRangeOfMatch: 2].length, 3u);
    NSString* snippet = [row snippetWithWordStart: @"[" wordEnd: @"]"];
    AssertEqual(snippet, @"a [dog] whøse ñame [was] “[Dog]”");

    row = rows[1];
    AssertEqual(row.fullText, @"it was a dark");
    AssertEqual(row.documentID, @"22222");
    AssertEqual(row.snippet, @"it \001was\002 a dark");
    AssertEq(row.matchCount, 1u);
    AssertEq([row termIndexOfMatch: 0], 0u);
    AssertEq([row textRangeOfMatch: 0].location, 3u);
    AssertEq([row textRangeOfMatch: 0].length, 3u);

    // Now delete a document:
    CBL_Revision* rev = docs[3];
    CBL_Revision* del = [[CBL_Revision alloc] initWithDocID: rev.docID revID: rev.revID deleted: YES];
    [db putRevision: del prevRevisionID: rev.revID allowConflict: NO status: &status];
    AssertEq(status, kCBLStatusOK);

    AssertEq([view updateIndex], kCBLStatusOK);

    // Make sure the deleted doc doesn't still show up in the query results:
    fullTextQuery = @"stormy OR dog";
    options.fullTextQuery = fullTextQuery;
    rows = [view _queryWithOptions: options status: &status];
    Assert(rows, @"_queryFullText failed: %d", status);
    Log(@"after deletion, rows = %@", rows);

    expectedRows = $array($dict({@"id",  @"44444"},
                                {@"matches", @[@{@"range": @[@4, @7], @"term": @0}]},
                                {@"snippet", @"and [STöRMy] night."},
                                {@"value", @"44444"}));
    AssertEqual(rowsToDicts(rows), expectedRows);
}


- (void) test_TotalDocs {
    // Create some docs
    NSArray* docs = [self putDocs];
    NSUInteger totalRows = [docs count];
    
    // Create a view
    CBLView* view = [self createView];
    AssertEq(view.totalRows, 0u);
    AssertEq([view updateIndex], kCBLStatusOK);
    AssertEq(view.totalRows, totalRows);

    // Create a conflict, won by the new revision:
    NSDictionary* props;
    CBLStatus status;
    CBL_Revision* rev;
    props = $dict({@"_id", @"44444"},
                  {@"_rev", @"1-~~~~~"},  // higher revID, will win conflict
                  {@"key", @"40ur"});
    rev = [[CBL_Revision alloc] initWithProperties: props];
    status = [db forceInsert: rev revisionHistory: @[] source: nil];
    Assert(status < 300);
    AssertEq([view updateIndex], kCBLStatusOK);
    AssertEq(view.totalRows, totalRows);
    
    // Create a conflict, won by the old revision:
    props = $dict({@"_id", @"44444"},
                  {@"_rev", @"1-...."},  // lower revID, will lose conflict
                  {@"key", @"40ur"});
    rev = [[CBL_Revision alloc] initWithProperties: props];
    status = [db forceInsert: rev revisionHistory: @[] source: nil];
    Assert(status < 300);
    AssertEq([view updateIndex], kCBLStatusOK);
    AssertEq(view.totalRows, totalRows);
    
    // Update a doc
    CBL_MutableRevision* nuRev = [[CBL_MutableRevision alloc] initWithDocID: rev.docID
                                                                      revID: nil deleted:NO];
    nuRev.properties = $dict({@"key", @"F0uR"});
    rev = [db putRevision: nuRev prevRevisionID: rev.revID allowConflict: NO status: &status];
    Assert(status < 300);
    AssertEq([view updateIndex], kCBLStatusOK);
    AssertEq(view.totalRows, totalRows);
    
    // Delete a doc
    CBL_Revision* del = [[CBL_Revision alloc] initWithDocID: rev.docID revID: rev.revID deleted: YES];
    [db putRevision: del prevRevisionID: rev.revID allowConflict: NO status: &status];
    AssertEq(status, kCBLStatusOK);
    AssertEq([view updateIndex], kCBLStatusOK);
    AssertEq(view.totalRows, totalRows - 1);
    
    // Delete the index
    [view deleteIndex];
    AssertEq(view.totalRows, 0u);
}


@end
