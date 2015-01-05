//
//  ReplicatorInternal_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/23/14.
//
//

#import "CBLTestCase.h"
#import "CouchbaseLitePrivate.h"
#import "CBL_Puller.h"
#import "CBL_Pusher.h"
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


- (void) test_01_Pusher {
    RequireTestCase(CBLDatabase);
    __block int filterCalls = 0;
    __weak ReplicatorInternal_Tests* weakSelf = self;
    [db setFilterNamed: @"filter" asBlock: ^BOOL(CBLSavedRevision *revision, NSDictionary* params) {
        ReplicatorInternal_Tests* self = weakSelf;
        Log(@"Test filter called with params = %@", params);
        Log(@"Rev = %@, properties = %@", revision, revision.properties);
        Assert(revision.properties);
        ++filterCalls;
        return YES;
    }];

    // Create some documents:
    NSMutableDictionary* props = $mdict({@"_id", @"doc1"},
                                        {@"foo", @1}, {@"bar", $false});
    CBLStatus status;
    CBL_Revision* rev1 = [db putRevision: [CBL_Revision revisionWithProperties: props]
                        prevRevisionID: nil allowConflict: NO status: &status];
    AssertEq(status, kCBLStatusCreated);
    
    props[@"_rev"] = rev1.revID;
    props[@"UPDATED"] = $true;
    CBL_Revision* rev2 = [db putRevision: [CBL_Revision revisionWithProperties: props]
                        prevRevisionID: rev1.revID allowConflict: NO status: &status];
    AssertEq(status, kCBLStatusCreated);
    
    props = $mdict({@"_id", @"doc2"},
                   {@"baz", @(666)}, {@"fnord", $true});
    [db putRevision: [CBL_Revision revisionWithProperties: props]
                        prevRevisionID: nil allowConflict: NO status: &status];
    AssertEq(status, kCBLStatusCreated);
#pragma unused(rev2)
    
    // Push them to the remote:
    NSURL* remoteDB = [self remoteTestDBURL: kScratchDBName];
    if (remoteDB) {
        [self deleteRemoteDB: remoteDB];
        id lastSeq = replic8(db, remoteDB, YES, @"filter", nil, nil);
        AssertEqual(lastSeq, @"3");
        AssertEq(filterCalls, 2);
    } else {
        Warn(@"Skipping rest of test CBL_Pusher (no remote test DB URL)");
        return;
    }
}


- (void) test_02_Puller {
    RequireTestCase(01_Pusher);
    NSURL* remoteURL = [self remoteTestDBURL: kScratchDBName];
    if (!remoteURL) {
        Warn(@"Skipping test CBL_Puller: no remote test DB URL");
        return;
    }

    id lastSeq = replic8(db, remoteURL, NO, nil, nil, nil);
    AssertEqual(lastSeq, @2);
    
    AssertEq(db.documentCount, 2u);
    AssertEq(db.lastSequenceNumber, 3);
    
    // Replicate again; should complete but add no revisions:
    Log(@"Second replication, should get no more revs:");
    replic8(db, ([self remoteTestDBURL: kScratchDBName]), NO, nil, nil, nil);
    AssertEq(db.lastSequenceNumber, 3);
    
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
    if (!remoteURL) {
        Warn(@"Skipping test CBL_Puller: no remote URL");
        return;
    }

    id lastSeq = replic8Continuous(db, remoteURL, NO, nil, nil, nil);
    AssertEqual(lastSeq, @2);

    AssertEq(db.documentCount, 2u);
    AssertEq(db.lastSequenceNumber, 3);

    // Replicate again; should complete but add no revisions:
    Log(@"Second replication, should get no more revs:");
    replic8Continuous(db, remoteURL, NO, nil, nil, nil);
    AssertEq(db.lastSequenceNumber, 3);

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
    if (!remoteURL) {
        Warn(@"Skipping test CBL_Puller: no remote test DB URL");
        return;
    }
    
    NSError* error = CBLStatusToNSError(kCBLStatusNotFound, nil);
    replic8Continuous(db, remoteURL, NO, nil, nil, error);
}


