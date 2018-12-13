//
//  CBLReplicator+Backgrounding.m
//  CouchbaseLite
//
//  Copyright (c) 2018 Couchbase, Inc All rights reserved.
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

#if TARGET_OS_IPHONE

#import <UIKit/UIKit.h>
#import "CBLReplicator+Backgrounding.h"
#import "CBLReplicator+Internal.h"
#import "MYBackgroundMonitor.h"


@implementation CBLReplicator (Backgrounding)


- (void) setupBackgrounding {
    CBLLogInfo(Sync, @"%@: Starting backgrounding monitor...", self);
    NSFileProtectionType prot = self.fileProtection;
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
    
    self.bgMonitor = [[MYBackgroundMonitor alloc] init];
    __weak CBLReplicator* weakSelf = self;
    self.bgMonitor.onAppBackgrounding = ^{ id strongSelf = weakSelf; [strongSelf appBackgrounding]; };
    self.bgMonitor.onAppForegrounding = ^{ id strongSelf = weakSelf; [strongSelf appForegrounding]; };
    self.bgMonitor.onBackgroundTaskExpired = ^{ id strongSelf = weakSelf; [strongSelf backgroundTaskExpired];};
    [self.bgMonitor start];
}


- (NSFileProtectionType) fileProtection {
    NSDictionary* attrs = [NSFileManager.defaultManager attributesOfItemAtPath: self.config.database.path error: NULL];
    return attrs[NSFileProtectionKey] ?: NSFileProtectionNone;
}


- (void) endBackgrounding {
    CBLLogInfo(Sync, @"%@: Ending backgrounding monitor...", self);
    [NSNotificationCenter.defaultCenter removeObserver: self
                                                  name: UIApplicationProtectedDataWillBecomeUnavailable
                                                object: nil];
    [NSNotificationCenter.defaultCenter removeObserver: self
                                                  name: UIApplicationProtectedDataDidBecomeAvailable
                                                object: nil];
    [self.bgMonitor stop];
}


// Called when the replicator goes idle
- (void) endCurrentBackgroundTask {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.bgMonitor hasBackgroundTask]) {
            _deepBackground = YES;
            [self updateSuspended];
            CBLLogInfo(Sync, @"%@: ending background task as idle.", self);
            [self.bgMonitor endBackgroundTask];  // will probably suspend the process immediately
        }
    });
}


////// All the methods below are called on the MAIN THREAD ////////


- (void) appBackgrounding {
    if (self.active && [self.bgMonitor beginBackgroundTaskNamed: self.description]) {
        CBLLogInfo(Sync, @"%@: App backgrounding, starting temporary background task", self);
    } else {
        CBLLogInfo(Sync, @"%@: App backgrounding, not active, suspending the replicator", self);
        _deepBackground = YES;
        [self updateSuspended];
    }
}


- (void) appForegrounding {
    BOOL ended = [self.bgMonitor endBackgroundTask];
    if (ended)
        CBLLogInfo(Sync, @"%@: App foregrounding, ending background task.", self);
    if (_deepBackground) {
        _deepBackground = NO;
        [self updateSuspended];
    }
}


- (void) backgroundTaskExpired {
    CBLLogInfo(Sync, @"%@: Background task time expired!", self);
    _deepBackground = YES;
    [self updateSuspended];
}


// Called when the app is about to lose access to files:
- (void) fileAccessChanged: (NSNotification*)n {
    CBLLogInfo(Sync, @"%@: Device locked, database unavailable.", self);
    _filesystemUnavailable = [n.name isEqual: UIApplicationProtectedDataWillBecomeUnavailable];
    [self updateSuspended];
}


- (void) updateSuspended {
    BOOL suspended = (_filesystemUnavailable || _deepBackground);
    self.suspended = suspended;
}


@end

#endif // TARGET_OS_IPHONE
