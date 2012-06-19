//
//  DemoAppDelegate.m
//  iOS Demo
//
//  Created by Jens Alfke on 12/9/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "DemoAppDelegate.h"
#import "RootViewController.h"
#import "TDPublic.h"


static TDDatabaseManager* sDBManager;


@implementation DemoAppDelegate


@synthesize window, navigationController, database;


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // Add the navigation controller's view to the window and display.
	[window addSubview:navigationController.view];
	[window makeKeyAndVisible];
        
    NSLog(@"Creating database...");
    NSError* error;
    sDBManager = [[TDDatabaseManager alloc] initWithDirectory: [TDDatabaseManager defaultDirectory] 
                                                        error: &error];
    NSAssert(sDBManager, @"Error initializing TouchDB: %@", error);
    
    // Create the database on the first run of the app.
    self.database = [sDBManager databaseNamed: @"grocery-sync"];
    BOOL opened = [self.database open];
    NSAssert(opened, @"Couldn't open database");
    (void)opened;
    
    // Tell the RootViewController:
    RootViewController* root = (RootViewController*)navigationController.topViewController;
    [root useDatabase: database];

    return YES;
}




// Display an error alert, without blocking.
// If 'fatal' is true, the app will quit when it's pressed.
- (void)showAlert: (NSString*)message error: (NSError*)error fatal: (BOOL)fatal {
    if (error) {
        message = [NSString stringWithFormat: @"%@\n\n%@", message, error.localizedDescription];
    }
    UIAlertView* alert = [[UIAlertView alloc] initWithTitle: (fatal ? @"Fatal Error" : @"Error")
                                                    message: message
                                                   delegate: (fatal ? self : nil)
                                          cancelButtonTitle: (fatal ? @"Quit" : @"Sorry")
                                          otherButtonTitles: nil];
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    exit(0);
}


@end
