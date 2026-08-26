//
//  CBLTestHelper.m
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLTestHelper.h"

#ifndef CBL_BINARY_TEST
#import <stdatomic.h>
extern atomic_int gC4ExpectExceptions;
// Marks a scope that intentionally provokes exceptions, so that LiteCore's
// exception diagnostics don't flag them. No-op when testing a binary framework.
#define CBLExpectExceptionsBegin() ((void)++gC4ExpectExceptions)
#define CBLExpectExceptionsEnd()   ((void)--gC4ExpectExceptions)
#else
#define CBLExpectExceptionsBegin()
#define CBLExpectExceptionsEnd()
#endif

@implementation CBLTestHelper

+ (void) allowExceptionIn: (void (^)(void))block {
    CBLExpectExceptionsBegin();
    @try {
        block();
    }
    @finally {
        CBLExpectExceptionsEnd();
    }
}

+ (BOOL) catchException: (void(^)(void))tryBlock error: (NSError **)error {
    CBLExpectExceptionsBegin();
    @try {
        tryBlock();
        return YES;
    }
    @catch (NSException *exception) {
        if (error) {
            *error = [[NSError alloc] initWithDomain: exception.name code: 0
                                            userInfo: exception.userInfo];
        }
        return NO;
    }
    @finally {
        CBLExpectExceptionsEnd();
    }
}

@end
