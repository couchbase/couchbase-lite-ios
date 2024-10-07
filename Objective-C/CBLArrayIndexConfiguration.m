//
//  CBLArrayIndexConfiguration.m
//  CouchbaseLite
//
//  Copyright (c) 2024 Couchbase, Inc All rights reserved.
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

#import "CBLArrayIndexConfiguration.h"
#import "CBLIndexConfiguration+Internal.h"

@implementation CBLArrayIndexConfiguration

@synthesize path=_path, expressions=_expressions;

- (instancetype) initWithPath: (NSString*) path
                  expressions: (nullable NSArray<NSString*>*)expressions {
    
    if(!expressions) {
        self = [super initWithIndexType: kC4ArrayIndex
                            expressions: @[@""]];
    } else if ([expressions count] == 0 || [expressions[0] length] == 0) {
        [NSException raise: NSInvalidArgumentException format:
         @"Empty expressions is not allowed, use nil instead"];
    }
    
    self = [super initWithIndexType: kC4ArrayIndex
                        expressions: expressions];
    
    if (self) {
        _path = path;
        _expressions = expressions;
    }
    
    return self;
}

- (instancetype) initWithPath: (NSString*)path {
    self = [self initWithPath: path expressions: nil];
    return self;
}

- (C4IndexOptions) indexOptions {
    C4IndexOptions c4options = { };
    c4options.unnestPath = [_path UTF8String];
    return c4options;
}

@end
