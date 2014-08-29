//
//  CBLChangeTracker_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/11/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLChangeTracker.h"
#import "CBLAuthorizer.h"
#import "CBLInternal.h"
#import "Test.h"
#import "MYURLUtils.h"


void TestDictOf(void);
void TestDictOf(void) {
    NSDictionary *d = $dict({@"seq", @1},
                            {@"id", @"foo"},
                            {@"changes", @[@"hi"]});
    CAssertEqual(d[@"seq"], @1);
}


#if DEBUG

TestCase(DictOf) {
    NSDictionary* z = @{@"hi": @"there"};
    NSLog(@"%@",z);
    //typedef struct { __unsafe_unretained id key; __unsafe_unretained id value; } Pair;
    typedef id Pair[2];
    typedef Pair Pairs[];
    Pairs pairs= {
        {@"changes", @[@"hi"]}
    };
    NSLog(@"it's %@", pairs[0][1]);
    //NSDictionary* d = _dictof(pairs,sizeof(pairs)/sizeof(struct _dictpair));
    //CAssertEqual(d[@"changes"], @[@"hi"]);
}

@interface CBLChangeTrackerTester : NSObject <CBLChangeTrackerClient>
{
    NSMutableArray* _changes;
    BOOL _running, _finished;
}
@property (readonly) NSArray* changes;
@property NSArray* anchorCerts;
@property BOOL onlyTrustAnchorCerts;
@property BOOL checkedAnSSLCert;
@property (readonly) BOOL caughtUp, finished;
@end


@implementation CBLChangeTrackerTester

@synthesize changes=_changes, checkedAnSSLCert=_checkedAnSSLCert, caughtUp=_caughtUp, finished=_finished, anchorCerts=_anchorCerts, onlyTrustAnchorCerts=_onlyTrustAnchorCerts;

- (void) run: (CBLChangeTracker*)tracker expectingChanges: (NSArray*)expectedChanges {
    [tracker start];
    _running = YES;
    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow: 10];
    while (_running && _changes.count < expectedChanges.count
           && [timeout timeIntervalSinceNow] > 0
           && [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                       beforeDate: timeout])
    {
        AssertNil(tracker.error);
    }

    [tracker stop];
    if ([timeout timeIntervalSinceNow] <= 0) {
        Warn(@"Timeout contacting %@", tracker.databaseURL);
        Assert(NO, @"Failed to contact %@", tracker.databaseURL);
        return;
    }
    AssertNil(tracker.error);
    CAssertEqual(_changes, expectedChanges);
}

- (void) run: (CBLChangeTracker*)tracker expectingError: (NSError*)error {
    [tracker start];
    _running = YES;
    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow: 60];
    while (_running && [timeout timeIntervalSinceNow] > 0
           && [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                       beforeDate: timeout])
        ;
    Assert(!_running, @"-changeTrackerStoped: wasn't called");
    CAssertEqual(tracker.error.domain, error.domain);
    CAssertEq(tracker.error.code, error.code);
}

- (void) changeTrackerReceivedSequence:(id)sequence
                                 docID:(NSString *)docID
                                revIDs:(NSArray *)revIDs
                               deleted:(BOOL)deleted
{
    if (!_changes)
        _changes = [[NSMutableArray alloc] init];
    [_changes addObject: $dict({@"seq", sequence},
                               {@"id", docID},
                               {@"revs", revIDs},
                               {@"deleted", (deleted ? $true : nil)})];
}

- (void) changeTrackerCaughtUp {
    _caughtUp = YES;
}

- (void) changeTrackerFinished {
    _finished = YES;
}

- (void) changeTrackerStopped:(CBLChangeTracker *)tracker {
    _running = NO;
}

- (BOOL) changeTrackerApproveSSLTrust: (SecTrustRef)trust
                              forHost: (NSString*)host port: (UInt16)port
{
    self.checkedAnSSLCert = YES;

    if (_anchorCerts.count > 0) {
        SecTrustSetAnchorCertificates(trust, (__bridge CFArrayRef)_anchorCerts);
        SecTrustSetAnchorCertificatesOnly(trust, _onlyTrustAnchorCerts);
    }

    SecTrustResultType result;
    OSStatus err = SecTrustEvaluate(trust, &result);
    if (err) {
        Warn(@"SecTrustEvaluate failed with err %d for host %@:%d", (int)err, host, port);
        return NO;
    }
    if (result == kSecTrustResultProceed || result == kSecTrustResultUnspecified)
        return YES;
    CBLWarnUntrustedCert(@"", trust);
    return NO;
}

