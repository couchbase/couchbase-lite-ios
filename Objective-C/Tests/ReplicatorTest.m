//
//  ReplicatorTest.m
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
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

#import "CBLTestCase.h"
#import "CBLJSON.h"
#import "CBLReplicator+Backgrounding.h"
#import "CBLReplicator+Internal.h"
#import "CBLURLEndpoint+Internal.h"
#import "CBLDatabase+Internal.h"
#import "CollectionUtils.h"


@interface ReplicatorTest : CBLTestCase
@end


@implementation ReplicatorTest
{
    CBLDatabase* otherDB;
    CBLReplicator* repl;
    NSTimeInterval timeout;
    BOOL _stopped;
    BOOL _pinServerCert;
}


- (void) setUp {
    [super setUp];

    timeout = 5.0;
    _pinServerCert = YES;
    NSError* error;
    otherDB = [self openDBNamed: @"otherdb" error: &error];
    AssertNil(error);
    AssertNotNil(otherDB);
}


- (void) tearDown {
    NSError* error;
    Assert([otherDB close: &error]);
    otherDB = nil;
    repl = nil;
    [super tearDown];
}


/** Returns an endpoint for a Sync Gateway test database, or nil if SG tests are not enabled.
    To enable these tests, set the hostname of the server in the environment variable
    "CBL_TEST_HOST".
    The port number defaults to 4984, or 4994 for SSL. To override these, set the environment
    variables "CBL_TEST_PORT" and/or "CBL_TEST_PORT_SSL".
    Note: On iOS, all endpoints will be SSL regardless of the `secure` flag. */
- (CBLURLEndpoint*) remoteEndpointWithName: (NSString*)dbName secure: (BOOL)secure {
    NSString* host = NSProcessInfo.processInfo.environment[@"CBL_TEST_HOST"];
    if (!host) {
        Log(@"NOTE: Skipping test: no CBL_TEST_HOST configured in environment");
        return nil;
    }

    NSString* portKey = secure ? @"CBL_TEST_PORT_SSL" : @"CBL_TEST_PORT";
    NSInteger port = NSProcessInfo.processInfo.environment[portKey].integerValue;
    if (!port)
        port = secure ? 4994 : 4984;

    NSURLComponents *comp = [NSURLComponents new];
    comp.scheme = secure ? kCBLURLEndpointTLSScheme : kCBLURLEndpointScheme;
    comp.host = host;
    comp.port = @(port);
    comp.path = [NSString stringWithFormat:@"/%@", dbName];
    NSURL* url = comp.URL;
    Assert(url);
    return [[CBLURLEndpoint alloc] initWithURL: url];
}


- (void) eraseRemoteEndpoint: (CBLURLEndpoint*)endpoint {
    Assert([endpoint.url.path isEqualToString: @"/scratch"], @"Only scratch db should be erased");
    [self sendRequestToEndpoint: endpoint method: @"POST" path: @"_flush" body: nil];
    Log(@"Erased remote database %@", endpoint.url);
}


