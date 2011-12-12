//
//  AppDelegate.m
//  iOS Demo
//
//  Created by Jens Alfke on 12/9/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "AppDelegate.h"
#import <TouchDB/TouchDB.h>
#import <TouchDB/TDServer.h>

@implementation AppDelegate

@synthesize window = _window;

- (void)dealloc
{
    [_window release];
    [super dealloc];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // Override point for customization after application launch.
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        UISplitViewController *splitViewController = (UISplitViewController *)self.window.rootViewController;
        UINavigationController *navigationController = [splitViewController.viewControllers lastObject];
        splitViewController.delegate = (id)navigationController.topViewController;
    }
    
    TDServer* tdServer = [[TDServer alloc] initWithDirectory: @"/tmp/ShoppingDemo" error: nil];
    NSAssert(tdServer, @"Couldn't create TDServer");
    [TDURLProtocol setServer: tdServer];
    
    TDDatabase* db = [tdServer databaseNamed: @"demo-shopping"];
    [db open];
    [tdServer release];

    return YES;
}

@end
