//
//  ReplicatorTest+CustomConflict
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
#import "CBLDocument+Internal.h"
#import "CBLErrorMessage.h"
#import "CBLReplicator+Internal.h"
#import "CBLTestCustomLogSink.h"

@interface ReplicatorTest_CustomConflict : ReplicatorTest
@end

@implementation ReplicatorTest_CustomConflict {
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

#pragma mark - Tests without replication

- (void) testConflictResolverConfigProperty {
    TestConflictResolver* resolver;
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.remoteDocument;
    }];
    
    id foo = [[CBLURLEndpoint alloc] initWithURL: [NSURL URLWithString: @"wss://foo"]];
    CBLReplicatorConfiguration* rConfig = [self configForCollection: self.defaultCollection target: foo configBlock:^(CBLCollectionConfiguration* config) {
        config.conflictResolver = resolver;
    }];
    
    rConfig.replicatorType = kCBLReplicatorTypePull;
    repl = [[CBLReplicator alloc] initWithConfig: rConfig];
    
    // checks whether the conflict resolver can be set-to/get-from config
    AssertNotNil(rConfig.collectionConfigs[0].conflictResolver);
    AssertEqualObjects(rConfig.collectionConfigs[0].conflictResolver, resolver);
    AssertNotNil(repl.config.collectionConfigs[0].conflictResolver);
    AssertEqualObjects(repl.config.collectionConfigs[0].conflictResolver, resolver);
}

#pragma mark - Tests with replication

- (void) makeConflictFor: (NSString*)docID
               withLocal: (nullable NSDictionary*) localData
              withRemote: (nullable NSDictionary*) remoteData {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: docID];
    Assert([self.defaultCollection saveDocument: doc1 error: &error]);
    
    CBLReplicatorConfiguration* rConfig = [self configForCollection: self.defaultCollection
                                                             target: _target
                                                        configBlock: nil];
    rConfig.replicatorType = kCBLReplicatorTypePush;
    
    [self run: rConfig errorCode: 0 errorDomain: nil];
    
    // Now make different changes in db and otherDB:
    doc1 = [[self.defaultCollection documentWithID: docID error: &error] toMutable];
    if (localData) {
        [doc1 setData: localData];
        Assert([self.defaultCollection saveDocument: doc1 error: &error]);
    } else {
        Assert([self.defaultCollection deleteDocument: doc1 error: &error]);
    }
    
    // pass the remote revision
    CBLMutableDocument* doc2 = [[self.otherDBDefaultCollection documentWithID: docID error: &error] toMutable];
    if (remoteData) {
        [doc2 setData: remoteData];
        Assert([self.otherDBDefaultCollection saveDocument: doc2 error: &error]);
    } else {
        Assert([self.otherDBDefaultCollection deleteDocument: doc2 error: &error]);
    }
}

- (void) testConflictResolverRemoteWins {
    TestConflictResolver* resolver;
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.remoteDocument;
    }];
    
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    
    CBLReplicatorConfiguration* rConfig = [self configForCollection: self.defaultCollection
                                                             target: _target
                                                        configBlock:^(CBLCollectionConfiguration* config) {
        config.conflictResolver = resolver;
    }];
    rConfig.replicatorType = kCBLReplicatorTypePull;
    
    [self run: rConfig errorCode: 0 errorDomain: nil];
    
    // Check that it was resolved:
    AssertEqual(self.defaultCollection.count, 1u);
    AssertEqualObjects([self.defaultCollection documentWithID: docId error: nil].toDictionary, remoteData);
    
    UInt64 sequenceBeforePush = [self.otherDBDefaultCollection documentWithID: docId error: nil].sequence;
    
    rConfig.replicatorType = kCBLReplicatorTypePush;
    [self run: rConfig errorCode: 0 errorDomain: nil];
    
    // should be equal, so that nothing has pushed to remote
    AssertEqual(sequenceBeforePush, [self.otherDBDefaultCollection documentWithID: docId error: nil].sequence);
}

- (void) testConflictResolverLocalWins {
    TestConflictResolver* resolver;
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.localDocument;
    }];
    
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    
    CBLReplicatorConfiguration* rConfig = [self configForCollection: self.defaultCollection
                                                             target: _target
                                                        configBlock:^(CBLCollectionConfiguration* config) {
        config.conflictResolver = resolver;
    }];
    
    rConfig.replicatorType = kCBLReplicatorTypePull;

    [self run: rConfig errorCode: 0 errorDomain: nil];
    
    // Check that it was resolved:
    AssertEqual(self.defaultCollection.count, 1u);
    AssertEqualObjects([self.defaultCollection documentWithID: docId error: nil].toDictionary, localData);
    
    UInt64 sequenceBeforePush = [self.otherDBDefaultCollection documentWithID: docId error: nil].sequence;
    
    rConfig.replicatorType = kCBLReplicatorTypePush;
    [self run: rConfig errorCode: 0 errorDomain: nil];
    
    // there was changes to push to remote, and sequence increased
    Assert(sequenceBeforePush < [self.otherDBDefaultCollection documentWithID: docId error: nil].sequence);
}

