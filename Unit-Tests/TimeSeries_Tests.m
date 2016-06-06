//
//  TimeSeries_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 10/28/15.
//  Copyright © 2015 Couchbase, Inc. All rights reserved.
//

#import "CBLTestCase.h"
#import "CouchbaseLite.h"
#import "CBLTimeSeries.h"
#import "CBLGZip.h"


#define kScratchDBName @"cbl_replicator_scratch"


@interface TimeSeries_Tests : CBLTestCaseWithDB
@end


@implementation TimeSeries_Tests
{
    CBLTimeSeries* ts;
}


- (void) setUp {
    [super setUp];
    NSError* error;
    ts = [[CBLTimeSeries alloc] initWithDatabase: db
                                         docType: @"tstest"
                                           error: &error];
    Assert(ts, @"Couldn't create ts: %@", error);
}


// Generates 10000 events, one every 100µsec. Fulfils an expectation when they're all in the db.
- (void) generateEvents {
    Log(@"Generating events...");
    for (int i = 0; i < 10000; i++) {
        usleep(100);
        long r = random();
        [ts addEvent: @{@"i": @(i), @"random": @(r)}];
    }
}

- (void) generateEventsAsync {
    XCTestExpectation* done = [self expectationWithDescription: @"Done logging"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        [self generateEvents];
        [ts flushAsync: ^(BOOL ok) {
            Assert(ok);
            [done fulfill];
        }];
        AssertNil(ts.lastError);
    });
}


- (void) generateEventsSync {
    [self generateEvents];
    [ts flush];
    AssertNil(ts.lastError);
    Log(@"...Done generating events");
}


#define kFakeT0 100000


// Generates 10000 events with fake timestamps, starting at 100000. There are two events each
// fake-second, with exactly the same time: 100000, 100000, 100001, 100001, ...
- (void) generateFakeEventsAsync {
    XCTestExpectation* done = [self expectationWithDescription: @"Done logging"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        Log(@"Generating fake-time events...");
        CFAbsoluteTime t = kFakeT0;
        for (int i = 0; i < 10000; i++) {
            long r = random();
            [ts addEvent: @{@"i": @(i), @"random": @(r)} atTime: floor(t)];
            t += 0.5;
        }
        [ts flushAsync: ^(BOOL ok) {
            Assert(ok);
            AssertNil(ts.lastError);
            [done fulfill];
        }];
    });
}


- (void) test1_TimeSeriesCollector {
    [self generateEventsSync];
    int i = 0;
    for (CBLQueryRow *row in [[db createAllDocumentsQuery] run: NULL]) {
        NSDate* t0 = [CBLJSON dateWithJSONObject: row.document[@"t0"]];
        Assert(t0);
        NSArray* events = row.document[@"events"];
        Log(@"Doc %@: %lu events starting at %@",
            row.documentID, (unsigned long)events.count, t0);
        //Log(@"%@", [CBLJSON stringWithJSONObject: row.document.properties options: 0 error: NULL]);
        NSData* data = [CBLJSON dataWithJSONObject: row.document.properties options: 0 error: NULL];
        NSData* zipped = [CBLGZip dataByCompressingData: data];
        NSLog(@"Data = %lu bytes, gzipped %lu", (unsigned long)data.length, (unsigned long)zipped.length);
        for (NSDictionary* event in events) {
            AssertEqual(event[@"i"], @(i++));
            id dt = event[@"dt"];
            Assert([dt isKindOfClass: [NSNumber class]] || dt==nil);
            uint64_t t = [dt unsignedLongLongValue];
            Assert(t >= 0);
        }
    }
}


- (void) test2_PushTimeSeries {
    NSURL* remoteDbURL = [self remoteTestDBURL: kScratchDBName];
    if (!remoteDbURL)
        return;
    [self eraseRemoteDB: remoteDbURL];

    // Start continuous replication:
    CBLReplication* tsPush = [ts createPushReplication: remoteDbURL purgeWhenPushed: YES];
    tsPush.continuous = YES;
    Log(@"Starting replication...");
    [tsPush start];

    // Generate events:
    [self generateEventsAsync];
    Log(@"Waiting for events...");
    [self waitForExpectationsWithTimeout: 10.0 handler: NULL];

    // Wait for all the docs to be pushed:
    [self keyValueObservingExpectationForObject: tsPush keyPath: @"status"
                                        handler: ^BOOL(id observedObject, NSDictionary* change) {
        return tsPush.status == kCBLReplicationIdle && tsPush.pendingDocumentIDs.count == 0;
    }];
    Log(@"Waiting for replicator to finish...");
    [self waitForExpectationsWithTimeout: 10.0 handler: NULL];
    AssertNil(tsPush.lastError);

    // Stop the replication:
    [self keyValueObservingExpectationForObject: tsPush keyPath: @"status"
                                        handler: ^BOOL(id observedObject, NSDictionary* change) {
                                            return tsPush.status == kCBLReplicationStopped;
                                        }];
    [tsPush stop];
    Log(@"Waiting for replicator to stop...");
    [self waitForExpectationsWithTimeout: 10.0 handler: NULL];
    AssertNil(tsPush.lastError);

    // Did the docs get purged?
    Log(@"All docs = %@", [[db createAllDocumentsQuery] run: NULL].allObjects);
    AssertEq(db.documentCount, 0ull);
}


