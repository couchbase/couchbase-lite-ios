//
//  ReplicatorTest+CustomConflict
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
#import "CBLDocument+Internal.h"
#import "CustomLogger.h"
#import "CBLReplicator+Internal.h"
#import "CBLErrorMessage.h"

@interface TestConflictResolver: NSObject<CBLConflictResolver>

@property(nonatomic, nullable) CBLDocument* winner;

- (instancetype) init NS_UNAVAILABLE;

// set this resolver, which will be used while resolving the conflict
- (instancetype) initWithResolver: (CBLDocument* (^)(CBLConflict*))resolver;

@end

@interface ReplicatorTest_CustomConflict : ReplicatorTest
@end

@implementation ReplicatorTest_CustomConflict

#pragma mark - Tests without replication

- (void) testConflictResolverConfigProperty {
    id target = [[CBLURLEndpoint alloc] initWithURL: [NSURL URLWithString: @"wss://foo"]];
    CBLReplicatorConfiguration* config = [self configWithTarget: target
                                                           type: kCBLReplicatorTypePull
                                                     continuous: NO];
    TestConflictResolver* resolver;
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.remoteDocument;
    }];
    config.conflictResolver = resolver;
    repl = [[CBLReplicator alloc] initWithConfig: config];
    
    // checks whether the conflict resolver can be set-to/get-from config
    AssertNotNil(config.conflictResolver);
    AssertEqualObjects(config.conflictResolver, resolver);
    AssertNotNil(repl.config.conflictResolver);
    AssertEqualObjects(repl.config.conflictResolver, resolver);
    
    // check whether conflict resolver can be edited after setting to replicator
    [self expectException: @"NSInternalInconsistencyException" in: ^{
        repl.config.conflictResolver = nil;
    }];
}

#pragma mark - Tests with replication

#ifdef COUCHBASE_ENTERPRISE

- (void) makeConflictFor: (NSString*)docID
               withLocal: (nullable NSDictionary*) localData
              withRemote: (nullable NSDictionary*) remoteData {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: docID];
    Assert([self.db saveDocument: doc1 error: &error]);
    
    [self run: [self config: kCBLReplicatorTypePush] errorCode: 0 errorDomain: nil];
    
    // Now make different changes in db and otherDB:
    doc1 = [[self.db documentWithID: docID] toMutable];
    if (localData) {
        [doc1 setData: localData];
        Assert([self.db saveDocument: doc1 error: &error]);
    } else {
        Assert([self.db deleteDocument: doc1 error: &error]);
    }
    
    // pass the remote revision
    CBLMutableDocument* doc2 = [[self.otherDB documentWithID: docID] toMutable];
    if (remoteData) {
        [doc2 setData: remoteData];
        Assert([self.otherDB saveDocument: doc2 error: &error]);
    } else {
        Assert([self.otherDB deleteDocument: doc2 error: &error]);
    }
}

- (CBLReplicatorConfiguration*) config: (CBLReplicatorType)type {
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: self.otherDB];
    return [self configWithTarget: target
                             type: type
                       continuous: NO];
}

- (void) testConflictResolverRemoteWins {
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    
    TestConflictResolver* resolver;
    CBLReplicatorConfiguration* pullConfig = [self config: kCBLReplicatorTypePull];
    
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.remoteDocument;
    }];
    pullConfig.conflictResolver = resolver;
    
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    // Check that it was resolved:
    AssertEqual(self.db.count, 1u);
    AssertEqualObjects([self.db documentWithID: docId].toDictionary, remoteData);
    
    UInt64 sequenceBeforePush = [self.otherDB documentWithID: docId].sequence;
    [self run: [self config: kCBLReplicatorTypePush] errorCode: 0 errorDomain: nil];
    
    // should be equal, so that nothing has pushed to remote
    AssertEqual(sequenceBeforePush, [self.otherDB documentWithID: docId].sequence);
}

- (void) testConflictResolverLocalWins {
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    
    TestConflictResolver* resolver;
    CBLReplicatorConfiguration* pullConfig = [self config: kCBLReplicatorTypePull];
    
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.localDocument;
    }];
    pullConfig.conflictResolver = resolver;
    
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    // Check that it was resolved:
    AssertEqual(self.db.count, 1u);
    AssertEqualObjects([self.db documentWithID: docId].toDictionary, localData);
    
    UInt64 sequenceBeforePush = [self.otherDB documentWithID: docId].sequence;
    [self run: [self config: kCBLReplicatorTypePush] errorCode: 0 errorDomain: nil];
    
    // there was changes to push to remote, and sequence increased
    Assert(sequenceBeforePush < [self.otherDB documentWithID: docId].sequence);
}

