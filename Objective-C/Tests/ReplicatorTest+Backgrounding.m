//
//  ReplicatorTest+Backgrounding.m
//  CouchbaseLite
//
//  Copyright (c) 2026 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "ReplicatorTest.h"

// This test file uses internal APIs and is for the internal test targets only;
// it cannot be part of the binary test targets (CBL_*_Binary_Tests).
#ifdef CBL_BINARY_TEST
#error This test file uses internal APIs and cannot run against a binary framework.
#endif


#if TARGET_OS_IPHONE
#import "CBLBlockConflictResolver.h"
#import "CBLReplicator+Backgrounding.h"
#import "CBLReplicator+Internal.h"

/** White-box tests that drive the replicator's internal app-backgrounding and
    suspension hooks; not part of the binary test suite. */
@interface ReplicatorTest_Backgrounding : ReplicatorTest

@end

@implementation ReplicatorTest_Backgrounding {
    id _target;
}

- (void) setUp {
    [super setUp];
    _target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
}

- (void) tearDown {
    _target = nil;
    [super tearDown];
}

- (void) testSwitchBackgroundForeground {
    
    id config = [self configWithTarget: _target type: kCBLReplicatorTypePushAndPull continuous: YES];
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: config];
    
    static NSInteger numRounds = 10;
    
    NSMutableArray* foregroundExps = [NSMutableArray arrayWithCapacity: numRounds + 1];
    NSMutableArray* backgroundExps = [NSMutableArray arrayWithCapacity: numRounds];
    for (NSInteger i = 0; i < numRounds; i++) {
        [foregroundExps addObject: [self allowOverfillExpectationWithDescription: @"Foregrounding"]];
        [backgroundExps addObject: [self expectationWithDescription: @"Backgrounding"]];
    }
    [foregroundExps addObject: [self allowOverfillExpectationWithDescription: @"Foregrounding"]];
    
    __block NSInteger backgroundCount = 0;
    __block NSInteger foregroundCount = 0;
    
    XCTestExpectation* stopped = [self expectationWithDescription: @"Stopped"];
    
    id token = [r addChangeListener: ^(CBLReplicatorChange* change) {
        AssertNil(change.status.error);
        if (change.status.activity == kCBLReplicatorIdle) {
            if (foregroundCount <= numRounds)
                [foregroundExps[foregroundCount++] fulfill];
        } else if (change.status.activity == kCBLReplicatorOffline) {
            [backgroundExps[backgroundCount++] fulfill];
        } else if (change.status.activity == kCBLReplicatorStopped) {
            [stopped fulfill];
        }
    }];
    
    [r start];
    [self waitForExpectations: @[foregroundExps[0]] timeout: kExpTimeout];
    
    for (int i = 0; i < numRounds; i++) {
        [r appBackgrounding];
        [self waitForExpectations: @[backgroundExps[i]] timeout: kExpTimeout];
        Assert(r.conflictResolutionSuspended);
        
        [r appForegrounding];
        [self waitForExpectations: @[foregroundExps[i+1]] timeout: kExpTimeout];
        AssertFalse(r.conflictResolutionSuspended);
    }
    
    [r stop];
    [self waitForExpectations: @[stopped] timeout: kExpTimeout];
    
    AssertEqual(foregroundCount, numRounds + 1);
    AssertEqual(backgroundCount, numRounds);
    
    [token remove];
    r = nil;
}

- (void) testSwitchToForegroundImmediately {
    id config = [self configWithTarget: _target type: kCBLReplicatorTypePushAndPull continuous: YES];
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: config];

    XCTestExpectation* idle = [self allowOverfillExpectationWithDescription: @"idle"];
    XCTestExpectation* foregroundExp = [self allowOverfillExpectationWithDescription: @"Foregrounding"];
    XCTestExpectation* stopped = [self expectationWithDescription: @"Stopped"];

    __block int idleCount = 0;
    id token = [r addChangeListener: ^(CBLReplicatorChange* change) {
        AssertNil(change.status.error);
        if (change.status.activity == kCBLReplicatorIdle) {
            if (idleCount++)
                [foregroundExp fulfill];
            else
                [idle fulfill];
        } else if (change.status.activity == kCBLReplicatorStopped) {
            [stopped fulfill];
        }
    }];

    [r start];
    [self waitForExpectations: @[idle] timeout: kExpTimeout];

    // Switch to background and immediately comes back to foreground
    [r setSuspended: YES];
    [r setSuspended: NO];

    [self waitForExpectations: @[foregroundExp] timeout: kExpTimeout];

    [r stop];
    [self waitForExpectations: @[stopped] timeout: kExpTimeout];

    [token remove];
    r = nil;
}

