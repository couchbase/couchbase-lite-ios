//
//  ReplicatorTest_Main
//  CouchbaseLite
//
//  Copyright (c) 2025 Couchbase, Inc All rights reserved.
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
#import "CBLBlockConflictResolver.h"
#import "CBLDatabase+Internal.h"
#import "CBLDocumentReplication+Internal.h"
#import "CBLReplicator+Backgrounding.h"
#import "CBLReplicator+Internal.h"
#import "CBLWebSocket.h"
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <netdb.h>


#define kDummyTarget [[CBLURLEndpoint alloc] initWithURL: [NSURL URLWithString: @"ws://foo.cbl.com/db"]]

// connect to an unknown-db on same machine, for the connection refused transient error.
#define kConnRefusedTarget [[CBLURLEndpoint alloc] initWithURL: [NSURL URLWithString: @"ws://localhost:4083/unknown-db-wXBl5n3fed"]]

@interface ReplicatorTest_Main : ReplicatorTest
@end

@implementation ReplicatorTest_Main {
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

- (void) testCreateReplicatorWithNilConfig {
    [self expectException: NSInternalInconsistencyException in:^{
        CBLReplicatorConfiguration* config = nil;
        (void) [[CBLReplicator alloc] initWithConfig: config];
    }];
}

- (void) testStopContinuousReplicator {
    id config = [self configWithTarget: _target type: kCBLReplicatorTypePushAndPull continuous: YES];
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: config];
    
    NSArray* stopWhen = @[@(kCBLReplicatorConnecting), @(kCBLReplicatorBusy),
                          @(kCBLReplicatorIdle), @(kCBLReplicatorIdle)];
    NSArray* activities = @[@"stopped", @"offline", @"connecting", @"idle", @"busy"];
    for (id when in stopWhen) {
        XCTestExpectation* x = [self expectationWithDescription: @"Replicator Change"];
        __weak typeof(self) wSelf = self;
        id token = [r addChangeListener: ^(CBLReplicatorChange *change) {
            [wSelf verifyChange: change errorCode: 0 errorDomain: nil];
            NSUInteger whenValue = [when intValue];
            if (change.status.activity == whenValue) {
                NSLog(@"****** Stop Replicator (when %@) ******", activities[whenValue]);
                [change.replicator stop];
            } else if (change.status.activity == kCBLReplicatorStopped) {
                NSLog(@"****** Replicator is stopped ******");
                [x fulfill];
            }
        }];
        
        NSLog(@"****** Start Replicator ******");
        [r start];
        [self waitForExpectations: @[x] timeout: kExpTimeout];
        [token remove];
    }
    r = nil;
}

// Runs -testStopContinuousReplicator over and over again indefinitely. (Disabled, obviously)
- (void) _testStopContinuousReplicatorForever {
    for (int i = 0; true; i++) {
        @autoreleasepool {
            Log(@"**** Begin iteration %d ****", i);
            @autoreleasepool {
                [self testStopContinuousReplicator];
            }
            Log(@"**** End iteration %d ****", i);
            fprintf(stderr, "\n\n");
            [self tearDown];
            [NSThread sleepForTimeInterval: 1.0];
            [self setUp];
        }
    }
}

- (void) testPushBlob {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    NSData* data = [self dataFromResource: @"image" ofType: @"jpg"];
    Assert(data);
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType: @"image/jpg"
                                                    data: data];
    [doc1 setBlob: blob forKey: @"blob"];
    Assert([self.defaultCollection saveDocument: doc1 error: &error]);
    AssertEqual(self.defaultCollection.count, 1u);
    
    id config = [self configWithTarget: _target type: kCBLReplicatorTypePush continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(self.otherDBDefaultCollection.count, 1u);
    CBLDocument* savedDoc1 = [self.otherDBDefaultCollection documentWithID: @"doc1" error: &error];
    AssertEqualObjects([savedDoc1 blobForKey:@"blob"], blob);
}

- (void) testPullBlob {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    NSData* data = [self dataFromResource: @"image" ofType: @"jpg"];
    Assert(data);
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType: @"image/jpg"
                                                    data: data];
    [doc1 setBlob: blob forKey: @"blob"];
    Assert([self.otherDBDefaultCollection saveDocument: doc1 error: &error]);
    AssertEqual(self.otherDBDefaultCollection.count, 1u);
    
    id config = [self configWithTarget: _target type: kCBLReplicatorTypePull continuous: YES];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(self.defaultCollection.count, 1u);
    CBLDocument* savedDoc1 = [self.defaultCollection documentWithID: @"doc1" error: &error];
    AssertEqualObjects([savedDoc1 blobForKey:@"blob"], blob);
}

#if TARGET_OS_IPHONE

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

#endif // TARGET_OS_IPHONE

- (void) testStartWithResetCheckpoint {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"Tiger" forKey: @"species"];
    [doc1 setString: @"Hobbes" forKey: @"name"];
    Assert([self.defaultCollection saveDocument: doc1 error: &error]);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setString: @"Tiger" forKey: @"species"];
    [doc2 setString: @"striped" forKey: @"pattern"];
    Assert([self.defaultCollection saveDocument: doc2 error: &error]);
    
    // Push:
    id config = [self configWithTarget: _target type: kCBLReplicatorTypePush continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    // Pull:
    config = [self configWithTarget: _target type: kCBLReplicatorTypePull continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(self.defaultCollection.count, 2u);
    
    CBLDocument* doc = [self.defaultCollection documentWithID: @"doc1" error: &error];
    Assert([self.defaultCollection purgeDocument: doc error: &error]);
    
    doc = [self.defaultCollection documentWithID: @"doc2" error: &error];
    Assert([self.defaultCollection purgeDocument: doc error: &error]);
    
    AssertEqual(self.defaultCollection.count, 0u);
    
    // Pull again, shouldn't have any new changes:
    [self run: config errorCode: 0 errorDomain: nil];
    AssertEqual(self.defaultCollection.count, 0u);
    
    // Reset and pull:
    [self run: config reset: YES errorCode: 0 errorDomain: nil];
    AssertEqual(self.defaultCollection.count, 2u);
}

- (void) testStartWithResetCheckpointContinuous {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"Tiger" forKey: @"species"];
    [doc1 setString: @"Hobbes" forKey: @"name"];
    Assert([self.defaultCollection saveDocument: doc1 error: &error]);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setString: @"Tiger" forKey: @"species"];
    [doc2 setString: @"striped" forKey: @"pattern"];
    Assert([self.defaultCollection saveDocument: doc2 error: &error]);
    
    // Push:
    id config = [self configWithTarget: _target type: kCBLReplicatorTypePush continuous: YES];
    [self run: config errorCode: 0 errorDomain: nil];
    
    // Pull:
    config = [self configWithTarget: _target type: kCBLReplicatorTypePull continuous: YES];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(self.defaultCollection.count, 2u);
    
    CBLDocument* doc = [self.defaultCollection documentWithID: @"doc1" error: &error];
    Assert([self.defaultCollection purgeDocument: doc error: &error]);
    
    doc = [self.defaultCollection documentWithID: @"doc2" error: &error];
    Assert([self.defaultCollection purgeDocument: doc error: &error]);
    
    AssertEqual(self.defaultCollection.count, 0u);
    
    // Pull again, shouldn't have any new changes:
    [self run: config errorCode: 0 errorDomain: nil];
    AssertEqual(self.defaultCollection.count, 0u);
    
    // Reset and pull:
    [self run: config reset: YES errorCode: 0 errorDomain: nil];
    AssertEqual(self.defaultCollection.count, 2u);
}