- (id) sendRequestToEndpoint: (CBLURLEndpoint*)endpoint
                      method: (NSString*)method
                        path: (nullable NSString*)path
                        body: (nullable id)body
{
    NSURL* endpointURL = endpoint.url;
    NSURLComponents *comp = [NSURLComponents new];
    comp.scheme = [endpointURL.scheme isEqualToString: kCBLURLEndpointTLSScheme] ? @"https" : @"http";
    comp.host = endpointURL.host;
    comp.port = @([endpointURL.port intValue] + 1);   // assuming admin port is at usual offse
    path = path ? ([path hasPrefix: @"/"] ? path : [@"/" stringByAppendingString: path]) : @"";
    comp.path = [NSString stringWithFormat: @"%@%@", endpointURL.path, path];
    NSURL* url = comp.URL;
    Assert(url);
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL: url];
    request.HTTPMethod = method;
    if (body) {
        if ([body isKindOfClass: [NSData class]]) {
            request.HTTPBody = body;
        } else {
            NSError* err = nil;
            request.HTTPBody = [CBLJSON dataWithJSONObject: body options:0 error: &err];
            AssertNil(err);
        }
    }
    
    __block NSError* error = nil;
    __block NSInteger status = 0;
    __block NSData* data = nil;
    XCTestExpectation* x = [self expectationWithDescription: @"Complete Request"];
    NSURLSessionDataTask* task = [[NSURLSession sharedSession] dataTaskWithRequest: request
                                                                 completionHandler:
                                  ^(NSData *d, NSURLResponse *r, NSError *e)
                                  {
                                      error = e;
                                      data = d;
                                      status = ((NSHTTPURLResponse*)r).statusCode;
                                      [x fulfill];
                                  }];
    [task resume];
    [self waitForExpectations: @[x] timeout: timeout];
    
    if (error != nil || status >= 300) {
        XCTFail(@"Failed to send request; URL=<%@>, Method=<%@>, Status=%ld, Error=%@",
                url, method, (long)status, error);
        return nil;
    } else {
        Log(@"Send request succeeded; URL=<%@>, Method=<%@>, Status=%ld",
            url, method, status);
        id result = nil;
        if (data && data.length > 0) {
            result = [CBLJSON JSONObjectWithData: data options: 0 error: &error];
            Assert(result, @"Couldn't parse JSON response: %@", error);
        }
        return result;
    }
}


- (SecCertificateRef) secureServerCert {
    NSData* certData = [self dataFromResource: @"SelfSigned" ofType: @"cer"];
    SecCertificateRef cert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certData);
    Assert(cert);
    return (SecCertificateRef)CFAutorelease(cert);
}


- (CBLReplicatorConfiguration*) configWithTarget: (id<CBLEndpoint>)target
                                            type: (CBLReplicatorType)type
                                      continuous: (BOOL)continuous
{
    return [self configWithTarget: target
                             type: type
                       continuous: continuous
                    authenticator: nil];
}


- (CBLReplicatorConfiguration*) configWithTarget: (id<CBLEndpoint>)target
                                            type: (CBLReplicatorType)type
                                      continuous: (BOOL)continuous
                                   authenticator: (CBLAuthenticator*)authenticator
{
    CBLReplicatorConfiguration* c = [[CBLReplicatorConfiguration alloc] initWithDatabase: self.db
                                                                                  target: target];
    c.replicatorType = type;
    c.continuous = continuous;
    c.authenticator = authenticator;
    
    if ([$castIf(CBLURLEndpoint, target).url.scheme isEqualToString: @"wss"] && _pinServerCert)
        c.pinnedServerCertificate = self.secureServerCert;
    
    if (continuous)
        c.checkpointInterval = 1.0; // For testing only
    
    return c;
}


- (void) run: (CBLReplicatorConfiguration*)config
   errorCode: (NSInteger)errorCode
 errorDomain: (NSString*)errorDomain
{
    [self run: config reset: NO errorCode: errorCode errorDomain: errorDomain];
}

- (void) run: (CBLReplicatorConfiguration*)config
       reset: (BOOL)reset
   errorCode: (NSInteger)errorCode
 errorDomain: (NSString*)errorDomain
{
    repl = [[CBLReplicator alloc] initWithConfig: config];
    
    XCTestExpectation* x = [self expectationWithDescription: @"Replicator Change"];
    __weak typeof(self) wSelf = self;
    id token = [repl addChangeListener: ^(CBLReplicatorChange* change) {
        typeof(self) strongSelf = wSelf;
        [strongSelf verifyChange: change errorCode: errorCode errorDomain:errorDomain];
        if (config.continuous && change.status.activity == kCBLReplicatorIdle
                    && change.status.progress.completed == change.status.progress.total) {
            [strongSelf->repl stop];
        }
        if (change.status.activity == kCBLReplicatorStopped) {
            [x fulfill];
        }
    }];
    
    if (reset)
        [repl resetCheckpoint];
    
    [repl start];
    @try {
        [self waitForExpectations: @[x] timeout: timeout];
    }
    @finally {
        [repl stop];
        [repl removeChangeListenerWithToken: token];
    }
}


