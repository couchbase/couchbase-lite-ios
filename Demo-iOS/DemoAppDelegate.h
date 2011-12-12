//
//  DemoAppDelegate.h
//  iOS Demo
//
//  Created by Jens Alfke on 12/9/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <UIKit/UIKit.h>
@class CouchDatabase, TDDatabase;


@interface DemoAppDelegate : UIResponder <UIApplicationDelegate>

@property (nonatomic, retain) CouchDatabase *database;
@property (nonatomic, retain) TDDatabase *touchDatabase;

@property (strong, nonatomic) IBOutlet UIWindow *window;
@property (nonatomic, retain) IBOutlet UINavigationController *navigationController;

- (void)showAlert: (NSString*)message error: (NSError*)error fatal: (BOOL)fatal;

@end
