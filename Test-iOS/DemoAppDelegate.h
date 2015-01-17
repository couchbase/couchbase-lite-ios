//
//  DemoAppDelegate.h
//  iOS Demo
//
//  Created by Jens Alfke on 12/9/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import <UIKit/UIKit.h>
@class CBLDatabase;


@interface DemoAppDelegate : UIResponder <UIApplicationDelegate>

@property (nonatomic, strong) CBLDatabase *database;

@property (strong, nonatomic) IBOutlet UIWindow *window;
@property (nonatomic, strong) IBOutlet UINavigationController *navigationController;

- (void)showAlert: (NSString*)message error: (NSError*)error fatal: (BOOL)fatal;

@end
