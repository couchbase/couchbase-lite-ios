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

- (void) setUp {
    [super setUp];
}

- (void) tearDown {
    [super tearDown];
}

#pragma mark - Tests without replication

- (void) testConflictResolverConfigProperty {
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
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
    CBLDocument* savedDoc = [self.db documentWithID: @"doc"];
    
    NSDictionary* exp = @{@"species": @"Tiger", @"name": @"Hobbes"};
    AssertEqualObjects(savedDoc.toDictionary, exp);
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
    
    resolver = [[TestConflictResolver alloc] initWithResolver: ^CBLDocument* (CBLConflict* con) {
        CBLMutableDocument* mDoc = con.localDocument.toMutable;
        [mDoc setString: @"local" forKey: @"edit"];
        return mDoc;
    }];
    pullConfig.conflictResolver = resolver;
    
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    // Check that it was resolved:
    AssertEqual(self.db.count, 1u);
    CBLDocument* savedDoc = [self.db documentWithID: @"doc"];
    
    NSMutableDictionary* exp = [NSMutableDictionary dictionaryWithDictionary: localData];
    [exp setValue: @"local" forKey: @"edit"];
    AssertEqualObjects(savedDoc.toDictionary, exp);
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
