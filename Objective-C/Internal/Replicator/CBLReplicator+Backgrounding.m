//
//  CBLReplicator+Backgrounding.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/31/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#if TARGET_OS_IPHONE

#import <UIKit/UIKit.h>
#import "CBLReplicator+Backgrounding.h"
#import "CBLReplicator+Internal.h"
#import "MYBackgroundMonitor.h"


@implementation CBLReplicator (Backgrounding)


- (void) setupBackgrounding {
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
    [self.bgMonitor stop];
}


// Called when the replicator goes idle
- (void) okToEndBackgrounding {
    if ([self.bgMonitor hasBackgroundTask]) {
        _deepBackground = YES;
        [self updateSuspended];
        CBLLog(Sync, @"%@: Now idle; ending background task", self);
        [self.bgMonitor endBackgroundTask];  // will probably suspend the process immediately
    }
}


////// All the methods below are called on the MAIN THREAD ////////


- (void) appBackgrounding {
    dispatch_async(self.dispatchQueue, ^{
        if ([self isActive] && [self.bgMonitor beginBackgroundTaskNamed: self.description]) {
            CBLLog(Sync, @"%@: App backgrounding; starting temporary background task", self);
        } else {
            CBLLog(Sync, @"%@: App backgrounding, but replication is inactive; suspending", self);
            _deepBackground = YES;
            [self updateSuspended];
        }
    });
}


- (void) appForegrounding {
    dispatch_async(self.dispatchQueue, ^{
        BOOL ended = [self.bgMonitor endBackgroundTask];
        if (ended)
            CBLLog(Sync, @"%@: App foregrounded, ending background task", self);
        if (_deepBackground) {
            _deepBackground = NO;
            [self updateSuspended];
        }
    });
}


- (void) backgroundTaskExpired {
    dispatch_async(self.dispatchQueue, ^{
        CBLLog(Sync, @"%@: Background task time expired!", self);
        _deepBackground = YES;
        [self updateSuspended];
    });
}


// Called when the app is about to lose access to files:
- (void) fileAccessChanged: (NSNotification*)n {
    dispatch_async(self.dispatchQueue, ^{
        CBLLog(Sync, @"%@: Device locked, database unavailable", self);
        _filesystemUnavailable = [n.name isEqual: UIApplicationProtectedDataWillBecomeUnavailable];
        [self updateSuspended];
    });

}


- (void) updateSuspended {
    BOOL suspended = (_filesystemUnavailable || _deepBackground);
    self.suspended = suspended;
}


@end


#endif // TARGET_OS_IPHONE
