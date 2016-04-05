//
//  ReplicatorInternal_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/23/14.
//
//

#import "CBLTestCase.h"
#import "CouchbaseLitePrivate.h"
#import "CBLRestReplicator+Internal.h"
#import "CBLRestPuller.h"
#import "CBLRestPusher.h"
#import "CBLReachability.h"
#import "CBL_Server.h"
#import "CBLDatabase+Replication.h"
#import "CBLDatabase+Insertion.h"
#import "CBLRevision.h"
#import "CBLOAuth1Authorizer.h"
#import "CBLBase64.h"
#import "CBLInternal.h"
#import "CBLMisc.h"
#import "MYURLUtils.h"


// This db will get deleted and overwritten during every test.
#define kScratchDBName @"cbl_replicator_scratch"

// This is a read-only db whose contents should be a default CouchApp.
#define kCouchAppDBName @"couchapp_helloworld"


#define replic8(DB, REMOTE, PUSH, FILTER, DOCIDS, ERR) \
    [self replicate: REMOTE push: PUSH filter: FILTER docIDs: DOCIDS expectError: ERR]

#define replic8Continuous(DB, REMOTE, PUSH, FILTER, OPTIONS, ERR) \
    [self replicateContinuous: REMOTE push: PUSH filter: FILTER options: OPTIONS expectError: ERR]


@interface CBLManager (Seekrit)
- (CBLStatus) parseReplicatorProperties: (NSDictionary*)properties
                            toDatabase: (CBLDatabase**)outDatabase   // may be NULL
                                remote: (NSURL**)outRemote          // may be NULL
                                isPush: (BOOL*)outIsPush
                          createTarget: (BOOL*)outCreateTarget
                               headers: (NSDictionary**)outHeaders
                            authorizer: (id<CBLAuthorizer>*)outAuthorizer;
@end


@interface ReplicatorInternal_Tests : CBLTestCaseWithDB
@end


@implementation ReplicatorInternal_Tests
{
    BOOL _newReplicator;
}


- (void)invokeTest {
    // Run each test method twice, once with the old replicator and once with the new.
    _newReplicator = NO;
    [super invokeTest];
    if ([[NSUserDefaults standardUserDefaults] boolForKey: @"TestNewReplicator"]) {
        _newReplicator = YES;
        [super invokeTest];
    }
}

- (void) setUp {
    if (_newReplicator)
        Log(@"++++ Now using new replicator");
    [super setUp];
    if (_newReplicator) {
        dbmgr.replicatorClassName = @"CBLBlipReplicator";
        dbmgr.dispatchQueue = dispatch_get_main_queue();
    }
}


- (void) test_01_Pusher {
    RequireTestCase(CBLDatabase);
    __block int filterCalls = 0;
    __weak ReplicatorInternal_Tests* weakSelf = self;
    [db setFilterNamed: @"filter" asBlock: ^BOOL(CBLSavedRevision *revision, NSDictionary* params) {
        ReplicatorInternal_Tests* self = weakSelf;
        //Log(@"Test filter called with params = %@", params);
        //Log(@"Rev = %@, properties = %@", revision, revision.properties);
        Assert(revision.properties);
        ++filterCalls;
        return YES;
    }];

    // Create some documents:
    NSMutableDictionary* props = $mdict({@"_id", @"doc1"},
                                        {@"foo", @1}, {@"bar", $false});
    CBLStatus status;
    NSError* error;
    CBL_Revision* rev1 = [db putRevision: [CBL_MutableRevision revisionWithProperties: props]
                          prevRevisionID: nil allowConflict: NO status: &status error: &error];
    AssertEq(status, kCBLStatusCreated);
    AssertNil(error);
    
    props[@"_rev"] = rev1.revID;
    props[@"UPDATED"] = $true;
    CBL_Revision* rev2 = [db putRevision: [CBL_MutableRevision revisionWithProperties: props]
                          prevRevisionID: rev1.revID allowConflict: NO
                                  status: &status error: &error];
    AssertEq(status, kCBLStatusCreated);
    AssertNil(error);
    
    props = $mdict({@"_id", @"doc2"},
                   {@"baz", @(666)}, {@"fnord", $true});
    [db putRevision: [CBL_MutableRevision revisionWithProperties: props ]
     prevRevisionID: nil allowConflict: NO
             status: &status error: &error];
    AssertEq(status, kCBLStatusCreated);
    AssertNil(error);
#pragma unused(rev2)

    [self createDocuments: 100];
    
    // Push them to the remote:
    NSURL* remoteDB = [self remoteTestDBURL: kScratchDBName];
    if (!remoteDB)
        return;
    [self eraseRemoteDB: remoteDB];
    id lastSeq = replic8(db, remoteDB, YES, @"filter", nil, nil);
    AssertEq([lastSeq intValue], 103);
    AssertEq(filterCalls, 102);
}


