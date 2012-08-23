//
//  TDChangeTracker_Tests.m
//  TouchDB
//
//  Created by Jens Alfke on 5/11/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//
//
//  Created by Jens Alfke on 12/7/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TDConnectionChangeTracker.h"
#import "TDInternal.h"
#import "Test.h"
#import "MYURLUtils.h"


#if DEBUG


@interface TDChangeTrackerTester : NSObject <TDChangeTrackerClient>
{
    NSMutableArray* _changes;
    BOOL _running;
}
@property (readonly) NSArray* changes;
@end


@implementation TDChangeTrackerTester

@synthesize changes=_changes;

- (void) run: (TDChangeTracker*)tracker expectingChanges: (NSArray*)expectedChanges {
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
    AssertNil(tracker.error);
    CAssertEqual(_changes, expectedChanges);
}

- (void) run: (TDChangeTracker*)tracker expectingError: (NSError*)error {
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

- (void) changeTrackerStopped:(TDChangeTracker *)tracker {
    _running = NO;
}

- (void)dealloc
{
    [_changes release];
    [super dealloc];
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


TestCase(TDChangeTracker) {
    TDChangeTrackerTester* tester = [[[TDChangeTrackerTester alloc] init] autorelease];
    NSURL* url = [NSURL URLWithString: @"http://snej.iriscouch.com/tdpuller_test1"];
    TDChangeTracker* tracker = [[[TDConnectionChangeTracker alloc] initWithDatabaseURL: url mode: kOneShot conflicts: NO lastSequence: nil client: tester] autorelease];
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


TestCase(TDChangeTracker_SSL) {
    // The only difference here is the "https:" scheme in the URL.
    TDChangeTrackerTester* tester = [[[TDChangeTrackerTester alloc] init] autorelease];
    NSURL* url = [NSURL URLWithString: @"https://snej.iriscouch.com/tdpuller_test1"];
    TDChangeTracker* tracker = [[[TDConnectionChangeTracker alloc] initWithDatabaseURL: url mode: kOneShot conflicts: NO lastSequence: 0 client:  tester] autorelease];
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


TestCase(TDChangeTracker_Auth) {
    // This database requires authentication to access at all.
    TDChangeTrackerTester* tester = [[[TDChangeTrackerTester alloc] init] autorelease];
    NSURL* url = [NSURL URLWithString: @"https://dummy@snej.iriscouch.com/tdpuller_test2_auth"];
    addTemporaryCredential(url, @"snejdom", @"dummy", @"dummy");

    TDChangeTracker* tracker = [[[TDConnectionChangeTracker alloc] initWithDatabaseURL: url mode: kOneShot conflicts: NO lastSequence: 0 client:  tester] autorelease];
    NSArray* expected = $array($dict({@"seq", @1},
                                     {@"id", @"something"},
                                     {@"changes", $array($dict({@"rev", @"1-967a00dff5e02add41819138abb3284d"}))}) );
    [tester run: tracker expectingChanges: expected];
}


#if 0 // This test takes 31 seconds to run, so let's leave it turned off normally
TestCase(TDChangeTracker_Retry) {
    // Intentionally connect to a nonexistent server to see the retry logic.
    TDChangeTrackerTester* tester = [[[TDChangeTrackerTester alloc] init] autorelease];
    NSURL* url = [NSURL URLWithString: @"https://localhost:5999/db"];
    
    TDChangeTracker* tracker = [[[TDConnectionChangeTracker alloc] initWithDatabaseURL: url mode: kOneShot conflicts: NO lastSequence: 0 client:  tester] autorelease];
    [tester run: tracker expectingError: [NSError errorWithDomain: NSURLErrorDomain code: -1004 userInfo: nil]];
}
#endif

#endif // DEBUG
