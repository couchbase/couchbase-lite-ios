//
//  CBLTestHelper.m
//  CBL Swift Tests
//
//  Created by Pasin Suriyentrakorn on 8/24/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestHelper.h"

@implementation CBLTestHelper

+ (void) allowExceptionIn: (void (^)(void))block {
    ++gC4ExpectExceptions;
    block();
    --gC4ExpectExceptions;
}

@end