- (void) test_02_Puller {
    RequireTestCase(01_Pusher);
    NSURL* remoteURL = [self remoteTestDBURL: kScratchDBName];
    if (!remoteURL)
        return;

    id lastSeq = replic8(db, remoteURL, NO, nil, nil, nil);
    AssertEqual(lastSeq, @103);
    
    AssertEq(db.documentCount, 102u);
    AssertEq(db.lastSequenceNumber, (self.isSQLiteDB ? 103 : 102));
    
    // Replicate again; should complete but add no revisions:
    Log(@"Second replication, should get no more revs:");
    replic8(db, ([self remoteTestDBURL: kScratchDBName]), NO, nil, nil, nil);
    AssertEq(db.lastSequenceNumber, (self.isSQLiteDB ? 103 : 102));
    
    CBL_Revision* doc = [db getDocumentWithID: @"doc1" revisionID: nil];
    Assert(doc);
    Assert([doc.revID hasPrefix: @"2-"]);
    AssertEqual(doc[@"foo"], @1);
    
    doc = [db getDocumentWithID: @"doc2" revisionID: nil];
    Assert(doc);
    Assert([doc.revID hasPrefix: @"1-"]);
    AssertEqual(doc[@"fnord"], $true);
}


- (void) test_03_Puller_Continuous {
    RequireTestCase(02_Puller);
    NSURL* remoteURL = [self remoteTestDBURL: kScratchDBName];
    if (!remoteURL)
        return;

    id lastSeq = replic8Continuous(db, remoteURL, NO, nil, nil, nil);
    AssertEqual(lastSeq, @103);

    AssertEq(db.documentCount, 102u);
    AssertEq(db.lastSequenceNumber, (self.isSQLiteDB ? 103 : 102));

    // Replicate again; should complete but add no revisions:
    Log(@"Second replication, should get no more revs:");
    replic8Continuous(db, remoteURL, NO, nil, nil, nil);
    AssertEq(db.lastSequenceNumber, (self.isSQLiteDB ? 103 : 102));

    CBL_Revision* doc = [db getDocumentWithID: @"doc1" revisionID: nil];
    Assert(doc);
    Assert([doc.revID hasPrefix: @"2-"]);
    AssertEqual(doc[@"foo"], @1);

    doc = [db getDocumentWithID: @"doc2" revisionID: nil];
    Assert(doc);
    Assert([doc.revID hasPrefix: @"1-"]);
    AssertEqual(doc[@"fnord"], $true);
}


- (void) test_04_Puller_Continuous_PermanentError {
    RequireTestCase(Puller);
    NSURL* remoteURL = [self remoteTestDBURL: @"non_existent_remote_db"];
    if (!remoteURL)
        return;

    [self allowWarningsIn:^{
        NSError* error = CBLStatusToNSError(kCBLStatusNotFound);
        replic8Continuous(db, remoteURL, NO, nil, nil, error);
    }];
}