- (void) testConflictResolverNullDoc {
    TestConflictResolver* resolver;
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return nil;
    }];
    
    NSError* error;
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    
    CBLReplicatorConfiguration* rConfig = [self configForCollection: self.defaultCollection
                                                             target: _target
                                                        configBlock:^(CBLCollectionConfiguration* config) {
        config.conflictResolver = resolver;
    }];
    rConfig.replicatorType = kCBLReplicatorTypePull;
    
    [self run: rConfig errorCode: 0 errorDomain: nil];
    
    // Check whether the document is deleted, and returns null.
    AssertEqual(self.defaultCollection.count, 0u);
    AssertNil([self.defaultCollection documentWithID: docId error: &error]);
    
    UInt64 sequenceBeforePush = [self.otherDBDefaultCollection documentWithID: docId error: nil].sequence;
    
    rConfig.replicatorType = kCBLReplicatorTypePush;
    [self run: rConfig errorCode: 0 errorDomain: nil];
    
    // should be greater, so that it pushed new revision to remote
    Assert(sequenceBeforePush < [[CBLDocument alloc] initWithCollection: self.otherDBDefaultCollection
                                                             documentID: docId
                                                         includeDeleted: YES
                                                                  error: &error].sequence);
}

/** https://github.com/couchbaselabs/couchbase-lite-api/blob/master/spec/tests/T0005-Version-Vector.md 
 Test 4. DefaultConflictResolverDeleteWins -> testConflictResolverDeletedLocalWins + testConflictResolverDeletedRemoteWins
 */

- (void) testConflictResolverDeletedLocalWins {
    TestConflictResolver* resolver;
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return nil;
    }];
    
    NSError* error;
    NSString* docId = @"doc";
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: nil withRemote: remoteData];
    
    CBLReplicatorConfiguration* rConfig = [self configForCollection: self.defaultCollection
                                                             target: _target
                                                        configBlock:^(CBLCollectionConfiguration* config) {
        config.conflictResolver = resolver;
    }];
    rConfig.replicatorType = kCBLReplicatorTypePull;
    
    [self run: rConfig errorCode: 0 errorDomain: nil];
    
    // Check whether the document gets deleted and return null.
    AssertEqual(self.defaultCollection.count, 0u);
    AssertNil([self.defaultCollection documentWithID: @"doc" error: &error]);

    UInt64 sequenceBeforePush = [self.otherDBDefaultCollection documentWithID: docId error: nil].sequence;
    
    rConfig.replicatorType = kCBLReplicatorTypePush;
    [self run: rConfig errorCode: 0 errorDomain: nil];
    
    // should be greater, so that it pushed new revision to remote
    Assert(sequenceBeforePush < [[CBLDocument alloc] initWithCollection: self.otherDBDefaultCollection
                                                             documentID: docId
                                                         includeDeleted: YES
                                                                  error: &error].sequence);
}

- (void) testConflictResolverDeletedRemoteWins {
    TestConflictResolver* resolver;
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return nil;
    }];
    
    NSError* error;
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    [self makeConflictFor: docId withLocal: localData withRemote: nil];
    
    CBLReplicatorConfiguration* rConfig = [self configForCollection: self.defaultCollection
                                                             target: _target
                                                        configBlock:^(CBLCollectionConfiguration* config) {
        config.conflictResolver = resolver;
    }];
    rConfig.replicatorType = kCBLReplicatorTypePull;
    
    [self run: rConfig errorCode: 0 errorDomain: nil];
    
    // Check whether it deletes the document and returns nil.
    AssertEqual(self.defaultCollection.count, 0u);
    AssertNil([self.defaultCollection documentWithID: @"doc" error: &error]);
    
    CBLCollection* c = [self.otherDB defaultCollection: nil];
    UInt64 sequenceBeforePush = [[CBLDocument alloc] initWithCollection: c
                                                             documentID: docId
                                                         includeDeleted: YES
                                                                  error: &error].sequence;
    
    rConfig.replicatorType = kCBLReplicatorTypePush;
    [self run: rConfig errorCode: 0 errorDomain: nil];
    
    // The deleted doc shouldn't be pushed to the remote DB:
    AssertEqual(sequenceBeforePush, [[CBLDocument alloc] initWithCollection: c
                                                                 documentID: docId
                                                             includeDeleted: YES
                                                                      error: &error].sequence);
}

- (void) testConflictResolverDeletedBothRev {
    NSError* error;
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    TestConflictResolver* resolver;
    __block int count = 0;
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        count++;
        AssertNil(con.remoteDocument);
        AssertNotNil(con.localDocument);
        NSError* err;
        [self.defaultCollection deleteDocument: [self.defaultCollection documentWithID: docId error: nil]
                                         error: &err];
        return nil;
    }];
    
    [self makeConflictFor: docId withLocal: localData withRemote: nil];
    
    CBLReplicatorConfiguration* rConfig = [self configForCollection: self.defaultCollection
                                                             target: _target
                                                        configBlock:^(CBLCollectionConfiguration* config) {
        config.conflictResolver = resolver;
    }];
    rConfig.replicatorType = kCBLReplicatorTypePull;
    
    // Skip exception breakpoint thrown from c4doc_resolve
    [self ignoreException:^{
        [self run: rConfig errorCode: 0 errorDomain: nil];
    }];
    
    // it should only call resolver once. 
    // since second time, both revisions are deleted, and automatically resolve
    AssertEqual(count, 1);
    
    // Check whether it deletes the document and returns nil.
    AssertEqual(self.defaultCollection.count, 0u);
    AssertNil([self.defaultCollection documentWithID: @"doc" error: &error]);
}

