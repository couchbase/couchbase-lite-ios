//
//  CBLRemoteLogging.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 11/2/15.
//  Copyright © 2015 Couchbase, Inc. All rights reserved.
//

#import "CBLRemoteLogging.h"
#import "CBLManager.h"
#import <libkern/OSAtomic.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#endif


@implementation CBLRemoteLogging


static CBLRemoteLogging* sShared;

+ (instancetype) sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSError* error;
        CBLDatabase* db = [[CBLManager sharedInstance] databaseNamed: @"cbl_logging" error: &error];
        if (db) {
            sShared = [[self alloc] initWithDatabase: db
                                             docType: kCBLRemoteLogDocType
                                               error: &error];
        }
        if (!sShared)
            Warn(@"Couldn't create shared CBLRemoteLogging: %@", error.my_compactDescription);
    });
    return sShared;
}


- (instancetype) initWithDatabase: (CBLDatabase*)db
                          docType: (NSString*)docType
                            error: (NSError**)outError
{
    self = [super initWithDatabase: db docType: docType error: outError];
    if (self) {
        [CBLManager redirectLogging:^(NSString* type, NSString* message) {
            // Could be called on any thread
            [self logType: type message: message];
        }];
        [CBLManager enableLogging: nil];

        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(onQuit:)
#if TARGET_OS_IPHONE
                                                     name: UIApplicationWillTerminateNotification
#else
                                                     name: NSApplicationWillTerminateNotification
#endif
                                                   object: nil];
    }
    return self;
}


- (void) enableLogging: (NSArray*)types {
    for (NSString* type in types)
        [CBLManager enableLogging: type];
}


- (void) stop {
    [CBLManager redirectLogging: nil];
    [super stop];
}


- (void) logType: (NSString*)type message: (NSString*)message {
    [self addEvent: $dict({@"key", type}, {@"msg", message})];
}


- (void) onQuit: (NSNotification*)n {
    [self flush];
}


@end