- (void) testConflictResolverNullDoc {
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    
    TestConflictResolver* resolver;
    CBLReplicatorConfiguration* pullConfig = [self config: kCBLReplicatorTypePull];
    
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return nil;
    }];
    pullConfig.conflictResolver = resolver;
    
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    // Check whether the document is deleted, and returns null.
    AssertEqual(self.db.count, 0u);
    AssertNil([self.db documentWithID: docId]);
    NSError* error;
    UInt64 sequenceBeforePush = [self.otherDB documentWithID: docId].sequence;
    [self run: [self config: kCBLReplicatorTypePush] errorCode: 0 errorDomain: nil];
    
    // should be greater, so that it pushed new revision to remote
    Assert(sequenceBeforePush < [[CBLDocument alloc] initWithDatabase: self.otherDB
                                                           documentID: docId
                                                       includeDeleted: YES error: &error].sequence);
}

- (void) testConflictResolverDeletedLocalWins {
    NSString* docId = @"doc";
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: nil withRemote: remoteData];
    
    TestConflictResolver* resolver;
    CBLReplicatorConfiguration* pullConfig = [self config: kCBLReplicatorTypePull];
    
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return nil;
    }];
    pullConfig.conflictResolver = resolver;
    
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    // Check whether the document gets deleted and return null.
    AssertEqual(self.db.count, 0u);
    AssertNil([self.db documentWithID: @"doc"]);
    
    NSError* error;
    UInt64 sequenceBeforePush = [self.otherDB documentWithID: docId].sequence;
    [self run: [self config: kCBLReplicatorTypePush] errorCode: 0 errorDomain: nil];
    
    // should be greater, so that it pushed new revision to remote
    Assert(sequenceBeforePush < [[CBLDocument alloc] initWithDatabase: self.otherDB
                                                           documentID: docId
                                                       includeDeleted: YES
                                                                error: &error].sequence);
}

- (void) testConflictResolverDeletedRemoteWins {
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    [self makeConflictFor: docId withLocal: localData withRemote: nil];
    
    TestConflictResolver* resolver;
    CBLReplicatorConfiguration* pullConfig = [self config: kCBLReplicatorTypePull];
    
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return nil;
    }];
    pullConfig.conflictResolver = resolver;
    
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    // Check whether it deletes the document and returns nil.
    AssertEqual(self.db.count, 0u);
    AssertNil([self.db documentWithID: @"doc"]);
    
    NSError* error;
    UInt64 sequenceBeforePush = [[CBLDocument alloc] initWithDatabase: self.otherDB
                                                           documentID: docId
                                                       includeDeleted: YES
                                                                error: &error].sequence;
    [self run: [self config: kCBLReplicatorTypePush] errorCode: 0 errorDomain: nil];
    
    // The deleted doc shouldn't be pushed to the remote DB:
    AssertEqual(sequenceBeforePush, [[CBLDocument alloc] initWithDatabase: self.otherDB
                                                               documentID: docId
                                                           includeDeleted: YES
                                                                    error: &error].sequence);
}

- (void) testConflictResolverDeletedBothRev {
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    [self makeConflictFor: docId withLocal: localData withRemote: nil];
    
    TestConflictResolver* resolver;
    CBLReplicatorConfiguration* pullConfig = [self config: kCBLReplicatorTypePull];
    
    __block int count = 0;
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        count++;
        AssertNil(con.remoteDocument);
        AssertNotNil(con.localDocument);
        NSError* error = nil;
        [self.db deleteDocument: [self.db documentWithID: docId]
                          error: &error];
        return nil;
    }];
    pullConfig.conflictResolver = resolver;
    
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    // it should only call resolver once. 
    // since second time, both revisions are deleted, and automatically resolve
    AssertEqual(count, 1);
    
    // Check whether it deletes the document and returns nil.
    AssertEqual(self.db.count, 0u);
    AssertNil([self.db documentWithID: @"doc"]);
}

