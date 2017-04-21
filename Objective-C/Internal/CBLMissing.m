//
//  CBLMissing.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/19/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLMissing.h"

@implementation CBLMissing

+ (instancetype) value {
    static dispatch_once_t once;
    static id sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

@end
