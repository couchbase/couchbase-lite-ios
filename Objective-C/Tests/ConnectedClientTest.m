//
//  ConnectedClientTest.m
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
#import "CBLConnectedClient.h"
#import "CBLErrors.h"

// Note: Only for EE runs

@interface ConnectedClientTest : URLEndpointListenerTest

@end

@implementation ConnectedClientTest {
    CBLConnectedClient* _client;
}

- (void)setUp {
    [super setUp];
    timeout = 5.0;
}

- (void)tearDown {
    if (_client)
        [_client stop];
    _client = nil;
    
    [self stopListen];
    [super tearDown];
}

- (void) startConnectedClient: (nullable NSURL*)url {
    _client = [[CBLConnectedClient alloc] initWithURL: url
                                        authenticator: nil];
}

- (void) testConnectedClient {
    XCTestExpectation* e = [self expectationWithDescription: @"expectation"];
    
    // create a doc in server (listener)
    NSError* err = nil;
    CBLMutableDocument* doc1 = [self createDocument: @"doc-1"];
    [doc1 setString: @"someString" forKey: @"someKeyString"];
    Assert([self.otherDB saveDocument: doc1 error: &err], @"Fail to save db1 %@", err);
    
    // start the listener
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    config.disableTLS = YES;
    [self listen: config errorCode: 0 errorDomain: nil];
    
    // start the connected client
    [self startConnectedClient: _listener.localEndpoint.url];
    
    // get the document with ID
    [_client documentWithID: @"doc-1" completion:^(CBLDocumentInfo* doc, NSError* error) {
        AssertNil(error);                     // empty error
        
        // same doc-information returned
        AssertEqualObjects(doc.id, @"doc-1");
        AssertEqualObjects(doc.revisionID, @"1-32a289db92b52a11cc4fe04216ada40c17296b45");
        AssertEqualObjects([doc stringForKey: @"someKeyString"], @"someString");
        AssertEqual(doc.count, 1);
        AssertEqualObjects(doc.keys, @[@"someKeyString"]);
        
        [e fulfill];
    }];
    [self waitForExpectations: @[e] timeout: timeout];
}

- (void) testConnectedClientUnknownHostname {
    XCTestExpectation* e = [self expectationWithDescription: @"ex"];
    
    // start the client to an unknown host
    [self startConnectedClient: [NSURL URLWithString: @"ws://foo"]];
    
    // try to get a doc
    [_client documentWithID: @"doc-1" completion:^(CBLDocumentInfo* doc, NSError* error) {
        AssertEqual(error.code, CBLErrorUnknownHost);   // gets `unknown hostname` error
        AssertNil(doc);                                 // empty doc
        [e fulfill];
    }];
    [self waitForExpectations: @[e] timeout: timeout];
}

@end