- (void) testDocumentReplicationEvent {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"Tiger" forKey: @"species"];
    [doc1 setString: @"Hobbes" forKey: @"pattern"];
    Assert([self.defaultCollection saveDocument: doc1 error: &error]);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setString: @"Tiger" forKey: @"species"];
    [doc2 setString: @"Striped" forKey: @"pattern"];
    Assert([self.defaultCollection saveDocument: doc2 error: &error]);
    
    // Push:
    id config = [self configWithTarget: _target type: kCBLReplicatorTypePush continuous: NO];
    
    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    NSMutableArray<CBLReplicatedDocument*>* docs = [NSMutableArray array];
    [self run: config reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
        replicator = r;
        token = [r addDocumentReplicationListener: ^(CBLDocumentReplication *docReplication) {
            Assert(docReplication.isPush);
            for (CBLReplicatedDocument* doc in docReplication.documents) {
                [docs addObject: doc];
            }
        }];
    }];
    
    // Check if getting two document replication events:
    AssertEqual(docs.count, 2u);
    AssertEqualObjects(docs[0].id, @"doc1");
    AssertNil(docs[0].error);
    Assert((docs[0].flags & kCBLDocumentFlagsDeleted) != kCBLDocumentFlagsDeleted);
    Assert((docs[0].flags & kCBLDocumentFlagsAccessRemoved) != kCBLDocumentFlagsAccessRemoved);
    
    AssertEqualObjects(docs[1].id, @"doc2");
    AssertNil(docs[1].error);
    Assert((docs[1].flags & kCBLDocumentFlagsDeleted) != kCBLDocumentFlagsDeleted);
    Assert((docs[1].flags & kCBLDocumentFlagsAccessRemoved) != kCBLDocumentFlagsAccessRemoved);
    
    // Add another doc:
    CBLMutableDocument* doc3 = [[CBLMutableDocument alloc] initWithID: @"doc3"];
    [doc3 setString: @"Tiger" forKey: @"species"];
    [doc3 setString: @"Star" forKey: @"pattern"];
    Assert([self.defaultCollection saveDocument: doc3 error: &error]);
    
    // Run the replicator again:
    [self runWithReplicator: replicator errorCode: 0 errorDomain: 0];
    
    // Check if getting a new document replication event:
    AssertEqual(docs.count, 3u);
    AssertEqualObjects(docs[2].id, @"doc3");
    AssertNil(docs[2].error);
    Assert((docs[2].flags & kCBLDocumentFlagsDeleted) != kCBLDocumentFlagsDeleted);
    Assert((docs[2].flags & kCBLDocumentFlagsAccessRemoved) != kCBLDocumentFlagsAccessRemoved);
    
    // Add another doc:
    CBLMutableDocument* doc4 = [[CBLMutableDocument alloc] initWithID: @"doc4"];
    [doc4 setString: @"Tiger" forKey: @"species"];
    [doc4 setString: @"WhiteStriped" forKey: @"pattern"];
    Assert([self.defaultCollection saveDocument: doc4 error: &error]);
    
    // Remove document replication listener:
    [token remove];
    
    // Run the replicator again:
    [self runWithReplicator: replicator errorCode: 0 errorDomain: 0];
    
    // Should not getting a new document replication event:
    AssertEqual(docs.count, 3u);
}

- (void) testDocumentReplicationEventAfterReplicatorStops {
    // --- 1. Create a continuous push-pull (or push only) replicator
    XCTestExpectation* xc1 = [self expectationWithDescription: @"stop1"];
    id t = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    id c = [self configWithTarget: t type: kCBLReplicatorTypePush continuous: YES];
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: c];
    id token1 = [r addChangeListener:^(CBLReplicatorChange * change) {
        if (change.status.activity == kCBLReplicatorIdle &&
            change.status.progress.completed == change.status.progress.total) {
            [change.replicator stop];
        } else if (change.status.activity == kCBLReplicatorStopped) {
            [xc1 fulfill];
        }
    }];
    
    // --- 2. Start then stop after IDLE
    [r start];
    [self waitForExpectations: @[xc1] timeout: kExpTimeout];
    [token1 remove];
    
    // --- 3. Add some documents to the database
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"Tiger" forKey: @"species"];
    [doc1 setString: @"Hobbes" forKey: @"pattern"];
    Assert([self.defaultCollection saveDocument: doc1 error: &error]);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setString: @"Tiger" forKey: @"species"];
    [doc2 setString: @"Striped" forKey: @"pattern"];
    Assert([self.defaultCollection saveDocument: doc2 error: &error]);
    
    // --- 4. Add document replication listener to the replicator
    NSMutableArray* array = [NSMutableArray array];
    __block BOOL eventNotified = NO;
    [r addDocumentReplicationListener:^(CBLDocumentReplication * docReplication) {
        [array addObjectsFromArray: docReplication.documents];
        eventNotified = YES;
    }];
    
    // --- 5. Start the replicator again.
    XCTestExpectation* xc2 = [self expectationWithDescription: @"stop2"];
    id token2 = [r addChangeListener:^(CBLReplicatorChange * change) {
        if (change.status.activity == kCBLReplicatorIdle &&
            change.status.progress.completed == change.status.progress.total) {
            [change.replicator stop];
        } else if (change.status.activity == kCBLReplicatorStopped) {
            [xc2 fulfill];
        }
    }];
    [r start];
    [self waitForExpectations: @[xc2] timeout: kExpTimeout];
    [token2 remove];
    
    // --- 6. There should be some document replication events notified
    AssertEqual(array.count, 2u);
    Assert(eventNotified);
}

