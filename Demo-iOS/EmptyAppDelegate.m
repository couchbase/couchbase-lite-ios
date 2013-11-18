//
//  EmptyAppDelegate.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/18/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import "EmptyAppDelegate.h"
#import "CouchbaseLite.h"
#import "Test.h"

@implementation EmptyAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    CBLManager* mgr = [CBLManager sharedInstance];
    if (!mgr)
        [NSException raise: NSInternalInconsistencyException format: @"Couldn't initialize CouchbaseLite"];
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