- (void) testConflictResolverMergeDoc {
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    TestConflictResolver* resolver;
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        CBLMutableDocument* mDoc = con.localDocument.toMutable;
        [mDoc setString: @"local" forKey: @"edit"];
        return mDoc;
    }];
    
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    
    CBLReplicatorConfiguration* rConfig1 = [self configForCollection: self.defaultCollection
                                                              target: _target
                                                         configBlock:^(CBLCollectionConfiguration* config) {
         config.conflictResolver = resolver;
    }];
    rConfig1.replicatorType = kCBLReplicatorTypePull;
    
    // EDIT LOCAL DOCUMENT
    [self run: rConfig1 errorCode: 0 errorDomain: nil];
    
    NSMutableDictionary* exp = [NSMutableDictionary dictionaryWithDictionary: localData];
    [exp setValue: @"local" forKey: @"edit"];
    AssertEqualObjects([self.defaultCollection documentWithID: docId error: nil].toDictionary, exp);
    
    // make sure it updates remote doc
    UInt64 sequenceBeforePush = [self.otherDBDefaultCollection documentWithID: docId error: nil].sequence;
    
    rConfig1.replicatorType = kCBLReplicatorTypePush;
    [self run: rConfig1 errorCode: 0 errorDomain: nil];
    Assert(sequenceBeforePush < [self.otherDBDefaultCollection documentWithID: docId error: nil].sequence);
    
    // EDIT REMOTE DOCUMENT
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        CBLMutableDocument* mDoc = con.remoteDocument.toMutable;
        [mDoc setString: @"remote" forKey: @"edit"];
        return mDoc;
    }];
    
    CBLReplicatorConfiguration* rConfig2 = [self configForCollection: self.defaultCollection
                                                              target: _target
                                                         configBlock:^(CBLCollectionConfiguration* config) {
         config.conflictResolver = resolver;
    }];
    rConfig2.replicatorType = kCBLReplicatorTypePull;
    [self run: rConfig2 errorCode: 0 errorDomain: nil];
    
    exp = [NSMutableDictionary dictionaryWithDictionary: remoteData];
    [exp setValue: @"remote" forKey: @"edit"];
    AssertEqualObjects([self.defaultCollection documentWithID: docId error: nil].toDictionary, exp);
    
    // make sure it updates remote doc
    sequenceBeforePush = [self.otherDBDefaultCollection documentWithID: docId error: nil].sequence;
    
    rConfig2.replicatorType = kCBLReplicatorTypePush;
    [self run: rConfig2 errorCode: 0 errorDomain: nil];
    Assert(sequenceBeforePush < [self.otherDBDefaultCollection documentWithID: docId error: nil].sequence);
    
    // CREATE NEW DOCUMENT
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        CBLMutableDocument* mDoc = [[CBLMutableDocument alloc] initWithID: con.localDocument.id];
        [mDoc setString: @"new-with-same-ID" forKey: @"docType"];
        return mDoc;
    }];
    
    CBLReplicatorConfiguration* rConfig3 = [self configForCollection: self.defaultCollection
                                                              target: _target
                                                         configBlock:^(CBLCollectionConfiguration* config) {
         config.conflictResolver = resolver;
    }];
    rConfig3.replicatorType = kCBLReplicatorTypePull;
    [self run: rConfig3 errorCode: 0 errorDomain: nil];
    
    exp = [NSMutableDictionary dictionaryWithObject: @"new-with-same-ID" forKey: @"docType"];
    AssertEqualObjects([self.defaultCollection documentWithID: docId error: nil].toDictionary, exp);
    
    // make sure it updates remote doc
    sequenceBeforePush = [self.otherDBDefaultCollection documentWithID: docId error: nil].sequence;
    rConfig3.replicatorType = kCBLReplicatorTypePush;
    [self run: rConfig3 errorCode: 0 errorDomain: nil];
    Assert(sequenceBeforePush < [self.otherDBDefaultCollection documentWithID: docId error: nil].sequence);
}

- (void) testDocumentReplicationEventForConflictedDocs {
    TestConflictResolver* resolver;
    
    // when resolution is skipped: here doc from otherDB throws an exception & skips it
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return [self.otherDBDefaultCollection documentWithID: @"doc" error: nil];
    }];
    [self validateDocumentReplicationEventForConflictedDocs: resolver];
    
    // when resolution is successfull but wrong docID
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return [CBLMutableDocument documentWithID: @"wrongDocID"];
    }];
    [self validateDocumentReplicationEventForConflictedDocs: resolver];
    
    // when resolution is successfull.
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.remoteDocument;
    }];
    [self validateDocumentReplicationEventForConflictedDocs: resolver];
}

- (void) validateDocumentReplicationEventForConflictedDocs: (TestConflictResolver*)resolver {
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    
    CBLReplicatorConfiguration* rConfig = [self configForCollection: self.defaultCollection
                                                              target: _target
                                                         configBlock:^(CBLCollectionConfiguration* config) {
         config.conflictResolver = resolver;
    }];
    rConfig.replicatorType = kCBLReplicatorTypePull;
    
    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    __block NSMutableArray<NSString*>* docIds = [NSMutableArray array];
    [self ignoreException:^{
        [self run: rConfig reset: NO errorCode: 0 errorDomain: nil onReplicatorReady:^(CBLReplicator * r) {
            replicator = r;
            token = [r addDocumentReplicationListener:^(CBLDocumentReplication * docRepl) {
                for (CBLReplicatedDocument* replDoc in docRepl.documents) {
                    [docIds addObject: replDoc.id];
                }
            }];
        }];
    }];
    
    // make sure only single listener event is fired when conflict occured.
    AssertEqual(docIds.count, 1u);
    AssertEqualObjects(docIds.firstObject, docId);
    [token remove];
    
    // resolve any un-resolved conflict through pull replication.
    [self run: rConfig errorCode: 0 errorDomain: nil];
}

