//
//  AppDelegateCBLIS.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/18/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>

@interface AppDelegateCBLIS : NSObject

@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) NSManagedObjectContext *context;
@property (nonatomic, strong) IBOutlet UINavigationController *navigationController;

- (void)saveContext;
- (void)setupCoreDataStackWithCompletion:(void (^)())completion;

@end