- (void) testDocumentReplicationEventWithPushConflict {
    NSError* error;
    CBLMutableDocument* doc1a = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1a setString: @"Tiger" forKey: @"species"];
    [doc1a setString: @"Star" forKey: @"pattern"];
    Assert([self.defaultCollection saveDocument: doc1a error: &error]);
    
    CBLMutableDocument* doc1b = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1b setString: @"Tiger" forKey: @"species"];
    [doc1b setString: @"Striped" forKey: @"pattern"];
    Assert([self.otherDBDefaultCollection saveDocument: doc1b error: &error]);
    
    // Push:
    id config = [self configWithTarget: _target type: kCBLReplicatorTypePush continuous: NO];
    
    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    NSMutableArray<CBLReplicatedDocument*>* docs = [NSMutableArray array];
    [self run: config reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
        replicator = r;
        token = [r addDocumentReplicationListener: ^(CBLDocumentReplication *docReplication) {
            Assert(docReplication.isPush);
            for (CBLReplicatedDocument* doc in docReplication.documents) {
                [docs addObject: doc];
            }
        }];
    }];
    
    // Run the replicator:
    [self runWithReplicator: replicator errorCode: 0 errorDomain: 0];
    
    // Check:
    AssertEqual(docs.count, 1u);
    AssertEqualObjects(docs[0].id, @"doc1");
    AssertNotNil(docs[0].error);
    AssertEqualObjects(docs[0].error.domain, CBLErrorDomain);
    AssertEqual(docs[0].error.code, CBLErrorHTTPConflict);
    Assert((docs[0].flags & kCBLDocumentFlagsDeleted) != kCBLDocumentFlagsDeleted);
    Assert((docs[0].flags & kCBLDocumentFlagsAccessRemoved) != kCBLDocumentFlagsAccessRemoved);
    
    // Remove document replication listener:
    [token remove];
}

- (void) testDocumentReplicationEventWithPullConflict {
    NSError* error;
    CBLMutableDocument* doc1a = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1a setString: @"Tiger" forKey: @"species"];
    [doc1a setString: @"Star" forKey: @"pattern"];
    Assert([self.defaultCollection saveDocument: doc1a error: &error]);
    
    CBLMutableDocument* doc1b = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1b setString: @"Tiger" forKey: @"species"];
    [doc1b setString: @"Striped" forKey: @"pattern"];
    Assert([self.otherDBDefaultCollection saveDocument: doc1b error: &error]);
    
    // Pull:
    id config = [self configWithTarget: _target type: kCBLReplicatorTypePull continuous: NO];
    
    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    NSMutableArray<CBLReplicatedDocument*>* docs = [NSMutableArray array];
    [self run: config reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
        replicator = r;
        token = [r addDocumentReplicationListener: ^(CBLDocumentReplication *docReplication) {
            AssertFalse(docReplication.isPush);
            for (CBLReplicatedDocument* doc in docReplication.documents) {
                [docs addObject: doc];
            }
        }];
    }];
    
    // Check:
    AssertEqual(docs.count, 1u);
    AssertEqualObjects(docs[0].id, @"doc1");
    AssertNil(docs[0].error);
    Assert((docs[0].flags & kCBLDocumentFlagsDeleted) != kCBLDocumentFlagsDeleted);
    Assert((docs[0].flags & kCBLDocumentFlagsAccessRemoved) != kCBLDocumentFlagsAccessRemoved);
    
    // Remove document replication listener:
    [token remove];
}

- (void) testDocumentReplicationEventWithDeletion {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"Tiger" forKey: @"species"];
    [doc1 setString: @"Star" forKey: @"pattern"];
    Assert([self.defaultCollection saveDocument: doc1 error: &error]);
    
    // Delete:
    Assert([self.defaultCollection deleteDocument: doc1 error: &error]);
    
    // Push:
    id config = [self configWithTarget: _target type: kCBLReplicatorTypePush continuous: NO];
    
    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    NSMutableArray<CBLReplicatedDocument*>* docs = [NSMutableArray array];
    [self run: config reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
        replicator = r;
        token = [r addDocumentReplicationListener: ^(CBLDocumentReplication *docReplication) {
            Assert(docReplication.isPush);
            for (CBLReplicatedDocument* doc in docReplication.documents) {
                [docs addObject: doc];
            }
        }];
    }];
    
    // Run the replicator:
    [self runWithReplicator: replicator errorCode: 0 errorDomain: 0];
    
    // Check:
    AssertEqual(docs.count, 1u);
    AssertEqualObjects(docs[0].id, @"doc1");
    AssertNil(docs[0].error);
    Assert((docs[0].flags & kCBLDocumentFlagsDeleted) == kCBLDocumentFlagsDeleted);
    Assert((docs[0].flags & kCBLDocumentFlagsAccessRemoved) != kCBLDocumentFlagsAccessRemoved);
    
    // Remove document replication listener:
    [token remove];
}

- (void) testRemoveDocumentReplicationListener {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"Tiger" forKey: @"species"];
    [doc1 setString: @"Star" forKey: @"pattern"];
    Assert([self.defaultCollection saveDocument: doc1 error: &error]);
    
    XCTestExpectation* exp = [self expectationWithDescription: @"Document Replication - Inverted"];
    exp.inverted = YES;
    
    
    id config = [self configWithTarget: _target type: kCBLReplicatorTypePush continuous: NO];
    [self run: config reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
        id<CBLListenerToken> token = [r addDocumentReplicationListener: ^(CBLDocumentReplication *docReplication) {
            [exp fulfill];
        }];
        [token remove];
    }];
    
    [self waitForExpectations: @[exp] timeout: kExpTimeout];
}

- (void) testPushAndForget {
    NSError* error;
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] initWithID: @"doc"];
    [doc setString: @"Tiger" forKey: @"species"];
    [doc setString: @"Hobbes" forKey: @"pattern"];
    Assert([self.defaultCollection saveDocument: doc error: &error]);
    
    XCTestExpectation* expectation = [self expectationWithDescription: @"Document expiry test"];
    id docChangeToken = [self.defaultCollection addDocumentChangeListenerWithID: doc.id
                                                                       listener: ^(CBLDocumentChange *change) {
        NSError* err;
        AssertEqualObjects(change.documentID, doc.id);
        if ([change.collection documentWithID: change.documentID error: &err] == nil) [expectation fulfill];
    }];
    
    // Push:
    
    id config = [self configWithTarget: _target type: kCBLReplicatorTypePush continuous: NO];
    
    __block id<CBLListenerToken> docReplToken;
    __block CBLReplicator* replicator;
    [self run: config reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
        replicator = r;
        docReplToken = [r addDocumentReplicationListener: ^(CBLDocumentReplication *docReplication) {
            NSError* err;
            Assert([self.defaultCollection setDocumentExpirationWithID: doc.id
                                                            expiration: [NSDate date]
                                                                 error: &err]);
        }];
    }];
    
    [self waitForExpectations: @[expectation] timeout: kExpTimeout];
    
    AssertEqual(self.defaultCollection.count, 0u);
    AssertEqual(self.otherDBDefaultCollection.count, 1u);
    [docChangeToken remove];
    [docReplToken remove];
}

