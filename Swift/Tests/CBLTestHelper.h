//
//  CBLTestHelper.h
//  CBL Swift Tests
//
//  Created by Pasin Suriyentrakorn on 8/24/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <stdatomic.h>

extern atomic_int gC4ExpectExceptions;

@interface CBLTestHelper : NSObject

+ (void) allowExceptionIn: (void (^)(void))block;

@end
