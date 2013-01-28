//
//  TDJSFunction.h
//  TouchDB
//
//  Created by Jens Alfke on 1/28/13.
//
//

#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScript.h>


/** Abstract base class for JavaScript-based TD*Compilers */
@interface TDJSCompiler : NSObject
@property (readonly) JSGlobalContextRef context;
@end


/** Wrapper for a compiled JavaScript function. */
@interface TDJSFunction : NSObject

- (id) initWithCompiler: (TDJSCompiler*)compiler
             sourceCode: (NSString*)source
             paramNames: (NSArray*)paramNames;

- (JSValueRef) call: (id)param1, ...;

@end