#pragma mark Removed Doc with Filter

- (void) testPullRemovedDocWithFilterSingleShot {
    [self testPullRemovedDocWithFilter: NO];
}

- (void) testPullRemovedDocWithFilterContinuous {
    [self testPullRemovedDocWithFilter: YES];
}

- (void) testPullRemovedDocWithFilter: (BOOL)isContinuous {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"pass" forKey: @"name"];
    Assert([self.otherDBDefaultCollection saveDocument: doc1 error: &error]);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"pass"];
    [doc2 setString: @"pass" forKey: @"name"];
    Assert([self.otherDBDefaultCollection saveDocument: doc2 error: &error]);
    
    // replicator with pull filter
    NSMutableSet<NSString*>* docIds = [NSMutableSet set];
    
    CBLReplicatorConfiguration* rConfig = [self configForCollection: self.defaultCollection
                                                             target: _target
                                                        configBlock:^(CBLCollectionConfiguration* config) {
        config.pullFilter = ^BOOL(CBLDocument* document, CBLDocumentFlags flags) {
            AssertNotNil(document.id);
            AssertNotNil(document.revisionID);
            BOOL isAccessRemoved = (flags & kCBLDocumentFlagsAccessRemoved) == kCBLDocumentFlagsAccessRemoved;
            if (isAccessRemoved) {
                [docIds addObject: document.id];
                
                // if access removed only allow  `docID = pass` is allowed.
                return [document.id isEqualToString: @"pass"];
            }
            // allow all docs with `name = pass`
            return [[document stringForKey: @"name"] isEqualToString: @"pass"];
        };
    }];
    
    rConfig.replicatorType = kCBLReplicatorTypePull;
    rConfig.continuous = isContinuous;
    
    [self run: rConfig errorCode: 0 errorDomain: nil];
    AssertEqual(docIds.count, 0u);
    
    // Update the `_removed` flag
    doc1 = [[self.otherDBDefaultCollection documentWithID: @"doc1" error: &error] toMutable];
    [doc1 setData: @{@"_removed": @YES}];
    Assert([self.otherDBDefaultCollection saveDocument: doc1 error: &error]);
    
    doc2 = [[self.otherDBDefaultCollection documentWithID: @"pass" error: &error] toMutable];
    [doc2 setData: @{@"_removed": @YES}];
    Assert([self.otherDBDefaultCollection saveDocument: doc2 error: &error]);
    
    // pull replication again...
    [self run: rConfig errorCode: 0 errorDomain: nil];
    
    AssertEqual(docIds.count, 2u);
    
    // shouldn't delete the one with `docID != pass`
    AssertNotNil([self.defaultCollection documentWithID: @"doc1" error: nil]);
    AssertNil([self.defaultCollection documentWithID: @"pass" error: nil]);
}

#pragma mark Deleted Doc with Filter

- (void) testPushDeletedDocWithFilterSingleShot {
    [self testPushDeletedDocWithFilter: NO];
}

- (void) testPushDeletedDocWithFilterContinuous {
    [self testPushDeletedDocWithFilter: YES];
}

- (void) testPullDeletedDocWithFilterSingleShot {
    [self testPullDeletedDocWithFilter: NO];
}

- (void) testPullDeletedDocWithFilterContinuous {
    [self testPullDeletedDocWithFilter: YES];
}

- (void) testPushDeletedDocWithFilter: (BOOL)isContinuous {
    // Create documents:
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"pass" forKey: @"name"];
    Assert([self.defaultCollection saveDocument: doc1 error: &error]);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"pass"];
    [doc2 setString: @"pass" forKey: @"name"];
    Assert([self.defaultCollection saveDocument: doc2 error: &error]);
    
    // Create replicator with push filter:
    NSMutableSet<NSString*>* docIds = [NSMutableSet set];
    
    CBLReplicatorConfiguration* rConfig = [self configForCollection: self.defaultCollection
                                                             target: _target
                                                        configBlock:^(CBLCollectionConfiguration* config) {
        config.pushFilter = ^BOOL(CBLDocument* document, CBLDocumentFlags flags) {
            AssertNotNil(document.id);
            AssertNotNil(document.revisionID);
            
            BOOL isDeleted = (flags & kCBLDocumentFlagsDeleted) == kCBLDocumentFlagsDeleted;
            if (isDeleted) {
                [docIds addObject: document.id];
                
                // if deleted only allow  `docID = pass` is allowed.
                return [document.id isEqualToString: @"pass"];
            }
            // allow all docs with `name = pass`
            return [[document stringForKey: @"name"] isEqualToString: @"pass"];
        };
    }];
    
    rConfig.replicatorType = kCBLReplicatorTypePush;
    rConfig.continuous = isContinuous;
    
    [self run: rConfig errorCode: 0 errorDomain: nil];
    AssertEqual(docIds.count, 0u);
    
    // Check replicated documents:
    AssertNotNil([self.otherDBDefaultCollection documentWithID: @"doc1" error: &error]);
    AssertNotNil([self.otherDBDefaultCollection documentWithID: @"pass" error: &error]);
    
    Assert([self.defaultCollection deleteDocument: doc1 error: &error]);
    Assert([self.defaultCollection deleteDocument: doc2 error: &error]);
    
    [self run: rConfig errorCode: 0 errorDomain: nil];
    
    AssertEqual(docIds.count, 2u);
    Assert([docIds containsObject: @"doc1"]);
    Assert([docIds containsObject: @"pass"]);
    
    // shouldn't delete the one with `docID != pass`
    AssertNotNil([self.otherDBDefaultCollection documentWithID: @"doc1" error: &error]);
    AssertNil([self.otherDBDefaultCollection documentWithID: @"pass" error: &error]);
}