- (void) testConflictResolverMergeDoc {
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    
    TestConflictResolver* resolver;
    CBLReplicatorConfiguration* pullConfig = [self config: kCBLReplicatorTypePull];
    
    // EDIT LOCAL DOCUMENT
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        CBLMutableDocument* mDoc = con.localDocument.toMutable;
        [mDoc setString: @"local" forKey: @"edit"];
        return mDoc;
    }];
    pullConfig.conflictResolver = resolver;
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    NSMutableDictionary* exp = [NSMutableDictionary dictionaryWithDictionary: localData];
    [exp setValue: @"local" forKey: @"edit"];
    AssertEqualObjects([self.db documentWithID: docId].toDictionary, exp);
    
    // make sure it updates remote doc
    UInt64 sequenceBeforePush = [self.otherDB documentWithID: docId].sequence;
    [self run: [self config: kCBLReplicatorTypePush] errorCode: 0 errorDomain: nil];
    Assert(sequenceBeforePush < [self.otherDB documentWithID: docId].sequence);
    
    // EDIT REMOTE DOCUMENT
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        CBLMutableDocument* mDoc = con.remoteDocument.toMutable;
        [mDoc setString: @"remote" forKey: @"edit"];
        return mDoc;
    }];
    pullConfig.conflictResolver = resolver;
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    exp = [NSMutableDictionary dictionaryWithDictionary: remoteData];
    [exp setValue: @"remote" forKey: @"edit"];
    AssertEqualObjects([self.db documentWithID: docId].toDictionary, exp);
    
    // make sure it updates remote doc
    sequenceBeforePush = [self.otherDB documentWithID: docId].sequence;
    [self run: [self config: kCBLReplicatorTypePush] errorCode: 0 errorDomain: nil];
    Assert(sequenceBeforePush < [self.otherDB documentWithID: docId].sequence);
    
    // CREATE NEW DOCUMENT
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        CBLMutableDocument* mDoc = [[CBLMutableDocument alloc] initWithID: con.localDocument.id];
        [mDoc setString: @"new-with-same-ID" forKey: @"docType"];
        return mDoc;
    }];
    pullConfig.conflictResolver = resolver;
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    exp = [NSMutableDictionary dictionaryWithObject: @"new-with-same-ID" forKey: @"docType"];
    AssertEqualObjects([self.db documentWithID: docId].toDictionary, exp);
    
    // make sure it updates remote doc
    sequenceBeforePush = [self.otherDB documentWithID: docId].sequence;
    [self run: [self config: kCBLReplicatorTypePush] errorCode: 0 errorDomain: nil];
    Assert(sequenceBeforePush < [self.otherDB documentWithID: docId].sequence);
}

