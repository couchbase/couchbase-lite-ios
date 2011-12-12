//
//  TDView_Tests.m
//  TouchDB
//
//  Created by Jens Alfke on 12/8/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

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
    CAssertNil(view.mapBlock);
    
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


TestCase(TDView_Index) {
    RequireTestCase(TDView_Create);
    TDDatabase *db = [TDDatabase createEmptyDBAtPath: @"/tmp/TouchDB_ViewTest.touchdb"];
    TDRevision* rev1 = putDoc(db, $dict({@"key", @"one"}));
    TDRevision* rev2 = putDoc(db, $dict({@"key", @"two"}));
    TDRevision* rev3 = putDoc(db, $dict({@"key", @"three"}));
    putDoc(db, $dict({@"clef", @"quatre"}));
    
    TDView* view = [db viewNamed: @"aview"];
    [view setMapBlock: ^(NSDictionary* doc, TDMapEmitBlock emit) { 
        emit([doc objectForKey: @"key"], nil);
    } version: @"1"];
    CAssertEq(view.viewID, 1);
    
    CAssert([view updateIndex]);
    
    NSArray* dump = [view dump];
    Log(@"View dump: %@", dump);
    CAssertEqual(dump, $array($dict({@"key", @"\"one\""}, {@"seq", $object(1)}),
                              $dict({@"key", @"\"three\""}, {@"seq", $object(3)}),
                              $dict({@"key", @"\"two\""}, {@"seq", $object(2)}) ));
    // No-op reindex:
    CAssert([view updateIndex]);
    
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
    CAssert([view updateIndex]);

    dump = [view dump];
    Log(@"View dump: %@", dump);
    CAssertEqual(dump, $array($dict({@"key", @"\"3hree\""}, {@"seq", $object(5)}),
                              $dict({@"key", @"\"four\""}, {@"seq", $object(6)}),
                              $dict({@"key", @"\"one\""}, {@"seq", $object(1)}) ));
    
    // Now do a real query:
    NSDictionary* query = [view queryWithOptions: NULL];
    CAssertEqual([query objectForKey: @"rows"], $array(
                               $dict({@"key", @"3hree"}, {@"id", rev3.docID}),
                               $dict({@"key", @"four"}, {@"id", rev4.docID}),
                               $dict({@"key", @"one"}, {@"id", rev1.docID}) ));
    CAssertEqual([query objectForKey: @"total_rows"], $object(3));
    CAssertEqual([query objectForKey: @"offset"], $object(0));
    
    [view removeIndex];
    
    [db close];
}

#endif
