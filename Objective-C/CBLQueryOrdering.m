//
//  CBLQueryOrdering.m
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

#import "CBLQueryOrdering.h"
#import "CBLQuery+Internal.h"
#import "CBLQueryExpression+Internal.h"

@implementation CBLQueryOrdering

@synthesize expression=_expression;

+ (CBLQuerySortOrder *) property: (NSString*)name {
    CBLAssertNotNil(name);
    
    return [[self class] expression: [CBLQueryExpression property: name]];
}


+ (CBLQuerySortOrder *) expression: (CBLQueryExpression*)expression {
    CBLAssertNotNil(expression);
    
    return [[CBLQuerySortOrder alloc] initWithExpression: expression];
}


#pragma mark - Internal

- (instancetype) initWithExpression: (CBLQueryExpression*)expression {
    self = [super init];
    if (self) {
        _expression = expression;
    }
    return self;
}


- (id) asJSON {
    return [self.expression asJSON];
}


@end


@implementation CBLQuerySortOrder

@synthesize isAscending=_isAscending;


- (instancetype) initWithExpression: (CBLQueryExpression*)expression {
    self = [super initWithExpression: expression];
    if (self) {
        _isAscending = YES;
    }
    return self;
}


- (CBLQueryOrdering*) ascending {
    _isAscending = YES;
    return self;
}


- (CBLQueryOrdering*) descending {
    _isAscending = NO;
    return self;
}


- (id) asJSON {
    id json = _isAscending ? [super asJSON] : @[@"DESC", [super asJSON]];
    return json;
}


@end
