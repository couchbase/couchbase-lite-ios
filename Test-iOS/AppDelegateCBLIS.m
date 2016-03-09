//
//  AppDelegateCBLIS.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/18/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import "AppDelegateCBLIS.h"
#import "CBLISRootViewController.h"
#import "CouchbaseLite.h"
#import "CBLIncrementalStore.h"

#define COUCHBASE_SYNC_URL @"http://178.62.197.145:4985/demo/"

@interface AppDelegateCBLIS ()

@property (strong, nonatomic) NSManagedObjectContext *parentContext;
@property (strong, nonatomic) CBLIncrementalStore *incrementalStore;
@property (nonatomic, strong) CBLReplication *pullReplication;
@property (nonatomic, strong) CBLReplication *pushReplication;

@end

@implementation AppDelegateCBLIS

@synthesize window, context, parentContext, incrementalStore, pullReplication, pushReplication;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    [self.window makeKeyAndVisible];
    
    return YES;
}

- (void)setupCoreDataStackWithCompletion:(void (^)())completion {
    NSString *applicationName = [[[NSBundle mainBundle] infoDictionary] valueForKey:(NSString *)kCFBundleNameKey];
    NSURL *pathToStoreURL = [NSURL fileURLWithPath:[[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:applicationName]];
    
    // DIRECTORY
    NSError *error = nil;
    BOOL pathWasCreated = [[NSFileManager defaultManager] createDirectoryAtPath:pathToStoreURL.path withIntermediateDirectories:YES attributes:nil error:&error];
    
    if (error || pathWasCreated) {
        NSLog(@"%@", error);
    }
    
    // MODEL
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"CBLISModel" withExtension:@"momd"];
    NSManagedObjectModel *model = [[[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL] mutableCopy];
    [CBLIncrementalStore updateManagedObjectModel:model];
   
    // PERSISTENT STORE
    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    NSString *couchbaseDatabaseName = [NSString stringWithFormat:@"couchbasedatabase"];
    NSURL *incrementalStoreURL = [pathToStoreURL URLByAppendingPathComponent:couchbaseDatabaseName];
    CBLManager *manager = [[CBLManager sharedInstance] copy];
    [CBLIncrementalStore setCBLManager:manager];
    
    // CONTEXT
    self.parentContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    [self.parentContext setPersistentStoreCoordinator: coordinator];
    
    [self.parentContext performBlock:^{
        manager.dispatchQueue = dispatch_get_current_queue();
        
        NSError *error;
        
        
        self.incrementalStore = (CBLIncrementalStore*)[coordinator addPersistentStoreWithType:[CBLIncrementalStore type]
                                                                                configuration:nil
                                                                                          URL:incrementalStoreURL
                                                                                      options:nil
                                                                                        error:&error];
        
        self.context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        self.context.parentContext = self.parentContext;
        
        [self.incrementalStore addObservingManagedObjectContext:self.context];
        [self.incrementalStore addObservingManagedObjectContext:self.parentContext];
        
        NSURL *remoteDbURL = [NSURL URLWithString:COUCHBASE_SYNC_URL];
        self.pullReplication = [self.incrementalStore.database createPullReplication:remoteDbURL];
        self.pushReplication = [self.incrementalStore.database createPushReplication:remoteDbURL];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self startReplication:self.pullReplication];
            [self startReplication:self.pushReplication];
        });
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion();
        });
    }];
}

- (void)startReplication:(CBLReplication *)repl {
    repl.continuous = YES;
    [repl start];
}

- (void)saveContext {
    [self.context performBlock:^{
        [self.context save:nil];
        [self.parentContext performBlock:^{
            [self.parentContext save:nil];
        }];
    }];
}

@end
