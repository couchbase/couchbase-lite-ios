//
//  CBLQuerySelectResult.m
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

#import "CBLQuerySelectResult.h"
#import "CBLQueryExpression+Internal.h"
#import "CBLPropertyExpression.h"

@implementation CBLQuerySelectResult {
    CBLQueryExpression* _expression;
    NSString* _alias;
}

+ (instancetype) property: (NSString*)property {
    return [self property: property as: nil];
}


+ (instancetype) property: (NSString*)property as: (nullable NSString*)alias {
    CBLAssertNotNil(property);
    
    return [[self alloc] initWithExpression: [CBLQueryExpression property: property]
                                         as: alias];
}


+ (instancetype) expression: (CBLQueryExpression*)expression {
    return [self expression: expression as: nil];
}


+ (instancetype) expression: (CBLQueryExpression*)expression as: (nullable NSString*)alias {
    CBLAssertNotNil(expression);
    
    return [[self alloc] initWithExpression: expression as: alias];
}


+ (instancetype) all {
    return [self allFrom: nil];
}


+ (instancetype) allFrom: (nullable NSString*)alias {
    CBLQueryExpression* expr = [CBLQueryExpression allFrom: alias];
    return [[self alloc] initWithExpression: expr as: alias];
}


#pragma mark - Internal


- (instancetype) initWithExpression: (CBLQueryExpression*)expression
                                 as: (nullable NSString*)alias
{
    self = [super init];
    if (self) {
        _expression = expression;
        _alias = alias;
    }
    return self;
}


- (nullable NSString*) columnName {
    if (_alias)
        return _alias;
    
    CBLPropertyExpression* property = $castIf(CBLPropertyExpression, _expression);
    if (property)
        return property.columnName;
    
    return nil;
}


- (id) asJSON {
    return [_expression asJSON];
}


@end