- (void) test_05_Puller_DatabaseValidation {
    RequireTestCase(Pusher);

    NSURL* remote = [self remoteTestDBURL: kScratchDBName];
    if (!remote)
        return;

    [db setValidationNamed:@"OnlyDoc1" asBlock:^(CBLRevision *newRevision, id<CBLValidationContext> context) {
        if (![newRevision.document.documentID isEqualToString:@"doc1"]) {
            [context reject];
        }
    }];

    // Start a named document pull replication.
    CBL_ReplicatorSettings* settings = [[CBL_ReplicatorSettings alloc] initWithRemote: remote push: NO];
    settings.authorizer = self.authorizer;
    id<CBL_Replicator> repl = [[dbmgr.replicatorClass alloc] initWithDB: db settings: settings];
    [repl start];

    // Let the replicator run.
    Assert(repl.status != kCBLReplicatorStopped);
    Log(@"Waiting for replicator to finish...");
    while (repl.status != kCBLReplicatorStopped || repl.savingCheckpoint) {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                      beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]])
            break;
    }
    AssertEq(repl.status, kCBLReplicatorStopped);
    Assert(!repl.savingCheckpoint);
    AssertNil(repl.error);
    Log(@"...replicator finished. lastSequence=%@", repl.lastSequence);
    id lastSeq = repl.lastSequence;
    AssertEqual(lastSeq, @103);

    AssertEq(db.documentCount, 1u);
    AssertEq(db.lastSequenceNumber, (self.isSQLiteDB ? 2 : 1));

    CBL_Revision* doc = [db getDocumentWithID: @"doc1" revisionID: nil];
    Assert(doc);
    Assert([doc.revID hasPrefix: @"2-"]);
    AssertEqual(doc[@"foo"], @1);
}


- (void) test_06_Puller_Authenticate {
    RequireTestCase(Puller);
    NSURL* remoteURL = [self remoteTestDBURL: @"cbl_auth_test"];
    if (!remoteURL)
        return;

    CBL_ReplicatorSettings* settings = [[CBL_ReplicatorSettings alloc] initWithRemote: remoteURL
                                                                                 push: NO];
    [self replicate: settings expectError: CBLStatusToNSError(kCBLStatusUnauthorized)];

    settings.authorizer = [[CBLPasswordAuthorizer alloc] initWithUser: @"test" password: @"abc123"];
    [self replicate: settings expectError: nil];
}


- (void) test_06_Puller_SSL {
    if (_newReplicator) {
        Warn(@"Skipping SSL tests until new replicator supports cert validation");
        return;
    }
    RequireTestCase(Pusher);
    NSURL* remoteURL = [self remoteSSLTestDBURL: @"public"];
    if (!remoteURL)
        return;

    Log(@"Replicating without root cert; should fail...");
    CBLSetAnchorCerts(nil, NO);
    [self allowWarningsIn:^{
        replic8(db, remoteURL, NO, nil, nil,
                ([NSError errorWithDomain: NSURLErrorDomain
                                    code: NSURLErrorServerCertificateUntrusted userInfo: nil]));
    }];

    Log(@"Now replicating with root cert installed...");
    CBLSetAnchorCerts([self remoteTestDBAnchorCerts], NO);
    id lastSeq = replic8(db, remoteURL, NO, nil, nil, nil);
    CBLSetAnchorCerts(nil, NO);
    Assert([lastSeq intValue] >= 2);

    AssertEq(db.documentCount, 2u);
    AssertEq(db.lastSequenceNumber, 2);
}

- (void) test_07_Puller_SSL_Continuous {
    if (_newReplicator) {
        Warn(@"Skipping SSL tests until new replicator supports cert validation");
        return;
    }
    RequireTestCase(Pusher);
    NSURL* remoteURL = [self remoteSSLTestDBURL: @"public"];
    if (!remoteURL)
        return;

    Log(@"Replicating without root cert; should fail...");
    CBLSetAnchorCerts(nil, NO);
    [self allowWarningsIn:^{
        replic8Continuous(db, remoteURL, NO, nil, nil,
                          [NSError errorWithDomain: NSURLErrorDomain
                                              code: NSURLErrorServerCertificateUntrusted
                                          userInfo: nil]);
    }];

    Log(@"Now replicating with root cert installed...");
    CBLSetAnchorCerts([self remoteTestDBAnchorCerts], NO);
    id lastSeq = replic8Continuous(db, remoteURL, NO, nil, nil, nil);
    CBLSetAnchorCerts(nil, NO);
    Assert([lastSeq intValue] >= 2);

    AssertEq(db.documentCount, 2u);
    AssertEq(db.lastSequenceNumber, 2);
}