- (void) testDocumentReplicationEventForConflictedDocs {
    TestConflictResolver* resolver;
    
    // when resolution is skipped: here doc from otherDB throws an exception & skips it
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return [self.otherDB documentWithID: @"doc"];
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
    CBLReplicatorConfiguration* config = [self config: kCBLReplicatorTypePull];
    config.conflictResolver = resolver;
    
    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    __block NSMutableArray<NSString*>* docIds = [NSMutableArray array];
    [self ignoreException:^{
        [self run: config reset: NO errorCode: 0 errorDomain: nil onReplicatorReady:^(CBLReplicator * r) {
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
    [replicator removeChangeListenerWithToken: token];
    
    // resolve any un-resolved conflict through pull replication.
    [self run: [self config: kCBLReplicatorTypePull] errorCode: 0 errorDomain: nil];
}

- (void) testConflictResolverCalledTwice {
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    
    TestConflictResolver* resolver;
    CBLReplicatorConfiguration* pullConfig = [self config: kCBLReplicatorTypePull];
    
    __block int count = 0;
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        count++;
        // update the doc will cause a second conflict
        CBLMutableDocument* savedDoc = [[self.db documentWithID: docId] toMutable];
        if (![savedDoc booleanForKey: @"secondUpdate"]) {
            NSError* error;
            [savedDoc setBoolean: YES forKey: @"secondUpdate"];
            [self.db saveDocument: savedDoc error: &error];
            AssertNil(error);
        }
        
        CBLMutableDocument* mDoc = con.localDocument.toMutable;
        [mDoc setString: @"local" forKey: @"edit"];
        return mDoc;
    }];
    pullConfig.conflictResolver = resolver;
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    // make sure the resolver method called twice due to second conflict
    AssertEqual(count, 2u);
    
    AssertEqual(self.db.count, 1u);
    NSMutableDictionary* exp = [NSMutableDictionary dictionaryWithDictionary: localData];
    [exp setValue: @"local" forKey: @"edit"];
    [exp setValue: @YES forKey: @"secondUpdate"];
    AssertEqualObjects([self.db documentWithID: docId].toDictionary, exp);
}

-  (void) testConflictResolverWrongDocID {
    // Enable Logging to check whether the logs are printing
    CustomLogger* custom = [[CustomLogger alloc] init];
    custom.level = kCBLLogLevelWarning;
    CBLDatabase.log.custom = custom;
    
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    TestConflictResolver* resolver;
    CBLReplicatorConfiguration* pullConfig = [self config: kCBLReplicatorTypePull];
    
    NSString* wrongDocID = @"wrongDocID";
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        CBLMutableDocument* mDoc = [CBLMutableDocument documentWithID: wrongDocID];
        [mDoc setData: con.localDocument.toDictionary]; // update with local contents
        [mDoc setString: @"update" forKey: @"edit"]; // add one extra key-value
        return mDoc;
    }];
    pullConfig.conflictResolver = resolver;
    
    // make sure resolver is thrown the exception and skips the resolution.
    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    __block NSMutableSet* docIds = [NSMutableSet set];
    [self run: pullConfig reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
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
    
    AssertEqual(self.db.count, 1u);
    Assert([docIds containsObject: docId]);
    NSMutableDictionary* exp = [NSMutableDictionary dictionaryWithDictionary: localData];
    [exp setValue: @"update" forKey: @"edit"];
    AssertEqualObjects([self.db documentWithID: docId].toDictionary, exp);

    // validate the warning message!
    NSString* warning = [NSString stringWithFormat: @"The document ID of the resolved document '%@'"
                         " is not matching with the document ID of the conflicting document '%@'.",
                         wrongDocID, docId];
    AssertEqualObjects(custom.lines.lastObject, warning);
    
    [replicator removeChangeListenerWithToken: token];
    CBLDatabase.log.custom = nil;
}

- (void) testConflictResolverDifferentDBDoc {
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    TestConflictResolver* resolver;
    CBLReplicatorConfiguration* pullConfig = [self config: kCBLReplicatorTypePull];
    
    __weak CBLDatabase* weakOtherDB = self.otherDB;
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return [weakOtherDB documentWithID: con.localDocument.id]; // doc from different DB!!
    }];
    pullConfig.conflictResolver = resolver;
    
    // make sure resolver is thrown the exception and skips the resolution.
    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    __block NSMutableArray<NSError*>* errors = [NSMutableArray array];
    [self ignoreException: ^{
        [self run: pullConfig reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
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
    AssertEqualObjects([self.db documentWithID: docId].toDictionary, localData);
    [replicator removeChangeListenerWithToken: token];
    
    // should be solved when the replicator runs next time!!
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.remoteDocument;
    }];
    pullConfig.conflictResolver = resolver;
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    AssertEqualObjects([self.db documentWithID: docId].toDictionary, remoteData);
}

// TODO: enable this and handle expected memory leak in tests. 
- (void) _testConflictResolverThrowingException {
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    TestConflictResolver* resolver;
    CBLReplicatorConfiguration* pullConfig = [self config: kCBLReplicatorTypePull];
    
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        [NSException raise: NSInternalInconsistencyException
                    format: @"this exception is from resolve method!"];
        return nil;
    }];
    pullConfig.conflictResolver = resolver;
    
    // make sure resolver is thrown the exception and skips the resolution.
    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    __block NSMutableArray<NSError*>* errors = [NSMutableArray array];
    [self run: pullConfig reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
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
    AssertEqualObjects([self.db documentWithID: docId].toDictionary, localData);
    [replicator removeChangeListenerWithToken: token];
    
    // should be solved when the replicator runs next time!!
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.remoteDocument;
    }];
    pullConfig.conflictResolver = resolver;
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    AssertEqualObjects([self.db documentWithID: docId].toDictionary, remoteData);
}

