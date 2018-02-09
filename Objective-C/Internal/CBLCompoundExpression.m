//
//  CBLCompoundExpression.m
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

#import "CBLCompoundExpression.h"
#import "CBLQueryExpression+Internal.h"

@implementation CBLCompoundExpression {
    NSArray<CBLQueryExpression*>* _expressions;
    CBLCompoundExpType _type;
}


- (instancetype) initWithExpressions: (NSArray<CBLQueryExpression*>*)expressions
                                type: (CBLCompoundExpType)type
{
    self = [super initWithNone];
    if (self) {
        _expressions = expressions;
        _type = type;
    }
    return self;
}


- (id) asJSON {
    NSMutableArray* json = [NSMutableArray array];
    
    switch (_type) {
        case CBLAndCompundExpType:
            [json addObject: @"AND"];
            break;
        case CBLOrCompundExpType:
            [json addObject: @"OR"];
            break;
        case CBLNotCompundExpType:
            [json addObject: @"NOT"];
            break;
        default:
            break;
    }
    
    for (CBLQueryExpression* expr in _expressions) {
        [json addObject: [expr asJSON]];
    }
    
    return json;
}


@end
