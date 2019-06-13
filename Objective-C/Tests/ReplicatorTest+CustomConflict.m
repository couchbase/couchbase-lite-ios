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
    
    // checks whether the conflict resolver can be set/get to/from config
    AssertNotNil(config.conflictResolver);
    AssertEqualObjects(config.conflictResolver, resolver);
    AssertNotNil(repl.config.conflictResolver);
    AssertEqualObjects(repl.config.conflictResolver, resolver);
    
    // check whether comflict resolver can be edited after setting to replicator
    @try {
        repl.config.conflictResolver = nil;
    } @catch (NSException *exception) {
        AssertEqualObjects(exception.name, @"NSInternalInconsistencyException");
    }
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
    CBLMutableDocument* doc2 = [[otherDB documentWithID: docID] toMutable];
    if (remoteData) {
        [doc2 setData: remoteData];
        Assert([otherDB saveDocument: doc2 error: &error]);
    } else {
        Assert([otherDB deleteDocument: doc2 error: &error]);
    }
}

- (CBLReplicatorConfiguration*) config: (CBLReplicatorType)type {
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
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
    CBLDocument* savedDoc = [self.db documentWithID: docId];
    
    AssertEqualObjects(savedDoc.toDictionary, remoteData);
    
    UInt64 sequenceBeforePush = [otherDB documentWithID: docId].sequence;
    [self run: [self config: kCBLReplicatorTypePush] errorCode: 0 errorDomain: nil];
    
    // should be equal, so that nothing has pushed to remote
    AssertEqual(sequenceBeforePush, [otherDB documentWithID: docId].sequence);
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
    
    UInt64 sequenceBeforePush = [otherDB documentWithID: docId].sequence;
    [self run: [self config: kCBLReplicatorTypePush] errorCode: 0 errorDomain: nil];
    
    // there was changes to push to remote, and sequence increased
    Assert(sequenceBeforePush < [otherDB documentWithID: docId].sequence);
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
    NSError* error;
    UInt64 sequenceBeforePush = [otherDB documentWithID: docId].sequence;
    [self run: [self config: kCBLReplicatorTypePush] errorCode: 0 errorDomain: nil];
    
    // should be greater, so that it pushed new revision to remote
    Assert(sequenceBeforePush < [[CBLDocument alloc] initWithDatabase: otherDB
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
    CBLDocument* savedDoc = [self.db documentWithID: @"doc"];
    AssertNil(savedDoc);
    
    NSError* error;
    UInt64 sequenceBeforePush = [otherDB documentWithID: docId].sequence;
    [self run: [self config: kCBLReplicatorTypePush] errorCode: 0 errorDomain: nil];
    
    // should be greater, so that it pushed new revision to remote
    Assert(sequenceBeforePush < [[CBLDocument alloc] initWithDatabase: otherDB
                                                           documentID: docId
                                                       includeDeleted: YES error: &error].sequence);
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
    CBLDocument* savedDoc = [self.db documentWithID: @"doc"];
    AssertNil(savedDoc);
    
    NSError* error;
    UInt64 sequenceBeforePush = [[CBLDocument alloc] initWithDatabase: otherDB
                                                           documentID: docId
                                                       includeDeleted: YES error: &error].sequence;
    [self run: [self config: kCBLReplicatorTypePush] errorCode: 0 errorDomain: nil];
    
    // should be greater, so that it pushed new revision to remote
    AssertEqual(sequenceBeforePush, [[CBLDocument alloc] initWithDatabase: otherDB
                                                           documentID: docId
                                                       includeDeleted: YES error: &error].sequence);
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
    
    CBLDocument* savedDoc = [self.db documentWithID: docId];
    NSMutableDictionary* exp = [NSMutableDictionary dictionaryWithDictionary: localData];
    [exp setValue: @"local" forKey: @"edit"];
    AssertEqualObjects(savedDoc.toDictionary, exp);
    
    // EDIT REMOTE DOCUMENT
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        CBLMutableDocument* mDoc = con.remoteDocument.toMutable;
        [mDoc setString: @"remote" forKey: @"edit"];
        return mDoc;
    }];
    pullConfig.conflictResolver = resolver;
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    savedDoc = [self.db documentWithID: docId];
    exp = [NSMutableDictionary dictionaryWithDictionary: remoteData];
    [exp setValue: @"remote" forKey: @"edit"];
    AssertEqualObjects(savedDoc.toDictionary, exp);
    
    // CREATE NEW DOCUMENT
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        CBLMutableDocument* mDoc = [[CBLMutableDocument alloc] initWithID: con.localDocument.id];
        [mDoc setString: @"new-with-same-ID" forKey: @"docType"];
        return mDoc;
    }];
    pullConfig.conflictResolver = resolver;
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    savedDoc = [self.db documentWithID: docId];
    exp = [NSMutableDictionary dictionaryWithObject: @"new-with-same-ID" forKey: @"docType"];
    AssertEqualObjects(savedDoc.toDictionary, exp);
    
    UInt64 sequenceBeforePush = [otherDB documentWithID: docId].sequence;
    [self run: [self config: kCBLReplicatorTypePush] errorCode: 0 errorDomain: nil];
    
    // sequence before should be less than current; push sends some updated merged doc.
    Assert(sequenceBeforePush < [otherDB documentWithID: docId].sequence);
    
}

