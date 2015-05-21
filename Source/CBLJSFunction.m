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

#import <CouchbaseLite/CBLJSON.h>
#define COMMON_DIGEST_FOR_OPENSSL
#import <CommonCrypto/CommonDigest.h>

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
    NSString *_fnName;
}


- (instancetype) initWithCompiler: (CBLJSCompiler*)compiler sourceCode: (NSString*)source {
    self = [super init];
    if (self) {
        _compiler = compiler;

        // Evaluate source code:
        _fnName = [self functionNameFromSourceCode: source];
        NSString* script = [NSString stringWithFormat: @"var %@ = %@", _fnName, source];
        [compiler.context evaluateScript: script];
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

    JSValue *jsFunc = _compiler.context[_fnName];
    JSValue *result = [jsFunc callWithArguments: params];
    if (_compiler.context.exception)
        WarnJSException(@"JS function threw exception", _compiler.context.exception);
    return result;
}


- (NSData*) SHA1: (NSData*)input {
    unsigned char digest[SHA_DIGEST_LENGTH];
    SHA_CTX ctx;
    SHA1_Init(&ctx);
    SHA1_Update(&ctx, input.bytes, input.length);
    SHA1_Final(digest, &ctx);
    return [NSData dataWithBytes: &digest length: sizeof(digest)];
}


- (NSString*) functionNameFromSourceCode: (NSString*)source {
    // TODO: Use CBLMisc.CBLDigestFromObject instead when moving CBLJSViewCompiler
    // into CouchbaseLite.framework
    NSData* data = [source dataUsingEncoding: NSUTF8StringEncoding];
    NSString* encoded = [CBLJSON base64StringWithData: [self SHA1: data]];
    encoded = [encoded stringByReplacingOccurrencesOfString:@"=" withString:@""];
    encoded = [encoded stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    encoded = [encoded stringByReplacingOccurrencesOfString:@"+" withString:@"$"];
    NSString* fnName = [NSString stringWithFormat:@"fn%@", encoded];
    return fnName;
}

@end



void WarnJSException(NSString* warning, JSValue* exception) {
    NSLog(@"*** WARNING: %@: %@", warning, exception);
}
