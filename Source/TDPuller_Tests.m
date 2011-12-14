//
//  TDPuller_Tests.m
//  TouchDB
//
//  Created by Jens Alfke on 12/7/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TDPuller.h"
#import "TDServer.h"
#import "TDDatabase.h"
#import "TDInternal.h"
#import "Test.h"


#if DEBUG

static id pull(TDDatabase* db, NSString* urlStr, id lastSequence) {
    NSURL* remote = [NSURL URLWithString: urlStr];
    TDReplicator* puller = [[[TDReplicator alloc] initWithDB: db remote: remote push: NO continuous: NO] autorelease];
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


TestCase(TDPuller) {
    RequireTestCase(TDDatabase);
    TDServer* server = [TDServer createEmptyAtPath: @"/tmp/TDPullerTest"];
    TDDatabase* db = [server databaseNamed: @"db"];
    [db open];
    
    id lastSeq = pull(db, @"http://127.0.0.1:5984/revs_test_1", nil);
    CAssertEqual(lastSeq, @"6");
    
    CAssertEq(db.documentCount, 1u);
    CAssertEq(db.lastSequence, 5);
    
    pull(db, @"http://127.0.0.1:5984/revs_test_1", lastSeq);
    
    CAssertEq(db.lastSequence, 5);
}

#endif
