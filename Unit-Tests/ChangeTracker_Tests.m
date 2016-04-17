//
//  ChangeTracker_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/23/14.
//
//

#import "CBLTestCase.h"
#import "CBLChangeTracker.h"
#import "CBLChangeMatcher.h"
#import "CBLRemoteRequest.h"
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
    BOOL _gotHeaders;
}

- (void) test_Simple {
    for (CBLChangeTrackerMode mode = kOneShot; mode <= kLongPoll; ++mode) {
        for (int activeOnly = 0; activeOnly <= 1; ++activeOnly) {
            Log(@"Mode = %d, activeOnly=%d ...", mode, activeOnly);
            NSURL* url = [self remoteNonSSLTestDBURL: @"attach_test"];
            if (!url)
                return;
            CBLChangeTracker* tracker = [[CBLChangeTracker alloc] initWithDatabaseURL: url mode: mode conflicts: NO lastSequence: nil client: self];
            tracker.activeOnly = (BOOL)activeOnly;
            NSMutableArray* expected = $marray(
                                   $dict({@"seq", @1},
                                         {@"id", @"_user/GUEST"},
                                         {@"revs", $array()}),
                                   $dict({@"seq", @2},
                                         {@"id", @"oneBigAttachment"},
                                         {@"revs", $array(@"2-7a9086d57651b86882d4806bad25903c")}),
                                   $dict({@"seq", @3},
                                         {@"id", @"038c536dc29ff0f4127705879700062c"},
                                         {@"revs", $array(@"3-e715bcf1865f8283ab1f0ba76e7a92ba")}),
                                   $dict({@"seq", @4},
                                         {@"id", @"propertytest"},
                                         {@"revs", $array(@"2-61de0ad4b61a3106195e9b21bcb69d0c")},
                                         {@"deleted", @YES}),
                                   $dict({@"seq", @5},
                                         {@"id", @"extrameta"},
                                         {@"revs", $array(@"1-11d28a27038a6cce1f08674ab3d67653")}),
                                   $dict({@"seq", @6},
                                         {@"id", @"weirdmeta"},
                                         {@"revs", $array(@"1-eef1e19e2aa822dc3f1c62196cbe6746")}),
                                   $dict({@"seq", @7},
                                         {@"id", @"text_attachment"},
                                         {@"revs", $array(@"2-116dc4ccc934971ae14d8a8afb29b023")})
                                   );
            if (activeOnly)
                [expected removeObjectAtIndex: 3];
            [self run: tracker expectingChanges: expected];
            Assert(_gotHeaders);
        }
    }
}


- (void) test_DocIDs {
    for (CBLChangeTrackerMode mode = kOneShot; mode <= kLongPoll; ++mode) {
        if (mode == kLongPoll)  //FIX: SG doesn't support _doc_ids filter in longpoll mode: SG#1703
            continue;
        for (int activeOnly = 0; activeOnly <= 1; ++activeOnly) {
            Log(@"Mode = %d, activeOnly=%d ...", mode, activeOnly);
            NSURL* url = [self remoteNonSSLTestDBURL: @"attach_test"];
            if (!url)
                return;
            CBLChangeTracker* tracker = [[CBLChangeTracker alloc] initWithDatabaseURL: url mode: mode conflicts: NO lastSequence: nil client: self];
            tracker.docIDs = @[@"oneBigAttachment", @"weirdmeta", @"propertytest"];
            tracker.activeOnly = (BOOL)activeOnly;
            NSMutableArray* expected = $marray(
                                   $dict({@"seq", @2},
                                         {@"id", @"oneBigAttachment"},
                                         {@"revs", $array(@"2-7a9086d57651b86882d4806bad25903c")}),
#if 0 // FIX: commented out because SG doesn't correctly handle deleted docs; see issue SG#1702
                                   $dict({@"seq", @4},
                                         {@"id", @"propertytest"},
                                         {@"revs", $array(@"2-61de0ad4b61a3106195e9b21bcb69d0c")},
                                         {@"deleted", @YES}),
#endif
                                   $dict({@"seq", @6},
                                         {@"id", @"weirdmeta"},
                                         {@"revs", $array(@"1-eef1e19e2aa822dc3f1c62196cbe6746")})
                                   );
#if 0 // FIX: See above
            if (activeOnly)
                [expected removeObjectAtIndex: 1];
#endif
            [self run: tracker expectingChanges: expected];
            Assert(_gotHeaders);
        }
    }
}