- (void) test_05_Puller_DatabaseValidation {
    RequireTestCase(Pusher);

    NSURL* remote = [self remoteTestDBURL: kScratchDBName];
    if (!remote) {
        Warn(@"Skipping test: no remote URL");
        return;
    }

    [db setValidationNamed:@"OnlyDoc1" asBlock:^(CBLRevision *newRevision, id<CBLValidationContext> context) {
        if (![newRevision.document.documentID isEqualToString:@"doc1"]) {
            [context reject];
        }
    }];

    // Start a named document pull replication.
    CBL_Replicator* repl = [[CBL_Replicator alloc] initWithDB: db remote: remote
                                                         push: NO continuous: NO];
    repl.authorizer = self.authorizer;
    [repl start];

    // Let the replicator run.
    Assert(repl.running);
    Log(@"Waiting for replicator to finish...");
    while (repl.running || repl.savingCheckpoint) {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                      beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]])
            break;
    }
    Assert(!repl.running);
    Assert(!repl.savingCheckpoint);
    AssertNil(repl.error);
    Log(@"...replicator finished. lastSequence=%@", repl.lastSequence);
    id lastSeq = repl.lastSequence;
    AssertEqual(lastSeq, @2);

    Log(@"GOT DOCS: %@", [db getAllDocs:nil]);

    AssertEq(db.documentCount, 1u);
    AssertEq(db.lastSequenceNumber, 2);

    CBL_Revision* doc = [db getDocumentWithID: @"doc1" revisionID: nil];
    Assert(doc);
    Assert([doc.revID hasPrefix: @"2-"]);
    AssertEqual(doc[@"foo"], @1);
}


- (void) test_06_Puller_AuthFailure {
    RequireTestCase(Puller);
    NSURL* remoteURL = [self remoteTestDBURL: @"tdpuller_test2_auth"];
    if (!remoteURL) {
        Warn(@"Skipping test CBL_Puller: no remote test DB URL");
        return;
    }
    // Add a bogus user to make auth fail:
    NSString* urlStr = remoteURL.absoluteString;
    urlStr = [urlStr stringByReplacingOccurrencesOfString: @"http://" withString: @"http://bogus@"];
    remoteURL = $url(urlStr);

    NSError* error = CBLStatusToNSError(kCBLStatusUnauthorized, nil);
    replic8Continuous(db, remoteURL, NO, nil, nil, error);
}


- (void) test_06_Puller_SSL {
    RequireTestCase(Pusher);
    NSURL* remoteURL = [NSURL URLWithString: @"https://localhost:4994/public"];//FIX: Make portable

    Log(@"Replicating without root cert; should fail...");
    replic8(db, remoteURL, NO, nil, nil,
            ([NSError errorWithDomain: NSURLErrorDomain
                                code: NSURLErrorServerCertificateUntrusted userInfo: nil]));

    Log(@"Now replicating with root cert installed...");
    [CBL_Replicator setAnchorCerts: [self remoteTestDBAnchorCerts] onlyThese: NO];
    id lastSeq = replic8(db, remoteURL, NO, nil, nil, nil);
    [CBL_Replicator setAnchorCerts: nil onlyThese: NO];
    Assert([lastSeq intValue] >= 2);

    AssertEq(db.documentCount, 2u);
    AssertEq(db.lastSequenceNumber, 2);
}

- (void) test_07_Puller_SSL_Continuous {
    RequireTestCase(Pusher);
    NSURL* remoteURL = [NSURL URLWithString: @"https://localhost:4994/public"];//FIX: Make portable

    Log(@"Replicating without root cert; should fail...");
    replic8Continuous(db, remoteURL, NO, nil, nil,
                      [NSError errorWithDomain: NSURLErrorDomain
                                          code: NSURLErrorServerCertificateUntrusted
                                      userInfo: nil]);

    Log(@"Now replicating with root cert installed...");
    [CBL_Replicator setAnchorCerts: [self remoteTestDBAnchorCerts] onlyThese: NO];
    id lastSeq = replic8Continuous(db, remoteURL, NO, nil, nil, nil);
    [CBL_Replicator setAnchorCerts: nil onlyThese: NO];
    Assert([lastSeq intValue] >= 2);

    AssertEq(db.documentCount, 2u);
    AssertEq(db.lastSequenceNumber, 2);
}

