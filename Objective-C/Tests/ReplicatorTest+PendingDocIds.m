//
//  ReplicatorTest+PendingDocIds
//  CouchbaseLite
//
//  Copyright (c) 2019 Couchbase, Inc All rights reserved.
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

@interface ReplicatorTest_PendingDocIds : ReplicatorTest

@end

@implementation ReplicatorTest_PendingDocIds

#ifdef COUCHBASE_ENTERPRISE

- (void) testPendingDocIDsPullOnlyException {
    [self generateDocumentWithID: @"doc1"];
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO];
    
    repl = [[CBLReplicator alloc] initWithConfig: config];
    
    XCTestExpectation* x1 = [self expectationWithDescription: @"Replicator Busy"];
    __weak typeof(self) wSelf = self;
    id token = [repl addChangeListener: ^(CBLReplicatorChange* change) {
        if (change.status.activity == kCBLReplicatorBusy) {
            [wSelf expectError: CBLErrorDomain code: CBLErrorUnsupported in: ^BOOL(NSError** err) {
                return [change.replicator pendingDocumentIds: err].count != 0;
            }];
        } else if (change.status.activity == kCBLReplicatorStopped) {
            [x1 fulfill];
        }
    }];
    
    [repl start];
    [self waitForExpectations: @[x1] timeout: 5.0];
    [repl removeChangeListenerWithToken: token];
    repl = nil;
}

- (void) testPendingDocIDs {
    CBLMutableDocument* doc = [self createDocument: @"1"];
    [doc setString:@"Smokey" forKey:@"name"];
    [self saveDocument: doc];
    
    doc = [self createDocument: @"2"];
    [doc setString:@"Smokey" forKey:@"name"];
    [self saveDocument: doc];
    
    doc = [self createDocument: @"3"];
    [doc setString:@"Smokey" forKey:@"name"];
    [self saveDocument: doc];
    
    doc = [self createDocument: @"4"];
    [doc setString:@"Smokey" forKey:@"name"];
    [self saveDocument: doc];
    
    doc = [self createDocument: @"5"];
    [doc setString:@"Smokey" forKey:@"name"];
    [self saveDocument: doc];
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: NO];

    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    __block BOOL finishReplicating = NO;
    [self run: config reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
        replicator = r;
        
        [replicator addDocumentReplicationListener:^(CBLDocumentReplication * docRepl) {
            finishReplicating = YES;
        }];
        
        token = [replicator addChangeListener: ^(CBLReplicatorChange* change) {
            NSError* err = nil;
            if (change.status.activity == kCBLReplicatorConnecting) {
                XCTAssert([change.replicator pendingDocumentIds: &err].count == 5u);
                XCTAssertNil(err);
                
            } else if (change.status.activity == kCBLReplicatorBusy) {
                if (!finishReplicating) {
                    XCTAssert([change.replicator pendingDocumentIds: &err].count != 0);
                    XCTAssertNil(err);
                }
            } else if (change.status.activity == kCBLReplicatorStopped) {
                XCTAssert([change.replicator pendingDocumentIds: &err].count == 0);
                XCTAssertNil(err);
            }
        }];
    }];
    [replicator removeChangeListenerWithToken: token];
}

#endif

@end
