//
//  CBL_Replicator+Backgrounding.m
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

#import "CBL_Replicator.h"
#import "CBLInternal.h"
#import "CouchbaseLitePrivate.h"
#import "MYBlockUtils.h"

#import <UIKit/UIKit.h>


@implementation CBL_Replicator (Backgrounding)


// Called when the replicator starts
- (void) setupBackgrounding {
    _bgTask = UIBackgroundTaskInvalid;
    [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(appBackgrounding:)
                                                 name: UIApplicationDidEnterBackgroundNotification
                                               object: nil];
    [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(appForegrounding:)
                                                 name: UIApplicationWillEnterForegroundNotification
                                               object: nil];
}


- (void) endBGTask {
    if (_bgTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask: _bgTask];
        _bgTask = UIBackgroundTaskInvalid;
    }
}


// Called when the replicator stops
- (void) endBackgrounding {
    [self endBGTask];
    [[NSNotificationCenter defaultCenter] removeObserver: self
                                                    name: UIApplicationDidEnterBackgroundNotification
                                                  object: nil];
    [[NSNotificationCenter defaultCenter] removeObserver: self
                                                    name: UIApplicationWillEnterForegroundNotification
                                                  object: nil];
}


// Called when the replicator goes idle
- (void) okToEndBackgrounding {
    if (_bgTask != UIBackgroundTaskInvalid) {
        LogTo(Sync, @"%@: Now idle; stopping background task (%lu)",
              self, (unsigned long)_bgTask);
        [self stop];
    }
}


- (void) appBackgrounding: (NSNotification*)n {
    // Danger: This is called on the main thread! It switches to the replicator's thread to do its
    // work, but it has to block until that work is done, because UIApplication requires
    // background tasks to be registered before the notification handler returns; otherwise the app
    // simply suspends itself.
    Log(@"APP BACKGROUNDING");
    [self.db doSync: ^{
        if (self.active) {
            _bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler: ^{
                // Called if process runs out of background time before replication finishes:
                [self.db doSync: ^{
                    LogTo(Sync, @"%@: Background task (%lu) ran out of time!",
                          self, (unsigned long)_bgTask);
                    [self stop];
                }];
            }];
            LogTo(Sync, @"%@: App going into background (bgTask=%lu)", self, (unsigned long)_bgTask);
            if (_bgTask == UIBackgroundTaskInvalid) {
                // Backgrounding isn't possible for whatever reason, so just stop now:
                [self stop];
            }
        } else {
            [self stop];
        }
    }];
}


- (void) appForegrounding: (NSNotification*)n {
    // Danger: This is called on the main thread!
    Log(@"APP FOREGROUNDING");
    [self.db doAsync: ^{
        if (_bgTask != UIBackgroundTaskInvalid) {
            LogTo(Sync, @"%@: App returning to foreground (bgTask=%lu)", self, (unsigned long)_bgTask);
            [self endBGTask];
        }
    }];
}


@end

#endif // TARGET_OS_IPHONE
