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

#define kDocIdFormat @"doc-%d"
#define kActionKey @"action-key"

@interface ReplicatorTest_PendingDocIds : ReplicatorTest

@end

@implementation ReplicatorTest_PendingDocIds

#ifdef COUCHBASE_ENTERPRISE

#pragma mark - Helper Methods

- (void) createDocs: (int)count action: (NSString*)action {
    for (int i = 0; i < count; i++) {
        NSString* docId = [NSString stringWithFormat: kDocIdFormat, i];
        CBLMutableDocument* doc = [self createDocument: docId];
        [doc setString: action forKey: kActionKey];
        [self saveDocument: doc];
    }
}

- (void) updateDocs: (int)count action: (NSString*)action {
    for (int i = 0; i < count; i++) {
        NSString* docId = [NSString stringWithFormat: kDocIdFormat, i];
        CBLMutableDocument* doc = [[self.db documentWithID: docId] toMutable];
        [doc setString: action forKey: kActionKey];
        [self saveDocument: doc];
    }
}

- (void) deleteDocs: (int)count {
    for (int i = 0; i < count; i++) {
        NSError* err = nil;
        NSString* docId = [NSString stringWithFormat: kDocIdFormat, i];
        CBLDocument* doc = [self.db documentWithID: docId];
        [self.db deleteDocument: doc error: &err];
        AssertNil(err);
    }
}

- (void) validatePendingDocumentIds: (nullable NSString*)action {
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: NO];

    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    __block BOOL finishReplicating = NO;
    __weak typeof(self) wSelf = self;
    [self run: config reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
        replicator = r;
        
        [replicator addDocumentReplicationListener:^(CBLDocumentReplication * docRepl) {
            finishReplicating = YES;
        }];
        
        token = [replicator addChangeListener: ^(CBLReplicatorChange* change) {
            __strong id strongSelf = wSelf;
            
            NSError* err = nil;
            NSSet* docIds = [change.replicator pendingDocumentIds: &err];
            XCTAssertNil(err);
            
            if (action)
                [strongSelf validateAction: action forDocIds: docIds];
            
            if (change.status.activity == kCBLReplicatorConnecting) {
                XCTAssert(docIds.count == 5u);
            } else if (change.status.activity == kCBLReplicatorStopped) {
                XCTAssertEqual(docIds.count, 0);
            }
        }];
    }];
    [replicator removeChangeListenerWithToken: token];
}

- (void) validateAction: (NSString*)action forDocIds: (NSSet*)docIds {
    for (NSString* docId in docIds) {
        CBLDocument* doc = [self.db documentWithID: docId];
        AssertEqualObjects([doc stringForKey: kActionKey], action);
    }
}

#pragma mark - Unit Tests

- (void) testPendingDocIDsPullOnlyException {
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO];
    
    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    __weak typeof(self) wSelf = self;
    [self run: config reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
        replicator = r;
        
        token = [replicator addChangeListener: ^(CBLReplicatorChange* change) {
            if (change.status.activity == kCBLReplicatorBusy) {
                [wSelf expectError: CBLErrorDomain code: CBLErrorUnsupported in: ^BOOL(NSError** err) {
                    return [change.replicator pendingDocumentIds: err].count != 0;
                }];
            }
        }];
    }];
    
    [replicator removeChangeListenerWithToken: token];
}

- (void) testPendingDocIDs {
    NSString* action = @"create";
    int total = 5;
    [self createDocs: total action: action];
    [self validatePendingDocumentIds: action];
    
    action = @"update";
    [self updateDocs: total action: action];
    [self validatePendingDocumentIds: action];
    
    [self deleteDocs: total];
    [self validatePendingDocumentIds: nil];
}

#endif

@end
