//
//  URLEndpointListenerTest.m
//  CouchbaseLite
//
//  Created by Jayahari Vavachan on 5/13/20.
//  Copyright © 2020 Couchbase. All rights reserved.
//

#import "ReplicatorTest.h"
#import "CBLURLEndpointListener.h"
#import "CBLURLEndpointListenerConfiguration.h"

#define kPort 4984

API_AVAILABLE(macos(10.12), ios(10.0))
@interface URLEndpointListenerTest : ReplicatorTest
typedef CBLURLEndpointListenerConfiguration Config;
typedef CBLURLEndpointListener Listener;

@end

@implementation URLEndpointListenerTest

- (Listener*) listenAt: (uint16)port {
    Config* config = [[Config alloc] initWithDatabase: self.otherDB port: port];
    config.disableTLS = YES;
    Listener* list = [[Listener alloc] initWithConfig: config];
    
    // start listener
    NSError* err = nil;
    Assert([list startWithError: &err]);
    AssertNil(err);
    
    return list;
}

- (void) testPort {
    // initialize a listener
    Config* config = [[Config alloc] initWithDatabase: self.otherDB port: kPort];
    config.disableTLS = YES;
    Listener* list = [[Listener alloc] initWithConfig: config];
    AssertEqual(list.port, 0);
    
    // start listener
    NSError* err = nil;
    Assert([list startWithError: &err]);
    AssertNil(err);
    AssertEqual(list.port, kPort);
    
    // stops
    [list stop];
    AssertEqual(list.port, 0);
}

- (void) testEmptyPort {
    // initialize a listener
    Config* config = [[Config alloc] initWithDatabase: self.otherDB port: 0];
    config.disableTLS = YES;
    Listener* list = [[Listener alloc] initWithConfig: config];
    AssertEqual(list.port, 0);
    
    // start listener
    NSError* err = nil;
    Assert([list startWithError: &err]);
    AssertNil(err);
    Assert(list.port != 0);
    
    // stops
    [list stop];
    AssertEqual(list.port, 0);
}

- (void) testBusyPort {
    Listener* list1 = [self listenAt: kPort];
    
    // initialize a listener at same port
    Config* config = [[Config alloc] initWithDatabase: self.otherDB port: kPort];
    config.disableTLS = YES;
    Listener* list2 = [[Listener alloc] initWithConfig: config];
    
    // already in use when starting the second listener
    [self ignoreException:^{
        NSError* err = nil;
        [list2 startWithError: &err];
        AssertEqual(err.code, EADDRINUSE);
        AssertEqual(err.domain, NSPOSIXErrorDomain);
    }];
    
    // stops
    [list1 stop];
}

@end
