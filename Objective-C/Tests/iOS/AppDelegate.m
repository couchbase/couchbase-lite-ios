//
//  AppDelegate.m
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

#import "AppDelegate.h"
#ifdef CBL_PERF_TESTS
#import "TunesPerfTest.h"
#endif

@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Mark as host app for test:
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool: YES forKey: @"hostApp"];
    [defaults synchronize];
#if defined(CBL_PERF_TESTS) && !defined(DEBUG)
    // In an optimized build, run the performance tests:
    [TunesPerfTest runWithConfig: nil];
    exit(0);
#endif
    return YES;
}

@end

@implementation SceneDelegate

@end
