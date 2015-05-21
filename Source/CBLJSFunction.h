//
//  CBLJSFunction.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/28/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>


/** Abstract base class for JavaScript-based CBL*Compilers */
@interface CBLJSCompiler : NSObject
@property (readonly) JSContext* context;
@end


/** Wrapper for a compiled JavaScript function. */
@interface CBLJSFunction : NSObject

- (instancetype) initWithCompiler: (CBLJSCompiler*)compiler
                       sourceCode: (NSString*)source;

- (JSValue*) call: (id)param1, ...;

@end