- (void) testPullDeletedDocWithFilter: (BOOL)isContinuous {
    // Create documents:
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"pass" forKey: @"name"];
    Assert([self.otherDBDefaultCollection saveDocument: doc1 error: &error]);
    
    CBLMutableDocument* pass = [[CBLMutableDocument alloc] initWithID: @"pass"];
    [pass setString: @"pass" forKey: @"name"];
    Assert([self.otherDBDefaultCollection saveDocument: pass error: &error]);
    
    NSMutableSet<NSString*>* docIds = [NSMutableSet set];
    
    CBLReplicatorConfiguration* rConfig = [self configForCollection: self.defaultCollection
                                                             target: _target
                                                        configBlock:^(CBLCollectionConfiguration* config) {
        config.pullFilter = ^BOOL(CBLDocument* document, CBLDocumentFlags flags) {
            AssertNotNil(document.id);
            AssertNotNil(document.revisionID);
            
            BOOL isDeleted = (flags & kCBLDocumentFlagsDeleted) == kCBLDocumentFlagsDeleted;
            if (isDeleted) {
                [docIds addObject: document.id];
                
                // if deleted only allow  `docID = pass` is allowed.
                return [document.id isEqualToString: @"pass"];
            }
            // allow all docs with `name = pass`
            return [[document stringForKey: @"name"] isEqualToString: @"pass"];
        };
    }];
    
    rConfig.replicatorType = kCBLReplicatorTypePull;
    rConfig.continuous = isContinuous;
    
    [self run: rConfig errorCode: 0 errorDomain: nil];
    AssertEqual(docIds.count, 0u);
    
    // should replicate all docs with `name = pass`
    AssertNotNil([self.defaultCollection documentWithID: @"doc1" error: &error]);
    AssertNotNil([self.defaultCollection documentWithID: @"pass" error: &error]);
    AssertEqual(self.defaultCollection.count, 2u);
    AssertEqual(self.otherDBDefaultCollection.count, 2u);
    
    Assert([self.otherDBDefaultCollection deleteDocument: doc1 error: &error]);
    Assert([self.otherDBDefaultCollection deleteDocument: pass error: &error]);
    
    [self run: rConfig errorCode: 0 errorDomain: nil];
    
    // Check documents passed to the filter:
    AssertEqual(docIds.count, 2u);
    Assert([docIds containsObject: @"doc1"]);
    Assert([docIds containsObject: @"pass"]);
    
    // shouldn't delete the one with `docID != pass`
    AssertNotNil([self.defaultCollection documentWithID: @"doc1" error: nil]);
    AssertNil([self.defaultCollection documentWithID: @"pass" error: nil]);
    AssertEqual(self.defaultCollection.count, 1u);
    AssertEqual(self.otherDBDefaultCollection.count, 0u);
}

#pragma mark stop and restart the replication with filter

- (void) testStopAndRestartPushReplicationWithFilter {
    // Create documents
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"pass" forKey: @"name"];
    Assert([self.defaultCollection saveDocument: doc1 error: &error]);
    
    NSMutableSet<NSString*>* docIds = [NSMutableSet set];
    
    CBLReplicatorConfiguration* rConfig = [self configForCollection: self.defaultCollection
                                                             target: _target
                                                        configBlock:^(CBLCollectionConfiguration* config) {
        config.pushFilter = ^BOOL(CBLDocument* document, CBLDocumentFlags flags) {
            AssertNotNil(document.id);
            AssertNotNil(document.revisionID);
            [docIds addObject: document.id];
            
            // allow all docs with `name = pass`
            return [[document stringForKey: @"name"] isEqualToString: @"pass"];
        };
    }];
    
    rConfig.replicatorType = kCBLReplicatorTypePush;
    rConfig.continuous = YES;
    
    repl = [[CBLReplicator alloc] initWithConfig: rConfig];
    [self runWithReplicator: repl errorCode: 0 errorDomain: nil];
    AssertEqual(docIds.count, 1u);
    AssertEqual(self.defaultCollection.count, 1u);
    AssertEqual(self.otherDBDefaultCollection.count, 1u);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setString: @"pass" forKey: @"name"];
    Assert([self.defaultCollection saveDocument: doc2 error: &error]);
    
    CBLMutableDocument* doc3 = [[CBLMutableDocument alloc] initWithID: @"doc3"];
    [doc3 setString: @"donotpass" forKey: @"name"];
    Assert([self.defaultCollection saveDocument: doc3 error: &error]);
    
    [docIds removeAllObjects];
    [self runWithReplicator: repl errorCode: 0 errorDomain: nil];
    
    // Check documents passed to the filter:
    AssertEqual(docIds.count, 2u);
    Assert([docIds containsObject: @"doc3"]);
    Assert([docIds containsObject: @"doc2"]);
    
    // shouldn't delete the one with `docID != pass`
    AssertNotNil([self.otherDBDefaultCollection documentWithID: @"doc1" error: nil]);
    AssertNotNil([self.otherDBDefaultCollection documentWithID: @"doc2" error: nil]);
    AssertNil([self.otherDBDefaultCollection documentWithID: @"doc3" error: nil]);
    AssertEqual(self.defaultCollection.count, 3u);
    AssertEqual(self.otherDBDefaultCollection.count, 2u);
    
    // Cleanup:
    repl = nil;
}

- (void) testStopAndRestartPullReplicationWithFilter {
    // Create documents
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"pass" forKey: @"name"];
    Assert([self.otherDBDefaultCollection saveDocument: doc1 error: &error]);
    
    NSMutableSet<NSString*>* docIds = [NSMutableSet set];
    
    CBLReplicatorConfiguration* rConfig = [self configForCollection: self.defaultCollection
                                                             target: _target
                                                        configBlock:^(CBLCollectionConfiguration* config) {
        config.pullFilter = ^BOOL(CBLDocument* document, CBLDocumentFlags flags) {
            AssertNotNil(document.id);
            AssertNotNil(document.revisionID);
            
            [docIds addObject: document.id];
            
            // allow all docs with `name = pass`
            return [[document stringForKey: @"name"] isEqualToString: @"pass"];
        };
    }];
    
    rConfig.replicatorType = kCBLReplicatorTypePull;
    rConfig.continuous = YES;
    
    repl = [[CBLReplicator alloc] initWithConfig: rConfig];
    [self runWithReplicator: repl errorCode: 0 errorDomain: nil];
    AssertEqual(docIds.count, 1u);
    AssertEqual(self.defaultCollection.count, 1u);
    AssertEqual(self.otherDBDefaultCollection.count, 1u);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setString: @"pass" forKey: @"name"];
    Assert([self.otherDBDefaultCollection saveDocument: doc2 error: &error]);
    
    CBLMutableDocument* doc3 = [[CBLMutableDocument alloc] initWithID: @"doc3"];
    [doc3 setString: @"donotpass" forKey: @"name"];
    Assert([self.otherDBDefaultCollection saveDocument: doc3 error: &error]);
    
    [docIds removeAllObjects];
    [self runWithReplicator: repl errorCode: 0 errorDomain: nil];
    
    // Check documents passed to the filter:
    AssertEqual(docIds.count, 2u);
    Assert([docIds containsObject: @"doc3"]);
    Assert([docIds containsObject: @"doc2"]);
    
    // shouldn't delete the one with `docID != pass`
    AssertNotNil([self.defaultCollection documentWithID: @"doc1" error: nil]);
    AssertNotNil([self.defaultCollection documentWithID: @"doc2" error: nil]);
    AssertNil([self.defaultCollection documentWithID: @"doc3" error: nil]);
    AssertEqual(self.otherDBDefaultCollection.count, 3u);
    AssertEqual(self.defaultCollection.count, 2u);
    
    // Cleanup:
    repl = nil;
}

