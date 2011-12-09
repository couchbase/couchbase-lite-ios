//
//  ToyView.m
//  ToyCouch
//
//  Created by Jens Alfke on 12/8/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "ToyView.h"
#import "ToyDB_Internal.h"


@implementation ToyView


- (id) initWithDatabase: (ToyDB*)db name: (NSString*)name {
    Assert(db);
    Assert(name.length);
    self = [super init];
    if (self) {
        _db = [db retain];
        _name = [name copy];
        _viewID = -1;  // means 'unknown'
    }
    return self;
}


- (void)dealloc {
    [_db release];
    [_name release];
    [super dealloc];
}


@synthesize database=_db, name=_name, mapBlock=_mapBlock;


- (int) viewID {
    if (_viewID < 0)
        _viewID = [_db getIDOfViewNamed: _name];
    return _viewID;
}


- (BOOL) setMapBlock: (ToyMapBlock)mapBlock version:(NSString *)version {
    Assert(mapBlock);
    Assert(version);
    [_mapBlock release];
    _mapBlock = [mapBlock copy];
    return [_db setVersion: version ofView: _name] < 300;
}


- (void) deleteView {
    [_db deleteViewNamed: _name];
    _viewID = 0;
}


- (BOOL) reindex {
    return [_db reindexView: self];
}


- (NSDictionary*) queryWithOptions: (ToyDBQueryOptions*)options {
    return [_db queryView: self options: options];
}


@end



#if DEBUG

TestCase(ToyView_Create) {
    RequireTestCase(ToyDB);
    ToyDB *db = [ToyDB createEmptyDBAtPath: @"/tmp/ToyDB_ViewTest.toydb"];
    
    ToyView* view = [db viewNamed: @"aview"];
    CAssert(view);
    CAssertEq(view.database, db);
    CAssertEqual(view.name, @"aview");
    CAssertNil(view.mapBlock);
    
    BOOL changed = [view setMapBlock: ^(NSDictionary* doc, ToyEmitBlock emit) { } version: @"1"];
    CAssert(changed);
    
    CAssertEqual(db.allViews, $array(view));

    changed = [view setMapBlock: ^(NSDictionary* doc, ToyEmitBlock emit) { } version: @"1"];
    CAssert(!changed);
    
    changed = [view setMapBlock: ^(NSDictionary* doc, ToyEmitBlock emit) { } version: @"2"];
    CAssert(changed);
    
    [db close];
}


static ToyRev* putDoc(ToyDB* db, NSDictionary* props) {
    ToyRev* rev = [[ToyRev alloc] initWithProperties: props];
    ToyDBStatus status;
    ToyRev* result = [db putRevision: rev prevRevisionID: nil status: &status];
    CAssert(status < 300);
    return result;
}


TestCase(ToyView_Index) {
    RequireTestCase(ToyView_Create);
    ToyDB *db = [ToyDB createEmptyDBAtPath: @"/tmp/ToyDB_ViewTest.toydb"];
    ToyRev* rev1 = putDoc(db, $dict({@"key", @"one"}));
    ToyRev* rev2 = putDoc(db, $dict({@"key", @"two"}));
    ToyRev* rev3 = putDoc(db, $dict({@"key", @"three"}));
    putDoc(db, $dict({@"clef", @"quatre"}));
    
    ToyView* view = [db viewNamed: @"aview"];
    [view setMapBlock: ^(NSDictionary* doc, ToyEmitBlock emit) { 
        emit([doc objectForKey: @"key"], nil);
    } version: @"1"];
    CAssertEq(view.viewID, 1);
    
    CAssert([view reindex]);
    
    NSArray* dump = [db dumpView: view];
    Log(@"View dump: %@", dump);
    CAssertEqual(dump, $array(
                              $dict({@"key", @"\"one\""}, {@"seq", $object(1)}),
                              $dict({@"key", @"\"three\""}, {@"seq", $object(3)}),
                              $dict({@"key", @"\"two\""}, {@"seq", $object(2)})
                              ));
    // No-op reindex:
    CAssert([view reindex]);
    
    // Now add a doc and update a doc:
    ToyRev* threeUpdated = [[[ToyRev alloc] initWithDocID: rev3.docID revID: nil deleted:NO] autorelease];
    threeUpdated.properties = $dict({@"key", @"3hree"});
    int status;
    rev3 = [db putRevision: threeUpdated prevRevisionID: rev3.revID status: &status];
    CAssert(status < 300);

    ToyRev* rev4 = putDoc(db, $dict({@"key", @"four"}));

    // Reindex again:
    CAssert([view reindex]);

    dump = [db dumpView: view];
    Log(@"View dump: %@", dump);
    CAssertEqual(dump, $array(
                              $dict({@"key", @"\"3hree\""}, {@"seq", $object(5)}),
                              $dict({@"key", @"\"four\""}, {@"seq", $object(6)}),
                              $dict({@"key", @"\"one\""}, {@"seq", $object(1)}),
                              $dict({@"key", @"\"two\""}, {@"seq", $object(2)})
                              ));
    
    // Now do a real query:
    NSDictionary* query = [view queryWithOptions: NULL];
    CAssertEqual([query objectForKey: @"rows"], $array(
                               $dict({@"key", @"3hree"}, {@"id", rev3.docID}),
                               $dict({@"key", @"four"}, {@"id", rev4.docID}),
                               $dict({@"key", @"one"}, {@"id", rev1.docID}),
                               $dict({@"key", @"two"}, {@"id", rev2.docID})
                               ));
    CAssertEqual([query objectForKey: @"total_rows"], $object(4));
    CAssertEqual([query objectForKey: @"offset"], $object(0));
    
    [db close];
}

#endif