- (void) test_08_Puller_SSL_Pinned {
    if (_newReplicator) {
        Warn(@"Skipping SSL tests until new replicator supports cert validation");
        return;
    }
    RequireTestCase(Puller_SSL_Continuous);
    NSURL* remoteURL = [self remoteSSLTestDBURL: @"public"];
    if (!remoteURL)
        return;

    Log(@"Replicating with wrong pinned cert; should fail...");
    [self allowWarningsIn:^{
        NSString* digest = @"123456789abcdef0123456789abcdef012345678";
        replic8Continuous(db, remoteURL, NO, nil, @{kCBLReplicatorOption_PinnedCert: digest},
                          [NSError errorWithDomain: NSURLErrorDomain
                                              code: NSURLErrorServerCertificateUntrusted
                                          userInfo: nil]);
    }];

    Log(@"Now replicating with correct pinned cert...");
    NSString* digest = CBLHexSHA1Digest([self contentsOfTestFile: @"SelfSigned.cer"]);
    id lastSeq = replic8Continuous(db, remoteURL, NO, nil,
                                   @{kCBLReplicatorOption_PinnedCert: digest},
                                   nil);
    CBLSetAnchorCerts(nil, NO);
    Assert([lastSeq intValue] >= 2);

    AssertEq(db.documentCount, 2u);
    AssertEq(db.lastSequenceNumber, 2);
}

- (void) test_09_Pusher_NonExistentServer {
    RequireTestCase(Pusher);
    NSURL* remoteURL = [NSURL URLWithString:@"https://mylocalhost/db"];
    if (!remoteURL) {
        Warn(@"Skipping test CBL_Pusher_NonExistentServer: invalid URL");
        return;
    }

    replic8(db, remoteURL, YES, nil, nil, [NSError errorWithDomain: NSURLErrorDomain
                                                              code: NSURLErrorCannotFindHost
                                                          userInfo: nil]);
}

- (void) test_10_Puller_NonExistentServer {
    RequireTestCase(Puller);
    NSURL* remoteURL = [NSURL URLWithString:@"https://mylocalhost/db"];
    if (!remoteURL) {
        Warn(@"Skipping test CBL_Puller_NonExistentServer: invalid URL");
        return;
    }

    replic8(db, remoteURL, NO, nil, nil, [NSError errorWithDomain: NSURLErrorDomain
                                                             code: NSURLErrorCannotFindHost
                                                         userInfo: nil]);
}


#if 0 // FIX: Sync Gateway doesn't support this yet!
- (void) test_11_Puller_DocIDs {
    RequireTestCase(Pusher); // CBL_Pusher populates the remote db that this test pulls from...
    
    NSURL* remote = [self remoteTestDBURL: kScratchDBName];
    if (!remote) {
        Warn(@"Skipping test: no remote URL");
        return;
    }

    // Start a named document pull replication.
    CBL_Replicator* repl = [[CBL_Replicator alloc] initWithDB: db remote: remote
                                                     push: NO continuous: NO];
    repl.docIDs = @[@"doc1"];
    repl.authorizer = self.authorizer;
    [repl start];
    
    // Let the replicator run.
    Assert(repl.status != kCBLReplicatorStopped);
    Log(@"Waiting for replicator to finish...");
    while (repl.status != kCBLReplicatorStopped || repl.savingCheckpoint) {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                      beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]])
            break;
    }
    AssertEq(repl.status, kCBLReplicatorStopped);
    Assert(!repl.savingCheckpoint);
    AssertNil(repl.error);
    Log(@"...replicator finished. lastSequence=%@", repl.lastSequence);
    id lastSeq = repl.lastSequence;
    
    AssertEqual(lastSeq, @1);
    
    Log(@"GOT DOCS: %@", [db getAllDocs:nil]);
    
    AssertEq(db.documentCount, 1u);
    AssertEq(db.lastSequenceNumber, 2);
    
    // Replicate again; should complete but add no revisions:
    Log(@"Second replication, should get no more revs:");
    replic8(db, ([self remoteTestDBURL: kScratchDBName]), NO, nil, nil, nil);
    AssertEq(db.lastSequenceNumber, 3);
    
    CBL_Revision* doc = [db getDocumentWithID: @"doc1" revisionID: nil];
    Assert(doc);
    Assert([doc.revID hasPrefix: @"2-"]);
    AssertEqual(doc[@"foo"], @1);
}
#endif