@end


TestCase(CBLChangeTracker_Simple) {
    for (CBLChangeTrackerMode mode = kOneShot; mode <= kLongPoll; ++mode) {
        Log(@"Mode = %d ...", mode);
        CBLChangeTrackerTester* tester = [[CBLChangeTrackerTester alloc] init];
        NSURL* url = RemoteTestDBURL(@"attach-test");
        CBLChangeTracker* tracker = [[CBLChangeTracker alloc] initWithDatabaseURL: url mode: mode conflicts: NO lastSequence: nil client: tester];
        NSArray* expected = $array($dict({@"seq", @3},
                                         {@"id", @"038c536dc29ff0f4127705879700062c"},
                                         {@"revs", $array(@"3-e715bcf1865f8283ab1f0ba76e7a92ba")}),
                                   $dict({@"seq", @5},
                                         {@"id", @"oneBigAttachment"},
                                         {@"revs", $array(@"2-7a9086d57651b86882d4806bad25903c")}),
                                   $dict({@"seq", @6},
                                         {@"id", @"propertytest"},
                                         {@"revs", $array(@"1-132f0b3efda2b9126aa0b7565d47acd3")}),
                                   $dict({@"seq", @8},
                                         {@"id", @"text_attachment"},
                                         {@"revs", $array(@"2-116dc4ccc934971ae14d8a8afb29b023")}),
                                   $dict({@"seq", @11},
                                         {@"id", @"weirdmeta"},
                                         {@"revs", $array(@"1-eef1e19e2aa822dc3f1c62196cbe6746")}),
                                   $dict({@"seq", @12},
                                         {@"id", @"extrameta"},
                                         {@"revs", $array(@"1-11d28a27038a6cce1f08674ab3d67653")})
                                   );
        [tester run: tracker expectingChanges: expected];
    }
}


TestCase(CBLChangeTracker_SSL) {
    // First try without adding the custom root cert, which should fail:
    CBLChangeTrackerTester* tester = [[CBLChangeTrackerTester alloc] init];
    NSURL* url = [NSURL URLWithString: @"https://localhost:4994/public"];//FIX: Make portable
    CBLChangeTracker* tracker = [[CBLChangeTracker alloc] initWithDatabaseURL: url mode: kOneShot conflicts: NO lastSequence: 0 client:  tester];
    [tester run: tracker expectingError: [NSError errorWithDomain: NSURLErrorDomain
                                                             code:NSURLErrorServerCertificateUntrusted
                                                         userInfo: nil]];

    // Now get a copy of the server's certificate:
    NSData* certData = [NSData dataWithContentsOfFile: @"/Couchbase/sync_gateway/examples/ssl/cert.cer"];//FIX: Make portable
    Assert(certData, @"Couldn't load cert file");
    SecCertificateRef cert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certData);
    Assert(cert, @"Couldn't parse cert");

    // Retry, registering the server cert as a root:
    tester = [[CBLChangeTrackerTester alloc] init];
    tester.anchorCerts = @[(__bridge id)cert];
    tracker = [[CBLChangeTracker alloc] initWithDatabaseURL: url mode: kOneShot conflicts: NO lastSequence: 0 client:  tester];
    NSArray* expected = $array($dict({@"seq", @8},
                                     {@"id", @"foo"},
                                     {@"revs", $array(@"1-a154bf18a4d64ee6d93b6cc838b2b344")}),
                               $dict({@"seq", @9},
                                     {@"id", @"bar"},
                                     {@"revs", $array(@"1-a7a0e83c48d20397aed5703a06c01ea8")}),
                               $dict({@"seq", @11},
                                     {@"id", @"_user/GUEST"},
                                     {@"revs", $array()}),
                               );
    [tester run: tracker expectingChanges: expected];
    CAssert(tester.checkedAnSSLCert);
}


