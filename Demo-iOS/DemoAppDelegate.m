//
//  DemoAppDelegate.m
//  iOS Demo
//
//  Created by Jens Alfke on 12/9/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
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
#import "CouchbaseLite.h"

#define PERFORMANCE_TEST 0 // Enable this to do benchmarking (see RunViewPerformanceTest below)
#if PERFORMANCE_TEST
static void RunViewPerformanceTest(void);
#endif


@implementation DemoAppDelegate


@synthesize window, navigationController, database;


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
#if PERFORMANCE_TEST
    RunViewPerformanceTest();
    exit(0);
#endif

    // Add the navigation controller's view to the window and display.
	[window addSubview:navigationController.view];
	[window makeKeyAndVisible];
        
    NSLog(@"Opening database...");
    // Open the database, creating it on the first run:
    NSError* error;
    self.database = [[CBLManager sharedInstance] databaseNamed: @"grocery-sync"
                                                                      error: &error];
    if (!self.database)
        [self showAlert: @"Couldn't open database" error: error fatal: YES];
    
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



#if PERFORMANCE_TEST

@interface CBLView (seekrit)
- (void) updateIndex;
@end


static CBLDatabase* createEmptyDB(void) {
    CBLManager* dbmgr = [CBLManager sharedInstance];
    NSError* error;
    CBLDatabase* db = dbmgr[@"test_db"];
    if (db)
        assert([db deleteDatabase: &error]);
    return [dbmgr databaseNamed: @"test_db" error: &error];
}


static NSTimeInterval elapsed(void) {
    static CFAbsoluteTime time;
    CFAbsoluteTime curTime = CFAbsoluteTimeGetCurrent();
    NSTimeInterval t = curTime - time;
    time = curTime;
    return t;
}


static void RunViewPerformanceTest(void) {
    CBLDatabase* db = createEmptyDB();
    CBLView* view = [db viewNamed: @"vu"];
    [view setMapBlock: MAPBLOCK({
        emit(doc[@"sequence"], doc[@"testName"]);
    }) version: @"1"];

    (void)elapsed();
    static const NSUInteger kNDocs = 5000;
    NSLog(@"Creating %u documents...", (unsigned)kNDocs);
    [db inTransaction:^BOOL{
        for (unsigned i=0; i<kNDocs; i++) {
            @autoreleasepool {
                NSDictionary* properties = @{@"testName": @"testDatabase", @"sequence": @(i)};
                CBLDocument* doc = [db untitledDocument];
                NSError* error;
                __unused CBLRevision* rev = [doc putProperties: properties error: &error];
                NSCAssert(rev,@"Couldn't save: %@", error);  // save it!
            }
        }
        return YES;
    }];

    NSLog(@"Created docs:  %6.3f", elapsed());
    [view updateIndex];

    NSLog(@"Updated index: %6.3f", elapsed());
    CBLQuery* query = [view query];
    NSArray* rows = [query rows].allObjects;
    NSCAssert(rows, @"query failed");
    NSCAssert(rows.count == kNDocs, @"wrong number of rows");

    NSLog(@"Queried view:  %6.3f", elapsed());
    int expectedKey = 0;
    for (CBLQueryRow* row in rows) {
        NSCAssert([row.key intValue] == expectedKey, @"wrong key");
        ++expectedKey;
    }
    NSLog(@"Verified rows: %6.3f", elapsed());

    [db.manager close];
}

#endif // PERFORMANCE_TEST
