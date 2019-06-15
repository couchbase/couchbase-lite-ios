//
//  CBLUnaryExpression.m
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

#import "CBLUnaryExpression.h"
#import "CBLQueryExpression+Internal.h"

@implementation CBLUnaryExpression {
    CBLUnaryExpType _type;
    CBLQueryExpression* _operand;
}

- (instancetype) initWithExpression: (CBLQueryExpression*)operand
                               type: (CBLUnaryExpType)type
{
    self = [super initWithNone];
    if (self) {
        _operand = operand;
        _type = type;
    }
    return self;
}

- (id) asJSON {
    id operand = [_operand asJSON];
    
    switch (_type) {
        case CBLUnaryTypeMissing:
            return @[@"IS", operand, @[@"MISSING"]];
        case CBLUnaryTypeNotMissing:
            return @[@"IS NOT", operand, @[@"MISSING"]];
        case CBLUnaryTypeNull:
            return @[@"IS", operand, [NSNull null]];
        case CBLUnaryTypeNotNull:
            return @[@"IS NOT", operand, [NSNull null]];
        default:
            break;
    }
    
    return @[]; // Shouldn't happen
}

@end