- (void) verifyChange: (CBLReplicatorChange*)change
            errorCode: (NSInteger)code
          errorDomain: (NSString*)domain
{
    CBLReplicatorStatus* s = change.status;
    
    static const char* const kActivityNames[5] = { "stopped", "offline", "connecting", "idle", "busy" };
    NSLog(@"---Status: %s (%llu / %llu), lastError = %@",
          kActivityNames[s.activity], s.progress.completed, s.progress.total,
          s.error.localizedDescription);
    
    if (s.activity == kCBLReplicatorStopped) {
        if (code != 0) {
            AssertEqual(s.error.code, code);
            if (domain)
                AssertEqualObjects(s.error.domain, domain);
        } else
            AssertNil(s.error);
    }
}


#pragma mark - TESTS:

#ifdef COUCHBASE_ENTERPRISE

- (void)testEmptyPush {
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
}


- (void) testPushDoc {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setValue: @"Tiger" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    AssertEqual(self.db.count, 1u);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setValue: @"Cat" forKey: @"name"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(otherDB.count, 2u);
    CBLDocument* savedDoc1 = [otherDB documentWithID: @"doc1"];
    AssertEqualObjects([savedDoc1 stringForKey:@"name"], @"Tiger");
}


- (void) testPushDocContinuous {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setValue: @"Tiger" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    AssertEqual(self.db.count, 1u);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setValue: @"Cat" forKey: @"name"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: YES];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(otherDB.count, 2u);
    CBLDocument* savedDoc1 = [otherDB documentWithID: @"doc1"];
    AssertEqualObjects([savedDoc1 stringForKey:@"name"], @"Tiger");
}


- (void) testPullDoc {
    // For https://github.com/couchbase/couchbase-lite-core/issues/156
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setValue: @"Tiger" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    AssertEqual(self.db.count, 1u);

    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setValue: @"Cat" forKey: @"name"];
    Assert([otherDB saveDocument: doc2 error: &error]);

    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];

    AssertEqual(self.db.count, 2u);
    CBLDocument* savedDoc2 = [self.db documentWithID:@"doc2"];
    AssertEqualObjects([savedDoc2 stringForKey:@"name"], @"Cat");
}


- (void) testPullDocContinuous {
    // For https://github.com/couchbase/couchbase-lite-core/issues/156
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID:@"doc1"];
    [doc1 setValue: @"Tiger" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    AssertEqual(self.db.count, 1u);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID:@"doc2"];
    [doc2 setValue: @"Cat" forKey: @"name"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: YES];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(self.db.count, 2u);
    CBLDocument* savedDoc2 = [self.db documentWithID: @"doc2"];
    AssertEqualObjects([savedDoc2 stringForKey:@"name"], @"Cat");
}


