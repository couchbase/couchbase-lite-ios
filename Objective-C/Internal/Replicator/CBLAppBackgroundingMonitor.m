//
//  CBLAppBackgroundingMonitor.m
//  CouchbaseLite
//
//  Copyright (c) 2025 Couchbase, Inc All rights reserved.
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
#import "CBLAppBackgroundingMonitor.h"
#import "MYBackgroundMonitor.h"

@implementation CBLAppBackgroundingMonitor {
    MYBackgroundMonitor* _bgMonitor;
    
    __weak id<CBLAppBackgroundingMonitorDelegate> _delegate;
    NSString* _databasePath;
    
    BOOL _started;
    BOOL _deepBackground;
    BOOL _filesystemUnavailable;
}

- (instancetype) initWithDelegate: (nonnull id<CBLAppBackgroundingMonitorDelegate>)delegate
                     databasePath: (NSString*)databasePath {
    self = [super init];
    if (self) {
        _delegate = delegate;
        _databasePath = [databasePath copy];
        
        _bgMonitor = [[MYBackgroundMonitor alloc] init];
        
        __weak typeof(self) weakSelf = self;
        _bgMonitor.onAppBackgrounding = ^{
            id strongSelf = weakSelf;
            [strongSelf appBackgrounding];
        };
        _bgMonitor.onAppForegrounding = ^{
            id strongSelf = weakSelf;
            [strongSelf appForegrounding];
        };
        _bgMonitor.onBackgroundTaskExpired = ^{
            id strongSelf = weakSelf;
            [strongSelf backgroundTaskExpired];
        };
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (void) start {
    CBL_LOCK(self) {
        if (_started) return;
        
        CBLLogInfo(Sync, @"%@ Starting backgrounding monitor...", self);
        
        NSFileProtectionType protectionLevel = [self currentFileProtectionLevel];
        if ([protectionLevel isEqual: NSFileProtectionComplete] ||
            [protectionLevel isEqual: NSFileProtectionCompleteUnlessOpen]) {
            [NSNotificationCenter.defaultCenter addObserver: self
                                                   selector: @selector(fileAccessChanged:)
                                                       name: UIApplicationProtectedDataWillBecomeUnavailable
                                                     object: nil];
            [NSNotificationCenter.defaultCenter addObserver: self
                                                   selector: @selector(fileAccessChanged:)
                                                       name: UIApplicationProtectedDataDidBecomeAvailable
                                                     object: nil];
        }
        
        [_bgMonitor start];
        _started = YES;
    }
}

- (void) stop {
    CBL_LOCK(self) {
        if (!_started) return;
        
        CBLLogInfo(Sync, @"%@ Stop app backgrounding monitor...", self);
        
        [NSNotificationCenter.defaultCenter removeObserver: self
                                                      name: UIApplicationProtectedDataWillBecomeUnavailable
                                                    object: nil];
        [NSNotificationCenter.defaultCenter removeObserver: self
                                                      name: UIApplicationProtectedDataDidBecomeAvailable
                                                    object: nil];
        
        [_bgMonitor stop];
        _started = NO;
    }
}

- (void) endCurrentBackgroundTask {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        CBLAppBackgroundingMonitor* strongSelf = weakSelf;
        [strongSelf endBackgroundTask];
    });
}

#pragma mark - Internal

- (NSFileProtectionType) currentFileProtectionLevel {
    NSDictionary* attrs = [NSFileManager.defaultManager attributesOfItemAtPath: _databasePath error: NULL];
    return attrs[NSFileProtectionKey] ?: NSFileProtectionNone;
}

/** All the methods below are called on the MAIN THREAD */

- (void) appBackgrounding {
    BOOL extend = [_delegate appWillBackgroundAndShouldExtend: self];
    if (extend && [_bgMonitor beginBackgroundTaskNamed: self.description]) {
        CBLLogInfo(Sync, @"%@: App backgrounding, starting background task.", self);
        return;
    }
    
    CBLLogInfo(Sync, @"%@: App backgrounding without starting background task.", self);
    _deepBackground = YES;
    [self updateState];
}

- (void) appForegrounding {
    BOOL ended = [_bgMonitor endBackgroundTask];
    if (ended) {
        CBLLogInfo(Sync, @"%@: App foregrounding, ending background task.", self);
    }
    _deepBackground = NO;
    [self updateState];
}

- (void) backgroundTaskExpired {
    CBLLogInfo(Sync, @"%@: Background task is expired!", self);
    _deepBackground = YES;
    [self updateState];
}

- (void) endBackgroundTask {
    if ([_bgMonitor hasBackgroundTask]) {
        CBLLogInfo(Sync, @"%@: ending background task.", self);
        _deepBackground = YES;
        [_bgMonitor endBackgroundTask];
    }
    [self updateState];
}

// Called when the app is about to lose access to files:
- (void) fileAccessChanged: (NSNotification*)notif {
    CBLLogInfo(Sync, @"%@: Device lock status and file access changed to %@", self, notif.name);
    _filesystemUnavailable = [notif.name isEqual: UIApplicationProtectedDataWillBecomeUnavailable];
    [self updateState];
}

- (void) updateState {
    BOOL background = (_filesystemUnavailable || _deepBackground);
    CBLLogInfo(Sync, @"%@: Update app backgrounding state: %@", self, background ? @"background" : @"foreground");
    
    id <CBLAppBackgroundingMonitorDelegate> delegate = _delegate;
    if (background) {
        [delegate appDidBackground: self];
    } else {
        [delegate appDidForeground: self];
    }
}

@end

#else

#import "CBLAppBackgroundingMonitor.h"

@implementation CBLAppBackgroundingMonitor

- (instancetype) initWithDelegate: (nonnull id<CBLAppBackgroundingMonitorDelegate>)delegate
                     databasePath: (NSString*)databasePath {
    return [super init];
}

- (void) start { }

- (void) stop { }

- (void) endCurrentBackgroundTask { }

@end

#endif