- (void) testBackgroundingWhenStopping {
    id config = [self configWithTarget: _target type: kCBLReplicatorTypePushAndPull continuous: YES];
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: config];
    
    __block BOOL foregrounding = NO;
    
    XCTestExpectation* idle = [self allowOverfillExpectationWithDescription: @"Idle after starting"];
    XCTestExpectation* stopped = [self expectationWithDescription: @"Stopped"];
    XCTestExpectation* done = [self expectationWithDescription: @"Done"];
    
    id token = [r addChangeListener: ^(CBLReplicatorChange* change) {
        Assert(!foregrounding);
        AssertNil(change.status.error);
        Assert(change.status.activity != kCBLReplicatorOffline);
        
        if (change.status.activity == kCBLReplicatorIdle) {
            [idle fulfill];
        } else if (change.status.activity == kCBLReplicatorStopped) {
            [stopped fulfill];
        }
    }];
    
    [r start];
    [self waitForExpectations: @[idle] timeout: kExpTimeout];
    
    [r stop];
    
    // This shouldn't prevent the replicator to stop:
    [r appBackgrounding];
    [self waitForExpectations: @[stopped] timeout: kExpTimeout];
    
    // This shouldn't wake up the replicator:
    foregrounding = YES;
    [r appForegrounding];
    
    // Wait for 0.3 seconds to ensure no more changes notified and cause !foregrounding to fail:
    id block = [NSBlockOperation blockOperationWithBlock: ^{ [done fulfill]; }];
    [NSTimer scheduledTimerWithTimeInterval: 0.3
                                     target: block
                                   selector: @selector(main) userInfo: nil repeats: NO];
    [self waitForExpectations: @[done] timeout: kExpTimeout];
    
    [token remove];
    r = nil;
}

- (void) testBackgroundingDuringDataTransfer {
    XCTestExpectation* idle = [self allowOverfillExpectationWithDescription: @"idle-and-ready"];
    XCTestExpectation* busy = [self allowOverfillExpectationWithDescription: @"transferring data"];
    XCTestExpectation* offline = [self expectationWithDescription: @"app-in-background"];
    XCTestExpectation* stop = [self allowOverfillExpectationWithDescription: @"finish-transfer"];
    
    // setup replicator
    CBLReplicatorConfiguration* config = [self configWithTarget: _target type: kCBLReplicatorTypePush
                                                     continuous: YES];
    CBLReplicator* replicator = [[CBLReplicator alloc] initWithConfig: config];
    __block int busyCount = 0;
    __block int idleCount = 0;
    id token = [replicator addChangeListener: ^(CBLReplicatorChange* change) {
        if (change.status.activity == kCBLReplicatorIdle) {
            if (++idleCount == 1)
                [idle fulfill];
            else if (change.status.progress.completed == change.status.progress.total)
                [change.replicator stop];
        } else if (change.status.activity == kCBLReplicatorBusy) {
            if (++busyCount == 1)
                [busy fulfill];
        } else if (change.status.activity == kCBLReplicatorOffline) {
            [offline fulfill];
        } else if (change.status.activity == kCBLReplicatorStopped) {
            [stop fulfill];
        }
    }];
    
    // start and wait for idle
    AssertEqual(self.otherDBDefaultCollection.count, 0);
    [replicator start];
    [self waitForExpectations: @[idle] timeout: kExpTimeout];
    
    // replicate a doc with blob, and wait for busy
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    NSData* data = [self dataFromResource: @"image" ofType: @"jpg"];
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType: @"image/jpg" data: data];
    [doc1 setBlob: blob forKey: @"blob"];
    Assert([self.defaultCollection saveDocument: doc1 error: &error]);
    [self waitForExpectations: @[busy] timeout: kExpTimeout];
    
    // background during the data transfer!
    [replicator setSuspended: YES];
    [self waitForExpectations: @[offline] timeout: kExpTimeout];
    
    // forground after 0.2 secs
    [NSThread sleepForTimeInterval: 0.2];
    [replicator setSuspended: NO];
    
    [self waitForExpectations: @[stop] timeout: kExpTimeout];
    [token remove];
    
    // make sure the doc with blob transferred successfully!
    AssertEqual(self.otherDBDefaultCollection.count, 1);
    CBLDocument* doc = [self.otherDBDefaultCollection documentWithID: @"doc1" error: &error];
    CBLBlob* blob2 = [doc blobForKey: @"blob"];
    AssertEqualObjects(blob2.digest, blob.digest);
}

