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
    _bgMonitor = [[MYBackgroundMonitor alloc] init];
    __weak CBLRestReplicator* weakSelf = self;
    _bgMonitor.onAppBackgrounding = ^{ [weakSelf appBackgrounding]; };
    _bgMonitor.onAppForegrounding = ^{ [weakSelf appForegrounding]; };
    _bgMonitor.onBackgroundTaskExpired = ^{ [weakSelf backgroundTaskExpired]; };
}


// Called when the replicator stops
- (void) endBackgrounding {
    [_bgMonitor stop];
    _bgMonitor = nil;
}


// Called when the replicator goes idle (from -updateActive)
- (void) okToEndBackgrounding {
    if ([_bgMonitor endBackgroundTask]) {
        LogTo(Sync, @"%@: Now idle; ending background task", self);
        [self setSuspended: YES];
    }
}


- (void) appBackgrounding {
    // Danger: This is called on the main thread! It switches to the replicator's thread to do its
    // work, but it has to block until that work is done, because UIApplication requires
    // background tasks to be registered before the notification handler returns; otherwise the app
    // simply suspends itself.
    if (_active && [_bgMonitor beginBackgroundTaskNamed: self.description]) {
        LogTo(Sync, @"%@: App backgrounding; starting temporary background task", self);
    } else {
        [self.db doSync: ^{
            [self setSuspended: YES];
        }];
    }
}


- (void) appForegrounding {
    // Danger: This is called on the main thread!
    BOOL ended = [_bgMonitor endBackgroundTask];
    [self.db doSync: ^{                 // sync call avoids a race condition on _active
        if (ended)
            LogTo(Sync, @"%@: App foregrounded, ending background task", self);
        [self setSuspended: NO];
    }];
}


- (void) backgroundTaskExpired {
    // Danger: This is called on the main thread!
    // Called if process runs out of background time before replication finishes.
    // Must do its work synchronously, before the OS quits the app.
    [self.db doSync: ^{
        LogTo(Sync, @"%@: Background task time expired!", self);
        [self setSuspended: YES];
    }];
}


@end

#endif // TARGET_OS_IPHONE