- (void) testConflictResolverCalledTwice {
    TestConflictResolver* resolver;
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    
    __block int count = 0;
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        count++;
        // update the doc will cause a second conflict
        CBLMutableDocument* savedDoc = [[self.defaultCollection documentWithID: docId error: nil] toMutable];
        if (![savedDoc booleanForKey: @"secondUpdate"]) {
            NSError* error;
            [savedDoc setBoolean: YES forKey: @"secondUpdate"];
            [self.defaultCollection saveDocument: savedDoc error: &error];
            AssertNil(error);
        }
        
        CBLMutableDocument* mDoc = con.localDocument.toMutable;
        [mDoc setString: @"local" forKey: @"edit"];
        return mDoc;
    }];
    
    CBLReplicatorConfiguration* rConfig = [self configForCollection: self.defaultCollection
                                                              target: _target
                                                         configBlock:^(CBLCollectionConfiguration* config) {
         config.conflictResolver = resolver;
    }];
    rConfig.replicatorType = kCBLReplicatorTypePull;
    
    // Skip exception breakpoint thrown from c4doc_resolve
    [self ignoreException:^{
        [self run: rConfig errorCode: 0 errorDomain: nil];
    }];
    
    // make sure the resolver method called twice due to second conflict
    AssertEqual(count, 2u);
    
    AssertEqual(self.defaultCollection.count, 1u);
    NSMutableDictionary* exp = [NSMutableDictionary dictionaryWithDictionary: localData];
    [exp setValue: @"local" forKey: @"edit"];
    [exp setValue: @YES forKey: @"secondUpdate"];
    AssertEqualObjects([self.defaultCollection documentWithID: docId error: nil].toDictionary, exp);
}

-  (void) testConflictResolverWrongDocID {
    TestConflictResolver* resolver;
    
    // Enable Logging to check whether the logs are printing
    CBLTestCustomLogSink* logSink = [[CBLTestCustomLogSink alloc] init];
    CBLLogSinks.custom = [[CBLCustomLogSink alloc] initWithLevel: kCBLLogLevelWarning logSink: logSink];
    
    NSString* docId = @"doc";
    NSString* wrongDocID = @"wrongDocID";
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        CBLMutableDocument* mDoc = [CBLMutableDocument documentWithID: wrongDocID];
        [mDoc setData: con.localDocument.toDictionary]; // update with local contents
        [mDoc setString: @"update" forKey: @"edit"]; // add one extra key-value
        return mDoc;
    }];
    
    CBLReplicatorConfiguration* rConfig = [self configForCollection: self.defaultCollection
                                                              target: _target
                                                         configBlock:^(CBLCollectionConfiguration* config) {
         config.conflictResolver = resolver;
    }];
    rConfig.replicatorType = kCBLReplicatorTypePull;
    
    // make sure resolver is thrown the exception and skips the resolution.
    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    __block NSMutableSet* docIds = [NSMutableSet set];
    [self run: rConfig reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
        replicator = r;
        token = [r addDocumentReplicationListener: ^(CBLDocumentReplication* docRepl) {
            if (docRepl.documents.count != 0) {
                AssertEqual(docRepl.documents.count, 1u);
                [docIds addObject: docRepl.documents.firstObject.id];
            }
            
            // shouldn't report an error from replicator
            AssertNil(docRepl.documents.firstObject.error);
        }];
    }];
    
    AssertEqual(self.defaultCollection.count, 1u);
    Assert([docIds containsObject: docId]);
    NSMutableDictionary* exp = [NSMutableDictionary dictionaryWithDictionary: localData];
    [exp setValue: @"update" forKey: @"edit"];
    AssertEqualObjects([self.defaultCollection documentWithID: docId error: nil].toDictionary, exp);

    // validate the warning message!
    NSString* warning = [NSString stringWithFormat: @"The document ID of the resolved document '%@'"
                         " is not matching with the document ID of the conflicting document '%@'.",
                         wrongDocID, docId];
    Assert([logSink.lines containsObject: warning]);
    [token remove];
    CBLLogSinks.custom = nil;
}

- (void) testConflictResolverDifferentDBDoc {
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    
    TestConflictResolver* resolver;
    __weak CBLCollection* weakOtherDBDefaulCollection = self.otherDBDefaultCollection;
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return [weakOtherDBDefaulCollection documentWithID: con.localDocument.id error: nil]; // doc from different DB!!
    }];
    
    CBLReplicatorConfiguration* rConfig1 = [self configForCollection: self.defaultCollection
                                                              target: _target
                                                         configBlock:^(CBLCollectionConfiguration* config) {
         config.conflictResolver = resolver;
     }];
    rConfig1.replicatorType = kCBLReplicatorTypePull;
    
    // make sure resolver is thrown the exception and skips the resolution.
    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    __block NSMutableArray<NSError*>* errors = [NSMutableArray array];
    [self ignoreException: ^{
        [self run: rConfig1 reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
            replicator = r;
            token = [r addDocumentReplicationListener: ^(CBLDocumentReplication* docRepl) {
                NSError* err = docRepl.documents.firstObject.error;
                if (err)
                    [errors addObject: err];
            }];
        }];
    }];
    
    AssertEqual(errors.count, 1u);
    AssertEqual(errors.lastObject.code, CBLErrorConflict);
    AssertEqualObjects(errors.lastObject.domain, CBLErrorDomain);
    AssertEqualObjects([self.defaultCollection documentWithID: docId error: nil].toDictionary, localData);
    [token remove];
    
    // should be solved when the replicator runs next time!!
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.remoteDocument;
    }];
    
    CBLReplicatorConfiguration* rConfig2 = [self configForCollection: self.defaultCollection
                                                              target: _target
                                                         configBlock:^(CBLCollectionConfiguration* config) {
         config.conflictResolver = resolver;
    }];
    rConfig2.replicatorType = kCBLReplicatorTypePull;
    [self run: rConfig2 errorCode: 0 errorDomain: nil];
    AssertEqualObjects([self.defaultCollection documentWithID: docId error: nil].toDictionary, remoteData);
}

