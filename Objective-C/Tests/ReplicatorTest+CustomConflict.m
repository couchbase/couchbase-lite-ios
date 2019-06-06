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
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id pushConfig = [self configWithTarget: target type :kCBLReplicatorTypePush continuous: NO];
    [self run: pushConfig errorCode: 0 errorDomain: nil];
    
    // Now make different changes in db and otherDB:
    doc1 = [[self.db documentWithID: docID] toMutable];
    [doc1 setData: localData];
    Assert([self.db saveDocument: doc1 error: &error]);
    
    // pass the remote revision
    CBLMutableDocument* doc2 = [[otherDB documentWithID: docID] toMutable];
    Assert(doc2);
    [doc2 setData: remoteData];
    Assert([otherDB saveDocument: doc2 error: &error]);
}

- (CBLReplicatorConfiguration*) pullConfig {
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    return [self configWithTarget: target
                             type: kCBLReplicatorTypePull
                       continuous: NO];
}

- (void) testConflictResolverRemoteWins {
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    
    TestConflictResolver* resolver;
    CBLReplicatorConfiguration* pullConfig = [self pullConfig];
    
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.remoteDocument;
    }];
    pullConfig.conflictResolver = resolver;
    
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    // Check that it was resolved:
    AssertEqual(self.db.count, 1u);
    CBLDocument* savedDoc = [self.db documentWithID: docId];
    
    AssertEqualObjects(savedDoc.toDictionary, remoteData);
}

- (void) testConflictResolverLocalWins {
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    
    TestConflictResolver* resolver;
    CBLReplicatorConfiguration* pullConfig = [self pullConfig];
    
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return con.localDocument;
    }];
    pullConfig.conflictResolver = resolver;
    
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    // Check that it was resolved:
    AssertEqual(self.db.count, 1u);
    AssertEqualObjects([self.db documentWithID: docId].toDictionary, localData);
}

- (void) testConflictResolverNullDoc {
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    
    TestConflictResolver* resolver;
    CBLReplicatorConfiguration* pullConfig = [self pullConfig];
    
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return nil;
    }];
    pullConfig.conflictResolver = resolver;
    
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    // Check whether the document is deleted, and returns null.
    AssertEqual(self.db.count, 0u);
    CBLDocument* savedDoc = [self.db documentWithID: @"doc"];
    AssertNil(savedDoc);
}

- (void) testConflictResolverDeletedLocalWins {
    NSString* docId = @"doc";
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: nil withRemote: remoteData];
    
    TestConflictResolver* resolver;
    CBLReplicatorConfiguration* pullConfig = [self pullConfig];
    
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return nil;
    }];
    pullConfig.conflictResolver = resolver;
    
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    // Check whether the document gets deleted and return null.
    AssertEqual(self.db.count, 0u);
    CBLDocument* savedDoc = [self.db documentWithID: @"doc"];
    AssertNil(savedDoc);
}

- (void) testConflictResolverDeletedRemoteWins {
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    [self makeConflictFor: docId withLocal: localData withRemote: nil];
    
    TestConflictResolver* resolver;
    CBLReplicatorConfiguration* pullConfig = [self pullConfig];
    
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return nil;
    }];
    pullConfig.conflictResolver = resolver;
    
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    // Check whether it deletes the document and returns nil.
    AssertEqual(self.db.count, 0u);
    CBLDocument* savedDoc = [self.db documentWithID: @"doc"];
    AssertNil(savedDoc);
}

- (void) testConflictResolverMergeDoc {
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    
    TestConflictResolver* resolver;
    CBLReplicatorConfiguration* pullConfig = [self pullConfig];
    
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
    CBLReplicatorConfiguration* config = [self pullConfig];
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
    CBLReplicatorConfiguration* pullConfig = [self pullConfig];
    
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
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    TestConflictResolver* resolver;
    CBLReplicatorConfiguration* pullConfig = [self pullConfig];
    
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        return [CBLMutableDocument documentWithID: @"wrongDocID"];
    }];
    pullConfig.conflictResolver = resolver;
    
    // make sure resolver is thrown the exception and skips the resolution.
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

- (void) testConflictResolverDifferentDBDoc {
    CBLDatabase.log.console.domains = kCBLLogDomainAll;
    CBLDatabase.log.console.level = kCBLLogLevelInfo;
    NSString* docId = @"doc";
    NSDictionary* localData = @{@"key1": @"value1"};
    NSDictionary* remoteData = @{@"key2": @"value2"};
    [self makeConflictFor: docId withLocal: localData withRemote: remoteData];
    TestConflictResolver* resolver;
    CBLReplicatorConfiguration* pullConfig = [self pullConfig];
    
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
    CBLReplicatorConfiguration* pullConfig = [self pullConfig];
    
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