- (void) test_12_Pusher_DocIDs {
    RequireTestCase(Puller_DocIDs);
    // Create some documents:
    for (int i = 1; i <= 10; i++) {
        NSDictionary* props = @{@"_id": $sprintf(@"doc%d", i)};
        CBLStatus status;
        NSError* error;
        [db putRevision: [CBL_MutableRevision revisionWithProperties: props]
             prevRevisionID: nil allowConflict: NO status: &status error: &error];
        AssertEq(status, kCBLStatusCreated);
        AssertNil(error);
    }

    // Push them to the remote:
    NSURL* remoteDB = [self remoteTestDBURL: kScratchDBName];
    if (!remoteDB)
        return;
    [self eraseRemoteDB: remoteDB];
    replic8(db, remoteDB, YES, nil, (@[@"doc4", @"doc7"]), nil);

    // Check _all_docs on the remote db and make sure only doc4 and doc7 were pushed:
    NSURL* allDocsURL = [remoteDB URLByAppendingPathComponent: @"_all_docs"];
    NSDictionary* response = [self sendRemoteRequest: @"GET" toURL: allDocsURL];
    Assert(response);
    NSArray* rows = response[@"rows"];
    AssertEq(rows.count, 2u);
    AssertEqual((rows[0])[@"id"], @"doc4");
    AssertEqual((rows[1])[@"id"], @"doc7");
}


