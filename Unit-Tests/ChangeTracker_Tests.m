//
//  ChangeTracker_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/23/14.
//
//

#import "CBLTestCase.h"
#import "CBLChangeTracker.h"
#import "CBLAuthorizer.h"
#import "CBLInternal.h"
#import "MYURLUtils.h"


@interface ChangeTracker_Tests : CBLTestCaseWithDB <CBLChangeTrackerClient>
@property (readonly) NSArray* changes;
@property NSArray* anchorCerts;
@property BOOL onlyTrustAnchorCerts;
@property BOOL checkedAnSSLCert;
@property (readonly) BOOL caughtUp, finished;
- (void) run: (CBLChangeTracker*)tracker expectingChanges: (NSArray*)expectedChanges;
- (void) run: (CBLChangeTracker*)tracker expectingError: (NSError*)error;
@end


@implementation ChangeTracker_Tests
{
    NSMutableArray* _changes;
    BOOL _running, _finished;
}

- (void) test_Simple {
    for (CBLChangeTrackerMode mode = kOneShot; mode <= kLongPoll; ++mode) {
        Log(@"Mode = %d ...", mode);
        NSURL* url = [self remoteTestDBURL: @"attach-test"];
        CBLChangeTracker* tracker = [[CBLChangeTracker alloc] initWithDatabaseURL: url mode: mode conflicts: NO lastSequence: nil client: self];
        NSArray* expected = $array($dict({@"seq", @3},
                                         {@"id", @"038c536dc29ff0f4127705879700062c"},
                                         {@"revs", $array(@"3-e715bcf1865f8283ab1f0ba76e7a92ba")}),
                                   $dict({@"seq", @5},
                                         {@"id", @"oneBigAttachment"},
                                         {@"revs", $array(@"2-7a9086d57651b86882d4806bad25903c")}),
                                   $dict({@"seq", @8},
                                         {@"id", @"text_attachment"},
                                         {@"revs", $array(@"2-116dc4ccc934971ae14d8a8afb29b023")}),
                                   $dict({@"seq", @11},
                                         {@"id", @"weirdmeta"},
                                         {@"revs", $array(@"1-eef1e19e2aa822dc3f1c62196cbe6746")}),
                                   $dict({@"seq", @12},
                                         {@"id", @"extrameta"},
                                         {@"revs", $array(@"1-11d28a27038a6cce1f08674ab3d67653")}),
                                   $dict({@"seq", @13},
                                         {@"id", @"propertytest"},
                                         {@"revs", $array(@"2-61de0ad4b61a3106195e9b21bcb69d0c")},
                                         {@"deleted", @YES})
                                   );
        [self run: tracker expectingChanges: expected];
    }
}


- (void) test_SSL_Part1_Failure {
    // First try without adding the custom root cert, which should fail:
    NSURL* url = [NSURL URLWithString: @"https://localhost:4994/public"];//FIX: Make portable
    CBLChangeTracker* tracker = [[CBLChangeTracker alloc] initWithDatabaseURL: url mode: kOneShot conflicts: NO lastSequence: 0 client:  self];
    [self run: tracker expectingError: [NSError errorWithDomain: NSURLErrorDomain
                                                             code:NSURLErrorServerCertificateUntrusted
                                                         userInfo: nil]];
}

- (void) test_SSL_Part2_Success {
    // Now get a copy of the server's certificate:
    NSData* certData = [NSData dataWithContentsOfFile: @"/Couchbase/sync_gateway/examples/ssl/cert.cer"];//FIX: Make portable
    Assert(certData, @"Couldn't load cert file");
    SecCertificateRef cert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certData);
    Assert(cert, @"Couldn't parse cert");

    // Retry, registering the server cert as a root:
    self.anchorCerts = @[(__bridge id)cert];
    NSURL* url = [NSURL URLWithString: @"https://localhost:4994/public"];//FIX: Make portable
    CBLChangeTracker* tracker = [[CBLChangeTracker alloc] initWithDatabaseURL: url mode: kOneShot conflicts: NO lastSequence: 0 client:  self];
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
    [self run: tracker expectingChanges: expected];
    Assert(self.checkedAnSSLCert);
}


- (void) test_Auth {
    RequireTestCase(AuthFailure);
    // This database requires authentication to access at all.
    NSURL* url = [self remoteTestDBURL: @"tdpuller_test2_auth"];
    if (!url) {
        Warn(@"Skipping test; no remote DB URL configured");
        return;
    }

    AddTemporaryCredential(url, @"CouchDB", @"dummy", @"dummy");

    CBLChangeTracker* tracker = [[CBLChangeTracker alloc] initWithDatabaseURL: url mode: kOneShot conflicts: NO lastSequence: 0 client:  self];
    NSArray* expected = $array($dict({@"seq", @1},
                                     {@"id", @"something"},
                                     {@"revs", $array(@"1-31e4c2faf5cfcd56f4518c29367f9124")}) );
    [self run: tracker expectingChanges: expected];
}


- (void) test_AuthFailure {
    NSURL* url = [self remoteTestDBURL: @"tdpuller_test2_auth"];
    if (!url) {
        Warn(@"Skipping test; no remote DB URL configured");
        return;
    }
    // Add a bogus user to make auth fail:
    NSString* urlStr = url.absoluteString;
    urlStr = [urlStr stringByReplacingOccurrencesOfString: @"http://" withString: @"http://bogus@"];
    url = $url(urlStr);

    CBLChangeTracker* tracker = [[CBLChangeTracker alloc] initWithDatabaseURL: url mode: kOneShot conflicts: NO lastSequence: 0 client:  self];
    [self run: tracker expectingError: CBLStatusToNSError(kCBLStatusUnauthorized, url)];
}


- (void) test_CBLWebSocketChangeTracker_Auth {
    // This Sync Gateway database requires authentication to access at all.
    NSURL* url = $url(@"http://localhost:4984/cbl_auth_test"); //TEMP
    if (!url) {
        Warn(@"Skipping test; no remote DB URL configured");
        return;
    }
    CBLChangeTracker* tracker = [[CBLChangeTracker alloc] initWithDatabaseURL: url mode: kWebSocket conflicts: NO lastSequence: 0 client:  self];

    NSURLCredential* c = [NSURLCredential credentialWithUser: @"test" password: @"abc123"
                                                 persistence: NSURLCredentialPersistenceForSession];
    tracker.authorizer = [[CBLBasicAuthorizer alloc] initWithCredential: c];

    NSArray* expected = $array($dict({@"seq", @1},
                                     {@"id", @"_user/test"},
                                     {@"revs", $array()}) ,
                               $dict({@"seq", @2},
                                     {@"id", @"something"},
                                     {@"revs", $array(@"1-53b059eb633a9d58042318e478cc73dc")}) );
    [self run: tracker expectingChanges: expected];
}


- (void) test_Retry {
#if 0 // This test takes 31 seconds to run, so let's leave it turned off normally
    // Intentionally connect to a nonexistent server to see the retry logic.
    NSURL* url = [NSURL URLWithString: @"https://localhost:5999/db"];
    
    CBLChangeTracker* tracker = [[[CBLChangeTracker alloc] initWithDatabaseURL: url mode: kOneShot conflicts: NO lastSequence: 0 client:  self] autorelease];
    [self run: tracker expectingError: [NSError errorWithDomain: NSURLErrorDomain code: NSURLErrorCannotConnectToHost userInfo: nil]];
#endif
}


#pragma mark - CHANGE TRACKING


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
    AssertEqual(_changes, expectedChanges);
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
    AssertEqual(tracker.error.domain, error.domain);
    AssertEq(tracker.error.code, error.code);
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