- (void) testNonBlockingDatabaseOperationConflictResolver {
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: @"doc1" withLocal: localData withRemote: remoteData];

    TestConflictResolver* resolver;
    CBLReplicatorConfiguration* pullConfig = [self config: kCBLReplicatorTypePull];

    __block int count = 0;
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        count++;
        NSString* doc2ID = @"doc2";
        NSDictionary* data = @{@"timestamp": [NSString stringWithFormat: @"%@", [NSDate date]]};
        CBLMutableDocument* mDoc2 = [self createDocument: doc2ID data: data];
        [self saveDocument: mDoc2];
        
        CBLDocument* doc2 = [self.db documentWithID: doc2ID];
        AssertNotNil(doc2);
        AssertEqualObjects([doc2 toDictionary], data);
        
        return con.remoteDocument;
    }];
    pullConfig.conflictResolver = resolver;
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    AssertEqual(count, 1u);
}

- (void) testConflictResolutionDefault {
    NSError* error;
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    NSMutableArray* conflictedDocs = [NSMutableArray array];
    
    // higher generation-id
    NSString* docID = @"doc1";
    [self makeConflictFor: docID withLocal: localData withRemote: remoteData];
    CBLMutableDocument* doc = [[self.db documentWithID: docID] toMutable];
    [doc setValue: @"value3" forKey: @"key3"];
    [self saveDocument: doc];
    [conflictedDocs addObject: @[[self.db documentWithID: docID],
                                 [self.otherDB documentWithID: docID]]];
    
    // delete local
    docID = @"doc2";
    [self makeConflictFor: docID withLocal: localData withRemote: remoteData];
    [self.db deleteDocument: [self.db documentWithID: docID] error: &error];
    [conflictedDocs addObject: @[[NSNull null], [self.otherDB documentWithID: docID]]];
    
    // delete remote
    docID = @"doc3";
    [self makeConflictFor: docID withLocal: localData withRemote: remoteData];
    [self.otherDB deleteDocument: [self.otherDB documentWithID: docID] error: &error];
    [conflictedDocs addObject: @[[self.db documentWithID: docID], [NSNull null]]];
    
    // delete local but higher remote generation.
    docID = @"doc4";
    [self makeConflictFor: docID withLocal: localData withRemote: remoteData];
    [self.db deleteDocument: [self.db documentWithID: docID] error: &error];
    doc = [[self.otherDB documentWithID: docID] toMutable];
    [doc setValue: @"value3" forKey: @"key3"];
    [self.otherDB saveDocument: doc error: &error];
    doc = [[self.otherDB documentWithID: docID] toMutable];
    [doc setValue: @"value4" forKey: @"key4"];
    [self.otherDB saveDocument: doc error: &error];
    [conflictedDocs addObject: @[[NSNull null], [self.otherDB documentWithID: docID]]];
    
    CBLReplicatorConfiguration* pullConfig = [self config:kCBLReplicatorTypePull];
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    for (NSArray* docs in conflictedDocs) {
        CBLDocument* doc1 = docs[0];
        CBLDocument* doc2 = docs[1];
        
        // if any deleted, success revision should be deleted.
        if ([doc1 isEqual: [NSNull null]] || [doc2 isEqual: [NSNull null]]) {
            docID = [doc1 isKindOfClass: [NSNull class]] ? doc2.id : doc1.id;
            CBLDocument* successDoc = [[CBLDocument alloc] initWithDatabase: self.db
                                                                 documentID: docID
                                                             includeDeleted: YES
                                                                      error: &error];
            AssertNil(error);
            Assert(successDoc.isDeleted);
        } else {
            // if generations are different
            AssertEqual(doc1.generation, [self.db documentWithID: doc1.id].generation);
            Assert(doc1.generation > doc2.generation);
        }
    }
}

