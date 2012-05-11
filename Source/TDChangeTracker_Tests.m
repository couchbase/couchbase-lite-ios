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

#import "TDSocketChangeTracker.h"
#import "TDInternal.h"
#import "Test.h"


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
    AssertNil(tracker.error);
    CAssertEqual(_changes, expectedChanges);
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


TestCase(TDSocketChangeTracker) {
    TDChangeTrackerTester* tester = [[[TDChangeTrackerTester alloc] init] autorelease];
    NSURL* url = [NSURL URLWithString: @"http://snej.iriscouch.com/tdpuller_test1"];
    TDChangeTracker* tracker = [[[TDSocketChangeTracker alloc] initWithDatabaseURL: url mode:kContinuous conflicts: NO lastSequence: 0 client:  tester] autorelease];
    NSArray* expected = $array($dict({@"seq", $object(1)},
                                     {@"id", @"foo"},
                                     {@"changes", $array($dict({@"rev", @"5-ca289aa53cbbf35a5f5c799b64b1f16f"}))}),
                               $dict({@"seq", $object(2)},
                                     {@"id", @"attach"},
                                     {@"changes", $array($dict({@"rev", @"1-a7e2aad2bc8084b9041433182e292d8e"}))}),
                               $dict({@"seq", $object(5)},
                                     {@"id", @"bar"},
                                     {@"changes", $array($dict({@"rev", @"1-16f4304cd5ad8779fb40cb6bbbed60f5"}))}),
                               $dict({@"seq", $object(6)},
                                     {@"id", @"08a5cb4cc83156401c85bbe40e0007de"},
                                     {@"deleted", $true},
                                     {@"changes", $array($dict({@"rev", @"3-cbdb323dec78588cfea63bf7bb5a246f"}))}) );
    [tester run: tracker expectingChanges: expected];
}


TestCase(TDSocketChangeTracker_SSL) {
    // The only difference here is the "https:" scheme in the URL.
    TDChangeTrackerTester* tester = [[[TDChangeTrackerTester alloc] init] autorelease];
    NSURL* url = [NSURL URLWithString: @"https://snej.iriscouch.com/tdpuller_test1"];
    TDChangeTracker* tracker = [[[TDSocketChangeTracker alloc] initWithDatabaseURL: url mode:kContinuous conflicts: NO lastSequence: 0 client:  tester] autorelease];
    NSArray* expected = $array($dict({@"seq", $object(1)},
                                     {@"id", @"foo"},
                                     {@"changes", $array($dict({@"rev", @"5-ca289aa53cbbf35a5f5c799b64b1f16f"}))}),
                               $dict({@"seq", $object(2)},
                                     {@"id", @"attach"},
                                     {@"changes", $array($dict({@"rev", @"1-a7e2aad2bc8084b9041433182e292d8e"}))}),
                               $dict({@"seq", $object(5)},
                                     {@"id", @"bar"},
                                     {@"changes", $array($dict({@"rev", @"1-16f4304cd5ad8779fb40cb6bbbed60f5"}))}),
                               $dict({@"seq", $object(6)},
                                     {@"id", @"08a5cb4cc83156401c85bbe40e0007de"},
                                     {@"deleted", $true},
                                     {@"changes", $array($dict({@"rev", @"3-cbdb323dec78588cfea63bf7bb5a246f"}))}) );
    [tester run: tracker expectingChanges: expected];
}


#endif // DEBUG
