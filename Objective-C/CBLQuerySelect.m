//
//  CBLQuerySelect.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQuerySelect.h"
#import "CBLQuery+Internal.h"

@implementation CBLQuerySelect


@synthesize select=_select;


- (instancetype) initWithSelect: (id)select {
    self = [super init];
    if (self) {
        _select = select;
    }
    return self;
}


+ (instancetype) all {
    return [[[self class] alloc] initWithSelect: nil];
}


@end