- (void) testDocumentReplicationEventForConflictedDocs {
    TestConflictResolver* resolver;
    
    // when resolution is skipped: here wrong doc-id throws an exception & skips it
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
    [self run: config reset: NO errorCode: 0 errorDomain: nil onReplicatorReady:^(CBLReplicator * r) {
        replicator = r;
        token = [r addDocumentReplicationListener:^(CBLDocumentReplication * docRepl) {
            for (CBLReplicatedDocument* replDoc in docRepl.documents) {
                [docIds addObject: replDoc.id];
            }
        }];
    }];
    
    // make sure only single listener event is fired when conflict occured.
    AssertEqual(docIds.count, 1u);
    AssertEqualObjects(docIds.firstObject, docId);
    [replicator removeChangeListenerWithToken: token];
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
    CBLDatabase.log.console.domains = kCBLLogDomainAll;
    CBLDatabase.log.console.level = kCBLLogLevelInfo;
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    TestConflictResolver* resolver;
    CBLReplicatorConfiguration* pullConfig = [self config: kCBLReplicatorTypePull];
    
    __weak CBLDatabase* weakOtherDB = otherDB;
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return [weakOtherDB documentWithID: con.localDocument.id]; // doc from different DB!!
    }];
    pullConfig.conflictResolver = resolver;
    
    // make sure resolver is thrown the exception and skips the resolution.
    __block id<CBLListenerToken> token;
    __block CBLReplicator* replicator;
    __block NSMutableArray<NSError*>* errors = [NSMutableArray array];
    [self run: pullConfig reset: NO errorCode: 0 errorDomain: nil onReplicatorReady: ^(CBLReplicator* r) {
        token = [r addDocumentReplicationListener: ^(CBLDocumentReplication* docRepl) {
            NSError* err = docRepl.documents.firstObject.error;
            if (err)
                [errors addObject: err];
        }];
    }];
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
            NSError* err = docRepl.documents.firstObject.error;
            if (err)
                [errors addObject: err];
        }];
    }];
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
                                 [otherDB documentWithID: docID]]];
    
    // delete local
    docID = @"doc2";
    [self makeConflictFor: docID withLocal: localData withRemote: remoteData];
    [self.db deleteDocument: [self.db documentWithID: docID] error: &error];
    [conflictedDocs addObject: @[[NSNull null], [otherDB documentWithID: docID]]];
    
    // delete remote
    docID = @"doc3";
    [self makeConflictFor: docID withLocal: localData withRemote: remoteData];
    [otherDB deleteDocument: [otherDB documentWithID: docID] error: &error];
    [conflictedDocs addObject: @[[self.db documentWithID: docID], [NSNull null]]];
    
    // delete local but higher remote generation.
    docID = @"doc4";
    [self makeConflictFor: docID withLocal: localData withRemote: remoteData];
    [self.db deleteDocument: [self.db documentWithID: docID] error: &error];
    doc = [[otherDB documentWithID: docID] toMutable];
    [doc setValue: @"value3" forKey: @"key3"];
    [otherDB saveDocument: doc error: &error];
    doc = [[otherDB documentWithID: docID] toMutable];
    [doc setValue: @"value4" forKey: @"key4"];
    [otherDB saveDocument: doc error: &error];
    [conflictedDocs addObject: @[[NSNull null], [otherDB documentWithID: docID]]];
    
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
    NSDictionary* localData = @{@"key1": @"value1", @"blob": blob};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    TestConflictResolver* resolver;
    CBLReplicatorConfiguration* pullConfig = [self config: kCBLReplicatorTypePull];
    [self makeConflictFor: docID withLocal: localData withRemote: remoteData];
    
    // RESOLVE WITH REMOTE and BLOB data in LOCAL
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.remoteDocument;
    }];
    pullConfig.conflictResolver = resolver;
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    AssertNil([[self.db documentWithID: docID] blobForKey: @"blob"]);
    AssertEqualObjects([[self.db documentWithID: docID] toDictionary], remoteData);
    
    // RESOLVE WITH LOCAL with BLOB data
    localData = @{@"key1": @"value1", @"blob": blob};
    remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docID withLocal: localData withRemote: remoteData];
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.localDocument;
    }];
    pullConfig.conflictResolver = resolver;
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    AssertEqualObjects([[self.db documentWithID: docID] blobForKey: @"blob"], blob);
    AssertEqualObjects([[self.db documentWithID: docID] toDictionary], localData);
    
    // RESOLVE WITH LOCAL and BLOB data in REMOTE
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
    
    // RESOLVE WITH REMOTE with BLOB data
    blob = [[CBLBlob alloc] initWithContentType:@"text/plain" data: content];
    localData = @{@"key1": @"value1"};
    remoteData = @{@"key2": @"value2", @"blob": blob};
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