- (void) testPullConflict {
    // Create a document and push it to otherDB:
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID:@"doc"];
    [doc1 setValue: @"Tiger" forKey: @"species"];
    Assert([self.db saveDocument: doc1 error: &error]);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id pushConfig = [self configWithTarget: target type :kCBLReplicatorTypePush continuous: NO];
    [self run: pushConfig errorCode: 0 errorDomain: nil];
    
    // Now make different changes in db and otherDB:
    doc1 = [[self.db documentWithID: @"doc"] toMutable];
    [doc1 setValue: @"Hobbes" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    
    CBLMutableDocument* doc2 = [[otherDB documentWithID: @"doc"] toMutable];
    Assert(doc2);
    [doc2 setValue: @"striped" forKey: @"pattern"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    [doc2 setValue: @"black-yellow" forKey: @"color"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    // Pull from otherDB, creating a conflict to resolve:
    id pullConfig = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO];
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    // Check that it was resolved:
    AssertEqual(self.db.count, 1u);
    CBLDocument* savedDoc = [self.db documentWithID: @"doc"];
    
    // Most-Active Win:
    NSDictionary* expectedResult = @{@"species": @"Tiger",
                                     @"pattern": @"striped",
                                     @"color": @"black-yellow"};
    AssertEqualObjects(savedDoc.toDictionary, expectedResult);
    
    // Push to otherDB again to verify there is no replication conflict now,
    // and that otherDB ends up with the same resolved document:
    [self run: pushConfig errorCode: 0 errorDomain: nil];
    
    AssertEqual(otherDB.count, 1u);
    CBLDocument* otherSavedDoc = [otherDB documentWithID: @"doc"];
    AssertEqualObjects(otherSavedDoc.toDictionary, expectedResult);
}


- (void) testPullConflictNoBaseRevision {
    // Create the conflicting docs separately in each database. They have the same base revID
    // because the contents are identical, but because the db never pushed revision 1, it doesn't
    // think it needs to preserve its body; so when it pulls a conflict, there won't be a base
    // revision for the resolver.
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc"];
    [doc1 setValue: @"Tiger" forKey: @"species"];
    Assert([self.db saveDocument: doc1 error: &error]);
    [doc1 setValue: @"Hobbes" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc"];
    [doc2 setValue: @"Tiger" forKey: @"species"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    [doc2 setValue: @"striped" forKey: @"pattern"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    [doc2 setValue: @"black-yellow" forKey: @"color"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type :kCBLReplicatorTypePull continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(self.db.count, 1u);
    CBLDocument* savedDoc = [self.db documentWithID: @"doc"];
    AssertEqualObjects(savedDoc.toDictionary, (@{@"species": @"Tiger",
                                                 @"pattern": @"striped",
                                                 @"color": @"black-yellow"}));
}


- (void) testPullConflictDeleteWins {
    // Create a document and push it to otherDB:
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID:@"doc"];
    [doc1 setValue: @"Tiger" forKey: @"species"];
    Assert([self.db saveDocument: doc1 error: &error]);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id pushConfig = [self configWithTarget: target type :kCBLReplicatorTypePush continuous: NO];
    [self run: pushConfig errorCode: 0 errorDomain: nil];
    
    // Delete the document from db:
    Assert([self.db deleteDocument: doc1 error: &error]);
    AssertNil([self.db documentWithID: doc1.id]);
    
    // Update the document in otherDB:
    CBLMutableDocument* doc2 = [[otherDB documentWithID: doc1.id] toMutable];
    Assert(doc2);
    [doc2 setValue: @"striped" forKey: @"pattern"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    [doc2 setValue: @"black-yellow" forKey: @"color"];
    Assert([otherDB saveDocument: doc2 error: &error]);
    
    // Pull from otherDB, creating a conflict to resolve:
    id pullConfig = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO];
    [self run: pullConfig errorCode: 0 errorDomain: nil];
    
    // Check that it was resolved as delete wins:
    AssertEqual(self.db.count, 0u);
    AssertNil([self.db documentWithID: doc1.id]);
}


- (void) testStopContinuousReplicator {
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePushAndPull continuous: YES];
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: config];
    
    NSArray* stopWhen = @[@(kCBLReplicatorConnecting), @(kCBLReplicatorBusy),
                          @(kCBLReplicatorIdle), @(kCBLReplicatorIdle)];
    NSArray* activities = @[@"stopped", @"offline", @"connecting", @"idle", @"busy"];
    for (id when in stopWhen) {
        XCTestExpectation* x = [self expectationWithDescription: @"Replicator Change"];
        __weak typeof(self) wSelf = self;
        id token = [r addChangeListener: ^(CBLReplicatorChange *change) {
            [wSelf verifyChange: change errorCode: 0 errorDomain: nil];
            int whenValue = [when intValue];
            if (change.status.activity == whenValue) {
                NSLog(@"***** Stop Replicator (when %@) ******", activities[whenValue]);
                [change.replicator stop];
            } else if (change.status.activity == kCBLReplicatorStopped) {
                [x fulfill];
            }
        }];
        
        NSLog(@"***** Start Replicator ******");
        [r start];
        [self waitForExpectations: @[x] timeout: 10.0];
        [r removeChangeListenerWithToken: token];
        
        // Add some delay:
        [NSThread sleepForTimeInterval: 1.0];
    }
    r = nil;
}


// Runs -testStopContinuousReplicator over and over again indefinitely. (Disabled, obviously)
- (void) _testStopContinuousReplicatorForever {
    for (int i = 0; true; i++) {
        @autoreleasepool {
            Log(@"**** Begin iteration %d ****", i);
            @autoreleasepool {
                [self testStopContinuousReplicator];
            }
            Log(@"**** End iteration %d ****", i);
            fprintf(stderr, "\n\n");
            [self tearDown];
            [NSThread sleepForTimeInterval: 1.0];
            [self setUp];
        }
    }
}


- (void) testCloseDatabaseWithActiveReplicator {
    // Add a replicator to the DB:
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePushAndPull continuous: YES];
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: config];
    
    XCTestExpectation *x1 = [self expectationWithDescription: @"Idle"];
    XCTestExpectation *x2 = [self expectationWithDescription: @"Stop"];
    id token = [r addChangeListener: ^(CBLReplicatorChange* change) {
        if (change.status.activity == kCBLReplicatorIdle)
            [x1 fulfill];
        
        if (change.status.activity == kCBLReplicatorStopped)
            [x2 fulfill];
    }];
    
    [r start];
    AssertEqual(self.db.activeReplications.count,(unsigned long)1);
    [self waitForExpectations: @[x1] timeout: 5.0];
    
    // Close Database:
    [self expectError: CBLErrorDomain code: CBLErrorBusy in: ^BOOL(NSError** err) {
        return [self.db close: err];
    }];
    
    [r stop];
    [self waitForExpectations: @[x2] timeout: 5.0];
    [r removeChangeListenerWithToken: token];
    r = nil;
    AssertEqual(self.db.activeReplications.count, (unsigned long)0);
}


