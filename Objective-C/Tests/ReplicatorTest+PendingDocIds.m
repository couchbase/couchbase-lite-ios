//
//  ReplicatorTest+PendingDocIds
//  CouchbaseLite
//
//  Copyright (c) 2020 Couchbase, Inc All rights reserved.
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
#import "CBLReplicator+Internal.h"

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
        [self saveDocument: doc collection: self.defaultCollection];
        [docIds addObject: docId];
    }
    return [NSSet setWithSet: docIds];
}

- (void) validatePendingDocumentIDs: (NSSet*)docIds pushOnlyDocIds: (nullable NSSet*)pushOnlyDocIds {
    NSError* err;
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    
    
    CBLReplicatorConfiguration* rConfig = [self configForCollection: self.defaultCollection target: target configBlock:^(CBLCollectionConfiguration* config) {
        if (pushOnlyDocIds.count > 0) {
            config.pushFilter = ^BOOL(CBLDocument* document, CBLDocumentFlags flags) {
                return [pushOnlyDocIds containsObject: document.id];
            };
        }
    }];
    rConfig.replicatorType = kCBLReplicatorTypePush;
    CBLReplicator* replicator = [[CBLReplicator alloc] initWithConfig: rConfig];
    
    // Check document pendings:
    NSSet* pendingIds = [replicator pendingDocumentIDsForCollection: self.defaultCollection error: &err];
    AssertNotNil(pendingIds);
    AssertEqual(pendingIds.count, pushOnlyDocIds.count == 0 ? docIds.count : pushOnlyDocIds.count);
    
    for (NSString* docId in docIds) {
        Boolean willBePush = pushOnlyDocIds.count == 0 || [pushOnlyDocIds containsObject: docId];
        if (willBePush) {
            Assert([pendingIds containsObject: docId]);
            Assert([replicator isDocumentPending: docId collection: self.defaultCollection error: &err]);
            AssertNil(err);
        }
    }
    
    // Run replicator:
    [self runWithReplicator: replicator errorCode: 0 errorDomain: nil];
    
    // Check document pending:
    pendingIds = [replicator pendingDocumentIDsForCollection: self.defaultCollection error: &err];
    AssertNotNil(pendingIds);
    AssertEqual(pendingIds.count, 0);
    
    for (NSString* docId in docIds) {
        Assert(![replicator isDocumentPending: docId collection: self.defaultCollection error: &err]);
        AssertNil(err);
    }
}

#pragma mark - Unit Tests

#pragma mark - Pending Document API

- (void) testPendingDocIDsPullOnlyException {
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO];
    CBLReplicator* replicator = [[CBLReplicator alloc] initWithConfig: config];

    [self expectError: CBLErrorDomain code: CBLErrorUnsupported in: ^BOOL(NSError** err) {
        return [replicator pendingDocumentIDsForCollection: self.defaultCollection error: err].count != 0;
    }];
}

- (void) testPendingDocIDsWithCreate {
    NSSet* docIds = [self createDocs];
    [self validatePendingDocumentIDs: docIds pushOnlyDocIds: nil];
}

- (void) testPendingDocIDsWithUpdate {
    NSError* error;
    [self createDocs];
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePushAndPull continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];

    // Update all docs:
    NSSet* updatedDocIds = [NSSet setWithObjects: @"doc-1", @"doc-2", nil];
    for (NSString* docId in updatedDocIds) {
        CBLMutableDocument* doc = [[self.defaultCollection documentWithID: docId error: &error] toMutable];
        [doc setString: kUpdateActionValue forKey: kActionKey];
        [self saveDocument: doc collection: self.defaultCollection];
    }

    [self validatePendingDocumentIDs: updatedDocIds pushOnlyDocIds: nil];
}

- (void) testPendingDocIdsWithDelete {
    [self createDocs];
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePushAndPull continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];

    // delete all docs
    NSSet* updatedDocIds = [NSSet setWithObjects: @"doc-1", @"doc-2", nil];
    for (NSString* docId in updatedDocIds) {
        NSError* err = nil;
        CBLDocument* doc = [self.defaultCollection documentWithID: docId error: &err];
        [self.defaultCollection deleteDocument: doc error: &err];
        AssertNil(err);
    }
    [self validatePendingDocumentIDs: updatedDocIds pushOnlyDocIds: nil];
}

- (void) testPendingDocIdsWithPurge {
    NSSet* docIds = [self createDocs];

    // Purge a doc:
    NSError* err = nil;
    CBLDocument* doc = [self.defaultCollection documentWithID: @"doc-3" error: &err];
    [self.defaultCollection purgeDocument: doc error: &err];
    AssertNil(err);

    NSMutableSet* updatedDocIds = [NSMutableSet setWithSet: docIds];
    [updatedDocIds removeObject: @"doc-3"];
    [self validatePendingDocumentIDs: updatedDocIds pushOnlyDocIds: nil];
}

- (void) testPendingDocIdsWithFilter {
    NSSet* docIds = [self createDocs];
    
    NSSet* pushDocIds = [NSSet setWithObjects: @"doc-2", @"doc-4", nil];
    [self validatePendingDocumentIDs: docIds pushOnlyDocIds: pushDocIds];
}

- (void) testPendingDocumentIdsWithDatabaseClosed {
    NSError* error = nil;
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    
    CBLCollection* collection = self.defaultCollection;
    CBLReplicatorConfiguration* rConfig = [self configForCollection: collection target: target configBlock: nil];
    rConfig.replicatorType = kCBLReplicatorTypePush;
    CBLReplicator* replicator = [[CBLReplicator alloc] initWithConfig: rConfig];

    [self.db close: &error];
    [self expectException: @"NSInternalInconsistencyException" in: ^{
        [replicator pendingDocumentIDsForCollection: collection  error: nil];
    }];
}

#endif

@end
