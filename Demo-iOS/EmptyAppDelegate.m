//
//  EmptyAppDelegate.m
//  TouchDB
//
//  Created by Jens Alfke on 12/18/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "EmptyAppDelegate.h"
#import "TouchDB.h"
#import "Test.h"

@implementation EmptyAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    TouchDatabaseManager* mgr = [TouchDatabaseManager sharedInstance];
    NSAssert(mgr, @"Couldn't initialize TouchDB");
    return YES;
}

@end


int main(int argc, char *argv[])
{
    @autoreleasepool {
        RunTestCases(argc,(const char**)argv);
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([EmptyAppDelegate class]));
    }
}