// TODO: enable this and handle expected memory leak in tests. 
- (void) _testConflictResolverThrowingException {
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    
    TestConflictResolver* resolver;
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        [NSException raise: NSInternalInconsistencyException
                    format: @"this exception is from resolve method!"];
        return nil;
    }];
    
    CBLReplicatorConfiguration* rConfig1 = [self configForCollection: self.defaultCollection
                                                              target: _target
                                                         configBlock:^(CBLCollectionConfiguration* config) {
         config.conflictResolver = resolver;
    }];
    rConfig1.replicatorType = kCBLReplicatorTypePull;
    
    // make sure resolver is thrown the exception and skips the resolution.
    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    __block NSMutableArray<NSError*>* errors = [NSMutableArray array];
    [self run: rConfig1 reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
        token = [r addDocumentReplicationListener: ^(CBLDocumentReplication* docRepl) {
            replicator = r;
            NSError* err = docRepl.documents.firstObject.error;
            if (err)
                [errors addObject: err];
        }];
    }];
    AssertEqual(errors.count, 1u);
    AssertEqual(errors.lastObject.code, CBLErrorConflict);
    AssertEqualObjects(errors.lastObject.domain, CBLErrorDomain);
    AssertEqualObjects([self.defaultCollection documentWithID: docId error: nil].toDictionary, localData);
    [token remove];
    
    // should be solved when the replicator runs next time!!
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.remoteDocument;
    }];
    
    CBLReplicatorConfiguration* rConfig2 = [self configForCollection: self.defaultCollection
                                                              target: _target
                                                         configBlock:^(CBLCollectionConfiguration* config) {
         config.conflictResolver = resolver;
     }];
    rConfig2.replicatorType = kCBLReplicatorTypePull;
    [self run: rConfig2 errorCode: 0 errorDomain: nil];
    AssertEqualObjects([self.defaultCollection documentWithID: docId error: nil].toDictionary, remoteData);
}

- (void) testNonBlockingDatabaseOperationConflictResolver {
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: @"doc1" withLocal: localData withRemote: remoteData];

    TestConflictResolver* resolver;
    __block int count = 0;
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        count++;
        NSString* doc2ID = @"doc2";
        NSDictionary* data = @{@"timestamp": [NSString stringWithFormat: @"%@", [NSDate date]]};
        CBLMutableDocument* mDoc2 = [self createDocument: doc2ID data: data];
        [self saveDocument: mDoc2 collection: self.defaultCollection];
        
        CBLDocument* doc2 = [self.defaultCollection documentWithID: doc2ID error: nil];
        AssertNotNil(doc2);
        AssertEqualObjects([doc2 toDictionary], data);
        
        return con.remoteDocument;
    }];
    
    CBLReplicatorConfiguration* rConfig = [self configForCollection: self.defaultCollection
                                                             target: _target
                                                        configBlock:^(CBLCollectionConfiguration* config) {
         config.conflictResolver = resolver;
    }];
    rConfig.replicatorType = kCBLReplicatorTypePull;
    [self run: rConfig errorCode: 0 errorDomain: nil];
    
    AssertEqual(count, 1u);
}

/** https://github.com/couchbaselabs/couchbase-lite-api/blob/master/spec/tests/T0005-Version-Vector.md
 Test 3. DefaultConflictResolverLastWriteWins -> default resolver
 */
- (void) testConflictResolutionDefault {
    NSError* error;
    NSDictionary* localData = @{@"name": @"local"};
    NSDictionary* remoteData = @{@"name": @"remote"};
    
    // Higher generation-id
    NSString* docID = @"doc1";
    [self makeConflictFor: docID withLocal: localData withRemote: remoteData];
    CBLMutableDocument* doc = [[self.defaultCollection documentWithID: docID error: &error] toMutable];
    [doc setValue: @"value1" forKey: @"key1"];
    [self saveDocument: doc collection: self.defaultCollection];
    
    // Delete local
    docID = @"doc2";
    [self makeConflictFor: docID withLocal: localData withRemote: remoteData];
    [self.defaultCollection deleteDocument: [self.defaultCollection documentWithID: docID error: &error] error: &error];
    
    // Delete remote
    docID = @"doc3";
    [self makeConflictFor: docID withLocal: localData withRemote: remoteData];
    [self.otherDBDefaultCollection deleteDocument: [self.otherDBDefaultCollection documentWithID: docID error: &error] error: &error];
    
    // Delete local but higher remote generation.
    docID = @"doc4";
    [self makeConflictFor: docID withLocal: localData withRemote: remoteData];
    [self.defaultCollection deleteDocument: [self.defaultCollection documentWithID: docID error: &error] error: &error];
    doc = [[self.otherDBDefaultCollection documentWithID: docID error: &error] toMutable];
    [doc setValue: @"value3" forKey: @"key3"];
    [self.otherDBDefaultCollection saveDocument: doc error: &error];
    [doc setValue: @"value4" forKey: @"key4"];
    [self.otherDBDefaultCollection saveDocument: doc error: &error];
    
    CBLReplicatorConfiguration* pullConfig = [self configWithTarget: _target
                                                               type: kCBLReplicatorTypePull
                                                         continuous: NO];
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    NSDictionary* expectedData = @{@"name": @"local", @"key1": @"value1"};
    AssertEqualObjects([[self.defaultCollection documentWithID: @"doc1" error: nil] toDictionary], expectedData);
    
    AssertNil([self.defaultCollection documentWithID: @"doc2" error: &error]);
    AssertNil([self.defaultCollection documentWithID: @"doc3" error: &error]);
    AssertNil([self.defaultCollection documentWithID: @"doc4" error: &error]);
}