- (void) test_08_Puller_SSL_Pinned {
    RequireTestCase(Puller_SSL_Continuous);
    NSURL* remoteURL = [NSURL URLWithString: @"https://localhost:4994/public"];//FIX: Make portable

    Log(@"Replicating with wrong pinned cert; should fail...");
    NSString* digest = @"123456789abcdef0123456789abcdef012345678";
    replic8Continuous(db, remoteURL, NO, nil, @{kCBLReplicatorOption_PinnedCert: digest},
                      [NSError errorWithDomain: NSURLErrorDomain
                                          code: NSURLErrorServerCertificateUntrusted
                                      userInfo: nil]);

    Log(@"Now replicating with correct pinned cert...");
    digest = @"c745fbfc03382125271daffc2e715a5b0172d1d8";
    id lastSeq = replic8Continuous(db, remoteURL, NO, nil,
                                   @{kCBLReplicatorOption_PinnedCert: digest},
                                   nil);
    [CBL_Replicator setAnchorCerts: nil onlyThese: NO];
    Assert([lastSeq intValue] >= 2);

    AssertEq(db.documentCount, 2u);
    AssertEq(db.lastSequenceNumber, 2);
}

- (void) test_09_Pusher_NonExistentServer {
    RequireTestCase(Pusher);
    NSURL* remoteURL = [NSURL URLWithString:@"http://mylocalhost/db"];
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
    NSURL* remoteURL = [NSURL URLWithString:@"http://mylocalhost/db"];
    if (!remoteURL) {
        Warn(@"Skipping test CBL_Puller_NonExistentServer: invalid URL");
        return;
    }

    replic8(db, remoteURL, NO, nil, nil, [NSError errorWithDomain: NSURLErrorDomain
                                                             code: NSURLErrorCannotFindHost
                                                         userInfo: nil]);
}

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
    Assert(repl.running);
    Log(@"Waiting for replicator to finish...");
    while (repl.running || repl.savingCheckpoint) {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                      beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]])
            break;
    }
    Assert(!repl.running);
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


- (void) test_12_Pusher_DocIDs {
    RequireTestCase(Puller_DocIDs);
    // Create some documents:
    for (int i = 1; i <= 10; i++) {
        NSDictionary* props = @{@"_id": $sprintf(@"doc%d", i)};
        CBLStatus status;
        [db putRevision: [CBL_Revision revisionWithProperties: props]
             prevRevisionID: nil allowConflict: NO status: &status];
        AssertEq(status, kCBLStatusCreated);
    }

    // Push them to the remote:
    NSURL* remoteDB = [self remoteTestDBURL: kScratchDBName];
    if (remoteDB) {
        [self deleteRemoteDB: remoteDB];
        replic8(db, remoteDB, YES, nil, (@[@"doc4", @"doc7"]), nil);
    } else {
        Warn(@"Skipping rest of test CBL_Pusher_DocIDs (no remote test DB URL)");
        return;
    }

    // Check _all_docs on the remote db and make sure only doc4 and doc7 were pushed:
    NSURL* allDocsURL = [remoteDB URLByAppendingPathComponent: @"_all_docs"];
    NSData* data = [NSData dataWithContentsOfURL: allDocsURL];
    Assert(data);
    NSDictionary* response = [CBLJSON JSONObjectWithData: data options: 0 error: NULL];
    NSArray* rows = response[@"rows"];
    AssertEq(rows.count, 2u);
    AssertEqual((rows[0])[@"id"], @"doc4");
    AssertEqual((rows[1])[@"id"], @"doc7");
}


- (void) test_13_Puller_FromCouchApp {
    RequireTestCase(Puller);
    NSURL* remote = [self remoteTestDBURL: kCouchAppDBName];
    if (!remote) {
        Warn(@"Skipping test: no remote URL");
        return;
    }

    replic8(db, remote, NO, nil, nil, nil);

    CBLStatus status;
    CBL_Revision* rev = [db getDocumentWithID: @"_design/helloworld" revisionID: nil options: kCBLIncludeAttachments status: &status];
    NSDictionary* attachments = rev[@"_attachments"];
    AssertEq(attachments.count, 10u);
    for (NSString* name in attachments) { 
        NSDictionary* attachment = attachments[name];
        NSData* data = [CBLBase64 decode: attachment[@"data"]];
        Log(@"Attachment %@: %u bytes", name, (unsigned)data.length);
        Assert(data);
        AssertEq([data length], [attachment[@"length"] unsignedLongLongValue]);
    }
}