- (void) testRevisionIdInPushPullFilters {
    // Create documents:
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"Tiger" forKey: @"species"];
    Assert([self.defaultCollection saveDocument: doc1 error: &error]);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setString: @"Stripes" forKey: @"pattern"];
    Assert([self.otherDBDefaultCollection saveDocument: doc2 error: &error]);
    
    // Create replicator with push filter:
    NSMutableSet<NSString*>* pushDocIds = [NSMutableSet set];
    NSMutableSet<NSString*>* pullDocIds = [NSMutableSet set];
    
    CBLReplicatorConfiguration* rConfig = [self configForCollection: self.defaultCollection
                                                             target: _target
                                                        configBlock:^(CBLCollectionConfiguration* config) {
        config.pushFilter = ^BOOL(CBLDocument* document, CBLDocumentFlags flags) {
            AssertNotNil(document.id);
            AssertNotNil(document.revisionID);
            
            [self expectException: @"NSInternalInconsistencyException" in:^{
                [document toMutable];
            }];
            
            // Gather document ID:
            [pushDocIds addObject: document.id];
            return YES;
        };
        
        config.pullFilter = ^BOOL(CBLDocument* document, CBLDocumentFlags flags) {
            AssertNotNil(document.id);
            AssertNotNil(document.revisionID);
            
            [self expectException: @"NSInternalInconsistencyException" in:^{
                [document toMutable];
            }];
            
            // Gather document ID:
            [pullDocIds addObject: document.id];
            return YES;
        };
    }];
    
    rConfig.replicatorType = kCBLReplicatorTypePushAndPull;
    rConfig.continuous = NO;
    
    [self run: rConfig errorCode: 0 errorDomain: nil];
    
    // Check documents passed to the filter:
    AssertEqual(pullDocIds.count, 1u);
    Assert([pullDocIds containsObject: @"doc2"]);
    
    AssertEqual(pushDocIds.count, 1u);
    Assert([pushDocIds containsObject: @"doc1"]);
}

- (void) testWebSocketParseCookie {
    NSArray* inputs = @[
        @[@"a1=b1", @[@"a1=b1"]],
        @[@"a1=b1;a2=b2", @[@"a1=b1;a2=b2"]],
        @[@"a1=b1;expires=b2,3", @[@"a1=b1;expires=b2,3"]],
        @[@"a1=b1;a2=b2,a3=b3;a4=b4", @[@"a1=b1;a2=b2", @"a3=b3;a4=b4"]],
        @[@"a1=b1;expires=b2,3,a2=b2", @[@"a1=b1;expires=b2,3", @"a2=b2"]],
        @[@"a1=b1;expires=b1,2,a3=b3;Expires=b3,4",
          @[@"a1=b1;expires=b1,2", @"a3=b3;Expires=b3,4"]],
        
        // RFC 822, updated by RFC 1123
        @[@"a1=b1;expires=Sun, 06 Nov 1994 08:49:37 GMT;Path=/",
          @[@"a1=b1;expires=Sun, 06 Nov 1994 08:49:37 GMT;Path=/"]],
        
        // RFC 850, obsoleted by RFC 1036
        @[@"a1=b1;expires=Sunday, 06-Nov-94 08:49:37 GMT;Path=/",
          @[@"a1=b1;expires=Sunday, 06-Nov-94 08:49:37 GMT;Path=/"]],
        
        // ANSI C's asctime() format
        @[@"a1=b1;expires=Sun Nov  6 08:49:37 1994       ;Path=/",
          @[@"a1=b1;expires=Sun Nov  6 08:49:37 1994;Path=/"]],
        
        // GCLB cookie format => removes in between spaces as well
        @[@"GCLB=gclbValue1; path=/; HttpOnly; expires=Tue, 22-Nov-2022 07:21:38 GMT",
          @[@"GCLB=gclbValue1;path=/;HttpOnly;expires=Tue, 22-Nov-2022 07:21:38 GMT"]],
    ];
    
    for (NSArray* input in inputs) {
        AssertEqualObjects([CBLWebSocket parseCookies: input[0]], input[1]);
    }
}

- (void) testNetworkInterfaceName {
    AssertEqualObjects([CBLWebSocket getNetworkInterfaceName: @"en0" error: nil], @"en0");
    
    struct ifaddrs *ifaddrs;
    Assert(getifaddrs(&ifaddrs) == 0);
    
    NSString* networkInterface = nil;
    for (struct ifaddrs *ifa = ifaddrs; ifa != NULL; ifa = ifa->ifa_next) {
        struct sockaddr* addr = ifa->ifa_addr;
        if (!addr)
            continue;
        
        int family = ifa->ifa_addr->sa_family;
        char host[NI_MAXHOST];
        int s = getnameinfo(ifa->ifa_addr,
                            (family == AF_INET) ? sizeof(struct sockaddr_in) : sizeof(struct sockaddr_in6),
                            host, NI_MAXHOST, NULL, 0, NI_NUMERICHOST);
        
        if (strcmp(host, "") == 0)
            continue;
        
        AssertEqual(s, 0);
        networkInterface = [NSString stringWithUTF8String: ifa->ifa_name];
        if (family == AF_INET) {
            AssertEqualObjects([CBLWebSocket getNetworkInterfaceName: [NSString stringWithUTF8String: host] error: nil], networkInterface);
        } else if (family == AF_INET6) {
            // only checks 'en' series
            if (![networkInterface hasPrefix: @"en"]) {
                continue;
            }
            
            NSString* hostStr = [NSString stringWithUTF8String: host];
            NSString* localSuffix = [NSString stringWithFormat: @"%%%@", networkInterface];
            NSRange range = [hostStr rangeOfString: localSuffix];
            if (range.length > 0 ) {
                NSString* subString = [hostStr substringToIndex: range.location];
                AssertEqualObjects([CBLWebSocket getNetworkInterfaceName: subString error: nil], networkInterface);
            }
        }
        AssertEqualObjects([CBLWebSocket getNetworkInterfaceName: networkInterface error: nil], networkInterface);
    }
    
    freeifaddrs(ifaddrs);
}

#pragma mark - Replicator Config

