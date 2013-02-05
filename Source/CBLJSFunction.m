//
//  CBLJSFunction.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/28/13.
//
//

#import "CBLJSFunction.h"
#import <JavaScriptCore/JavaScript.h>
#import <JavaScriptCore/JSStringRefCF.h>


/* NOTE: JavaScriptCore is not a public system framework on iOS, so you'll need to link your iOS app
   with your own copy of it. See <https://github.com/phoboslab/JavaScriptCore-iOS>. */

/* NOTE: This source file requires ARC. */


static JSValueRef IDToValue(JSContextRef ctx, id object);
static void WarnJSException(JSContextRef context, NSString* warning, JSValueRef exception);


@implementation CBLJSCompiler
{
    JSGlobalContextRef _context;
}


@synthesize context=_context;


- (instancetype) init {
    self = [super init];
    if (self) {
        _context = JSGlobalContextCreate(NULL);
        if (!_context)
            return nil;
    }
    return self;
}


- (void)dealloc {
    if (_context)
        JSGlobalContextRelease(_context);
}


@end




@implementation CBLJSFunction
{
    CBLJSCompiler* _compiler;
    unsigned _nParams;
    JSObjectRef _fn;
}

- (instancetype) initWithCompiler: (CBLJSCompiler*)compiler
                       sourceCode: (NSString*)source
                       paramNames: (NSArray*)paramNames
{
    self = [super init];
    if (self) {
        _compiler = compiler;
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
        _fn = JSObjectMakeFunction(_compiler.context, NULL, _nParams, jsParamNames, jsBody,
                                   NULL, 1, &exception);
        JSStringRelease(jsBody);
        for (NSUInteger i = 0; i < _nParams; ++i)
            JSStringRelease(jsParamNames[i]);
        
        if (!_fn) {
            WarnJSException(_compiler.context, @"JS function compile failed", exception);
            return nil;
        }
        JSValueProtect(_compiler.context, _fn);
    }
    return self;
}

- (JSValueRef) call: (id)param1, ... {
    JSContextRef context = _compiler.context;
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
        JSValueUnprotect(_compiler.context, _fn);
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


void WarnJSException(JSContextRef context, NSString* warning, JSValueRef exception) {
    JSStringRef error = JSValueToStringCopy(context, exception, NULL);
    CFStringRef cfError = error ? JSStringCopyCFString(NULL, error) : NULL;
    NSLog(@"*** WARNING: %@: %@", warning, cfError);
    if (cfError)
        CFRelease(cfError);
}
