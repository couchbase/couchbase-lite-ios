//
//  CBLPrecondition.m
//  CouchbaseLite
//
//  Copyright (c) 2025 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLPrecondition.h"

@implementation CBLPrecondition

+ (void) assert: (BOOL)condition message: (NSString*)message {
    if (!condition) {
        @throw [NSException exceptionWithName: NSInvalidArgumentException
                                       reason: message
                                     userInfo: nil];
    }
}

+ (void) assert: (BOOL)condition format: (NSString*)format, ... {
    if (!condition) {
        va_list args;
        va_start(args, format);
        NSString *reason = [[NSString alloc] initWithFormat: format arguments: args];
        va_end(args);
        @throw [NSException exceptionWithName: NSInvalidArgumentException
                                       reason: reason
                                     userInfo: nil];
    }
}

+ (void) assertNotNil: (nullable id)object name: (NSString*)name {
    [self assert: (object != nil) format: @"%@ must not be nil.", name];
}

+ (void) assertArrayNotEmpty: (NSArray*)array name: (NSString*)name {
    [self assertNotNil: array name: name];
    [self assert: (array.count > 0) format: @"%@ must not be empty", name];
}

@end