- (void) test_SSL_Part1_Failure {
    // First try without adding the custom root cert, which should fail:
    NSURL* url = [self remoteSSLTestDBURL: @"public"];
    if (!url)
        return;
    CBLChangeTracker* tracker = [[CBLChangeTracker alloc] initWithDatabaseURL: url mode: kOneShot conflicts: NO lastSequence: 0 client: self];
    [self allowWarningsIn:^{
        [self run: tracker expectingError: [NSError errorWithDomain: NSURLErrorDomain
                                                                 code:NSURLErrorServerCertificateUntrusted
                                                             userInfo: nil]];
    }];
}

- (void) test_SSL_Part2_Success {
    // Now get a copy of the server's certificate:
    NSData* certData = [self contentsOfTestFile: @"SelfSigned.cer"]; // same as Server/cert.pem
    Assert(certData, @"Couldn't load cert file");
    SecCertificateRef cert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certData);
    Assert(cert, @"Couldn't parse cert");

    // Retry, registering the server cert as a root:
    self.anchorCerts = @[(__bridge id)cert];
    NSURL* url = [self remoteSSLTestDBURL: @"public"];
    if (!url)
        return;
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
    Assert(_gotHeaders);
}


- (void) test_Auth {
    RequireTestCase(AuthFailure);
    // This database requires authentication to access at all.
    NSURL* url = [self remoteNonSSLTestDBURL: @"cbl_auth_test"];
    if (!url)
        return;

    AddTemporaryCredential(url, @"Couchbase Sync Gateway", @"test", @"abc123");

    CBLChangeTracker* tracker = [[CBLChangeTracker alloc] initWithDatabaseURL: url mode: kOneShot conflicts: NO lastSequence: 0 client:  self];
    NSArray* expected = $array($dict({@"seq", @1},
                                     {@"id", @"_user/test"},
                                     {@"revs", @[]}),
                               $dict({@"seq", @2},
                                     {@"id", @"something"},
                                     {@"revs", $array(@"1-53b059eb633a9d58042318e478cc73dc")}) );
    [self run: tracker expectingChanges: expected];
    RemoveTemporaryCredential(url, @"Couchbase Sync Gateway", @"test", @"abc123");
    Assert(_gotHeaders);
}


- (void) test_AuthFailure {
    NSURL* url = [self remoteNonSSLTestDBURL: @"cbl_auth_test"];
    if (!url)
        return;
    // Add a bogus user to make auth fail:
    NSString* urlStr = url.absoluteString;
    urlStr = [urlStr stringByReplacingOccurrencesOfString: @"http://" withString: @"http://bogus@"];
    url = $url(urlStr);

    CBLChangeTracker* tracker = [[CBLChangeTracker alloc] initWithDatabaseURL: url mode: kOneShot conflicts: NO lastSequence: 0 client:  self];
    [self allowWarningsIn: ^{
        [self run: tracker expectingError: CBLStatusToNSErrorWithInfo(kCBLStatusUnauthorized,
                                                                      nil, url, nil)];
    }];
}