- (void) testNewDocWithBlob {
    NSError* error;
    NSString* docID = @"doc";
    NSData* content = [@"I'm a tiger." dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType:@"text/plain" data: content];

    // RESOLVE WITH REMOTE & BLOB data in LOCAL
    TestConflictResolver* resolver;
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docID withLocal: localData withRemote: remoteData];
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        CBLMutableDocument* mDoc = [[CBLMutableDocument alloc] initWithID: con.documentID];
        [mDoc setString: @"newString" forKey: @"newKey"];
        [mDoc setBlob: blob forKey: @"blob"];
        return mDoc;
    }];
    
    CBLReplicatorConfiguration* rConfig = [self configForCollection: self.defaultCollection
                                                             target: _target
                                                        configBlock:^(CBLCollectionConfiguration* config) {
         config.conflictResolver = resolver;
    }];
    rConfig.replicatorType = kCBLReplicatorTypePull;
    
    CBLDocument* d = [self.otherDBDefaultCollection documentWithID: docID error: &error];
    Assert((d.c4Doc.revFlags & kRevHasAttachments) == 0);
    d = [self.defaultCollection documentWithID: docID error: &error];
    Assert((d.c4Doc.revFlags & kRevHasAttachments) == 0);
    
    [self run: rConfig errorCode: 0 errorDomain: nil];
    
    rConfig.replicatorType = kCBLReplicatorTypePush;
    [self run: rConfig errorCode: 0 errorDomain: nil];
    d = [self.otherDBDefaultCollection documentWithID: docID error: &error];
    Assert(d.c4Doc.revFlags & kRevHasAttachments);
    AssertEqualObjects([d stringForKey: @"newKey"], @"newString");
    d = [self.defaultCollection documentWithID: docID error: &error];
    Assert(d.c4Doc.revFlags & kRevHasAttachments);
    AssertEqualObjects([d stringForKey: @"newKey"], @"newString");
    
}

- (void) testConflictResolverReturningBlob {
    NSError* error;
    NSString* docID = @"doc";
    NSData* content = [@"I'm a tiger." dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType:@"text/plain" data: content];
    
    // RESOLVE WITH REMOTE & BLOB data in LOCAL
    TestConflictResolver* resolver;
    NSDictionary* localData = @{@"key1": @"value1", @"blob": blob};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docID withLocal: localData withRemote: remoteData];
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.remoteDocument;
    }];
    
    CBLReplicatorConfiguration* rConfig = [self configForCollection: self.defaultCollection
                                                             target: _target
                                                        configBlock:^(CBLCollectionConfiguration* config) {
         config.conflictResolver = resolver;
    }];
    rConfig.replicatorType = kCBLReplicatorTypePull;
    [self run: rConfig errorCode: 0 errorDomain: nil];
    
    AssertNil([[self.defaultCollection documentWithID: docID error: &error] blobForKey: @"blob"]);
    AssertEqualObjects([[self.defaultCollection documentWithID: docID error: nil] toDictionary], remoteData);
    
    // RESOLVE WITH LOCAL & BLOB data in LOCAL
    [self makeConflictFor: docID withLocal: localData withRemote: remoteData];
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.localDocument;
    }];
    
    CBLReplicatorConfiguration* rConfig2 = [self configForCollection: self.defaultCollection
                                                              target: _target
                                                         configBlock:^(CBLCollectionConfiguration* config) {
         config.conflictResolver = resolver;
    }];
    rConfig2.replicatorType = kCBLReplicatorTypePull;
    [self run: rConfig2 errorCode: 0 errorDomain: nil];
    
    AssertEqualObjects([[self.defaultCollection documentWithID: docID error: &error] blobForKey: @"blob"], blob);
    AssertEqualObjects([[self.defaultCollection documentWithID: docID error: nil] toDictionary], localData);
    
    // RESOLVE WITH LOCAL & BLOB data in REMOTE
    blob = [[CBLBlob alloc] initWithContentType:@"text/plain" data: content];
    localData = @{@"key1": @"value1"};
    remoteData = @{@"key2": @"value2", @"blob": blob};
    [self makeConflictFor: docID withLocal: localData withRemote: remoteData];
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.localDocument;
    }];
    
    CBLReplicatorConfiguration* rConfig3 = [self configForCollection: self.defaultCollection
                                                              target: _target
                                                         configBlock:^(CBLCollectionConfiguration* config) {
         config.conflictResolver = resolver;
    }];
    rConfig3.replicatorType = kCBLReplicatorTypePull;
    [self run: rConfig3 errorCode: 0 errorDomain: nil];
    
    AssertNil([[self.defaultCollection documentWithID: docID error: &error] blobForKey: @"blob"]);
    AssertEqualObjects([[self.defaultCollection documentWithID: docID error: nil] toDictionary], localData);
    
    // RESOLVE WITH REMOTE & BLOB data in REMOTE
    [self makeConflictFor: docID withLocal: localData withRemote: remoteData];
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.remoteDocument;
    }];
    
    CBLReplicatorConfiguration* rConfig4 = [self configForCollection: self.defaultCollection
                                                              target: _target
                                                         configBlock:^(CBLCollectionConfiguration* config) {
         config.conflictResolver = resolver;
    }];
    rConfig4.replicatorType = kCBLReplicatorTypePull;
    [self run: rConfig4 errorCode: 0 errorDomain: nil];
    
    AssertEqualObjects([[self.defaultCollection documentWithID: docID error: &error] blobForKey: @"blob"], blob);
    AssertEqualObjects([[self.defaultCollection documentWithID: docID error: nil] toDictionary], remoteData);
    
    // RESOLVED WITH A NEWLY CREATED DOC WITH BLOB
    blob = [[CBLBlob alloc] initWithContentType:@"text/plain" data: content];
    localData = @{@"key1": @"value1"};
    remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docID withLocal: localData withRemote: remoteData];
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        CBLMutableDocument* resolvedDoc = [CBLMutableDocument documentWithID: con.localDocument.id];
        [resolvedDoc setBlob: blob forKey: @"blob"];
        return resolvedDoc;
    }];
    
    CBLReplicatorConfiguration* rConfig5 = [self configForCollection: self.defaultCollection
                                                              target: _target
                                                         configBlock:^(CBLCollectionConfiguration* config) {
         config.conflictResolver = resolver;
    }];
    rConfig5.replicatorType = kCBLReplicatorTypePull;
    [self run: rConfig5 errorCode: 0 errorDomain: nil];
    
    AssertEqualObjects([[self.defaultCollection documentWithID: docID error: &error] blobForKey: @"blob"], blob);
    AssertEqual([[[self.defaultCollection documentWithID: docID error: nil] toDictionary] allKeys].count, 1u);
}

