//
//  CBLChangeTracker_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/11/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLChangeTracker.h"
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
    BOOL _running;
}
@property (readonly) NSArray* changes;
@property BOOL checkedAnSSLCert;
@end


@implementation CBLChangeTrackerTester

@synthesize changes=_changes, checkedAnSSLCert=_checkedAnSSLCert;

- (void) run: (CBLChangeTracker*)tracker expectingChanges: (NSArray*)expectedChanges {
    [tracker start];
    _running = YES;
    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow: 10];
    while (_running && _changes.count < expectedChanges.count
           && [timeout timeIntervalSinceNow] > 0
           && [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                       beforeDate: timeout])
        ;
    [tracker stop];
    if ([timeout timeIntervalSinceNow] <= 0) {
        Warn(@"Timeout contacting %@", tracker.databaseURL);
        return;
    }
    Assert(!tracker.error, nil);
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

- (void) changeTrackerReceivedChange: (NSDictionary*)change {
    if (!_changes)
        _changes = [[NSMutableArray alloc] init];
    [_changes addObject: change];
}

- (void) changeTrackerStopped:(CBLChangeTracker *)tracker {
    _running = NO;
}

- (BOOL) changeTrackerApproveSSLTrust: (SecTrustRef)trust
                              forHost: (NSString*)host port: (UInt16)port
{
    self.checkedAnSSLCert = YES;
    return YES;
}

@end


static void addTemporaryCredential(NSURL* url, NSString* realm,
                                   NSString* username, NSString* password)
{
    NSURLCredential* c = [NSURLCredential credentialWithUser: username password: password
                                                 persistence: NSURLCredentialPersistenceForSession];
    NSURLProtectionSpace* s = [url my_protectionSpaceWithRealm: realm
                                          authenticationMethod: NSURLAuthenticationMethodDefault];
    [[NSURLCredentialStorage sharedCredentialStorage] setCredential: c forProtectionSpace: s];
}


TestCase(CBLChangeTracker_Simple) {
    for (CBLChangeTrackerMode mode = kOneShot; mode <= kContinuous; ++mode) {
        Log(@"Mode = %d ...", mode);
        CBLChangeTrackerTester* tester = [[CBLChangeTrackerTester alloc] init];
        NSURL* url = [NSURL URLWithString: @"http://snej.iriscouch.com/tdpuller_test1"];
        CBLChangeTracker* tracker = [[CBLChangeTracker alloc] initWithDatabaseURL: url mode: mode conflicts: NO lastSequence: nil client: tester];
        NSArray* expected = $array($dict({@"seq", @1},
                                         {@"id", @"foo"},
                                         {@"changes", $array($dict({@"rev", @"5-ca289aa53cbbf35a5f5c799b64b1f16f"}))}),
                                   $dict({@"seq", @2},
                                         {@"id", @"attach"},
                                         {@"changes", $array($dict({@"rev", @"1-a7e2aad2bc8084b9041433182e292d8e"}))}),
                                   $dict({@"seq", @5},
                                         {@"id", @"bar"},
                                         {@"changes", $array($dict({@"rev", @"1-16f4304cd5ad8779fb40cb6bbbed60f5"}))}),
                                   $dict({@"seq", @6},
                                         {@"id", @"08a5cb4cc83156401c85bbe40e0007de"},
                                         {@"deleted", $true},
                                         {@"changes", $array($dict({@"rev", @"3-cbdb323dec78588cfea63bf7bb5a246f"}))}) );
        [tester run: tracker expectingChanges: expected];
    }
}


TestCase(CBLChangeTracker_SSL) {
    // The only difference here is the "https:" scheme in the URL.
    CBLChangeTrackerTester* tester = [[CBLChangeTrackerTester alloc] init];
    NSURL* url = [NSURL URLWithString: @"https://snej.iriscouch.com/tdpuller_test1"];
    CBLChangeTracker* tracker = [[CBLChangeTracker alloc] initWithDatabaseURL: url mode: kOneShot conflicts: NO lastSequence: 0 client:  tester];
    NSArray* expected = $array($dict({@"seq", @1},
                                     {@"id", @"foo"},
                                     {@"changes", $array($dict({@"rev", @"5-ca289aa53cbbf35a5f5c799b64b1f16f"}))}),
                               $dict({@"seq", @2},
                                     {@"id", @"attach"},
                                     {@"changes", $array($dict({@"rev", @"1-a7e2aad2bc8084b9041433182e292d8e"}))}),
                               $dict({@"seq", @5},
                                     {@"id", @"bar"},
                                     {@"changes", $array($dict({@"rev", @"1-16f4304cd5ad8779fb40cb6bbbed60f5"}))}),
                               $dict({@"seq", @6},
                                     {@"id", @"08a5cb4cc83156401c85bbe40e0007de"},
                                     {@"deleted", $true},
                                     {@"changes", $array($dict({@"rev", @"3-cbdb323dec78588cfea63bf7bb5a246f"}))}) );
    [tester run: tracker expectingChanges: expected];
    CAssert(tester.checkedAnSSLCert);
}


TestCase(CBLChangeTracker_Auth) {
    // This database requires authentication to access at all.
    NSURL* url = RemoteTestDBURL(@"tdpuller_test2_auth");
    if (!url) {
        Warn(@"Skipping test; no remote DB URL configured");
        return;
    }
    CBLChangeTrackerTester* tester = [[CBLChangeTrackerTester alloc] init];
    addTemporaryCredential(url, @"snejdom", @"dummy", @"dummy");

    CBLChangeTracker* tracker = [[CBLChangeTracker alloc] initWithDatabaseURL: url mode: kOneShot conflicts: NO lastSequence: 0 client:  tester];
    NSArray* expected = $array($dict({@"seq", @1},
                                     {@"id", @"something"},
                                     {@"changes", $array($dict({@"rev", @"1-967a00dff5e02add41819138abb3284d"}))}) );
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
    RequireTestCase(CBLChangeTracker_Retry);
}

#endif // DEBUG