- (void) testReplicationConfigSetterMethods {
    CBLBasicAuthenticator* basic = [[CBLBasicAuthenticator alloc] initWithUsername: @"abcd"
                                                                          password: @"efgh"];
    
    id target = [[CBLURLEndpoint alloc]
                 initWithURL: [NSURL URLWithString: @"ws://foo.couchbase.com/db"]];
    CBLReplicatorConfiguration* temp = [self configWithTarget: target
                                                         type: kCBLReplicatorTypePush
                                                   continuous: YES];
    AssertEqual(temp.heartbeat, kCBLDefaultReplicatorHeartbeat);
#ifdef COUCHBASE_ENTERPRISE
    AssertEqual(temp.acceptOnlySelfSignedServerCertificate, kCBLDefaultReplicatorSelfSignedCertificateOnly);
#endif
    
    [temp setContinuous: YES];
    [temp setAuthenticator: basic];
    
    NSDictionary* headers = [NSDictionary dictionaryWithObjectsAndKeys:
                             @"someObject", @"someKey", nil];
    [temp setHeaders: headers];
    
#ifdef COUCHBASE_ENTERPRISE
    [temp setAcceptOnlySelfSignedServerCertificate: true];
#endif
    
    SecCertificateRef cert = [self defaultServerCert];
    [temp setPinnedServerCertificate: cert];
    CBLReplicatorConfiguration* config = [[CBLReplicatorConfiguration alloc] initWithConfig: temp];
    
    // Make sure all values are set!!
    AssertEqualObjects(basic, config.authenticator);
    AssertEqual(YES, config.continuous);
    AssertEqualObjects([self getCertificateID: cert],
                       [self getCertificateID: config.pinnedServerCertificate]);
    AssertEqualObjects(headers, config.headers);
    AssertEqual(config.heartbeat, kCBLDefaultReplicatorHeartbeat);
#ifdef COUCHBASE_ENTERPRISE
    AssertEqual(temp.acceptOnlySelfSignedServerCertificate, YES);
#endif

}

- (void) testReplicatorConfigDefaultValues {
    CBLReplicatorConfiguration* config = [[CBLReplicatorConfiguration alloc] initWithDefaults];
    
    AssertEqual(config.replicatorType, kCBLDefaultReplicatorType);
    AssertEqual(config.continuous, kCBLDefaultReplicatorContinuous);
    
#if TARGET_OS_IPHONE
    AssertEqual(config.allowReplicatingInBackground, kCBLDefaultReplicatorAllowReplicatingInBackground);
#endif
    
    AssertEqual(config.heartbeat, kCBLDefaultReplicatorHeartbeat);
    AssertEqual(config.maxAttempts, kCBLDefaultReplicatorMaxAttemptsSingleShot);
    AssertEqual(config.maxAttemptWaitTime, kCBLDefaultReplicatorMaxAttemptsWaitTime);
    AssertEqual(config.enableAutoPurge, kCBLDefaultReplicatorEnableAutoPurge);
    
    config.continuous = YES;
    Assert(config.continuous);
    AssertEqual(config.maxAttempts, kCBLDefaultReplicatorMaxAttemptsContinuous);
}

#pragma mark - HeartBeat

- (void) testHeartbeatWithInvalidValue {
    CBLReplicatorConfiguration* config = [self configWithTarget: kDummyTarget
                                                           type: kCBLReplicatorTypePush
                                                     continuous: YES];
    
    [self expectException: @"NSInvalidArgumentException" in:^{
        config.heartbeat = -1;
    }];
    
    config.heartbeat = DBL_MAX;
    AssertEqual(config.heartbeat, DBL_MAX);
}

- (void) testCustomHeartbeat {
    CBLReplicatorConfiguration* config = [self configWithTarget: kDummyTarget
                                                           type: kCBLReplicatorTypePush
                                                     continuous: YES];
    
    AssertEqual(config.heartbeat, kCBLDefaultReplicatorHeartbeat);
    config.heartbeat = 60;
    repl = [[CBLReplicator alloc] initWithConfig: config];
    
    AssertEqual(config.heartbeat, 60);
    AssertEqual(repl.config.heartbeat, 60);
    
    // Cleanup:
    repl = nil;
}

#pragma mark - Max Attempt Count

- (void) testMaxAttemptCount {
    // continuous
    CBLReplicatorConfiguration* config = [self configWithTarget: kDummyTarget
                                                           type: kCBLReplicatorTypePush
                                                     continuous: YES];
    AssertEqual(config.maxAttempts, kCBLDefaultReplicatorMaxAttemptsContinuous);
    
    // single shot
    config = [self configWithTarget: kDummyTarget
                               type: kCBLReplicatorTypePush
                         continuous: NO];
    AssertEqual(config.maxAttempts, kCBLDefaultReplicatorMaxAttemptsSingleShot);
}

- (void) testCustomMaxAttemptCount {
    // continuous
    CBLReplicatorConfiguration* config = [self configWithTarget: kDummyTarget
                                                           type: kCBLReplicatorTypePush
                                                     continuous: YES];
    config.maxAttempts = 22;
    AssertEqual(config.maxAttempts, 22);
    
    // continous
    config = [self configWithTarget: kDummyTarget
                               type: kCBLReplicatorTypePush
                         continuous: NO];
    config.maxAttempts = 11;
    AssertEqual(config.maxAttempts, 11);
}

- (void) testMaxAttempt: (int) attempt count: (int)count continuous: (BOOL)continuous {
    XCTestExpectation* exp = [self expectationWithDescription: @"replicator finish"];
    CBLReplicatorConfiguration* config = [self configWithTarget: kConnRefusedTarget
                                                           type: kCBLReplicatorTypePush
                                                     continuous: continuous];
    __block int offlineCount = 0;
    config.maxAttempts = attempt;
    
    repl = [[CBLReplicator alloc] initWithConfig: config];
    [repl addChangeListener: ^(CBLReplicatorChange * c) {
        if (c.status.activity == kCBLReplicatorOffline) {
            offlineCount++;
        } else if (c.status.activity == kCBLReplicatorStopped) {
            [exp fulfill];
        }
    }];
    [repl start];
    [self waitForExpectations: @[exp] timeout: pow(2, count + 1) + kExpTimeout];
    AssertEqual(offlineCount, count);
}

- (void) testMaxAttempt {
    // replicator with no retry; only initial request
    [self testMaxAttempt: 1 count: 0 continuous: NO];
    [self testMaxAttempt: 1 count: 0 continuous: YES];
    
    // replicator with one retry; initial + one retry(offline)
    [self testMaxAttempt: 2 count: 1 continuous: NO];
    [self testMaxAttempt: 2 count: 1 continuous: YES];
}

