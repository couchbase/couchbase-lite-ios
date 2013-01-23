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
void WarnJSException(JSContextRef context, NSString* warning, JSValueRef exception);


@interface TDJSViewCompiler ()
@property (readonly) JSGlobalContextRef context;
@end


@interface TDJSFunction : NSObject
- (id) initWithOwner: (TDJSViewCompiler*)owner
          sourceCode: (NSString*)source
          paramNames: (NSArray*)paramNames;
- (JSValueRef) call: (id)param1, ...;
@end


@implementation TDJSViewCompiler
{
    JSGlobalContextRef _context;
}


@synthesize context=_context;


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

    // Compile the function:
    TDJSFunction* fn = [[TDJSFunction alloc] initWithOwner: self
                                                sourceCode: mapSource
                                                paramNames: @[@"doc"]];
    if (!fn)
        return nil;

    // Return the TDMapBlock; the code inside will be called when TouchDB wants to run the map fn:
    TDMapBlock mapBlock = ^(NSDictionary* doc, TDMapEmitBlock emit) {
        sCurrentEmitBlock = emit;
        [fn call: doc];
        sCurrentEmitBlock = nil;
    };
    return [mapBlock copy];
}


- (TDReduceBlock) compileReduceFunction: (NSString*)reduceSource language: (NSString*)language {
    if (![language isEqualToString: @"javascript"])
        return nil;

    // Compile the function:
    TDJSFunction* fn = [[TDJSFunction alloc] initWithOwner: self
                                                sourceCode: reduceSource
                                                paramNames: @[@"keys", @"values", @"rereduce"]];
    if (!fn)
        return nil;

    // Return the TDReduceBlock; the code inside will be called when TouchDB wants to reduce:
    TDReduceBlock reduceBlock = ^id(NSArray* keys, NSArray* values, BOOL rereduce) {
        JSValueRef result = [fn call: keys, values, @(rereduce)];
        return ValueToID(_context, result);
    };
    return [reduceBlock copy];
}


@end




@implementation TDJSFunction
{
    TDJSViewCompiler* _owner;
    unsigned _nParams;
    JSObjectRef _fn;
}

- (id) initWithOwner: (TDJSViewCompiler*)owner
          sourceCode: (NSString*)source
          paramNames: (NSArray*)paramNames
{
    self = [super init];
    if (self) {
        _owner = owner;
        _nParams = (unsigned)paramNames.count;

        // The source code given is a complete function, like "function(doc){....}".
        // But JSObjectMakeFunction wants the source code of the _body_ of a function.
        // Therefore we wrap the given source in an expression that will call it:
        NSString* body = [NSString stringWithFormat: @"return (%@)(%@);",
                                               source, [paramNames componentsJoinedByString: @","]];

        // Compile the function:
        JSStringRef jsParamNames[_nParams];
        for (NSUInteger i = 0; i < _nParams; ++i)
            jsParamNames[i] = JSStringCreateWithCFString((__bridge CFStringRef)paramNames[i]);
        JSStringRef jsBody = JSStringCreateWithCFString((__bridge CFStringRef)body);
        JSValueRef exception;
        _fn = JSObjectMakeFunction(_owner.context, NULL, _nParams, jsParamNames, jsBody,
                                   NULL, 1, &exception);
        JSStringRelease(jsBody);
        for (NSUInteger i = 0; i < _nParams; ++i)
            JSStringRelease(jsParamNames[i]);
        
        if (!_fn) {
            WarnJSException(_owner.context, @"JS function compile failed", exception);
            return nil;
        }
        JSValueProtect(_owner.context, _fn);
    }
    return self;
}

- (JSValueRef) call: (id)param1, ... {
    JSContextRef context = _owner.context;
    JSValueRef jsParams[_nParams];
    jsParams[0] = IDToValue(context, param1);
    if (_nParams > 1) {
        va_list args;
        va_start(args, param1);
        for (NSUInteger i = 1; i < _nParams; ++i)
            jsParams[i] = IDToValue(context, va_arg(args, id));
        va_end(args);
    }
    JSValueRef exception = NULL;
    JSValueRef result = JSObjectCallAsFunction(context, _fn, NULL, _nParams, jsParams, &exception);
    if (!result)
        WarnJSException(context, @"JS function threw exception", exception);
    return result;
}

- (void)dealloc
{
    if (_fn)
        JSValueUnprotect(_owner.context, _fn);
}

@end




// Converts a JSON-compatible NSObject to a JSValue.
static JSValueRef IDToValue(JSContextRef ctx, id object) {
    if (object == nil) {
        return NULL;
    } else if (object == (id)kCFBooleanFalse || object == (id)kCFBooleanTrue) {
        return JSValueMakeBoolean(ctx, object == (id)kCFBooleanTrue);
    } else if (object == [NSNull null]) {
        return JSValueMakeNull(ctx);
    } else if ([object isKindOfClass: [NSNumber class]]) {
        return JSValueMakeNumber(ctx, [object doubleValue]);
    } else if ([object isKindOfClass: [NSString class]]) {
        JSStringRef jsStr = JSStringCreateWithCFString((__bridge CFStringRef)object);
        JSValueRef value = JSValueMakeString(ctx, jsStr);
        JSStringRelease(jsStr);
        return value;
    } else {
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


void WarnJSException(JSContextRef context, NSString* warning, JSValueRef exception) {
    JSStringRef error = JSValueToStringCopy(context, exception, NULL);
    CFStringRef cfError = error ? JSStringCopyCFString(NULL, error) : NULL;
    NSLog(@"*** WARNING: %@: %@", warning, cfError);
    if (cfError)
        CFRelease(cfError);
}
