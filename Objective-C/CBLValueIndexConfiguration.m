//
//  CBLValueIndexConfiguration.m
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

#import "CBLValueIndexConfiguration.h"
#import "CBLIndexConfiguration+Internal.h"

@implementation CBLValueIndexConfiguration

@synthesize where=_where;

- (instancetype) initWithExpression: (NSArray<NSString*>*)expressions {
    return [self initWithExpression: expressions where: nil];
}

- (instancetype) initWithExpression: (NSArray<NSString*>*)expressions
                              where: (nullable NSString*)where {
    self = [super initWithIndexType: kC4ValueIndex expressions: expressions];
    if (self) {
        _where = where;
    }
    return self;
}

- (C4IndexOptions) indexOptions {
    C4IndexOptions c4options = { };
    c4options.where = _where.UTF8String;
    return c4options;
}

@end