- (void) test3_QueryTimeSeries {
    // Generate events with fake times:
    [self generateFakeEventsAsync];
    [self waitForExpectationsWithTimeout: 5.0 handler: NULL];

    [self checkQueryFrom: 0 to: 0
                expectI0: 0 i1: 9999 t0: kFakeT0 t1: kFakeT0+4999];
    [self checkQueryFrom: 0 to: kFakeT0 - 1
                expectI0: -1 i1: -1 t0: -1 t1: -1];
    [self checkQueryFrom: kFakeT0 + 100 to: kFakeT0 + 200
                expectI0: 200 i1: 401 t0: kFakeT0+100 t1: kFakeT0+200];
    [self checkQueryFrom: kFakeT0 + 100 to: kFakeT0 + 2000
                expectI0: 200 i1: 4001 t0: kFakeT0+100 t1: kFakeT0+2000];
    [self checkQueryFrom: kFakeT0 + 999 to: kFakeT0 + 1001
                expectI0: 1998 i1: 2003 t0: kFakeT0+999 t1: kFakeT0+1001];
    [self checkQueryFrom: kFakeT0 + 999.5 to: kFakeT0 + 1001
                expectI0: 2000 i1: 2003 t0: kFakeT0+1000 t1: kFakeT0+1001];
    [self checkQueryFrom: kFakeT0 + 1000 to: kFakeT0 + 1002
                expectI0: 2000 i1: 2005 t0: kFakeT0+1000 t1: kFakeT0+1002];
    [self checkQueryFrom: kFakeT0 + 5555 to: 0
                expectI0: -1 i1: -1 t0: -1 t1: -1];
    [self checkQueryFrom: kFakeT0 + 5555 to: kFakeT0 + 999999
                expectI0: -1 i1: -1 t0: -1 t1: -1];
}

- (void) checkQueryFrom: (CFAbsoluteTime)t0 to: (CFAbsoluteTime)t1
               expectI0: (int)expectI0 i1: (int)expectI1
                     t0: (CFAbsoluteTime)expectT0 t1: (CFAbsoluteTime)expectT1
{
    NSDate* date0, *date1;
    if (t0 > 0)
        date0 = [NSDate dateWithTimeIntervalSinceReferenceDate: t0];
    if (t1 > 0)
        date1 = [NSDate dateWithTimeIntervalSinceReferenceDate: t1];
    NSError* error;
    NSEnumerator* e = [ts eventsFromDate: date0 toDate: date1 error: &error];
    Assert(e, @"query failed: %@", error);
    int n = 0, i = -1;
    int i0 = -1, i1 = -1;
    CFAbsoluteTime realt0 = -1, realt1 = -1;
    CFAbsoluteTime lastT = t0;
    for (NSDictionary* event in e) {
        Assert([event[@"i"] isKindOfClass: [NSNumber class]]);
        Assert([event[@"t"] isKindOfClass: [NSDate class]]);
        i1 = [event[@"i"] intValue];
        realt1 = [event[@"t"] timeIntervalSinceReferenceDate];
        if (n++ == 0) {
            i = i0 = i1;
            realt0 = realt1;
        }
        AssertEq(i1, i);
        i++;
        Assert(realt1 >= lastT || lastT == 0);
        Assert(realt1 <= t1 || t1==0.0);
        lastT = realt1;
    }
    if (t1 > 0)
        Assert(realt1 <= t1);
    Log(@"Query returned events %4d-%4d with time from %g to %g",
        i0, i1, realt0, realt1);
    AssertEq(i0, expectI0);
    AssertEq(i1, expectI1);
    AssertEq(realt0, expectT0);
    AssertEq(realt1, expectT1);
}


@end