- (void) test_15_ParseReplicatorProperties {
    CBLDatabase* parsedDB = nil;
    NSURL* remote = nil;
    BOOL isPush = NO, createTarget = NO;
    NSDictionary* headers = nil;
    
    NSDictionary* props;
    props = $dict({@"source", db.name},
                  {@"target", @"http://example.com"},
                  {@"create_target", $true});
    AssertEq(200, [dbmgr parseReplicatorProperties: props
                                        toDatabase: &parsedDB
                                            remote: &remote
                                            isPush: &isPush
                                      createTarget: &createTarget
                                           headers: &headers
                                        authorizer: NULL]);
    AssertEq(parsedDB, db);
    AssertEqual(remote, $url(@"http://example.com"));
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
    props = $dict({@"source", $dict({@"url", @"http://example.com"},
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
    AssertEqual(remote, $url(@"http://example.com"));
    AssertEq(isPush, NO);
    AssertEq(createTarget, NO);
    AssertEqual(headers, $dict({@"Excellence", @"Most"}));
    Assert([authorizer isKindOfClass: [CBLOAuth1Authorizer class]]);
}



#pragma mark - UTILITY FUNCTIONS


- (void) deleteRemoteDB: (NSURL*)dbURL {
    Log(@"Deleting %@", dbURL);
    __block NSError* error = nil;
    __block BOOL finished = NO;
    CBLRemoteRequest* request = [[CBLRemoteRequest alloc] initWithMethod: @"DELETE"
                                                                     URL: dbURL
                                                                    body: nil
                                                          requestHeaders: nil
                                                            onCompletion:
        ^(id result, NSError *err) {
            finished = YES;
            error = err;
        }
                                ];
    request.authorizer = self.authorizer;
    [request start];
    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow: 10];
    while (!finished && [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                                 beforeDate: timeout])
        ;
    Assert(error == nil || error.code == kCBLStatusNotFound, @"Couldn't delete remote: %@", error);
}


- (NSString*) replicate: (NSURL*)remote
                   push: (BOOL)push
                 filter: (NSString*)filter
                 docIDs: (NSArray*)docIDs
            expectError: (NSError*) expectError
{
    CBL_Replicator* repl = [[CBL_Replicator alloc] initWithDB: db remote: remote
                                                        push: push continuous: NO];
    if (push)
        ((CBL_Pusher*)repl).createTarget = YES;
    repl.filterName = filter;
    repl.docIDs = docIDs;
    repl.authorizer = self.authorizer;
    [repl start];
    
    Assert(repl.running);
    Log(@"Waiting for replicator to finish...");
    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow: 10];
    while ((repl.running || repl.savingCheckpoint) && timeout.timeIntervalSinceNow > 0.0) {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                      beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]]) {
            Warn(@"Runloop exiting unexpectedly!");
            break;
        }
    }
    Assert(!repl.running);
    Assert(!repl.savingCheckpoint);
    if (expectError) {
        Assert(!repl.running);
        AssertEqual(repl.error.domain, expectError.domain);
        AssertEq(repl.error.code, expectError.code);
        Log(@"...replicator got expected error %@", repl.error);
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
    CBL_Replicator* repl = [[CBL_Replicator alloc] initWithDB: db remote: remote
                                                         push: push continuous: YES];
    if (push)
        ((CBL_Pusher*)repl).createTarget = YES;
    repl.filterName = filter;
    repl.authorizer = self.authorizer;
    repl.options = options;
    [repl start];

    // Start the replicator and wait for it to go active, then inactive:
    Assert(repl.running);
    Log(@"Waiting for replicator to go idle...");
    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow: 10];
    bool wasActive = repl.active;
    while ((repl.running || repl.savingCheckpoint) && timeout.timeIntervalSinceNow > 0.0) {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                      beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]])
            break;
        if (!wasActive)
            wasActive = repl.active;
        else if (!repl.active)
            break;  // Went inactive, so it's done
    }
    Assert(wasActive && !repl.active);
    Assert(!repl.savingCheckpoint);

    if (expectError) {
        Assert(!repl.running);
        AssertEqual(repl.error.domain, expectError.domain);
        AssertEq(repl.error.code, expectError.code);
        Log(@"...replicator finished. error=%@", repl.error);
    } else {
        Assert(repl.running);
        AssertNil(repl.error);
        Log(@"...replicator finished. lastSequence=%@", repl.lastSequence);
    }
    NSString* result = repl.lastSequence;
    [repl stop];
    return result;
}


@end