- (void) test_15_ParseReplicatorProperties {
    __block CBLDatabase* parsedDB = nil;
    __block NSURL* remote = nil;
    __block BOOL isPush = NO, createTarget = NO;
    __block NSDictionary* headers = nil;
    
    __block NSDictionary* props;
    props = $dict({@"source", db.name},
                  {@"target", @"http://example.com/foo"},
                  {@"create_target", $true});
    AssertEq(200, [dbmgr parseReplicatorProperties: props
                                        toDatabase: &parsedDB
                                            remote: &remote
                                            isPush: &isPush
                                      createTarget: &createTarget
                                           headers: &headers
                                        authorizer: NULL]);
    AssertEq(parsedDB, db);
    AssertEqual(remote, $url(@"http://example.com/foo"));
    AssertEq(isPush, YES);
    AssertEq(createTarget, YES);
    AssertEqual(headers, nil);
    
    props = $dict({@"source", @"cbl:///foo"},
                  {@"target", db.name});
    AssertEq(200, [dbmgr parseReplicatorProperties: props
                                             toDatabase: &parsedDB
                                                 remote: &remote
                                                 isPush: &isPush
                                           createTarget: &createTarget
                                                headers: &headers
                                             authorizer: NULL]);
    AssertEq(parsedDB, db);
    AssertEqual(remote, $url(@"cbl:///foo"));
    AssertEq(isPush, NO);
    AssertEq(createTarget, NO);
    AssertEqual(headers, nil);

    // Invalid URLs:
    [self allowWarningsIn:^{
        NSArray* badTargets = @[@"http://example.com",
                                @"http://example.com/",
                                @"http://example.com/foo?x=y",
                                @"http://example.com/foo#frag",
                                @"gopher://example.com/foo"];
        for (NSString* target in badTargets) {
            props = $dict({@"source", db.name},
                          {@"target", target});
            AssertEq(400, [dbmgr parseReplicatorProperties: props
                                                toDatabase: &parsedDB
                                                    remote: &remote
                                                    isPush: &isPush
                                              createTarget: &createTarget
                                                   headers: &headers
                                                authorizer: NULL]);
        }
    }];

    if (NSClassFromString(@"CBLURLProtocol")) {
        // Local-to-local replication:
        props = $dict({@"source", @"foo"},
                      {@"target", @"bar"});
        AssertEq([dbmgr parseReplicatorProperties: props
                                            toDatabase: &parsedDB
                                                remote: &remote
                                                isPush: &isPush
                                          createTarget: &createTarget
                                               headers: &headers
                                            authorizer: NULL],
                  404);
        props = $dict({@"source", @"foo"},
                      {@"target", @"bar"}, {@"create_target", $true});
        AssertEq([dbmgr parseReplicatorProperties: props
                                            toDatabase: &parsedDB
                                                remote: &remote
                                                isPush: &isPush
                                          createTarget: &createTarget
                                               headers: &headers
                                            authorizer: NULL],
                  200);
        AssertEq(parsedDB, db);
        AssertEqual(remote, $url(@"http://lite.couchbase./bar/"));
        AssertEq(isPush, YES);
        AssertEq(createTarget, YES);
        AssertEqual(headers, nil);
    }

    NSDictionary* oauthDict = $dict({@"consumer_secret", @"consumer_secret"},
                                    {@"consumer_key", @"consumer_key"},
                                    {@"token_secret", @"token_secret"},
                                    {@"token", @"token"});
    props = $dict({@"source", $dict({@"url", @"http://example.com/foo"},
                                    {@"headers", $dict({@"Excellence", @"Most"})},
                                    {@"auth", $dict({@"oauth", oauthDict})})},
                  {@"target", db.name});
    id<CBLAuthorizer> authorizer = nil;
    AssertEq(200, [dbmgr parseReplicatorProperties: props
                                             toDatabase: &parsedDB
                                                 remote: &remote
                                                 isPush: &isPush
                                           createTarget: &createTarget
                                                headers: &headers
                                             authorizer: &authorizer]);
    AssertEq(parsedDB, db);
    AssertEqual(remote, $url(@"http://example.com/foo"));
    AssertEq(isPush, NO);
    AssertEq(createTarget, NO);
    AssertEqual(headers, $dict({@"Excellence", @"Most"}));
    Assert([authorizer isKindOfClass: [CBLOAuth1Authorizer class]]);
}


- (void) test_16_FindCommonAncestor {
    NSDictionary* revDict = $dict({@"ids", @[@"second", @"first"]}, {@"start", @2});
    CBL_Revision* rev = [CBL_Revision revisionWithProperties: $dict({@"_revisions", revDict})];
    AssertEq(CBLFindCommonAncestor(rev, @[]), 0);
    AssertEq(CBLFindCommonAncestor(rev, @[@"3-noway", @"1-nope"]), 0);
    AssertEq(CBLFindCommonAncestor(rev, @[@"3-noway", @"1-first"]), 1);
    AssertEq(CBLFindCommonAncestor(rev, @[@"3-noway", @"2-second", @"1-first"]), 2);
}


- (void) test_17_Reachability {
    NSArray* hostnames = @[@"couchbase.com", @"localhost", @"127.0.0.1", @"67.221.231.37",
                           @"fsdfsaf.fsdfdaf.fsfddf"];
    for (NSString* hostname in hostnames) {
        Log(@"Test reachability of %@ ...", hostname);
        CBLReachability* r = [[CBLReachability alloc] initWithHostName: hostname];
        Assert(r);
        Log(@"\tCBLReachability = %@", r);
        AssertEqual(r.hostName, hostname);
        __block BOOL resolved = NO;
        
        __weak CBLReachability *weakR = r;
        r.onChange = ^{
            CBLReachability *strongR = weakR;
            Log(@"\tonChange: known=%d, flags=%x --> reachable=%d",
                strongR.reachabilityKnown, strongR.reachabilityFlags, strongR.reachable);
            Log(@"\tCBLReachability = %@", strongR);
            if (strongR.reachabilityKnown)
                resolved = YES;
        };
        Assert([r startOnRunLoop:CFRunLoopGetCurrent()]);

        BOOL known = r.reachabilityKnown;
        Log(@"\tInitially: known=%d, flags=%x --> reachable=%d",
            known, r.reachabilityFlags, r.reachable);
        if (!known) {
            while (!resolved) {
                Log(@"\twaiting...");
                [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                         beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]];
            }
        }
        [r stop];
        Log(@"\t...done!");
    }
}


