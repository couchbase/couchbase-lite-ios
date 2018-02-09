//
//  CBLFunctionExpression.m
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
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

#import "CBLFunctionExpression.h"

@implementation CBLFunctionExpression {
    NSString* _function;
    NSArray<CBLQueryExpression*>* _params;
}


- (instancetype) initWithFunction: (NSString*)function
                           params: (nullable NSArray<CBLQueryExpression*>*)params {
    self = [super initWithNone];
    if (self) {
        _function = function;
        _params = params;
    }
    return self;
}


- (id) asJSON {
    NSMutableArray* json = [NSMutableArray arrayWithCapacity: _params.count + 1];
    [json addObject: _function];
    
    for (CBLQueryExpression* param in _params) {
        [json addObject: [param asJSON]];
    }
    
    return json;
}

@end
