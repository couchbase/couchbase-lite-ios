//
//  P2P_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 7/6/15.
//  Copyright © 2015 Couchbase, Inc. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLSyncListener.h"
#import "CBLHTTPListener.h"
#import "CBLManager+Internal.h"


#define kListenerDBName @"listy"
#define kNDocuments 100
#define kMinAttachmentLength   4000
#define kMaxAttachmentLength 100000

#define USE_AUTH 1
#define USE_SSL  1


static UInt16 sPort = 60100;


@interface P2P_HTTP_Tests : CBLTestCaseWithDB
@end


@implementation P2P_HTTP_Tests
{
    @protected
    CBLListener* listener;
    CBLDatabase* listenerDB;
    NSURL* listenerDBURL;
    id<CBLAuthenticator> clientAuthenticator;
}


- (Class) listenerClass {
    return [CBLHTTPListener class];
}

- (NSString*) replicatorClassName {
    return @"CBLRestReplicator";
}


- (void) setUp {
    [super setUp];

    dbmgr.replicatorClassName = self.replicatorClassName;

    listenerDB = [dbmgr databaseNamed: kListenerDBName error: NULL];

    listener = [[[self listenerClass] alloc] initWithManager: dbmgr port: sPort];
#if USE_AUTH
    listener.requiresAuth = YES;
    listener.passwords = @{@"bob": @"slack"};
    clientAuthenticator = [CBLAuthenticator basicAuthenticatorWithName: @"bob"
                                                              password: @"slack"];
#endif

#if USE_SSL
    NSError* error;
    Assert([listener setAnonymousSSLIdentityWithLabel: @"CBLUnitTests" error: &error],
           @"Failed to set SSL identity: %@", error);
#endif

    listenerDBURL = [listener.URL URLByAppendingPathComponent: listenerDB.name];
    Log(@"'Remote' db URL = <%@>", listenerDBURL);

    // Wait for listener to start:
    [self keyValueObservingExpectationForObject: listener keyPath: @"port" expectedValue: @(sPort)];
    Assert([listener start: &error], @"Couldn't start listener: %@", error);
    [self waitForExpectationsWithTimeout: 5.0 handler: nil];
}


- (void) tearDown {
    [listener stop];
    // Each test run uses a different port number (sPort is incremented) to prevent CFNetwork from
    // resuming the previous SSL session. Because if it does that, the previous client cert gets
    // used on the server side, which breaks the test. Haven't found a workaround for this yet.
    // --Jens 7/2015
    ++sPort;
    [super tearDown];
}


- (void) testPush {
    [self createDocsIn: db withAttachments: NO];
    Log(@"Pushing...");
    CBLReplication* repl = [db createPushReplication: listenerDBURL];
    if ([self runReplication: repl expectedChangesCount: kNDocuments])
        [self verifyDocsIn: listenerDB withAttachments: NO];
}

- (void) testPull {
    [self createDocsIn: listenerDB withAttachments: NO];
    Log(@"Pulling...");
    CBLReplication* repl = [db createPullReplication: listenerDBURL];
    if ([self runReplication: repl expectedChangesCount: kNDocuments])
        [self verifyDocsIn: db withAttachments: NO];
}

- (void) testPushAttachments {
    if (self.isSQLiteDB)
        return;
    [self createDocsIn: db withAttachments: YES];
    Log(@"Pushing...");
    CBLReplication* repl = [db createPushReplication: listenerDBURL];
    if ([self runReplication: repl expectedChangesCount: 0])
        [self verifyDocsIn: listenerDB withAttachments: YES];
}

- (void) testPullAttachments {
    [self createDocsIn: listenerDB withAttachments: YES];
    Log(@"Pulling...");
    CBLReplication* repl = [db createPullReplication: listenerDBURL];
    if ([self runReplication: repl expectedChangesCount: 0])
        [self verifyDocsIn: db withAttachments: YES];
}

- (void) testWrongAuth {
#if !USE_AUTH
    XCTFail(@"This test requires HTTP auth to be enabled");
#else
    clientAuthenticator = [CBLAuthenticator basicAuthenticatorWithName: @"bob"
                                                              password: @"pink"];
    [self createDocsIn: listenerDB withAttachments: YES];
    Log(@"Pulling...");
    CBLReplication* repl = [db createPullReplication: listenerDBURL];
    [self runReplication: repl];
    NSError* error = repl.lastError;
    AssertEqual(error.domain, CBLHTTPErrorDomain);
    AssertEq(error.code, 401);
#endif
}