- (void) test_18_DistinctCheckpointIDs {
    NSMutableDictionary* props = [@{@"source": @"http://fake.fake/fakedb",
                                    @"target": db.name,
                                    @"continuous": @NO} mutableCopy];
    CBLStatus status;
    id<CBL_Replicator> r1 = [dbmgr replicatorWithProperties: props status: &status];
    Assert(r1);
    NSString* check1 = r1.remoteCheckpointDocID;

    props[@"continuous"] = @YES;
    id<CBL_Replicator> r2 = [dbmgr replicatorWithProperties: props status: &status];
    Assert(r2);
    NSString* check2 = r2.remoteCheckpointDocID;
    Assert(![check1 isEqualToString: check2]);

    props[@"filter"] = @"Melitta";
    props[@"query_params"] = @{@"unbleached": @"true"};     // Test fix for #728
    id<CBL_Replicator> r3 = [dbmgr replicatorWithProperties: props status: &status];
    Assert(r3);
    NSString* check3 = r3.remoteCheckpointDocID;
    Assert(![check3 isEqualToString: check2]);
}


- (void) test_19_UseRemoteUUID {   // Test kCBLReplicatorOption_RemoteUUID (see #733)
    NSDictionary* props = @{@"source": @"http://alice.local:55555/db",
                            @"target": db.name,
                            kCBLReplicatorOption_RemoteUUID: @"cafebabe"};
    CBLStatus status;
    id<CBL_Replicator> r1 = [dbmgr replicatorWithProperties: props status: &status];
    Assert(r1);
    NSString* check1 = r1.remoteCheckpointDocID;

    // Different URL, but same remoteUUID:
    NSMutableDictionary* props2 = [props mutableCopy];
    props2[@"source"] = @"http://alice17.local:44444/db";
    id<CBL_Replicator> r2 = [dbmgr replicatorWithProperties: props2 status: &status];
    Assert(r2);
    NSString* check2 = r2.remoteCheckpointDocID;
    AssertEqual(check1, check2);
    AssertEqual(r2.settings, r1.settings);

    // Same UUID but different "filter" setting:
    NSMutableDictionary* props3 = [props2 mutableCopy];
    props3[@"filter"] = @"Melitta";
    id<CBL_Replicator> r3 = [dbmgr replicatorWithProperties: props3 status: &status];
    Assert(r3);
    NSString* check3 = r3.remoteCheckpointDocID;
    Assert(![check3 isEqualToString: check2]);
    Assert(!$equal(r3.settings, r2.settings));
}


- (void) test20_PullActiveOnly {
    // Database 'attach_test' happens to have a deleted document named 'propertytest'.
    // Make sure the puller doesn't add it to an empty database:
    NSURL* remoteURL = [self remoteTestDBURL: @"attach_test"];
    if (!remoteURL)
        return;
    id lastSeq = replic8(db, remoteURL, NO, nil, nil, nil);
    AssertEqual(lastSeq, @7);
    // Ensure we didn't pull the deleted document 'propertytest':
    CBL_RevisionList* revs = [db.storage getAllRevisionsOfDocumentID: @"propertytest" onlyCurrent: NO];
    AssertEq(revs.count, 0u);
}

- (void) test21_PullNotActiveOnly {
    // If database _isn't_ empty, the puller won't use the active_only optimization:
    [self createDocuments: 1];

    NSURL* remoteURL = [self remoteTestDBURL: @"attach_test"];
    if (!remoteURL)
        return;
    id lastSeq = replic8(db, remoteURL, NO, nil, nil, nil);
    AssertEqual(lastSeq, @7);
    // Verify we did pull the deleted document 'propertytest':
    CBL_RevisionList* revs = [db.storage getAllRevisionsOfDocumentID: @"propertytest" onlyCurrent: NO];
    Assert(revs);
    Assert(revs[0].deleted);
}