// disbale the test, since this test will take 13mints to finish
- (void) _testMaxAttemptForSingleShot {
    [self testMaxAttempt: 0 count: 9 continuous: NO];
}

#pragma mark - Max Attempt Wait Time

- (void) testMaxAttemptWaitTime {
    // single shot
    CBLReplicatorConfiguration* config = [self configWithTarget: kDummyTarget
                                                           type: kCBLReplicatorTypePush
                                                     continuous: NO];
    AssertEqual(config.maxAttemptWaitTime, kCBLDefaultReplicatorMaxAttemptsWaitTime);
    repl = [[CBLReplicator alloc] initWithConfig: config];
    AssertEqual(repl.config.maxAttemptWaitTime, kCBLDefaultReplicatorMaxAttemptsWaitTime);
    
    // continuous
    config = [self configWithTarget: kDummyTarget
                               type: kCBLReplicatorTypePush
                         continuous: YES];
    AssertEqual(config.maxAttemptWaitTime, kCBLDefaultReplicatorMaxAttemptsWaitTime);
    repl = [[CBLReplicator alloc] initWithConfig: config];
    AssertEqual(repl.config.maxAttemptWaitTime, kCBLDefaultReplicatorMaxAttemptsWaitTime);
    
    repl = nil;
}

- (void) testCustomMaxAttemptWaitTime {
    // single shot
    CBLReplicatorConfiguration* config = [self configWithTarget: kDummyTarget
                                                           type: kCBLReplicatorTypePush
                                                     continuous: NO];
    config.maxAttemptWaitTime = 444;
    AssertEqual(config.maxAttemptWaitTime, 444);
    
    // continuous
    config = [self configWithTarget: kDummyTarget
                               type: kCBLReplicatorTypePush
                         continuous: YES];
    config.maxAttemptWaitTime = 444;
    AssertEqual(config.maxAttemptWaitTime, 444);
}

- (void) testInvalidMaxAttemptWaitTime {
    CBLReplicatorConfiguration* config = [self configWithTarget: kDummyTarget
                                                           type: kCBLReplicatorTypePush
                                                     continuous: NO];
    [self expectException: @"NSInvalidArgumentException" in:^{
        config.maxAttemptWaitTime = -1;
    }];
}

- (void) testMaxAttemptWaitTimeOfReplicator {
    XCTestExpectation* exp = [self expectationWithDescription: @"replicator finish"];
    CBLReplicatorConfiguration* config = [self configWithTarget: kConnRefusedTarget
                                                           type: kCBLReplicatorTypePush
                                                     continuous: NO];
    config.maxAttemptWaitTime = 2;
    config.maxAttempts = 3;
    repl = [[CBLReplicator alloc] initWithConfig: config];
    __block NSDate* begin = [NSDate date];
    __block NSTimeInterval diff;
    [repl addChangeListener: ^(CBLReplicatorChange * c) {
        if (c.status.activity == kCBLReplicatorOffline) {
            diff = [[NSDate date] timeIntervalSinceDate: begin];
            begin = [NSDate date];
        } else if (c.status.activity == kCBLReplicatorStopped) {
            [exp fulfill];
        }
    }];
    [repl start];
    [self waitForExpectations: @[exp] timeout: kExpTimeout];
    Assert(ABS(diff - config.maxAttemptWaitTime) < 1.0);
}

# pragma mark - CBLDocumentReplication

- (void) testCreateDocumentReplicator {
    id target = [[CBLURLEndpoint alloc] initWithURL:[NSURL URLWithString:@"ws://foo.couchbase.com/db"]];
    CBLReplicatorConfiguration* config = [self configWithTarget: target
                                                           type: kCBLReplicatorTypePush
                                                     continuous: YES];
    repl = [[CBLReplicator alloc] initWithConfig: config];
    CBLDocumentReplication* docReplication = [[CBLDocumentReplication alloc] initWithReplicator: repl
                                                                                         isPush: YES
                                                                                      documents: @[]];
    Assert(docReplication.isPush);
    AssertEqualObjects(docReplication.documents, @[]);
    AssertEqualObjects(docReplication.replicator, repl);
    
    // Cleanup:
    repl = nil;
}

- (void) testReplicatedDocument {
    C4DocumentEnded end;
    end.docID = C4STR("docID");
    end.revID = C4STR("revID");
    end.flags = kRevDeleted;
    end.error = c4error_make(1, kC4ErrorBusy, C4STR("error"));
    end.errorIsTransient = true;
    end.collectionSpec = kC4DefaultCollectionSpec;
    
    CBLReplicatedDocument* replicatedDoc = [[CBLReplicatedDocument alloc] initWithC4DocumentEnded: &end];
    AssertEqualObjects(replicatedDoc.id, @"docID");
    Assert((replicatedDoc.flags & kCBLDocumentFlagsDeleted) == kCBLDocumentFlagsDeleted);
    AssertEqual(replicatedDoc.c4Error.code, kC4ErrorBusy);
    AssertEqual(replicatedDoc.c4Error.domain, 1);
    AssertEqual(replicatedDoc.error.code, kC4ErrorBusy);
    AssertEqualObjects(replicatedDoc.collection, kCBLDefaultCollectionName);
    AssertEqualObjects(replicatedDoc.scope, kCBLDefaultScopeName);
    
    [replicatedDoc updateError: nil];
    AssertEqual(replicatedDoc.c4Error.code, 0);
    AssertEqual(replicatedDoc.c4Error.domain, 0);
    AssertNil(replicatedDoc.error);
}

# pragma mark - Change Listener

- (void) testRemoveChangeListnener {
    XCTestExpectation* exp1 = [self expectationWithDescription: @"Replicator Stopped"];
    XCTestExpectation* exp2 = [self expectationWithDescription: @"Replicator Stopped - Inverted"];
    exp2.inverted = YES;
    
    CBLReplicatorConfiguration* config = [self configWithTarget: kConnRefusedTarget
                                                           type: kCBLReplicatorTypePush
                                                     continuous: NO];
    config.maxAttempts = 1;
    repl = [[CBLReplicator alloc] initWithConfig: config];
    id token1 = [repl addChangeListener: ^(CBLReplicatorChange * c) {
        if (c.status.activity == kCBLReplicatorStopped) {
            [exp1 fulfill];
        }
    }];
    
    id<CBLListenerToken> token2 = [repl addChangeListener: ^(CBLReplicatorChange * c) {
        [exp2 fulfill];
    }];
    [token2 remove];
    
    [repl start];
    [self waitForExpectations: @[exp1, exp2] timeout: kExpTimeout];
    [token1 remove];
}

@end