- (void) testConflictResolverReturningBlob {
    NSString* docID = @"doc";
    NSData* content = [@"I'm a tiger." dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType:@"text/plain" data: content];
    TestConflictResolver* resolver;
    CBLReplicatorConfiguration* pullConfig = [self config: kCBLReplicatorTypePull];
    
    // RESOLVE WITH REMOTE & BLOB data in LOCAL
    NSDictionary* localData = @{@"key1": @"value1", @"blob": blob};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docID withLocal: localData withRemote: remoteData];
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.remoteDocument;
    }];
    pullConfig.conflictResolver = resolver;
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    AssertNil([[self.db documentWithID: docID] blobForKey: @"blob"]);
    AssertEqualObjects([[self.db documentWithID: docID] toDictionary], remoteData);
    
    // RESOLVE WITH LOCAL & BLOB data in LOCAL
    [self makeConflictFor: docID withLocal: localData withRemote: remoteData];
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.localDocument;
    }];
    pullConfig.conflictResolver = resolver;
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    AssertEqualObjects([[self.db documentWithID: docID] blobForKey: @"blob"], blob);
    AssertEqualObjects([[self.db documentWithID: docID] toDictionary], localData);
    
    // RESOLVE WITH LOCAL & BLOB data in REMOTE
    blob = [[CBLBlob alloc] initWithContentType:@"text/plain" data: content];
    localData = @{@"key1": @"value1"};
    remoteData = @{@"key2": @"value2", @"blob": blob};
    [self makeConflictFor: docID withLocal: localData withRemote: remoteData];
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.localDocument;
    }];
    pullConfig.conflictResolver = resolver;
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    AssertNil([[self.db documentWithID: docID] blobForKey: @"blob"]);
    AssertEqualObjects([[self.db documentWithID: docID] toDictionary], localData);
    
    // RESOLVE WITH REMOTE & BLOB data in REMOTE
    [self makeConflictFor: docID withLocal: localData withRemote: remoteData];
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.remoteDocument;
    }];
    pullConfig.conflictResolver = resolver;
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    AssertEqualObjects([[self.db documentWithID: docID] blobForKey: @"blob"], blob);
    AssertEqualObjects([[self.db documentWithID: docID] toDictionary], remoteData);
    
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
    pullConfig.conflictResolver = resolver;
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    AssertEqualObjects([[self.db documentWithID: docID] blobForKey: @"blob"], blob);
    AssertEqual([[[self.db documentWithID: docID] toDictionary] allKeys].count, 1u);
}

- (void) testNonBlockingConflictResolver {
    XCTestExpectation* ex = [self expectationWithDescription: @"testNonBlockingConflictResolver"];
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: @"doc1" withLocal: localData withRemote: remoteData];
    [self makeConflictFor: @"doc2" withLocal: localData withRemote: remoteData];
    
    TestConflictResolver* resolver;
    CBLReplicatorConfiguration* pullConfig = [self config: kCBLReplicatorTypePull];
    
    NSMutableArray* order = [NSMutableArray array];
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        @synchronized (order) {
            [order addObject: con.localDocument.id];
        }
        if (order.count == 1) {
            [NSThread sleepForTimeInterval: 0.5];
        }
        [order addObject: con.localDocument.id];
        
        if (order.count == 4) {
            [ex fulfill];
        }
        return con.remoteDocument;
    }];
    pullConfig.conflictResolver = resolver;
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    [self waitForExpectations: @[ex] timeout: 5.0];
    
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
- (void) testDoubleConflictResolutionOnSameConflicts {
    NSString* docID = @"doc1";
    CustomLogger* custom = [[CustomLogger alloc] init];
    custom.level = kCBLLogLevelWarning;
    CBLDatabase.log.custom = custom;
    XCTestExpectation* expCCR = [self expectationWithDescription:@"wait for conflict resolver"];
    XCTestExpectation* expSTOP = [self expectationWithDescription:@"wait for replicator to stop"];
    XCTestExpectation* expFirstDocResolve = [self expectationWithDescription:@"wait for first conflict to resolve"];
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docID withLocal: localData withRemote: remoteData];
    TestConflictResolver* resolver;
    CBLReplicatorConfiguration* pullConfig = [self config: kCBLReplicatorTypePull];
    
    __block int ccrCount = 0;
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        int c = ccrCount;
        if (ccrCount++ == 0) {
            // 2
            [expCCR fulfill];
            [self waitForExpectations: @[expFirstDocResolve] timeout: 5.0];
        }
        // 5
        return c == 1 ? con.localDocument /*non-sleeping*/ : con.remoteDocument /*sleeping*/;
    }];
    pullConfig.conflictResolver = resolver;
    CBLReplicator* replicator = [[CBLReplicator alloc] initWithConfig: pullConfig];
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
    [self waitForExpectations: @[expCCR] timeout: 5.0];
    
    // 3
    // in between the conflict, we wil suspend replicator.
    [replicator setSuspended: YES];
    [self waitForExpectations: @[expSTOP] timeout: 15.0];
    
    AssertEqual(ccrCount, 2u);
    AssertEqual(noOfNotificationReceived, 2u);
    CBLDocument* doc = [self.db documentWithID: docID];
    AssertEqualObjects([doc toDictionary], localData);
    
    // 7
    AssertEqualObjects(custom.lines.lastObject, @"Unable to select conflicting revision for doc1, "
            "the conflict may have been resolved...");
    
    [replicator removeChangeListenerWithToken: changeToken];
    [replicator removeChangeListenerWithToken: docReplToken];
}

