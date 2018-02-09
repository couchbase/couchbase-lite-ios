//
//  CBLReachability.h
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import <Foundation/Foundation.h>
#import <SystemConfiguration/SCNetworkReachability.h>

NS_ASSUME_NONNULL_BEGIN


typedef void (^CBLReachabilityOnChangeBlock)(void);


/** Asynchronously tracks the reachability of an Internet host, using the SystemConfiguration 
    framework's reachability API. You can get called when reachability changes by either
    KV-observing the properties, or setting an "onChange" block.
    "Reachable" means simply that the local IP stack has resolved the host's DNS name and knows how
    to route packets toward its IP address. It does NOT guarantee that you can successfully connect.
    Generally it just means that you have an Internet connection. */
@interface CBLReachability : NSObject

/** An instance initialized with this call will track the reachability of the given URL. In general
    this just uses the URL's hostname, but if the URL must be reached via a proxy, it will track 
    reachability of a local network. */
- (instancetype) initWithURL: (NSURL*)url;

/** An instance initialized with this call will track the reachability of _any_ network address,
    i.e. whether there is any network connection. */
- (instancetype) init;

/** The hostname of the URL this instance was created with, or nil if there is no URL. */
@property (readonly, nullable, nonatomic) NSString* hostName;

/** Starts tracking reachability.
    You have to call this after creating the object, or none of its properties will change.
    Change notifications (onChange or KVO) will be called on the specified runloop's thread.
    @return  YES if tracking started, or NO if there was an error. */
- (BOOL) startOnRunLoop: (CFRunLoopRef)runLoop;

/** Starts tracking reachability.
    You have to call this after creating the object, or none of its properties will change.
    Change notifications (onChange or KVO) will be called on the specified dispatch queue.
    @return  YES if tracking started, or NO if there was an error. */
- (BOOL) startOnQueue: (dispatch_queue_t)queue;

/** Stops tracking reachability.
    This is called automatically by -dealloc, but to be safe you can call it when you release your
    CBLReachability instance, to make sure that in case of a leak it isn't left running forever. */
- (void) stop;

/** YES if the host's reachability has been determined, NO if it hasn't or if there was an error. */
@property (readonly, nonatomic) BOOL reachabilityKnown;

/** The exact reachability flags; see Apple docs for the meanings of the bits. */
@property (readonly, nonatomic) SCNetworkReachabilityFlags reachabilityFlags;

/** Is this host reachable via a currently active network interface? */
@property (readonly, nonatomic) BOOL reachable;

/** Is this host reachable by WiFi (or wired Ethernet)? */
@property (readonly, nonatomic) BOOL reachableByWiFi;

/** If you set this, the block will be called whenever the reachability related properties change.
    The call will be on the runloop or dispatch queue specified in the start method. */
@property (copy, nullable, nonatomic) CBLReachabilityOnChangeBlock onChange;


#if DEBUG
+ (void) setAlwaysAssumesProxy: (BOOL)alwaysAssumesProxy;   // For debugging
#endif

@end

NS_ASSUME_NONNULL_END
