//
//  CBLReachability.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/13/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#ifdef GNUSTEP
typedef uint32_t SCNetworkReachabilityFlags;
typedef void* SCNetworkReachabilityRef;
typedef void* CFRunLoopRef;
#else
#import <SystemConfiguration/SCNetworkReachability.h>
#endif


typedef void (^CBLReachabilityOnChangeBlock)(void);


/** Asynchronously tracks the reachability of an Internet host, using the SystemConfiguration framework's reachability API.
    You can get called when reachability changes by either KV-observing the properties, or setting an "onChange" block.
    "Reachable" means simply that the local IP stack has resolved the host's DNS name and knows how to route packets toward its IP address. It does NOT guarantee that you can successfully connect. Generally it just means that you have an Internet connection. */
@interface CBLReachability : NSObject

/** Tracks the reachability of the given URL. In general this just uses the URL's hostname,
    but if the URL must be reached via a proxy, it will track reachability of a local network. */
- (instancetype) initWithURL: (NSURL*)url;

/** Tracks reachability of any network address, i.e. whether there is a network connection. */
- (instancetype) init;

@property (readonly, nonatomic) NSString* hostName;

/** Starts tracking reachability.
    You have to call this after creating the object, or none of its properties will change. The current thread must have a runloop.
    @return  YES if tracking started, or NO if there was an error. */
- (BOOL) startOnRunLoop: (CFRunLoopRef)runLoop;

- (BOOL) startOnQueue: (dispatch_queue_t)queue;

/** Stops tracking reachability.
    This is called automatically by -dealloc, but to be safe you can call it when you release your CBLReachability instance, to make sure that in case of a leak it isn't left running forever. */
- (void) stop;

/** YES if the host's reachability has been determined, NO if it hasn't yet or if there was an error. */
@property (readonly, nonatomic) BOOL reachabilityKnown;

/** The exact reachability flags; see Apple docs for the meanings of the bits. */
@property (readonly, nonatomic) SCNetworkReachabilityFlags reachabilityFlags;

/** Is this host reachable via a currently active network interface? */
@property (readonly) BOOL reachable;

/** Is this host reachable by WiFi (or wired Ethernet)? */
@property (readonly) BOOL reachableByWiFi;

/** If you set this, the block will be called whenever the reachability related properties change. */
@property (copy) CBLReachabilityOnChangeBlock onChange;


#if DEBUG
+ (void) setAlwaysAssumesProxy: (BOOL)alwaysAssumesProxy;   // For debugging
#endif

@end
