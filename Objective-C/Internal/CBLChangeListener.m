//
//  CBLChangeListener.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/22/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLChangeListener.h"

@implementation CBLChangeListener

@synthesize block=_block;

- (instancetype) initWithBlock: (id)block {
    self = [super init];
    if (self) {
        _block = block;
    }
    return self;
}

@end
