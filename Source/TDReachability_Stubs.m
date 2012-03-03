//
//  TDReachability_Stubs.m
//  TouchDB
//
//  Created by Jens Alfke on 2/28/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDReachability.h"


@implementation TDReachability


- (id) initWithHostName: (NSString*)hostName {
    Assert(hostName);
    self = [super init];
    if (self) {
        _hostName = [hostName copy];
        _reachabilityKnown = YES;
    }
    return self;
}


- (BOOL) start {
    return YES;
}


- (void) stop {
}


- (void)dealloc {
    [_onChange release];
    [_hostName release];
    [super dealloc];
}


@synthesize hostName=_hostName, onChange=_onChange,
            reachabilityKnown=_reachabilityKnown, reachabilityFlags=_reachabilityFlags;


- (NSString*) status {
    if (!_reachabilityKnown)
        return @"unknown";
    else if (!self.reachable)
        return @"unreachable";
#if TARGET_OS_IPHONE
    else if (!self.reachableByWiFi)
        return @"reachable (3G)";
#endif
    else
        return @"reachable";
}

- (NSString*) description {
    return $sprintf(@"<%@>:%@", _hostName, self.status);
}


- (BOOL) reachable {
    return YES;
}

- (BOOL) reachableByWiFi {
    return self.reachable;
}


+ (NSSet*) keyPathsForValuesAffectingReachable {
    return [NSSet setWithObjects: @"reachabilityKnown", @"reachabilityFlags", nil];
}

+ (NSSet*) keyPathsForValuesAffectingReachableByWiFi {
    return [NSSet setWithObjects: @"reachabilityKnown", @"reachabilityFlags", nil];
}


@end