- (void) testDeleteDatabaseWithActiveReplicator {
    // add a replicator to the DB
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePushAndPull continuous: YES];
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: config];
    
    XCTestExpectation *x1 = [self expectationWithDescription: @"Connect"];
    XCTestExpectation *x2 = [self expectationWithDescription: @"Stop"];
    
    // add observer to check if replicators are stopped on DB close
    id token = [r addChangeListener: ^(CBLReplicatorChange* change) {
        if (change.status.activity == kCBLReplicatorConnecting)
            [x1 fulfill];
        
        if (change.status.activity == kCBLReplicatorStopped)
            [x2 fulfill];
    }];
    
    [r start];
    AssertEqual(self.db.activeReplications.count,(unsigned long)1);
    [self waitForExpectations: @[x1] timeout: 5.0];
    
    // Close Database:
    [self expectError: CBLErrorDomain code: CBLErrorBusy in: ^BOOL(NSError** err) {
        return [self.db delete: err];
    }];
    
    [r stop];
    [self waitForExpectations: @[x2] timeout: 5.0];
    [r removeChangeListenerWithToken: token];
    r = nil;
    
    // Close Database - This should trigger a replication stop which should be caught by listener
    NSError* error;
    Assert([self.db delete:&error], @"Cannot delete database: %@", error);
}


- (void) testPushBlob {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    NSData* data = [self dataFromResource: @"image" ofType: @"jpg"];
    Assert(data);
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType: @"image/jpg"
                                                    data: data];
    [doc1 setBlob: blob forKey: @"blob"];
    Assert([self.db saveDocument: doc1 error: &error]);
    AssertEqual(self.db.count, 1u);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(otherDB.count, 1u);
    CBLDocument* savedDoc1 = [otherDB documentWithID: @"doc1"];
    AssertEqualObjects([savedDoc1 blobForKey:@"blob"], blob);
}


- (void) testPullBlob {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    NSData* data = [self dataFromResource: @"image" ofType: @"jpg"];
    Assert(data);
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType: @"image/jpg"
                                                    data: data];
    [doc1 setBlob: blob forKey: @"blob"];
    Assert([otherDB saveDocument: doc1 error: &error]);
    AssertEqual(otherDB.count, 1u);
    
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: YES];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(self.db.count, 1u);
    CBLDocument* savedDoc1 = [self.db documentWithID: @"doc1"];
    AssertEqualObjects([savedDoc1 blobForKey:@"blob"], blob);
}


#if TARGET_OS_IPHONE


