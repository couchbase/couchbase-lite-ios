//
//  ToyPuller_Tests.m
//  ToyCouch
//
//  Created by Jens Alfke on 12/7/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "ToyPuller.h"
#import "ToyServer.h"
#import "ToyDB.h"
#import "Test.h"
#import <CouchCocoa/CouchCocoa.h>


#if DEBUG

static id pull(ToyDB* db, NSString* urlStr, id lastSequence) {
    NSURL* remote = [NSURL URLWithString: urlStr];
    ToyPuller* puller = [[[ToyPuller alloc] initWithDB: db remote: remote continuous: NO] autorelease];
    puller.lastSequence = lastSequence;
    [puller start];
    
    CAssert(puller.running);
    Log(@"Waiting for puller to finish...");
    NSDate* timeout = [[NSDate date] dateByAddingTimeInterval: 5.0];
    while (puller.running) {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: timeout])
            break;
    }
    CAssert(!puller.running);
    return puller.lastSequence;
}


TestCase(ToyPuller) {
    RequireTestCase(ToyDB);
    //gCouchLogLevel = 3;
    ToyServer* server = [ToyServer createEmptyAtPath: @"/tmp/ToyPullerTest"];
    ToyDB* db = [server databaseNamed: @"db"];
    [db open];
    
    id lastSeq = pull(db, @"http://127.0.0.1:5984/revs_test_1", nil);
    CAssertEqual(lastSeq, $object(6));
    
    CAssertEq(db.documentCount, 1u);
    CAssertEq(db.lastSequence, 5);
    
    pull(db, @"http://127.0.0.1:5984/revs_test_1", lastSeq);
    
    CAssertEq(db.lastSequence, 5);
}

#endif
