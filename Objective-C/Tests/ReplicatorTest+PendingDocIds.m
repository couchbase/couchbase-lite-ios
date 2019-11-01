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
#define kNoOfDocument 5
#define kCreateActionValue @"doc-create"
#define kUpdateActionValue @"doc-update"

@interface ReplicatorTest_PendingDocIds : ReplicatorTest

@end

@implementation ReplicatorTest_PendingDocIds

#ifdef COUCHBASE_ENTERPRISE

#pragma mark - Helper Methods

- (NSSet*) createDocs {
    NSMutableSet<NSString*>* docIds = [NSMutableSet set];
    for (int i = 0; i < kNoOfDocument; i++) {
        NSString* docId = [NSString stringWithFormat: kDocIdFormat, i];
        CBLMutableDocument* doc = [self createDocument: docId];
        [doc setString: kCreateActionValue forKey: kActionKey];
        [self saveDocument: doc];
        [docIds addObject: docId];
    }
    return [NSSet setWithSet: docIds];
}

- (void) validatePendingDocumentIds: (NSSet*)docIds action: (nullable NSString*)action count: (NSUInteger)count {
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: NO];

    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    __weak typeof(self) wSelf = self;
    [self run: config reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
        replicator = r;
        
        token = [replicator addChangeListener: ^(CBLReplicatorChange* change) {
            __strong id strongSelf = wSelf;
            
            NSError* err = nil;
            NSSet* ids = [change.replicator pendingDocumentIds: &err];
            AssertNil(err);
            
            if (action)
                [strongSelf validateAction: action forDocIds: ids];
            
            if (change.status.activity == kCBLReplicatorConnecting) {
                Assert([ids isEqualToSet: docIds]);
                AssertEqual(ids.count, count);
            } else if (change.status.activity == kCBLReplicatorStopped) {
                AssertEqual(ids.count, 0);
            }
        }];
    }];
    [replicator removeChangeListenerWithToken: token];
}

- (void) validateIsDocumentPending: (NSString*)docId isPresent: (BOOL)isPresent {
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: NO];

    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    [self run: config reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
        replicator = r;
        
        token = [replicator addChangeListener: ^(CBLReplicatorChange* change) {
            NSError* err = nil;
            BOOL present = [change.replicator isDocumentPending: docId error: &err];
            AssertNil(err);
            
            if (change.status.activity == kCBLReplicatorConnecting) {
                AssertEqual(present, isPresent);
            } else if (change.status.activity == kCBLReplicatorStopped) {
                AssertEqual(present, NO);
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
#pragma mark - pendingDocumentIds API

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

- (void) testPendingDocIDsWithCreate {
    NSSet* docIds = [self createDocs];
    [self validatePendingDocumentIds: docIds action: kCreateActionValue count: kNoOfDocument];
}

- (void) testPendingDocIDsWithEdit {
    NSSet* docIds = [self createDocs];
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePushAndPull continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    // update all docs
    for (NSString* docId in docIds) {
        CBLMutableDocument* doc = [[self.db documentWithID: docId] toMutable];
        [doc setString: kUpdateActionValue forKey: kActionKey];
        [self saveDocument: doc];
    }
    [self validatePendingDocumentIds: docIds action: kUpdateActionValue count: kNoOfDocument];
}

- (void) testPendingDocIdsWithDelete {
    NSSet* docIds = [self createDocs];
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePushAndPull continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    // delete all docs
    for (NSString* docId in docIds) {
        NSError* err = nil;
        CBLDocument* doc = [self.db documentWithID: docId];
        [self.db deleteDocument: doc error: &err];
        AssertNil(err);
    }
    [self validatePendingDocumentIds: docIds action: nil count: kNoOfDocument];
}

- (void) testPendingDocIdsWithPurge {
    NSSet* docIds = [self createDocs];
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePushAndPull continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    // purge random doc
    NSError* err = nil;
    int i = arc4random_uniform(kNoOfDocument);
    NSString* docId = [NSString stringWithFormat: kDocIdFormat, i];
    CBLDocument* doc = [self.db documentWithID: docId];
    [self.db purgeDocument: doc error: &err];
    AssertNil(err);
    
    NSMutableSet* updatedDocIds = [NSMutableSet setWithSet: docIds];
    [updatedDocIds removeObject: docId];
    [self validatePendingDocumentIds: updatedDocIds
                              action: nil
                               count: kNoOfDocument - 1];
}

#pragma mark - IsDocumentPending API

- (void) testIsDocumentPendingPullOnlyException {
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
                    return [change.replicator isDocumentPending: @"document-id" error: err];
                }];
            }
        }];
    }];
    
    [replicator removeChangeListenerWithToken: token];
}

- (void) _testIsDocumentPendingWithCreate {
    NSString* docId = @"doc-1";
    CBLMutableDocument* doc = [self createDocument: docId];
    [doc setString: kCreateActionValue forKey: kActionKey];
    [self saveDocument: doc];
    
    [self validateIsDocumentPending: docId isPresent: YES];
    
    docId = @"doc-2";
    doc = [self createDocument: docId];
    [doc setString: kCreateActionValue forKey: kActionKey];
    [self saveDocument: doc];
    [self validateIsDocumentPending: @"no-doc" isPresent: NO];
}

- (void) _testIsDocumentPendingWithUpdate {
    NSString* docId = @"doc-1";
    CBLMutableDocument* doc = [self createDocument: docId];
    [doc setString: kCreateActionValue forKey: kActionKey];
    [self saveDocument: doc];
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePushAndPull continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    // update doc
    doc = [[self.db documentWithID: docId] toMutable];
    [doc setString: @"udpate1" forKey: kActionKey];
    [self saveDocument: doc];
    
    [self validateIsDocumentPending: docId isPresent: YES];
    
    // update doc
    doc = [[self.db documentWithID: docId] toMutable];
    [doc setString: @"update2" forKey: kActionKey];
    [self saveDocument: doc];
    [self validateIsDocumentPending: @"no-doc" isPresent: NO];
}

#endif

@end
