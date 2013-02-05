//
//  CBLJSFunction.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/28/13.
//
//

#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScript.h>


/** Abstract base class for JavaScript-based CBL*Compilers */
@interface CBLJSCompiler : NSObject
@property (readonly) JSGlobalContextRef context;
@end


/** Wrapper for a compiled JavaScript function. */
@interface CBLJSFunction : NSObject

- (instancetype) initWithCompiler: (CBLJSCompiler*)compiler
                       sourceCode: (NSString*)source
                       paramNames: (NSArray*)paramNames;

- (JSValueRef) call: (id)param1, ...;

@end
