//
//  CBLFragment.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLFragment.h"
#import "CBLDocument+Internal.h"


@implementation CBLFragment


- (void) setValue: (NSObject*)value {
    if (_key)
        [_parent setObject: value forKey: _key];
    else
        [_parent setObject: value atIndex: _index];
}


@end