- (void) test_CBLWebSocketChangeTracker_Auth {
    // This Sync Gateway database requires authentication to access at all.
    NSURL* url = [self remoteNonSSLTestDBURL: @"cbl_auth_test"];
    if (!url) {
        Warn(@"Skipping test; no remote DB URL configured");
        return;
    }
    CBLChangeTracker* tracker = [[CBLChangeTracker alloc] initWithDatabaseURL: url mode: kWebSocket conflicts: NO lastSequence: 0 client:  self];

    tracker.authorizer = [[CBLPasswordAuthorizer alloc] initWithUser: @"test" password: @"abc123"];

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


- (void) test_ChangeMatcher {
    NSString* kJSON = @"[\
    {\"seq\":1,\"id\":\"1\",\"changes\":[{\"rev\":\"2-751ac4eebdc2a3a4044723eaeb0fc6bd\"}],\"deleted\":true},\
    {\"seq\":2,\"id\":\"10\",\"changes\":[{\"rev\":\"2-566bffd5785eb2d7a79be8080b1dbabb\"}],\"deleted\":true},\
    {\"seq\":3,\"id\":\"100\",\"changes\":[{\"rev\":\"2-ec2e4d1833099b8a131388b628fbefbf\"}],\"deleted\":true}]";
    NSMutableArray* docIDs = $marray();
    CBLJSONMatcher* root = [CBLChangeMatcher changesFeedMatcherWithClient:
        ^(id sequence, NSString *docID, NSArray *revs, bool deleted) {
            [docIDs addObject: docID];
        } expectWrapperDict: NO];
    CBLJSONReader* parser = [[CBLJSONReader alloc] initWithMatcher: root];
    Assert([parser parseData: [kJSON dataUsingEncoding: NSUTF8StringEncoding]]);
    Assert([parser finish]);
    AssertEqual(docIDs, (@[@"1", @"10", @"100"]));

    kJSON = [NSString stringWithFormat: @"{\"results\":%@}", kJSON];
    docIDs = $marray();
    root = [CBLChangeMatcher changesFeedMatcherWithClient:
                            ^(id sequence, NSString *docID, NSArray *revs, bool deleted) {
                                [docIDs addObject: docID];
                            } expectWrapperDict: YES];
    parser = [[CBLJSONReader alloc] initWithMatcher: root];
    Assert([parser parseData: [kJSON dataUsingEncoding: NSUTF8StringEncoding]]);
    Assert([parser finish]);
    AssertEqual(docIDs, (@[@"1", @"10", @"100"]));
}


#pragma mark - CHANGE TRACKING


@synthesize changes=_changes, checkedAnSSLCert=_checkedAnSSLCert, caughtUp=_caughtUp, finished=_finished, anchorCerts=_anchorCerts, onlyTrustAnchorCerts=_onlyTrustAnchorCerts;

- (void) run: (CBLChangeTracker*)tracker expectingChanges: (NSArray*)expectedChanges {
    [tracker start];
    _running = YES;
    _changes = nil;
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
    AssertEqualish(_changes, expectedChanges);
}

- (void) run: (CBLChangeTracker*)tracker expectingError: (NSError*)error {
    [tracker start];
    _running = YES;
    _changes = nil;
    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow: 60];
    while (_running && [timeout timeIntervalSinceNow] > 0
           && [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                       beforeDate: timeout])
        ;
    Assert(!_running, @"-changeTrackerStoped: wasn't called");
    AssertEqual(tracker.error.domain, error.domain);
    AssertEq(tracker.error.code, error.code);
}

- (void) changeTrackerReceivedHTTPHeaders:(NSDictionary *)headers {
    _gotHeaders = YES;
    Assert([headers[@"Server"] hasPrefix: @"Couchbase Sync Gateway"]);
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

    // The hostname in our cheesy self-signed cert is 'localhost', so if the server isn't actually
    // the same device running the test, SecTrust will report a host-mismatch error.
    if (![host isEqualToString: @"localhost"]) {
        NSDictionary* result = CFBridgingRelease(SecTrustCopyResult(trust));
        NSDictionary* details = result[@"TrustResultDetails"];
        if ([details isEqual: @[@{@"SSLHostname": @NO}]])
            return YES;
    }

    CBLWarnUntrustedCert(@"", trust);
    return NO;
}

@end
