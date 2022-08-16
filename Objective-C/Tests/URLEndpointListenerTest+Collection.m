//
//  URLEndpointListenerTest+Collection.m
//  CouchbaseLite
//
//  Copyright (c) 2022 Couchbase, Inc All rights reserved.
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

#import "URLEndpointListenerTest.h"

@interface URLEndpointListenerTest_Collection : URLEndpointListenerTest

@end

@implementation URLEndpointListenerTest_Collection

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void) testCollectionsSingleShotPushPullReplication {
    if (!self.keyChainAccessAllowed) return;
    
    NSError* error = nil;
    CBLCollection* col1a = [self.db createCollectionWithName: @"colA"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1a);
    AssertNil(error);
    
    CBLCollection* col1b = [self.db createCollectionWithName: @"colB"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1b);
    AssertNil(error);
    
    CBLCollection* col2a = [self.otherDB createCollectionWithName: @"colA"
                                                            scope: @"scopeA" error: &error];
    AssertNotNil(col2a);
    AssertNil(error);
    
    CBLCollection* col2b = [self.otherDB createCollectionWithName: @"colB"
                                                            scope: @"scopeA" error: &error];
    AssertNotNil(col2b);
    AssertNil(error);
    
    [self createDocNumbered: col2a start: 0 num: 3];
    [self createDocNumbered: col2b start: 10 num: 5];
    AssertEqual(col1a.count, 0);
    AssertEqual(col1b.count, 0);
    AssertEqual(col2a.count, 3);
    AssertEqual(col2b.count, 5);
    
    Config* config = [[Config alloc] initWithCollections: @[col2a, col2b]];
    [self listen: config];
    
    CBLReplicatorConfiguration* rConfig = [[CBLReplicatorConfiguration alloc] initWithTarget: _listener.localEndpoint];
    rConfig.pinnedServerCertificate = (__bridge SecCertificateRef) _listener.tlsIdentity.certs[0];
    [rConfig addCollections: @[col1a, col1b] config: nil];
    
    [self run: rConfig errorCode: 0 errorDomain: nil];
    AssertEqual(col1a.count, 3);
    AssertEqual(col1b.count, 5);
    AssertEqual(col2a.count, 3);
    AssertEqual(col2b.count, 5);
    
    [self stopListener: _listener];
    _listener = nil;
}

- (void) testCollectionsContinuousPushPullReplication {
    if (!self.keyChainAccessAllowed) return;
    
    NSError* error = nil;
    CBLCollection* col1a = [self.db createCollectionWithName: @"colA"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1a);
    AssertNil(error);
    
    CBLCollection* col1b = [self.db createCollectionWithName: @"colB"
                                                       scope: @"scopeA" error: &error];
    AssertNotNil(col1b);
    AssertNil(error);
    
    CBLCollection* col2a = [self.otherDB createCollectionWithName: @"colA"
                                                            scope: @"scopeA" error: &error];
    AssertNotNil(col2a);
    AssertNil(error);
    
    CBLCollection* col2b = [self.otherDB createCollectionWithName: @"colB"
                                                            scope: @"scopeA" error: &error];
    AssertNotNil(col2b);
    AssertNil(error);
    
    [self createDocNumbered: col2a start: 0 num: 10];
    [self createDocNumbered: col2b start: 10 num: 10];
    
    Config* config = [[Config alloc] initWithCollections: @[col2a, col2b]];
    [self listen: config];
    
    CBLReplicatorConfiguration* rConfig = [[CBLReplicatorConfiguration alloc] initWithTarget: _listener.localEndpoint];
    rConfig.continuous = YES;
    rConfig.pinnedServerCertificate = (__bridge SecCertificateRef) _listener.tlsIdentity.certs[0];
    [rConfig addCollections: @[col1a, col1b] config: nil];
    
    [self run: rConfig errorCode: 0 errorDomain: nil];
    AssertEqual(col1a.count, 10);
    AssertEqual(col1b.count, 10);
    AssertEqual(col2a.count, 10);
    AssertEqual(col2b.count, 10);
    
    [self stopListener: _listener];
    _listener = nil;
}

- (void) testMismatchedCollectionReplication {
    if (!self.keyChainAccessAllowed) return;
    
    NSError* error = nil;
    CBLCollection* colA = [self.db createCollectionWithName: @"colA"
                                                      scope: @"scopeA" error: &error];
    AssertNotNil(colA);
    AssertNil(error);
    
    [self createDocNumbered: colA start: 0 num: 10];
    
    CBLCollection* colB = [self.otherDB createCollectionWithName: @"colB"
                                                           scope: @"scopeA" error: &error];
    AssertNotNil(colB);
    AssertNil(error);
    
    Config* config = [[Config alloc] initWithCollections: @[colB]];
    [self listen: config];
    
    CBLReplicatorConfiguration* rConfig = [[CBLReplicatorConfiguration alloc] initWithTarget: _listener.localEndpoint];
    rConfig.pinnedServerCertificate = (__bridge SecCertificateRef) _listener.tlsIdentity.certs[0];
    [rConfig addCollections: @[colA] config: nil];
    
    [self run: rConfig errorCode: CBLErrorHTTPNotFound errorDomain: CBLErrorDomain];
    
    [self stopListener: _listener];
    _listener = nil;
}

- (void) testCreateListenerConfigWithEmptyCollection {
    [self expectException: NSInvalidArgumentException in:^{
        Config* config = [[Config alloc] initWithCollections: @[]];
        NSLog(@"%@", config);
    }];
}

@end
