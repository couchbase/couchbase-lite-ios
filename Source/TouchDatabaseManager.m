//
//  TouchDatabaseManager.m
//  TouchDB
//
//  Created by Jens Alfke on 6/19/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TouchDatabaseManager.h"
#import "TDDatabase.h"
#import "TDDatabaseManager.h"
#import "TouchDatabase.h"


@implementation TouchDatabaseManager


+ (TouchDatabaseManager*) sharedInstance {
    static TouchDatabaseManager* sInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sInstance = [[self alloc] init];
    });
    return sInstance;
}


- (id)init {
    return [self initWithDirectory: [TDDatabaseManager defaultDirectory] error: nil];
}


- (id) initWithDirectory: (NSString*)directory error: (NSError**)outError {
    self = [super init];
    if (self) {
        _mgr = [[TDDatabaseManager alloc] initWithDirectory: directory error: outError];
        if (!_mgr) {
            [self release];
            return nil;
        }
    }
    return self;
}


- (void) close {
    [_mgr close];
    _mgr = nil;
}



- (NSArray*) allDatabaseNames {
    return _mgr.allDatabaseNames;
}


- (TouchDatabase*) databaseNamed: (NSString*)name {
    TDDatabase* db = [_mgr existingDatabaseNamed: name];
    if (![db open])
        return nil;
    return db.touchDatabase;
}


- (TouchDatabase*) createDatabaseNamed: (NSString*)name error: (NSError**)outError {
    TDDatabase* db = [_mgr databaseNamed: name];
    if (![db open: outError])
        return nil;
    return db.touchDatabase;
}


@end
