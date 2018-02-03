//
//  CBLQuantifiedExpression.m
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

#import "CBLQuantifiedExpression.h"
#import "CBLQueryExpression+Internal.h"
#import "CBLQueryVariableExpression+Internal.h"

@implementation CBLQuantifiedExpression {
    CBLQuantifiedType _type;
    CBLQueryVariableExpression* _variable;
    CBLQueryExpression* _inExpression;
    CBLQueryExpression* _satisfies;
}


- (instancetype) initWithType: (CBLQuantifiedType)type
                     variable: (CBLQueryVariableExpression*)variable
                           in: (CBLQueryExpression*)inExpression
                    satisfies: (CBLQueryExpression*)satisfies
{
    self = [super initWithNone];
    if (self) {
        _type = type;
        _variable = variable;
        _inExpression = inExpression;
        _satisfies = satisfies;
    }
    return self;
}


- (id) asJSON {
    NSMutableArray* json = [NSMutableArray arrayWithCapacity: 4];
    
    switch (_type) {
        case CBLQuantifiedTypeAny:
            [json addObject: @"ANY"];
            break;
        case CBLQuantifiedTypeAnyAndEvery:
            [json addObject: @"ANY AND EVERY"];
            break;
        case CBLQuantifiedTypeEvery:
            [json addObject: @"EVERY"];
            break;
        default:
            break;
    }
    
    [json addObject: _variable.name];
    [json addObject: [_inExpression asJSON]];
    [json addObject: [_satisfies asJSON]];
    
    return json;
}

@end