- (void) testSwitchBackgroundForeground {
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePushAndPull continuous: YES];
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: config];
    
    static NSInteger numRounds = 10;
    
    NSMutableArray* foregroundExps = [NSMutableArray arrayWithCapacity: numRounds + 1];
    NSMutableArray* backgroundExps = [NSMutableArray arrayWithCapacity: numRounds];
    for (NSInteger i = 0; i < numRounds; i++) {
        [foregroundExps addObject: [self expectationWithDescription: @"Foregrounding"]];
        [backgroundExps addObject: [self expectationWithDescription: @"Backgrounding"]];
    }
    [foregroundExps addObject: [self expectationWithDescription: @"Foregrounding"]];
    
    __block NSInteger backgroundCount = 0;
    __block NSInteger foregroundCount = 0;
    
    XCTestExpectation* stopped = [self expectationWithDescription: @"Stopped"];
    
    id token = [r addChangeListener: ^(CBLReplicatorChange* change) {
        AssertNil(change.status.error);
        if (change.status.activity == kCBLReplicatorIdle) {
            [foregroundExps[foregroundCount++] fulfill];
        } else if (change.status.activity == kCBLReplicatorOffline) {
            [backgroundExps[backgroundCount++] fulfill];
        } else if (change.status.activity == kCBLReplicatorStopped) {
            [stopped fulfill];
        }
    }];
    
    [r start];
    [self waitForExpectations: @[foregroundExps[0]] timeout: 5.0];
    
    for (int i = 0; i < numRounds; i++) {
        [r appBackgrounding];
        [self waitForExpectations: @[backgroundExps[i]] timeout: 5.0];
        
        [r appForegrounding];
        [self waitForExpectations: @[foregroundExps[i+1]] timeout: 5.0];
    }
    
    [r stop];
    [self waitForExpectations: @[stopped] timeout: 5.0];
    
    AssertEqual(foregroundCount, numRounds + 1);
    AssertEqual(backgroundCount, numRounds);
    
    [r removeChangeListenerWithToken: token];
    r = nil;
}


- (void) testBackgroundingWhenStopping {
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePushAndPull continuous: YES];
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: config];
    
    __block BOOL foregrounding = NO;
    
    XCTestExpectation* idle = [self expectationWithDescription: @"Idle after starting"];
    XCTestExpectation* stopped = [self expectationWithDescription: @"Stopped"];
    XCTestExpectation* done = [self expectationWithDescription: @"Done"];
    
    id token = [r addChangeListener: ^(CBLReplicatorChange* change) {
        Assert(!foregrounding);
        AssertNil(change.status.error);
        Assert(change.status.activity != kCBLReplicatorOffline);
        
        if (change.status.activity == kCBLReplicatorIdle) {
            [idle fulfill];
        } else if (change.status.activity == kCBLReplicatorStopped) {
            [stopped fulfill];
        }
    }];
    
    [r start];
    [self waitForExpectations: @[idle] timeout: 5.0];
    
    [r stop];
    
    // This shouldn't prevent the replicator to stop:
    [r appBackgrounding];
    [self waitForExpectations: @[stopped] timeout: 5.0];
    
    // This shouldn't wake up the replicator:
    foregrounding = YES;
    [r appForegrounding];
    
    // Wait for 0.3 seconds to ensure no more changes notified and cause !foregrounding to fail:
    id block = [NSBlockOperation blockOperationWithBlock: ^{ [done fulfill]; }];
    [NSTimer scheduledTimerWithTimeInterval: 0.3
                                     target: block
                                   selector: @selector(main) userInfo: nil repeats: NO];
    [self waitForExpectations: @[done] timeout: 1.0];
    
    [r removeChangeListenerWithToken: token];
    r = nil;
}

#endif // TARGET_OS_IPHONE