- (void) testMissingAuth {
#if !USE_AUTH
    XCTFail(@"This test requires HTTP auth to be enabled");
#else
    clientAuthenticator = nil; // Don't authenticate!
    [self createDocsIn: listenerDB withAttachments: YES];
    Log(@"Pulling...");
    CBLReplication* repl = [db createPullReplication: listenerDBURL];
    [self runReplication: repl];
    NSError* error = repl.lastError;
    AssertEqual(error.domain, CBLHTTPErrorDomain);
    AssertEq(error.code, 401);
#endif
}


- (void) createDocsIn: (CBLDatabase*)database withAttachments: (BOOL)withAttachments {
    Log(@"Creating %d documents in %@...", kNDocuments, database.name);
    [database inTransaction:^BOOL{
        for (int i = 1; i <= kNDocuments; i++) {
            @autoreleasepool {
                CBLDocument* doc = database[ $sprintf(@"doc-%d", i) ];
                CBLUnsavedRevision* rev = doc.newRevision;
                rev[@"index"] = @(i);
                rev[@"bar"] = @NO;
                if (withAttachments) {
                    NSUInteger length = (NSUInteger)(kMinAttachmentLength +
                         random()/(double)INT32_MAX*(kMaxAttachmentLength - kMinAttachmentLength));
                    NSMutableData* data = [NSMutableData dataWithLength: length];
                    (void)SecRandomCopyBytes(kSecRandomDefault, length, data.mutableBytes);
                    [rev setAttachmentNamed: @"README" withContentType: @"application/octet-stream"
                                    content: data];
                }
                NSError* error;
                Assert([rev save: &error] != nil, @"Error saving rev: %@", error);
                AssertNil(error);
            }
        }
        return YES;
    }];
}

- (void) verifyDocsIn: (CBLDatabase*)database withAttachments: (BOOL)withAttachments {
    for (int i = 1; i <= kNDocuments; i++) {
        CBLDocument* doc = database[ $sprintf(@"doc-%d", i) ];
        AssertEqual(doc.properties[@"index"], @(i));
        AssertEqual(doc.properties[@"bar"], $false);
        if (withAttachments)
            Assert([doc.currentRevision attachmentNamed: @"README"] != nil);
    }
    AssertEq(database.documentCount, (unsigned)kNDocuments);
}


- (void) runReplication: (CBLReplication*)repl {
#if USE_AUTH
    repl.authenticator = clientAuthenticator;
#endif
    [repl start];

    __block bool started = false;
    [self expectationForNotification: kCBLReplicationChangeNotification object: repl
         handler: ^BOOL(NSNotification *n) {
             Log(@"Repl running=%d, status=%d", repl.running, repl.status);
             if (repl.running)
                 started = true;
             if (repl.lastError)
                 return true;
             if (repl.status == kCBLReplicationStopped)
                 NSLog(@"Stop");
             return started && (repl.status == kCBLReplicationStopped ||
                                repl.status == kCBLReplicationIdle);
         }];

    if ([listener respondsToSelector:@selector(connectionCount)]) // observe for changes:
        [self keyValueObservingExpectationForObject: listener
                                            keyPath: @"connectionCount" expectedValue: @0];
    
    [self waitForExpectationsWithTimeout: 30.0 handler: nil];
}


- (BOOL) runReplication: (CBLReplication*)repl
         expectedChangesCount: (NSUInteger)expectedChangesCount
{
    [self runReplication: repl];
    AssertNil(repl.lastError);
    if (repl.lastError)
        return NO;
    if (expectedChangesCount > 0) {
        AssertEq(repl.completedChangesCount, expectedChangesCount);
    }
    return YES;
}


@end




@interface P2P_BLIP_Tests : P2P_HTTP_Tests
@end

@implementation P2P_BLIP_Tests

- (void)invokeTest {
    // Skip these tests if TestNewReplicator isn't enabled:
    if ([[NSUserDefaults standardUserDefaults] boolForKey: @"TestNewReplicator"])
        [super invokeTest];
    else
        Log(@"(Skipping test; TestNewReplicator is not enabled)");
}

- (Class) listenerClass {
    return [CBLSyncListener class];
}

- (NSString*) replicatorClassName {
    return @"CBLBlipReplicator";
}

- (void) testPush               {[super testPush];}
- (void) testPull               {[super testPull];}
- (void) testPushAttachments    {[super testPushAttachments];}
- (void) testPullAttachments    {[super testPullAttachments];}

@end

