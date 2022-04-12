//
//  RemoteDatabaseTest.m
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

#import "RemoteDatabaseTest.h"
#import "CBLRemoteDatabase.h"
#import "CBLErrors.h"

@implementation RemoteDatabaseTest {
    CBLRemoteDatabase* _client;
}

#pragma mark - helper methods

- (void) startConnectedClient: (nullable NSURL*)url {
    _client = [[CBLRemoteDatabase alloc] initWithURL: url
                                        authenticator: nil];
}

- (void) validateDocument: (CBLDocument*)expDoc
                errorCode: (NSInteger)errorCode  {
    XCTestExpectation* e = [self expectationWithDescription: @"validation exp"];
    __block NSInteger code = errorCode;
    [_client documentWithID: expDoc.id completion:^(CBLDocument* doc, NSError* error) {
        if (code != 0) {
            AssertEqual(error.code, code);  // error code as expected
            AssertNil(doc);                 // empty doc in case of error.
        } else {
            AssertNil(error);               // empty error

                                            // same doc-information returned
            AssertEqualObjects(doc.id, expDoc.id);
            AssertEqualObjects([doc toDictionary], [expDoc toDictionary]);
        }
        [e fulfill];
    }];
    
    [self waitForExpectations: @[e] timeout: timeout];
}

#pragma mark - lifecycle

- (void) setUp {
    [super setUp];
    timeout = 10.0;
}

- (void) tearDown {
    if (_client)
        [_client stop];
    _client = nil;
    
    [self stopListen];
    [super tearDown];
}

#pragma mark - Tests

- (void) testConnectedClient {
    CBLDatabase.log.console.level = kCBLLogLevelDebug;
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
    [_client documentWithID: @"doc-1" completion: ^(CBLDocument* doc, NSError* error) {
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
    [_client documentWithID: @"doc-1" completion:^(CBLDocument* doc, NSError* error) {
        AssertEqual(error.code, CBLErrorUnknownHost);   // gets `unknown hostname` error
        AssertNil(doc);                                 // empty doc
        [e fulfill];
    }];
    [self waitForExpectations: @[e] timeout: timeout];
}

- (void) testSaveDocument {
    XCTestExpectation* e = [self expectationWithDescription: @"save document exp"];
    
    // start the listener
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    config.disableTLS = YES;
    [self listen: config errorCode: 0 errorDomain: nil];
    
    // start the connected client
    [self startConnectedClient: _listener.localEndpoint.url];
    
    CBLMutableDocument* doc1 = [self createDocument: @"doc-1"];
    [doc1 setString: @"someString" forKey: @"someKeyString"];
    [_client saveDocument: doc1
               completion:^(CBLDocument* doc, NSError *error) {
        AssertNil(error);
        
        [e fulfill];
    }];
    
    [self waitForExpectations: @[e] timeout: timeout];
    
    [self validateDocument: doc1 errorCode: 0];
}

- (void) testDeleteDocument {
    XCTestExpectation* e = [self expectationWithDescription: @"save document exp"];
    
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
    
    [_client deleteDocument: doc1 completion:^(CBLDocument* doc, NSError *error) {
        AssertNil(error);       // make sure no error
        AssertNil(doc);         // make sure it 'nil'
        [e fulfill];
    }];
    
    [self waitForExpectations: @[e] timeout: timeout];
    
    [self validateDocument: doc1 errorCode: CBLErrorNotFound];
}

- (void) testSaveUpdatedDocument {
    // ---
    // CREATE A DOC & SYNC & GET IT BACK
    // ---
    
    // save a doc in otherDB
    NSError* err = nil;
    CBLMutableDocument* doc1 = [self createDocument: @"doc-1"];
    [doc1 setString: @"someString" forKey: @"someKeyString"];
    Assert([self.otherDB saveDocument: doc1 error: &err], @"Fail to save db1 %@", err);
    
    // start the listener & get it to 'doc'
    __block CBLDocument* doc = nil;
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    config.disableTLS = YES;
    [self listen: config errorCode: 0 errorDomain: nil];
    [self startConnectedClient: _listener.localEndpoint.url];
    XCTestExpectation* eGet = [self expectationWithDescription: @"get document exp"];
    [_client documentWithID: @"doc-1" completion: ^(CBLDocument* d, NSError* error) {
        AssertNil(error);                     // empty error
        doc = d;
        [eGet fulfill];
    }];
    [self waitForExpectations: @[eGet] timeout: timeout];
    
    // ---
    // UPDATE THE DOC
    // ---
    XCTestExpectation* eSave = [self expectationWithDescription: @"save document exp"];
    CBLMutableDocument* doc2 = [doc toMutable];
    [doc2 setString: @"updated" forKey: @"revised"];
    [_client saveDocument: doc2
               completion:^(CBLDocument* d, NSError *error) {
        AssertNil(error);
        AssertEqualObjects(d.id, @"doc-1");
        AssertEqualObjects([d stringForKey: @"someKeyString"], @"someString");
        AssertEqualObjects([d stringForKey: @"revised"], @"updated");
        AssertEqual(d.count, 2);
        [eSave fulfill];
    }];
    
    [self waitForExpectations: @[eSave] timeout: timeout];
    
    // ---
    // GET THE DOC AGAIN AND VERIFY
    // ---
    XCTestExpectation* eGet2 = [self expectationWithDescription: @"get document exp2"];
    [_client documentWithID: @"doc-1" completion: ^(CBLDocument* d, NSError* error) {
        AssertNil(error);                     // empty error
        doc = d;
        [eGet2 fulfill];
    }];
    [self waitForExpectations: @[eGet2] timeout: timeout];
    AssertEqualObjects(doc.id, @"doc-1");
    AssertEqualObjects([doc stringForKey: @"someKeyString"], @"someString");
    AssertEqualObjects([doc stringForKey: @"revised"], @"updated");
    AssertEqual(doc.count, 2);
}

@end