- (void) testSuspendConflictResolution {
    // Prepare conflicts:
    NSUInteger numDocs = 1000;
    for (NSUInteger i = 0; i < numDocs; i++) {
        NSError* error;
        NSString* docID = [NSString stringWithFormat: @"doc-%lu", (unsigned long)i];
        CBLMutableDocument *doc1a = [[CBLMutableDocument alloc] initWithID: docID];
        [doc1a setString: self.db.name forKey: @"name"];
        Assert([self.defaultCollection saveDocument: doc1a error: &error]);
        
        CBLMutableDocument *doc1b = [[CBLMutableDocument alloc] initWithID: docID];
        [doc1b setString: self.otherDB.name forKey: @"name"];
        Assert([self.otherDBDefaultCollection saveDocument: doc1b error: &error]);
    }
    
    NSLock* lock = [[NSLock alloc] init];
    
    __block NSUInteger resolvingCount = 0;
    XCTestExpectation* resolving = [self allowOverfillExpectationWithDescription: @"Resolver was called"];
    CBLBlockConflictResolver* resolver = [[CBLBlockConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* conflict) {
        [lock lock];
        resolvingCount++;
        [lock unlock];
        
        [resolving fulfill];
        return conflict.remoteDocument;
    }];

    CBLReplicatorConfiguration* rConfig = [self configForCollection: self.defaultCollection target: _target configBlock:^(CBLCollectionConfiguration* config) {
        config.conflictResolver = resolver;
    }];
    rConfig.replicatorType = kCBLReplicatorTypePull;
    rConfig.continuous = YES;
    
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: rConfig];
    
    XCTestExpectation* offline = [self expectationWithDescription: @"Offline"];
    XCTestExpectation* stopped = [self expectationWithDescription: @"Stopped"];
    
    id token = [r addChangeListener: ^(CBLReplicatorChange* change) {
        NSLog(@">>> %d (%llu/%llu) %@", change.status.activity, change.status.progress.completed, change.status.progress.total, change.status.error);
        if (change.status.activity == kCBLReplicatorOffline) {
            [offline fulfill];
        } else if (change.status.activity == kCBLReplicatorStopped) {
            [stopped fulfill];
        }
    }];
    
    [r start];
    
    // Wait until there is at least one conflict resolver is called.
    [self waitForExpectations: @[resolving] timeout: kExpTimeout];
    
    // Now suspend.
    [r setSuspended: YES];
    
    // Wait until no pending conflcit resolver:
    NSDate* checkTimeout = [NSDate dateWithTimeIntervalSinceNow: 10.0];
    while (r.pendingConflictCount != 0 && checkTimeout.timeIntervalSinceNow > 0.0) {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]]) {
            break;
        }
    }
    
    AssertEqual(r.pendingConflictCount, 0);
    Assert(resolvingCount > 0);
    Assert(resolvingCount < numDocs);
    
    // Wait until suspended:
    [self waitForExpectations: @[offline] timeout: kExpTimeout];
    
    // Stop the replicator:
    [r stop];
    
    // Wait until the replicator is stopped:
    [self waitForExpectations: @[stopped] timeout: kExpTimeout];
    
    [token remove];
}

@end

#endif // TARGET_OS_IPHONE