- (void) testNonBlockingConflictResolver {
    XCTestExpectation* ex = [self expectationWithDescription: @"testNonBlockingConflictResolver"];
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: @"doc1" withLocal: localData withRemote: remoteData];
    [self makeConflictFor: @"doc2" withLocal: localData withRemote: remoteData];
    
    TestConflictResolver* resolver;
    NSMutableArray* order = [NSMutableArray array];
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        NSUInteger count;
        @synchronized (order) {
            [order addObject: con.localDocument.id];
            count = order.count;
        }
        if (count == 1) {
            [NSThread sleepForTimeInterval: 0.5];
        }
        [order addObject: con.localDocument.id];
        
        if (order.count == 4) {
            [ex fulfill];
        }
        return con.remoteDocument;
    }];
    
    CBLReplicatorConfiguration* rConfig = [self configForCollection: self.defaultCollection
                                                              target: _target
                                                         configBlock:^(CBLCollectionConfiguration* config) {
         config.conflictResolver = resolver;
    }];
    rConfig.replicatorType = kCBLReplicatorTypePull;
    [self run: rConfig errorCode: 0 errorDomain: nil];
    
    [self waitForExpectations: @[ex] timeout: kExpTimeout];
    
    // make sure, first doc starts resolution but finishes last.
    // in between second doc starts and finishes it.
    AssertEqualObjects(order.firstObject, order.lastObject);
    AssertEqualObjects(order[1], order[2]);
}

/*
 1. starts replication and tries to resolve the conflict
 2. inside CCR, it wait for same conflict to resolve(via another attempt separately).
 3. suspend the replicator
 4. once replicator becomes offline, make replicator unsuspend.
 5. when replcator becomes unsuspend, it will attempt to resolve conflict separately.
 6. document resolved successfully, with second attempt,
 7. once the first CCR tries again, conflict is already been resolved.
 */
// CBL-6976: Refactor this test
- (void) dontTestDoubleConflictResolutionOnSameConflicts {
    NSError* error;
    NSString* docID = @"doc1";
    CBLTestCustomLogSink* logSink = [[CBLTestCustomLogSink alloc] init];
    CBLLogSinks.custom = [[CBLCustomLogSink alloc] initWithLevel: kCBLLogLevelWarning logSink: logSink];

    XCTestExpectation* expCCR = [self expectationWithDescription:@"wait for conflict resolver"];
    XCTestExpectation* expSTOP = [self expectationWithDescription:@"wait for replicator to stop"];
    XCTestExpectation* expFirstDocResolve = [self expectationWithDescription:@"wait for first conflict to resolve"];
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docID withLocal: localData withRemote: remoteData];
    
    TestConflictResolver* resolver;
    __block int ccrCount = 0;
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        int c = ccrCount;
        if (ccrCount++ == 0) {
            // 2
            [expCCR fulfill];
            [self waitForExpectations: @[expFirstDocResolve] timeout: kExpTimeout];
        }
        // 5
        return c == 1 ? con.localDocument /*non-sleeping*/ : con.remoteDocument /*sleeping*/;
    }];
    
    CBLReplicatorConfiguration* rConfig = [self configForCollection: self.defaultCollection
                                                              target: _target
                                                         configBlock:^(CBLCollectionConfiguration* config) {
         config.conflictResolver = resolver;
    }];
    rConfig.replicatorType = kCBLReplicatorTypePull;
    
    CBLReplicator* replicator = [[CBLReplicator alloc] initWithConfig: rConfig];
    __weak CBLReplicator* r = replicator;
    id changeToken = [replicator addChangeListener:^(CBLReplicatorChange * change) {
        __strong CBLReplicator* re = r;
        if (change.status.activity == kCBLReplicatorOffline) {
            // 4
            [re setSuspended: NO];
        }
        if (change.status.activity == kCBLReplicatorStopped) {
            [expSTOP fulfill];
        }
    }];
    __block int noOfNotificationReceived = 0;
    id docReplToken = [replicator addDocumentReplicationListener:^(CBLDocumentReplication * docRepl) {
        noOfNotificationReceived++;
        if (noOfNotificationReceived == 1) {
            // 6
            [expFirstDocResolve fulfill];
        }
        AssertEqualObjects(docRepl.documents.firstObject.id, docID);
    }];
    
    // 1
    [replicator start];
    [self waitForExpectations: @[expCCR] timeout: kExpTimeout];
    
    // 3
    // in between the conflict, we wil suspend replicator.
    [replicator setSuspended: YES];
    
    // Skip exception breakpoint thrown from c4doc_resolve
    [self ignoreException:^{
        [self waitForExpectations: @[expSTOP] timeout: kExpTimeout];
    }];
    
    AssertEqual(ccrCount, 2u);
    AssertEqual(noOfNotificationReceived, 2u);
    CBLDocument* doc = [self.defaultCollection documentWithID: docID error: &error];
    AssertEqualObjects([doc toDictionary], localData);
    
    // 7
    Assert([logSink.lines containsObject: @"Unable to select conflicting revision for doc1, "
            "the conflict may have been resolved..."]);
    
    [changeToken remove];
    [docReplToken remove];
    
    CBLLogSinks.custom = nil;
}