- (void) testResetCheckpoint {
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    [doc1 setString: @"Tiger" forKey: @"species"];
    [doc1 setString: @"Hobbes" forKey: @"name"];
    Assert([self.db saveDocument: doc1 error: &error]);
    
    CBLMutableDocument* doc2 = [[CBLMutableDocument alloc] initWithID: @"doc2"];
    [doc2 setString: @"Tiger" forKey: @"species"];
    [doc2 setString: @"striped" forKey: @"pattern"];
    Assert([self.db saveDocument: doc2 error: &error]);
    
    // Push:
    id target = [[CBLDatabaseEndpoint alloc] initWithDatabase: otherDB];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    // Pull:
    config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    AssertEqual(self.db.count, 2u);
    
    CBLDocument* doc = [self.db documentWithID: @"doc1"];
    Assert([self.db purgeDocument: doc error: &error]);
    
    doc = [self.db documentWithID: @"doc2"];
    Assert([self.db purgeDocument: doc error: &error]);
    
    AssertEqual(self.db.count, 0u);
    
    // Pull again, shouldn't have any new changes:
    [self run: config errorCode: 0 errorDomain: nil];
    AssertEqual(self.db.count, 0u);
    
    // Reset and pull:
    [self run: config reset: YES errorCode: 0 errorDomain: nil];
    AssertEqual(self.db.count, 2u);
}


#endif // COUCHBASE_ENTERPRISE


#pragma mark - Sync Gateway Tests


- (void) testAuthenticationFailure_SG {
    id target = [self remoteEndpointWithName: @"seekrit" secure: NO];
    if (!target)
        return;
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO];
    [self run: config errorCode: CBLErrorHTTPAuthRequired errorDomain: CBLErrorDomain];
}


- (void) testAuthenticatedPull_SG {
    id target = [self remoteEndpointWithName: @"seekrit" secure: NO];
    if (!target)
        return;
    id auth = [[CBLBasicAuthenticator alloc] initWithUsername: @"pupshaw" password: @"frank"];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO authenticator: auth];
    [self run: config errorCode: 0 errorDomain: nil];
}


- (void) testPushBlob_SG {
    id target = [self remoteEndpointWithName: @"scratch" secure: NO];
    if (!target)
        return;

    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID: @"doc1"];
    NSData* data = [self dataFromResource: @"image" ofType: @"jpg"];
    Assert(data);
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType: @"image/jpeg"
                                                    data: data];
    [doc1 setBlob: blob forKey: @"blob"];
    Assert([self.db saveDocument: doc1 error: &error]);
    AssertEqual(self.db.count, 1u);

    [self eraseRemoteEndpoint: target];
    id config = [self configWithTarget: target type : kCBLReplicatorTypePush continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
}


- (void) dontTestMissingHost_SG {
    // Note: The replication doesn't fail with an error; because the unknown-host error is
    // considered transient, the replicator just stays offline and waits for a network change.
    // This causes the test to time out.
    timeout = 200;
    
    id target = [[CBLURLEndpoint alloc] initWithURL:[NSURL URLWithString:@"ws://foo.couchbase.com/db"]];
    if (!target)
        return;
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: YES];
    [self run: config errorCode: 0 errorDomain: nil];
}


- (void) testSelfSignedSSLFailure_SG {
    id target = [self remoteEndpointWithName: @"scratch" secure: YES];
    if (!target)
        return;
    _pinServerCert = NO;    // without this, SSL handshake will fail
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO];
    [self run: config errorCode: CBLErrorTLSCertUnknownRoot errorDomain: CBLErrorDomain];
}


- (void) testSelfSignedSSLPinned_SG {
    id target = [self remoteEndpointWithName: @"scratch" secure: YES];
    if (!target)
        return;
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
}


- (void) dontTestContinuousPushNeverending_SG {
    // NOTE: This test never stops even after the replication goes idle.
    // It can be used to test the response to connectivity issues like killing the remote server.
    [CBLDatabase setLogLevel: kCBLLogLevelVerbose domain: kCBLLogDomainNetwork];
    
    id target = [self remoteEndpointWithName: @"scratch" secure: NO];
    if (!target)
        return;
    id config = [self configWithTarget: target type: kCBLReplicatorTypePush continuous: YES];
    repl = [[CBLReplicator alloc] initWithConfig: config];
    [repl start];

    XCTestExpectation* x = [self expectationWithDescription: @"When pigs fly"];
    [self waitForExpectations: @[x] timeout: 1e9];
}


