//
//  TDJSViewCompiler.m
//  TouchDB
//
//  Created by Jens Alfke on 1/4/13.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TDJSViewCompiler.h"
#import <JavaScriptCore/JavaScript.h>
#import <JavaScriptCore/JSStringRefCF.h>

/* NOTE: JavaScriptCore is not a public system framework on iOS, so you'll need to link your iOS app
   with your own copy of it. See <https://github.com/phoboslab/JavaScriptCore-iOS>. */

/* NOTE: This source file requires ARC. */


static JSValueRef IDToValue(JSContextRef ctx, id object);
static id ValueToID(JSContextRef ctx, JSValueRef value);


@implementation TDJSViewCompiler
{
    JSGlobalContextRef _context;
}


// This is a kludge that remembers the emit block passed to the currently active map block.
// It's valid only while a map block is running its JavaScript function.
static
#if !TARGET_OS_IPHONE   /* iOS doesn't support __thread ? */
__thread
#endif
__unsafe_unretained TDMapEmitBlock sCurrentEmitBlock;


// This is the body of the JavaScript "emit(key,value)" function.
static JSValueRef EmitCallback(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject,
                               size_t argumentCount, const JSValueRef arguments[],
                               JSValueRef* exception)
{
    NSLog(@"EMIT!");
    id key = nil, value = nil;
    if (argumentCount > 0) {
        key = ValueToID(ctx, arguments[0]);
        if (argumentCount > 1)
            value = ValueToID(ctx, arguments[1]);
    }
    sCurrentEmitBlock(key, value);
    return JSValueMakeUndefined(ctx);
}


- (id)init {
    self = [super init];
    if (self) {
        _context = JSGlobalContextCreate(NULL);
        if (!_context)
            return nil;
        // Install the "emit" function in the context's namespace:
        JSStringRef name = JSStringCreateWithCFString(CFSTR("emit"));
        JSObjectRef fn = JSObjectMakeFunctionWithCallback(_context, name, &EmitCallback);
        JSObjectSetProperty(_context, JSContextGetGlobalObject(_context),
                            name, fn,
                            kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontDelete,
                            NULL);
        JSStringRelease(name);
    }
    return self;
}


- (void)dealloc {
    if (_context)
        JSGlobalContextRelease(_context);
}


- (TDMapBlock) compileMapFunction: (NSString*)mapSource language: (NSString*)language {
    if (![language isEqualToString: @"javascript"])
        return nil;

    // The source code given is a complete function, like "function(doc){....}".
    // But JSObjectMakeFunction wants the source code of the _body_ of a function.
    // Therefore we wrap the given source in an expression that will call it:
    mapSource = [NSString stringWithFormat: @"(%@)(doc);", mapSource];

    // Compile the function:
    JSStringRef paramName = JSStringCreateWithCFString(CFSTR("doc"));
    JSStringRef body = JSStringCreateWithCFString((__bridge CFStringRef)mapSource);
    JSValueRef exception = NULL;
    JSObjectRef fn = JSObjectMakeFunction(_context, NULL, 1, &paramName, body, NULL, 1, &exception);
    JSStringRelease(body);
    JSStringRelease(paramName);

    if (!fn) {
        [self warn: @"JS map compile failed" withJSException: exception];
        return nil;
    }

    // Return the TDMapBlock; the code inside will be called when TouchDB wants to run the map fn:
    TDMapBlock mapBlock = ^(NSDictionary* doc, TDMapEmitBlock emit) {
        JSValueRef jsDoc = IDToValue(_context, doc);
        sCurrentEmitBlock = emit;
        JSValueRef exception = NULL;
        JSValueRef result = JSObjectCallAsFunction(_context, fn, NULL, 1, &jsDoc, &exception);
        sCurrentEmitBlock = nil;
        if (!result) {
            [self warn: @"JS map function failed" withJSException: exception];
        }
    };
    return [mapBlock copy];
}


- (TDReduceBlock) compileReduceFunction: (NSString*)reduceSource language: (NSString*)language {
    if (![language isEqualToString: @"javascript"])
        return nil;

    // The source code given is a complete function, like "function(k,v,re){....}".
    // But JSObjectMakeFunction wants the source code of the _body_ of a function.
    // Therefore we wrap the given source in an expression that will call it:
    reduceSource = [NSString stringWithFormat: @"return (%@)(keys,values,rereduce);", reduceSource];

    // Compile the function:
    JSStringRef paramNames[3] = {
        JSStringCreateWithCFString(CFSTR("keys")),
        JSStringCreateWithCFString(CFSTR("values")),
        JSStringCreateWithCFString(CFSTR("rereduce"))
    };
    JSStringRef body = JSStringCreateWithCFString((__bridge CFStringRef)reduceSource);
    JSValueRef exception = NULL;
    JSObjectRef fn = JSObjectMakeFunction(_context, NULL, 3, paramNames, body, NULL, 1, &exception);
    JSStringRelease(body);
    JSStringRelease(paramNames[0]);
    JSStringRelease(paramNames[1]);
    JSStringRelease(paramNames[2]);

    if (!fn) {
        [self warn: @"JS reduce compile failed" withJSException: exception];
        return nil;
    }

    // Return the TDReduceBlock; the code inside will be called when TouchDB wants to reduce:
    TDReduceBlock reduceBlock = ^id(NSArray* keys, NSArray* values, BOOL rereduce) {
        JSValueRef jsParams[3] = {
            IDToValue(_context, keys),
            IDToValue(_context, values),
            JSValueMakeBoolean(_context, rereduce)
        };
        JSValueRef exception = NULL;
        JSValueRef result = JSObjectCallAsFunction(_context, fn, NULL, 3, jsParams, &exception);
        if (!result) {
            [self warn: @"JS reduce function failed" withJSException: exception];
        }
        return ValueToID(_context, result);
    };
    return [reduceBlock copy];
}


- (void) warn: (NSString*)warning withJSException: (JSValueRef)exception {
    JSStringRef error = JSValueToStringCopy(_context, exception, NULL);
    CFStringRef cfError = error ? JSStringCopyCFString(NULL, error) : NULL;
    NSLog(@"*** WARNING: %@: %@", warning, cfError);
    if (cfError)
        CFRelease(cfError);
}


@end


// Converts a JSON-compatible NSObject to a JSValue.
static JSValueRef IDToValue(JSContextRef ctx, id object) {
    if (!object)
        return NULL;
    //FIX: Going through JSON is inefficient.
    NSData* json = [NSJSONSerialization dataWithJSONObject: object options: 0 error: NULL];
    if (!json)
        return NULL;
    NSString* jsonStr = [[NSString alloc] initWithData: json encoding: NSUTF8StringEncoding];
    JSStringRef jsStr = JSStringCreateWithCFString((__bridge CFStringRef)jsonStr);
    JSValueRef value = JSValueMakeFromJSONString(ctx, jsStr);
    JSStringRelease(jsStr);
    return value;
}


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
