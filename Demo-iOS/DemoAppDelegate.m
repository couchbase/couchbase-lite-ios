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

    // Ensure that every public class is an exported symbol in the CouchbaseLite framework:
    [CBLAttachment class];
    [CBLAuthenticator class];
    [CBLDatabase class];
    [CBLDatabaseChange class];
    [CBLDocument class];
    [CBLFullTextQueryRow class];
    [CBLGeoQueryRow class];
    [CBLJSON class];
    [CBLLiveQuery class];
    [CBLManager class];
    [CBLModel class];
    [CBLModelFactory class];
    [CBLQuery class];
    [CBLQueryEnumerator class];
    [CBLQueryRow class];
    [CBLReplication class];
    [CBLRevision class];
    [CBLSavedRevision class];
    [CBLUnsavedRevision class];
    [CBLView class];
    NSAssert(&kCBLDatabaseChangeNotification != nil, @"Invalid value");
    NSAssert(&kCBLDocumentChangeNotification != nil, @"Invalid value");
    NSAssert(&kCBLReplicationChangeNotification != nil, @"Invalid value");
    NSAssert(CBLHTTPErrorDomain != nil, @"Invalid value");

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


#define kNumberOfDocuments 10000


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

    elapsed(); // mark start time
    @autoreleasepool {
        [db inTransaction:^BOOL{
            for (int i = 0; i < kNumberOfDocuments; i++) {
                @autoreleasepool {
                    NSString* name = [NSString stringWithFormat:@"%@%@", @"n", @(i)];
                    bool vacant = (i+2) % 2 ? 1 : 0;
                    NSDictionary* props = @{@"name":name,
                                            @"apt": @(i),
                                            @"phone":@(408100000+i),
                                            @"vacant":@(vacant)};
                    CBLDocument* doc = [db createDocument];
                    NSError* error;
                    __unused BOOL ok = [doc putProperties: props error: &error] != nil;
                    NSCAssert(ok, @"putProperties failed");
                }
            }
            return YES;
        }];
    }
    NSLog(@"Creating docs took %.3g sec", elapsed());

    CBLView* view = [db viewNamed: @"vacant"];

    @autoreleasepool {
        [view setMapBlock: MAPBLOCK({
            id v = [doc objectForKey: @"vacant"];
            id name = [doc objectForKey: @"name"];
            if (v && name) emit(name, v);
        }) reduceBlock: REDUCEBLOCK({return [CBLView totalValues:values];})
                  version: @"3"];

        [view updateIndex];
    }
    NSLog(@"Indexing view took %.3g sec", elapsed());

    @autoreleasepool {
        CBLQuery* query = [[db viewNamed: @"vacant"] createQuery];
        query.descending = NO;
        query.mapOnly = YES;

        NSString *key;
        NSString *value;
        NSError *error;
        CBLQueryEnumerator *rowEnum = [query run: &error];
        unsigned n = 0;
        for (CBLQueryRow* row in rowEnum) {
            @autoreleasepool {
                key = row.key;
                value = row.value;
                n++;
            }
        }
        if (n != kNumberOfDocuments) {
            NSLog(@"Wrong number of rows: %u", n);
            abort();
        }
    }
    NSLog(@"Querying view took %.3g sec", elapsed());

    @autoreleasepool {
        CBLQuery* query = [[db viewNamed: @"vacant"] createQuery];
        query.mapOnly = NO;
        NSError* error;
        CBLQueryEnumerator* rowEnum = [query run: &error];
        CBLQueryRow *row = [rowEnum rowAtIndex:0];
        if ([row.value unsignedIntegerValue] != 5000) {
            NSLog(@"Wrong reduced value %@", row.value);
            abort();
        }
    }
    NSLog(@"Reduced query took %.3g sec", elapsed());
}

#endif // PERFORMANCE_TEST