- (void) testConflictResolverReturningBlobFromDifferentDB {
    NSString* docID = @"doc";
    NSData* content = [@"I'm a blob." dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType:@"text/plain" data: content];
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2", @"blob": blob};
    TestConflictResolver* resolver;
    CBLReplicatorConfiguration* pullConfig = [self config: kCBLReplicatorTypePull];
    
    // using remote document blob is okay to use!
    [self makeConflictFor: docID withLocal: localData withRemote: remoteData];
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        CBLMutableDocument* mDoc = con.localDocument.toMutable;
        [mDoc setBlob: [con.remoteDocument blobForKey: @"blob"] forKey: @"blob"];
        return mDoc;
    }];
    pullConfig.conflictResolver = resolver;
    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    [self run: pullConfig reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
        replicator = r;
        token = [r addDocumentReplicationListener: ^(CBLDocumentReplication* docRepl) {
            AssertEqual(docRepl.documents.count, 1u);
            AssertNil(docRepl.documents.firstObject.error);
        }];
    }];
    [replicator removeChangeListenerWithToken: token];
    
    // using blob from remote document of user's- which is a different database
    CBLDocument* otherDBDoc = [self.otherDB documentWithID: docID];
    [self makeConflictFor: docID withLocal: localData withRemote: remoteData];
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        CBLMutableDocument* mDoc = con.localDocument.toMutable;
        [mDoc setBlob: [otherDBDoc blobForKey: @"blob"] forKey: @"blob"];
        return mDoc;
    }];
    pullConfig.conflictResolver = resolver;
    __block NSError* error = nil;
    [self ignoreException:^{
        [self run: pullConfig reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
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
    [replicator removeChangeListenerWithToken: token];
}

- (void) testConflictResolverWhenDocumentIsPurged {
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    
    TestConflictResolver* resolver;
    CBLReplicatorConfiguration* pullConfig = [self config: kCBLReplicatorTypePull];
    
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        [self.db purgeDocument: [self.db documentWithID: docId] error: nil];
        return con.remoteDocument;
    }];
    pullConfig.conflictResolver = resolver;
    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    __block NSMutableArray<NSError*>* errors = [NSMutableArray array];
    [self run: pullConfig reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
        replicator = r;
        token = [r addDocumentReplicationListener: ^(CBLDocumentReplication* docRepl) {
            NSError* err = docRepl.documents.firstObject.error;
            if (err)
                [errors addObject: err];
        }];
    }];
    
    AssertEqual(errors.count, 1u);
    AssertEqual(errors.firstObject.code, CBLErrorNotFound);
    [replicator removeChangeListenerWithToken: token];
}

- (void) testConflictResolverPreservesFlags {
    NSString* docId = @"doc";
    NSData* content = [@"I'm a blob." dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType:@"text/plain" data: content];
    NSDictionary* localData = @{@"key1": @"value1", @"blob": blob};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    
    CBLDocument* localDoc = [self.db documentWithID: docId];
    Assert(0 != localDoc.c4Doc.revFlags);
    Assert(localDoc.c4Doc.revFlags & kRevHasAttachments);
    
    TestConflictResolver* resolver;
    CBLReplicatorConfiguration* pullConfig = [self config: kCBLReplicatorTypePull];
    
    __block C4RevisionFlags localRevFlags = 0;
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        localRevFlags = con.localDocument.c4Doc.revFlags;
        return con.localDocument;
    }];
    
    pullConfig.conflictResolver = resolver;
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    localDoc = [self.db documentWithID: docId];
    Assert(localDoc.c4Doc.revFlags & kRevHasAttachments & localRevFlags);
}

#endif

@end

#pragma mark - Helper class

@implementation TestConflictResolver {
    CBLDocument* (^_resolver)(CBLConflict*);
}

@synthesize winner=_winner;

// set this resolver, which will be used while resolving the conflict
- (instancetype) initWithResolver: (CBLDocument* (^)(CBLConflict*))resolver {
    self = [super init];
    if (self) {
        _resolver = resolver;
    }
    return self;
}

- (CBLDocument *) resolve:(CBLConflict *)conflict {
    _winner = _resolver(conflict);
    return _winner;
}

@end
