//
//  CBLLock.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/6/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLLock.h"

@implementation CBLLock {
    id <NSLocking> _lock;
}

@synthesize name=_name, recursive=_recursive;

- (instancetype) initWithName: (NSString*)name {
    return [self initWithName: name recursive: NO];
}


- (instancetype) initWithName:(NSString *)name recursive:(BOOL)recursive {
    self = [super init];
    if (self) {
        _name = name;
        _recursive = recursive;
        if (_recursive)
            _lock = [[NSRecursiveLock alloc] init];
        else
            _lock = [[NSLock alloc] init];
    }
    return self;
}


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%@][resursive=%d]", self.class, _name, _recursive];
}


- (void) lock {
    [_lock lock];
}


- (void) unlock {
    [_lock unlock];
}


- (void) withLock: (void(^)(void))block {
    [self lock];
    @try {
        block();
    } @finally {
        [self unlock];
    }
}

@end