TestCase(CBLChangeTracker_Auth) {
    RequireTestCase(CBLChangeTracker_AuthFailure);
    // This database requires authentication to access at all.
    NSURL* url = RemoteTestDBURL(@"tdpuller_test2_auth");
    if (!url) {
        Warn(@"Skipping test; no remote DB URL configured");
        return;
    }
    CBLChangeTrackerTester* tester = [[CBLChangeTrackerTester alloc] init];
    AddTemporaryCredential(url, @"CouchDB", @"dummy", @"dummy");

    CBLChangeTracker* tracker = [[CBLChangeTracker alloc] initWithDatabaseURL: url mode: kOneShot conflicts: NO lastSequence: 0 client:  tester];
    NSArray* expected = $array($dict({@"seq", @1},
                                     {@"id", @"something"},
                                     {@"revs", $array(@"1-31e4c2faf5cfcd56f4518c29367f9124")}) );
    [tester run: tracker expectingChanges: expected];
}


TestCase(CBLChangeTracker_AuthFailure) {
    NSURL* url = RemoteTestDBURL(@"tdpuller_test2_auth");
    if (!url) {
        Warn(@"Skipping test; no remote DB URL configured");
        return;
    }
    // Add a bogus user to make auth fail:
    NSString* urlStr = url.absoluteString;
    urlStr = [urlStr stringByReplacingOccurrencesOfString: @"http://" withString: @"http://bogus@"];
    url = $url(urlStr);

    CBLChangeTrackerTester* tester = [[CBLChangeTrackerTester alloc] init];

    CBLChangeTracker* tracker = [[CBLChangeTracker alloc] initWithDatabaseURL: url mode: kOneShot conflicts: NO lastSequence: 0 client:  tester];
    [tester run: tracker expectingError: CBLStatusToNSError(kCBLStatusUnauthorized, url)];
}


TestCase(CBLWebSocketChangeTracker_Auth) {
    // This Sync Gateway database requires authentication to access at all.
    NSURL* url = $url(@"http://localhost:4984/cbl_auth_test"); //TEMP
    if (!url) {
        Warn(@"Skipping test; no remote DB URL configured");
        return;
    }
    CBLChangeTrackerTester* tester = [[CBLChangeTrackerTester alloc] init];
    CBLChangeTracker* tracker = [[CBLChangeTracker alloc] initWithDatabaseURL: url mode: kWebSocket conflicts: NO lastSequence: 0 client:  tester];

    NSURLCredential* c = [NSURLCredential credentialWithUser: @"test" password: @"abc123"
                                                 persistence: NSURLCredentialPersistenceForSession];
    tracker.authorizer = [[CBLBasicAuthorizer alloc] initWithCredential: c];

    NSArray* expected = $array($dict({@"seq", @1},
                                     {@"id", @"_user/test"},
                                     {@"revs", $array()}) ,
                               $dict({@"seq", @2},
                                     {@"id", @"something"},
                                     {@"revs", $array(@"1-53b059eb633a9d58042318e478cc73dc")}) );
    [tester run: tracker expectingChanges: expected];
}


TestCase(CBLChangeTracker_Retry) {
#if 0 // This test takes 31 seconds to run, so let's leave it turned off normally
    // Intentionally connect to a nonexistent server to see the retry logic.
    CBLChangeTrackerTester* tester = [[[CBLChangeTrackerTester alloc] init] autorelease];
    NSURL* url = [NSURL URLWithString: @"https://localhost:5999/db"];
    
    CBLChangeTracker* tracker = [[[CBLChangeTracker alloc] initWithDatabaseURL: url mode: kOneShot conflicts: NO lastSequence: 0 client:  tester] autorelease];
    [tester run: tracker expectingError: [NSError errorWithDomain: NSURLErrorDomain code: NSURLErrorCannotConnectToHost userInfo: nil]];
#endif
}


TestCase(CBLChangeTracker) {
    RequireTestCase(CBLChangeTracker_Simple);
    RequireTestCase(CBLChangeTracker_SSL);
    RequireTestCase(CBLChangeTracker_Auth);
    RequireTestCase(CBLChangeTracker_AuthFailure);
    RequireTestCase(CBLChangeTracker_Retry);
    RequireTestCase(CBLWebSocketChangeTracker_Auth);
}

#endif // DEBUG