#pragma mark - UTILITY FUNCTIONS


- (NSString*) replicate: (NSURL*)remote
                   push: (BOOL)push
                 filter: (NSString*)filter
                 docIDs: (NSArray*)docIDs
            expectError: (NSError*) expectError
{
    CBL_ReplicatorSettings* settings = [[CBL_ReplicatorSettings alloc] initWithRemote: remote push: push];
    settings.createTarget = push;
    settings.filterName = filter;
    settings.docIDs = docIDs;
    settings.authorizer = self.authorizer;
    Assert([settings compilePushFilterForDatabase: db status: NULL]);
    return [self replicate: settings expectError: expectError];
}


- (NSString*) replicate: (CBL_ReplicatorSettings*)settings
            expectError: (NSError*)expectError
{
    id<CBL_Replicator> repl = [[dbmgr.replicatorClass alloc] initWithDB: db settings: settings];
    [repl start];
    
    Assert(repl.status != kCBLReplicatorStopped);
    Log(@"Waiting for replicator to finish...");
    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow: 10];
    while ((repl.status != kCBLReplicatorStopped || repl.savingCheckpoint) && timeout.timeIntervalSinceNow > 0.0) {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                      beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]]) {
            Warn(@"Runloop exiting unexpectedly!");
            break;
        }
    }
    AssertEq(repl.status, kCBLReplicatorStopped);
    Assert(!repl.savingCheckpoint);
    if (expectError) {
        Assert($equal(repl.error.domain, expectError.domain) && repl.error.code == expectError.code,
               @"\nUnexpected error %@\n  Expected error %@",
               repl.error.my_compactDescription, expectError.my_compactDescription);
        Log(@"...replicator got expected error %@", repl.error.my_compactDescription);
    } else {
        AssertNil(repl.error);
        Log(@"...replicator finished. lastSequence=%@", repl.lastSequence);
    }
    Assert(!repl.active);
    return repl.lastSequence;
}


- (NSString*) replicateContinuous: (NSURL*)remote
                             push: (BOOL)push
                           filter: (NSString*)filter
                          options: (NSDictionary*)options
                      expectError: (NSError*) expectError
{
    CBL_ReplicatorSettings* settings = [[CBL_ReplicatorSettings alloc] initWithRemote: remote push: push];
    settings.continuous = YES;
    settings.createTarget = push;
    settings.authorizer = self.authorizer;
    settings.filterName = filter;
    settings.options = options;
    Assert([settings compilePushFilterForDatabase: db status: NULL]);
    id<CBL_Replicator> repl = [[dbmgr.replicatorClass alloc] initWithDB: db settings: settings];
    [repl start];

    // Start the replicator and wait for it to go active, then inactive:
    Assert(repl.status != kCBLReplicatorStopped);
    Log(@"Waiting for replicator to go idle...");
    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow: 10];
    bool wasActive = repl.active;
    BOOL stopping = NO;
    while ((repl.status != kCBLReplicatorStopped || repl.savingCheckpoint) && timeout.timeIntervalSinceNow > 0.0) {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                      beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]])
            break;
        if (!wasActive) {
            wasActive = repl.active;
        } else if (!repl.active && !stopping) {
            if (!expectError)
                Assert(repl.status != kCBLReplicatorStopped);
            stopping = YES;
            [repl stop];  // Went inactive, so it's done; give it time to save its checkpoint
        }
    }
    Assert(wasActive && !repl.active);
    Assert(!repl.savingCheckpoint);

    if (expectError) {
        AssertEq(repl.status, kCBLReplicatorStopped);
        AssertEqual(repl.error.domain, expectError.domain);
        AssertEq(repl.error.code, expectError.code);
        Log(@"...replicator finished. error=%@", repl.error.my_compactDescription);
    } else {
        AssertNil(repl.error);
        Log(@"...replicator finished. lastSequence=%@", repl.lastSequence);
    }
    NSString* result = repl.lastSequence;
    return result;
}


@end
