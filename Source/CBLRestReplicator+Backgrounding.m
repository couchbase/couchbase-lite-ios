//
//  CBLRestReplicator+Backgrounding.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/15/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#if TARGET_OS_IPHONE

#import "CBLRestReplicator+Internal.h"
#import "CBLInternal.h"
#import "CouchbaseLitePrivate.h"
#import "MYBlockUtils.h"
#import "MYBackgroundMonitor.h"


@implementation CBLRestReplicator (Backgrounding)


// Called when the replicator starts
- (void) setupBackgrounding {
    // Check iOS file protection:
    NSFileProtectionType prot = _db.fileProtection;
    if ([prot isEqual: NSFileProtectionComplete] ||
            [prot isEqual: NSFileProtectionCompleteUnlessOpen]) {
        [NSNotificationCenter.defaultCenter addObserver: self
                                        selector: @selector(fileAccessChanged:)
                                            name: UIApplicationProtectedDataWillBecomeUnavailable
                                            object: nil];
        [NSNotificationCenter.defaultCenter addObserver: self
                                        selector: @selector(fileAccessChanged:)
                                            name: UIApplicationProtectedDataDidBecomeAvailable
                                            object: nil];
    }

    // Start an app-backgrounding monitor:
    _bgMonitor = [[MYBackgroundMonitor alloc] init];
    __weak CBLRestReplicator* weakSelf = self;
    _bgMonitor.onAppBackgrounding = ^{ id strongSelf = weakSelf; [strongSelf appBackgrounding]; };
    _bgMonitor.onAppForegrounding = ^{ id strongSelf = weakSelf; [strongSelf appForegrounding]; };
    _bgMonitor.onBackgroundTaskExpired = ^{ id strongSelf = weakSelf; [strongSelf backgroundTaskExpired];};
    [_bgMonitor start];
}


// Called when the replicator stops
- (void) endBackgrounding {
    [NSNotificationCenter.defaultCenter removeObserver: self
                                            name: UIApplicationProtectedDataWillBecomeUnavailable
                                          object: nil];
    [NSNotificationCenter.defaultCenter removeObserver: self
                                            name: UIApplicationProtectedDataDidBecomeAvailable
                                          object: nil];
    [_bgMonitor stop];
    _bgMonitor = nil;
}


// Called when the replicator goes idle (from -updateActive)
- (void) okToEndBackgrounding {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([_bgMonitor hasBackgroundTask]) {
            _deepBackground = YES;
            [self updateSuspended];
            LogTo(Sync, @"%@: Now idle; ending background task", self);
            [_bgMonitor endBackgroundTask];  // will probably suspend the process immediately
        }
    });
}


////// All the methods below are called on the MAIN THREAD, not the replicator thread ////////


- (void) appBackgrounding {
    if (_active && [_bgMonitor beginBackgroundTaskNamed: self.description]) {
        LogTo(Sync, @"%@: App backgrounding; starting temporary background task", self);
    } else {
        LogTo(Sync, @"%@: App backgrounding, but can't run background task; suspending", self);
        _deepBackground = YES;
        [self updateSuspended];
    }
}


- (void) appForegrounding {
    BOOL ended = [_bgMonitor endBackgroundTask];
    if (ended)
        LogTo(Sync, @"%@: App foregrounded, ending background task", self);
    if (_deepBackground) {
        _deepBackground = NO;
        [self updateSuspended];
    }
}


// Called if process runs out of background time before replication finishes.
// Must do its work synchronously, before the OS quits the app.
- (void) backgroundTaskExpired {
    [self.db doSync: ^{
        LogTo(Sync, @"%@: Background task time expired!", self);
        _deepBackground = YES;
        [self updateSuspended];
    }];
}


// Called when the app is about to lose access to files:
- (void) fileAccessChanged: (NSNotification*)n {
    LogTo(Sync, @"%@: Device locked, database unavailable", self);
    _filesystemUnavailable = [n.name isEqual: UIApplicationProtectedDataWillBecomeUnavailable];
    [self updateSuspended];
}


- (void) updateSuspended {
    BOOL suspended = (_filesystemUnavailable || _deepBackground);
    [self.db doSync: ^{
        self.suspended = suspended;
    }];
}


@end

#endif // TARGET_OS_IPHONE
