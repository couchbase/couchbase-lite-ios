//
//  CBLJSViewCompiler.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/4/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLJSViewCompiler.h"
#import "CBLJSFunction.h"
#import "CBLRevision.h"
#import <JavaScriptCore/JavaScript.h>
#import <JavaScriptCore/JSStringRefCF.h>


/* NOTE: JavaScriptCore is not a public system framework on iOS, so you'll need to link your iOS app
   with your own copy of it. See <https://github.com/phoboslab/JavaScriptCore-iOS>. */

/* NOTE: This source file requires ARC. */


// Converts a JSON-compatible JSValue to an NSObject.
static id ValueToID(JSContextRef ctx, JSValueRef value) {
    if (!value)
        return nil;
    //FIX: Going through JSON is inefficient.
    JSStringRef jsStr = JSValueCreateJSONString(ctx, value, 0, NULL);
    if (!jsStr)
        return nil;
    NSString* str = (NSString*)CFBridgingRelease(JSStringCopyCFString(NULL, jsStr));
    JSStringRelease(jsStr);
    str = [NSString stringWithFormat: @"[%@]", str];    // make it a valid JSON object
    NSData* data = [str dataUsingEncoding: NSUTF8StringEncoding];
    NSArray* result = [NSJSONSerialization JSONObjectWithData: data options: 0 error: NULL];
    return [result objectAtIndex: 0];
}


@implementation CBLJSViewCompiler


// This is a kludge that remembers the emit block passed to the currently active map block.
// It's valid only while a map block is running its JavaScript function.
static
#if !TARGET_OS_IPHONE   /* iOS doesn't support __thread ? */
__thread
#endif
__unsafe_unretained CBLMapEmitBlock sCurrentEmitBlock;


// This is the body of the JavaScript "emit(key,value)" function.
static JSValueRef EmitCallback(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject,
                               size_t argumentCount, const JSValueRef arguments[],
                               JSValueRef* exception)
{
    id key = nil, value = nil;
    if (argumentCount > 0) {
        key = ValueToID(ctx, arguments[0]);
        if (argumentCount > 1)
            value = ValueToID(ctx, arguments[1]);
    }
    sCurrentEmitBlock(key, value);
    return JSValueMakeUndefined(ctx);
}


- (instancetype) init {
    self = [super init];
    if (self) {
        JSGlobalContextRef context = self.context;
        // Install the "emit" function in the context's namespace:
        JSStringRef name = JSStringCreateWithCFString(CFSTR("emit"));
        JSObjectRef fn = JSObjectMakeFunctionWithCallback(context, name, &EmitCallback);
        JSObjectSetProperty(context, JSContextGetGlobalObject(context),
                            name, fn,
                            kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontDelete,
                            NULL);
        JSStringRelease(name);
    }
    return self;
}


- (CBLMapBlock) compileMapFunction: (NSString*)mapSource language: (NSString*)language {
    if (![language isEqualToString: @"javascript"])
        return nil;

    // Compile the function:
    CBLJSFunction* fn = [[CBLJSFunction alloc] initWithCompiler: self
                                                   sourceCode: mapSource
                                                   paramNames: @[@"doc"]];
    if (!fn)
        return nil;

    // Return the CBLMapBlock; the code inside will be called when CouchbaseLite wants to run the map fn:
    CBLMapBlock mapBlock = ^(NSDictionary* doc, CBLMapEmitBlock emit) {
        sCurrentEmitBlock = emit;
        [fn call: doc];
        sCurrentEmitBlock = nil;
    };
    return [mapBlock copy];
}


- (CBLReduceBlock) compileReduceFunction: (NSString*)reduceSource language: (NSString*)language {
    if (![language isEqualToString: @"javascript"])
        return nil;

    // Compile the function:
    CBLJSFunction* fn = [[CBLJSFunction alloc] initWithCompiler: self
                                                   sourceCode: reduceSource
                                                   paramNames: @[@"keys", @"values", @"rereduce"]];
    if (!fn)
        return nil;

    // Return the CBLReduceBlock; the code inside will be called when CouchbaseLite wants to reduce:
    CBLReduceBlock reduceBlock = ^id(NSArray* keys, NSArray* values, BOOL rereduce) {
        JSValueRef result = [fn call: keys, values, @(rereduce)];
        return ValueToID(self.context, result);
    };
    return [reduceBlock copy];
}


@end




@implementation CBLJSFilterCompiler


- (CBLFilterBlock) compileFilterFunction: (NSString*)filterSource language: (NSString*)language {
    if (![language isEqualToString: @"javascript"])
        return nil;

    // Compile the function:
    CBLJSFunction* fn = [[CBLJSFunction alloc] initWithCompiler: self
                                                   sourceCode: filterSource
                                                   paramNames: @[@"doc", @"req"]];
    if (!fn)
        return nil;

    // Return the CBLMapBlock; the code inside will be called when CouchbaseLite wants to run the map fn:
    JSContextRef ctx = self.context;
    CBLFilterBlock block = ^BOOL(CBLSavedRevision* revision, NSDictionary* params) {
        return JSValueToBoolean(ctx, [fn call: revision.properties, params]);
    };
    return [block copy];
}


@end




