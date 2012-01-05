//
//  DemoAppDelegate.h
//  iOS Demo
//
//  Created by Jens Alfke on 12/9/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <UIKit/UIKit.h>
@class CouchDatabase;


@interface DemoAppDelegate : UIResponder <UIApplicationDelegate>

@property (nonatomic, strong) CouchDatabase *database;

@property (strong, nonatomic) IBOutlet UIWindow *window;
@property (nonatomic, strong) IBOutlet UINavigationController *navigationController;

- (void)showAlert: (NSString*)message error: (NSError*)error fatal: (BOOL)fatal;

@end
