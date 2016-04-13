//
//  CBLReachability.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/13/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLReachability.h"
#import <SystemConfiguration/SystemConfiguration.h>
#include <arpa/inet.h>


DefineLogDomain(Reachability);


static void ClientCallback(SCNetworkReachabilityRef target,
                           SCNetworkReachabilityFlags flags,
                           void *info);


@interface CBLReachability ()
@property (readwrite, nonatomic) BOOL reachabilityKnown;
@property (readwrite, nonatomic) SCNetworkReachabilityFlags reachabilityFlags;
- (void) flagsChanged: (SCNetworkReachabilityFlags)flags;
@end


@implementation CBLReachability
{
    NSString* _hostName;
    SCNetworkReachabilityRef _ref;
    CFRunLoopRef _runLoop;
    dispatch_queue_t _queue;
    SCNetworkReachabilityFlags _reachabilityFlags;
    BOOL _reachabilityKnown;
    BOOL _usingProxy;
    CBLReachabilityOnChangeBlock _onChange;
}


#if DEBUG
static BOOL sAlwaysAssumeProxy = NO;
+ (void) setAlwaysAssumesProxy: (BOOL)alwaysAssumesProxy {
    sAlwaysAssumeProxy = alwaysAssumesProxy;
}
#endif



+ (BOOL) usingProxyForURL: (NSURL*)url {
    NSDictionary* settings = CFBridgingRelease(CFNetworkCopySystemProxySettings());
    NSArray* proxies = CFBridgingRelease(CFNetworkCopyProxiesForURL((__bridge CFURLRef)url,
                                                                    (__bridge CFDictionaryRef)settings));
    for (NSDictionary* proxy in proxies) {
        if (![proxy[(id)kCFProxyTypeKey] isEqual: (id)kCFProxyTypeNone])
            return YES;
    }
#if DEBUG
    return sAlwaysAssumeProxy;
#endif
    return NO;
}


- (instancetype) initWithReachabilityRef: (SCNetworkReachabilityRef)ref {
    self = [super init];
    if (self) {
        _ref = ref;
        SCNetworkReachabilityContext context = {0, (__bridge void *)(self)};
        if (!_ref || !SCNetworkReachabilitySetCallback(_ref, ClientCallback, &context)) {
            return nil;
        }
    }
    return self;
}


- (instancetype) init {
    struct sockaddr_in addr = {sizeof(addr), AF_INET};  // IP address 0.0.0.0
    SCNetworkReachabilityRef ref = SCNetworkReachabilityCreateWithAddress(NULL,
                                                                          (struct sockaddr*)&addr);
    return [self initWithReachabilityRef: ref];
}


- (instancetype) initWithURL: (NSURL*)url {
    NSString* hostName = url.host;
    if (!hostName.length)
        hostName = @"localhost";
    // If network access requires a proxy, just track whether there is any network connection:
    if ([[self class] usingProxyForURL: url]) {
        self = [self init];
        if (self)
            _usingProxy = YES;
    } else {
        self = [self initWithReachabilityRef: SCNetworkReachabilityCreateWithName(NULL,
                                                                          hostName.UTF8String)];
    }
    if (self) {
        _hostName = [hostName copy];
    }
    return self;
}


- (BOOL) startOnRunLoop: (CFRunLoopRef)runLoop {
    if (_runLoop || _queue)
        return (_runLoop == runLoop);
    if (!SCNetworkReachabilityScheduleWithRunLoop(_ref, runLoop, kCFRunLoopCommonModes))
        return NO;
    _runLoop = (CFRunLoopRef) CFRetain(runLoop);
    return [self started];
}

- (BOOL) startOnQueue: (dispatch_queue_t)queue {
    if (_runLoop || _queue)
        return _queue == queue;
    if (!SCNetworkReachabilitySetDispatchQueue(_ref, queue))
        return NO;
    _queue = queue;
    return [self started];
}

- (BOOL) started {
    // See whether status is already known:
    if (SCNetworkReachabilityGetFlags(_ref, &_reachabilityFlags)) {
        _reachabilityKnown = YES;
        LogTo(Reachability, @"%@: flags=%x; starting...", self, _reachabilityFlags);
    } else {
        LogTo(Reachability, @"%@: starting...", self);
    }
    return YES;
}


- (void) stop {
    _reachabilityKnown = NO;
    if (_runLoop || _queue)
        LogTo(Reachability, @"%@: stopped", self);
    if (_runLoop) {
        SCNetworkReachabilityUnscheduleFromRunLoop(_ref, _runLoop, kCFRunLoopCommonModes);
        CFRelease(_runLoop);
        _runLoop = NULL;
    }
    if (_queue) {
        SCNetworkReachabilitySetDispatchQueue(_ref, NULL);
        _queue = NULL;
    }
}


- (void)dealloc {
    if (_ref) {
        [self stop];
        CFRelease(_ref);
    }
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
    NSString* desc;
    if (!_hostName)
        desc = @"<(any)>";
    else if (_usingProxy)
        desc = $sprintf(@"<(proxy to)%@>", _hostName);
    else
        desc = $sprintf(@"<%@>", _hostName);
    if (_reachabilityKnown)
        desc = [desc stringByAppendingFormat: @":%@", self.status];
    return desc;
}


- (BOOL) reachable {
    // We want 'reachable' flag to be on, but not if user intervention is required (like PPP login)
    return _reachabilityKnown
        &&  (_reachabilityFlags & kSCNetworkReachabilityFlagsReachable)
        && !(_reachabilityFlags & kSCNetworkReachabilityFlagsInterventionRequired);
}

- (BOOL) reachableByWiFi {
    return self.reachable
#if TARGET_OS_IPHONE
        && !(_reachabilityFlags & kSCNetworkReachabilityFlagsIsWWAN)
#endif
    ;
}


+ (NSSet*) keyPathsForValuesAffectingReachable {
    return [NSSet setWithObjects: @"reachabilityKnown", @"reachabilityFlags", nil];
}

+ (NSSet*) keyPathsForValuesAffectingReachableByWiFi {
    return [NSSet setWithObjects: @"reachabilityKnown", @"reachabilityFlags", nil];
}


- (void) flagsChanged: (SCNetworkReachabilityFlags)flags {
    if (!_reachabilityKnown || flags != _reachabilityFlags) {
        self.reachabilityFlags = flags;
        self.reachabilityKnown = YES;
        LogTo(Reachability, @"%@: flags <-- %x", self, flags);
        __typeof(_onChange) onChange = _onChange;
        if (onChange)
            onChange();
    }
}


static void ClientCallback(SCNetworkReachabilityRef target,
                           SCNetworkReachabilityFlags flags,
                           void *info)
{
    [(__bridge CBLReachability*)info flagsChanged: flags];
}


@end
