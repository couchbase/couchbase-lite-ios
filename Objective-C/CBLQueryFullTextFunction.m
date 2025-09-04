//
//  CBLQueryFullTextFunction.m
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

#import "CBLQueryFullTextFunction.h"
#import "CBLFunctionExpression.h"
#import "CBLQueryFullTextIndexExpression.h"

@implementation CBLQueryFullTextFunction

+ (CBLQueryExpression*) rankWithIndex: (id<CBLQueryIndexExpressionProtocol>)index {
    CBLAssertNotNil(index);
    
    CBLQueryExpression* indexExpr = [CBLQueryExpression string: ((CBLQueryFullTextIndexExpression*)index).stringValue];
    return [[CBLFunctionExpression alloc] initWithFunction: @"RANK()"
                                                    params: @[indexExpr]];
}

+ (CBLQueryExpression*) matchWithIndex:(id<CBLQueryIndexExpressionProtocol>)index query:(NSString *)query {
    CBLAssertNotNil(index);
    CBLAssertNotNil(query);
    
    CBLQueryExpression* indexExpr = [CBLQueryExpression string: ((CBLQueryFullTextIndexExpression*)index).stringValue];
    CBLQueryExpression* queryExpr = [CBLQueryExpression string: query];
    return [[CBLFunctionExpression alloc] initWithFunction: @"MATCH()"
                                                    params: @[indexExpr, queryExpr]];
}

@end
