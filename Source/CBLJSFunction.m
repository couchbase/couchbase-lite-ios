//
//  CBLJSFunction.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/28/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLJSFunction.h"

#import "CBLJSON.h"

/* NOTE: This source file requires ARC. */

static void WarnJSException(NSString* warning, JSValue* exception);


@implementation CBLJSCompiler {
    JSContext* _context;
}


@synthesize context=_context;


- (instancetype) init {
    self = [super init];
    if (self) {
        _context = [[JSContext alloc] init];
        if (!_context)
            return nil;
    }
    return self;
}


@end



#define kCBLJSFunctionName @"cblJSFunction"

@implementation CBLJSFunction {
    CBLJSCompiler* _compiler;
    JSValue* _fn;
}


- (instancetype) initWithCompiler: (CBLJSCompiler*)compiler sourceCode: (NSString*)source {
    self = [super init];
    if (self) {
        _compiler = compiler;

        // Evaluate source code:
        NSString* script = [NSString stringWithFormat: @"(%@)", source];
        _fn = [compiler.context evaluateScript: script];
        if (compiler.context.exception) {
            WarnJSException(@"JS function compile failed", compiler.context.exception);
            return nil;
        }
    }
    return self;
}


- (JSValue*) call: (id)param1, ... {
    NSMutableArray *params = [NSMutableArray array];
    va_list args;
    if (param1) {
        [params addObject: param1];
        va_start(args, param1);
        id param;
        while ((param = va_arg(args, id)))
            [params addObject: param];
        va_end(args);
    }

    JSValue *result = [_fn callWithArguments: params];
    if (_compiler.context.exception)
        WarnJSException(@"JS function threw exception", _compiler.context.exception);
    return result;
}

@end



void WarnJSException(NSString* warning, JSValue* exception) {
    NSLog(@"*** WARNING: %@: %@", warning, exception);
}
