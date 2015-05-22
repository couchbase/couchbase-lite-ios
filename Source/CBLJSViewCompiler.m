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
#import "CBLReduceFuncs.h"


/* NOTE: If you build this, you'll need to link against JavaScriptCore.framework */

/* NOTE: This source file requires ARC. */


@implementation CBLJSViewCompiler


// This is a kludge that remembers the emit block passed to the currently active map block.
// It's valid only while a map block is running its JavaScript function.
static
#if !TARGET_OS_IPHONE   /* iOS doesn't support __thread ? */
__thread
#endif
__unsafe_unretained CBLMapEmitBlock sCurrentEmitBlock;


- (instancetype) init {
    self = [super init];
    if (self) {
        // Register emit function:
        __weak CBLJSViewCompiler *weakSelf = self;
        self.context[@"emit"] = ^(id key, id value) {
            [weakSelf emitWithKey: key value: value];
        };
        // Register log function:
        self.context[@"log"] = ^(NSString *message) {
            NSLog(@"JS: %@", message);
        };
    }
    return self;
}

- (void) emitWithKey:(id)key value:(id)value {
    sCurrentEmitBlock(key, value);
}


- (CBLMapBlock) compileMapFunction: (NSString*)mapSource language: (NSString*)language {
    if (![language isEqualToString: @"javascript"])
        return nil;

    // Compile the function:
    CBLJSFunction* fn = [[CBLJSFunction alloc] initWithCompiler: self sourceCode: mapSource];
    if (!fn)
        return nil;

    // Return the CBLMapBlock; the code inside will be called when CouchbaseLite wants to run the map fn:
    CBLMapBlock mapBlock = ^(NSDictionary* doc, CBLMapEmitBlock emit) {
        sCurrentEmitBlock = emit;
        [fn call: doc, nil];
        sCurrentEmitBlock = nil;
    };
    return [mapBlock copy];
}


- (CBLReduceBlock) compileReduceFunction: (NSString*)reduceSource language: (NSString*)language {
    if (![language isEqualToString: @"javascript"])
        return nil;

    // Magic built-in reduce functions can be invoked by "_"-prefixed name, like "_count", "_sum"...
    if ([reduceSource hasPrefix: @"_"])
        return CBLGetReduceFunc([reduceSource substringFromIndex: 1]);

    // Compile the function:
    CBLJSFunction* fn = [[CBLJSFunction alloc] initWithCompiler: self sourceCode: reduceSource];
    if (!fn)
        return nil;

    // Return the CBLReduceBlock; the code inside will be called when CouchbaseLite wants to reduce:
    CBLReduceBlock reduceBlock = ^id(NSArray* keys, NSArray* values, BOOL rereduce) {
        JSValue* result = [fn call: keys, values, @(rereduce), nil];
        return [result toObject];
    };
    return [reduceBlock copy];
}


@end




@implementation CBLJSFilterCompiler


- (CBLFilterBlock) compileFilterFunction: (NSString*)filterSource language: (NSString*)language {
    if (![language isEqualToString: @"javascript"])
        return nil;

    // Compile the function:
    CBLJSFunction* fn = [[CBLJSFunction alloc] initWithCompiler: self sourceCode: filterSource];
    if (!fn)
        return nil;

    // Return the CBLMapBlock; the code inside will be called when CouchbaseLite wants to run the map fn:
    CBLFilterBlock block = ^BOOL(CBLSavedRevision* revision, NSDictionary* params) {
        JSValue* result = [fn call: revision.properties, params, nil];
        return [result toBool];
    };
    return [block copy];
}


@end




