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

- (void) validatePendingDocumentIds: (NSSet*)docIds count: (NSUInteger)count {
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: NO];

    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    [self run: config reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
        // FIXME: Check pending-document-id before starting the replicator. depends on #2569
        replicator = r;
        
        token = [replicator addChangeListener: ^(CBLReplicatorChange* change) {
            
            NSError* err = nil;
            NSSet* ids = [change.replicator pendingDocumentIds: &err];
            AssertNil(err);
            
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

// expected = @{"doc-1": YES, @"doc-2": NO, @"doc-3": NO}
- (void) validateIsDocumentPending: (NSDictionary*)expected {
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: NO];

    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    [self run: config reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
        // FIXME: Check pending-document-id before starting the replicator. depends on #2569
        replicator = r;
        
        token = [replicator addChangeListener: ^(CBLReplicatorChange* change) {
            if (change.status.activity == kCBLReplicatorConnecting) {
                for (NSString* key in expected.keyEnumerator) {
                    NSError* err = nil;
                    BOOL present = [change.replicator isDocumentPending: key error: &err];
                    AssertNil(err);
                    
                    AssertEqual(present, [[expected objectForKey: key] isEqual: @YES]);
                }
                
            } else if (change.status.activity == kCBLReplicatorStopped) {
                // all docs should be done when status is stopped
                for (NSString* key in expected.keyEnumerator) {
                    NSError* err = nil;
                    BOOL present = [change.replicator isDocumentPending: key error: &err];
                    AssertNil(err);
                    
                    AssertEqual(present, NO);
                }
            }
        }];
    }];
    [replicator removeChangeListenerWithToken: token];
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
    [self validatePendingDocumentIds: docIds count: kNoOfDocument];
}

- (void) testPendingDocIDsWithUpdate {
    [self createDocs];
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePushAndPull continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    // update all docs
    NSSet* updatedDocIds = [NSSet setWithObjects: @"doc-1", @"doc-2", nil];
    for (NSString* docId in updatedDocIds) {
        CBLMutableDocument* doc = [[self.db documentWithID: docId] toMutable];
        [doc setString: kUpdateActionValue forKey: kActionKey];
        [self saveDocument: doc];
    }
    
    [self validatePendingDocumentIds: updatedDocIds count: updatedDocIds.count];
}

- (void) testPendingDocIdsWithDelete {
    [self createDocs];
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePushAndPull continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    // delete all docs
    NSSet* updatedDocIds = [NSSet setWithObjects: @"doc-1", @"doc-2", nil];
    for (NSString* docId in updatedDocIds) {
        NSError* err = nil;
        CBLDocument* doc = [self.db documentWithID: docId];
        [self.db deleteDocument: doc error: &err];
        AssertNil(err);
    }
    [self validatePendingDocumentIds: updatedDocIds count: updatedDocIds.count];
}

- (void) testPendingDocIdsWithPurge {
    NSSet* docIds = [self createDocs];
    
    // purge random doc
    NSError* err = nil;
    CBLDocument* doc = [self.db documentWithID: @"doc-3"];
    [self.db purgeDocument: doc error: &err];
    AssertNil(err);
    
    NSMutableSet* updatedDocIds = [NSMutableSet setWithSet: docIds];
    [updatedDocIds removeObject: @"doc-3"];
    [self validatePendingDocumentIds: updatedDocIds count: kNoOfDocument - 1];
}

- (void) testPendingDocIdsWithFilter {
    [self createDocs];
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    CBLReplicatorConfiguration* config = [self configWithTarget: target
                                                           type: kCBLReplicatorTypePush
                                                     continuous: NO];
    int i = arc4random_uniform(kNoOfDocument);
    NSString* docId = [NSString stringWithFormat: kDocIdFormat, i];
    config.pushFilter = ^BOOL(CBLDocument* document, CBLDocumentFlags flags) {
        return [document.id isEqualToString: docId];
    };

    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    __block NSSet* docIds = [NSSet setWithObject: docId];
    [self run: config reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
        replicator = r;
        
        token = [replicator addChangeListener: ^(CBLReplicatorChange* change) {
            
            NSError* err = nil;
            NSSet* ids = [change.replicator pendingDocumentIds: &err];
            AssertNil(err);
            
            if (change.status.activity == kCBLReplicatorConnecting) {
                Assert([ids isEqualToSet: docIds]);
                AssertEqual(ids.count, 1);
            } else if (change.status.activity == kCBLReplicatorStopped) {
                AssertEqual(ids.count, 0);
            }
        }];
    }];
    [replicator removeChangeListenerWithToken: token];
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

- (void) testIsDocumentPendingWithCreate {
    NSString* docId = @"doc-1";
    CBLMutableDocument* doc = [self createDocument: docId];
    [doc setString: kCreateActionValue forKey: kActionKey];
    [self saveDocument: doc];
    
    [self validateIsDocumentPending: @{docId: @YES, @"doc-2": @NO}];
}

- (void) testIsDocumentPendingWithUpdate {
    [self createDocs];
    
    // sync it to otherdb
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePushAndPull continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    // update doc
    CBLMutableDocument* doc = [[self.db documentWithID: @"doc-1"] toMutable];
    [doc setString: @"update1" forKey: kActionKey];
    [self saveDocument: doc];
    [self validateIsDocumentPending: @{@"doc-1": @YES, @"doc-2": @NO}];
}

- (void) testIsDocumentPendingWithDelete {
    [self createDocs];
    
    // sync to otherdb
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target
                                  type: kCBLReplicatorTypePushAndPull
                            continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    // delete doc-1
    NSError* error = nil;
    [self.db deleteDocument: [self.db documentWithID: @"doc-1"] error: &error];
    [self validateIsDocumentPending: @{@"doc-1": @YES, @"doc-2": @NO}];
}

- (void) testIsDocumentPendingWithPurge {
    [self createDocs];
    
    // sync to otherdb
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target
                                  type: kCBLReplicatorTypePushAndPull
                            continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    // purge
    NSError* error = nil;
    [self.db purgeDocumentWithID: @"doc-3" error: &error];
    [self validateIsDocumentPending: @{@"doc-3": @NO, @"doc-2": @NO}];
}

- (void) testIsDocumentPendingWithPushFilter {
    [self createDocs];
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    CBLReplicatorConfiguration* config = [self configWithTarget: target
                                                           type: kCBLReplicatorTypePush
                                                     continuous: NO];
    config.pushFilter = ^BOOL(CBLDocument* document, CBLDocumentFlags flags) {
        return [document.id isEqualToString: @"doc-1"];
    };

    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    [self run: config reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
        replicator = r;
        
        token = [replicator addChangeListener: ^(CBLReplicatorChange* change) {
            NSError* err = nil;
            BOOL present = [change.replicator isDocumentPending: @"doc-1" error: &err];
            AssertNil(err);
            
            AssertFalse([change.replicator isDocumentPending: @"doc-2" error: &err]);
            AssertNil(err);
            
            AssertFalse([change.replicator isDocumentPending: @"no-doc" error: &err]);
            AssertNil(err);
            
            if (change.status.activity == kCBLReplicatorConnecting) {
                AssertEqual(present, YES);
            } else if (change.status.activity == kCBLReplicatorStopped) {
                AssertEqual(present, NO);
            }
        }];
    }];
    [replicator removeChangeListenerWithToken: token];
}

#endif

@end