- (void) testConflictResolverReturningBlobFromDifferentDB {
    NSString* docID = @"doc";
    NSData* content = [@"I'm a blob." dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType:@"text/plain" data: content];
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2", @"blob": blob};
    [self makeConflictFor: docID withLocal: localData withRemote: remoteData];
    
    TestConflictResolver* resolver;
    // using remote document blob is okay to use!
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        CBLMutableDocument* mDoc = con.localDocument.toMutable;
        [mDoc setBlob: [con.remoteDocument blobForKey: @"blob"] forKey: @"blob"];
        return mDoc;
    }];
    
    CBLReplicatorConfiguration* rConfig1 = [self configForCollection: self.defaultCollection
                                                              target: _target
                                                         configBlock:^(CBLCollectionConfiguration* config) {
         config.conflictResolver = resolver;
    }];
    rConfig1.replicatorType = kCBLReplicatorTypePull;
    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    [self run: rConfig1 reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
        replicator = r;
        token = [r addDocumentReplicationListener: ^(CBLDocumentReplication* docRepl) {
            AssertEqual(docRepl.documents.count, 1u);
            AssertNil(docRepl.documents.firstObject.error);
        }];
    }];
    [token remove];
    
    // using blob from remote document of user's- which is a different database
    CBLDocument* otherDBDoc = [self.otherDBDefaultCollection documentWithID: docID error: nil];
    [self makeConflictFor: docID withLocal: localData withRemote: remoteData];
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        CBLMutableDocument* mDoc = con.localDocument.toMutable;
        [mDoc setBlob: [otherDBDoc blobForKey: @"blob"] forKey: @"blob"];
        return mDoc;
    }];
    
    CBLReplicatorConfiguration* rConfig2 = [self configForCollection: self.defaultCollection
                                                              target: _target
                                                         configBlock:^(CBLCollectionConfiguration* config) {
         config.conflictResolver = resolver;
    }];
    rConfig2.replicatorType = kCBLReplicatorTypePull;
    __block NSError* error = nil;
    [self ignoreException:^{
        [self run: rConfig2 reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
            replicator = r;
            token = [r addDocumentReplicationListener: ^(CBLDocumentReplication* docRepl) {
                AssertEqual(docRepl.documents.count, 1u);
                if (docRepl.documents.firstObject.error) {
                    error = docRepl.documents.firstObject.error;
                }
            }];
        }];
    }];
    AssertNotNil(error);
    AssertEqual(error.code, CBLErrorUnexpectedError);
    AssertEqualObjects(error.userInfo[NSLocalizedDescriptionKey], kCBLErrorMessageBlobDifferentDatabase);
    [token remove];
}

- (void) testConflictResolverWhenDocumentIsPurged {
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    
    TestConflictResolver* resolver;
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        [self.defaultCollection purgeDocument: [self.defaultCollection documentWithID: docId error: nil] error: nil];
        return con.remoteDocument;
    }];
    
    CBLReplicatorConfiguration* rConfig = [self configForCollection: self.defaultCollection
                                                              target: _target
                                                         configBlock:^(CBLCollectionConfiguration* config) {
         config.conflictResolver = resolver;
    }];
    rConfig.replicatorType = kCBLReplicatorTypePull;
    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    __block NSMutableArray<NSError*>* errors = [NSMutableArray array];
    
    // Skip exception breakpoint thrown from c4doc_resolve
    [self ignoreException:^{
        [self run: rConfig reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
            replicator = r;
            token = [r addDocumentReplicationListener: ^(CBLDocumentReplication* docRepl) {
                NSError* err = docRepl.documents.firstObject.error;
                if (err)
                    [errors addObject: err];
            }];
        }];
    }];
    
    AssertEqual(errors.count, 1u);
    AssertEqual(errors.firstObject.code, CBLErrorNotFound);
    [token remove];
}

- (void) testConflictResolverPreservesFlags {
    NSString* docId = @"doc";
    NSData* content = [@"I'm a blob." dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType:@"text/plain" data: content];
    NSDictionary* localData = @{@"key1": @"value1", @"blob": blob};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    
    CBLDocument* localDoc = [self.defaultCollection documentWithID: docId error: nil];
    Assert(0 != localDoc.c4Doc.revFlags);
    Assert(localDoc.c4Doc.revFlags & kRevHasAttachments);
    
    TestConflictResolver* resolver;
    __block C4RevisionFlags localRevFlags = 0;
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        localRevFlags = con.localDocument.c4Doc.revFlags;
        return con.localDocument;
    }];
    
    CBLReplicatorConfiguration* rConfig = [self configForCollection: self.defaultCollection
                                                              target: _target
                                                         configBlock:^(CBLCollectionConfiguration* config) {
         config.conflictResolver = resolver;
    }];
    rConfig.replicatorType = kCBLReplicatorTypePull;
    [self run: rConfig errorCode: 0 errorDomain: nil];
    
    localDoc = [self.defaultCollection documentWithID: docId error: nil];
    Assert(localDoc.c4Doc.revFlags & kRevHasAttachments & localRevFlags);
}

@end