- (void) testStopReplicatorAfterOffline_SG {
    id target = [[CBLURLEndpoint alloc] initWithURL: [NSURL URLWithString:@"ws://foo.couchbase.com/db"]];
    id config = [self configWithTarget: target type: kCBLReplicatorTypePull continuous: YES];
    CBLReplicator* r = [[CBLReplicator alloc] initWithConfig: config];
    
    XCTestExpectation* x1 = [self expectationWithDescription: @"Offline"];
    XCTestExpectation* x2 = [self expectationWithDescription: @"Stopped"];
    id token = [r addChangeListener: ^(CBLReplicatorChange* change) {
        if (change.status.activity == kCBLReplicatorOffline) {
            [change.replicator stop];
            [x1 fulfill];
        }
        
        if (change.status.activity == kCBLReplicatorStopped) {
            [x2 fulfill];
        }
    }];
    
    [r start];
    [self waitForExpectations: @[x1, x2] timeout: 10.0];
    [repl removeChangeListenerWithToken: token];
    r = nil;
}


- (void) testPullConflictDeleteWins_SG {
    [CBLDatabase setLogLevel: kCBLLogLevelDebug domain: kCBLLogDomainReplicator];
    
    id target = [self remoteEndpointWithName: @"scratch" secure: NO];
    if (!target)
        return;
    
    NSError* error;
    CBLMutableDocument* doc1 = [[CBLMutableDocument alloc] initWithID:@"doc1"];
    [doc1 setValue: @"Tiger" forKey: @"species"];
    Assert([self.db saveDocument: doc1 error: &error]);
    
    [self eraseRemoteEndpoint: target];
    
    // Push to SG:
    id config = [self configWithTarget: target type :kCBLReplicatorTypePush continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    // Get doc form SG:
    NSDictionary* json = [self sendRequestToEndpoint: target method: @"GET" path: doc1.id body: nil];
    Assert(json);
    Log(@"----> Common ancestor revision is %@", json[@"_rev"]);
    
    // Update doc on SG:
    NSMutableDictionary* nuData = [json mutableCopy];
    nuData[@"species"] = @"Cat";
    json = [self sendRequestToEndpoint: target method: @"PUT" path: doc1.id body: nuData];
    Assert(json);
    Log(@"----> Conflicting server revision is %@", json[@"rev"]);

    // Delete local doc:
    Assert([self.db deleteDocument: doc1 error: &error]);
    AssertNil([self.db documentWithID: doc1.id]);
    
    // Start pull replicator:
    Log(@"-------- Starting pull replication to pick up conflict --------");
    config = [self configWithTarget: target type :kCBLReplicatorTypePull continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    // Verify local doc should be nil:
    AssertNil([self.db documentWithID: doc1.id]);
}


- (void) testPushAndPullBigBodyDocument_SG {
    timeout = 200;
    [CBLDatabase setLogLevel:kCBLLogLevelDebug domain:kCBLLogDomainAll];
    
    id target = [self remoteEndpointWithName: @"scratch" secure: NO];
    if (!target)
        return;
    
    // Create a big document (~500KB)
    CBLMutableDocument *doc = [[CBLMutableDocument alloc] init];
    for (int i = 0; i < 1000; i++) {
        NSString *text = [self randomStringWithLength: 512];
        [doc setValue:text forKey:[NSString stringWithFormat:@"text-%d", i]];
    }
    
    NSError* error;
    Assert([self.db saveDocument: doc error: &error], @"Save Error: %@", error);
    
    // Erase remote data:
    [self eraseRemoteEndpoint: target];
    
    // PUSH to SG:
    Log(@"-------- Starting push replication --------");
    id config = [self configWithTarget: target type :kCBLReplicatorTypePush continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
    
    // Clean database:
    [self cleanDB];
    
    // PULL from SG:
    Log(@"-------- Starting pull replication --------");
    config = [self configWithTarget: target type :kCBLReplicatorTypePull continuous: NO];
    [self run: config errorCode: 0 errorDomain: nil];
}

@end
