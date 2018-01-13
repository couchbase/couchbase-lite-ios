//
//  CBLQueryFullTextFunction.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 11/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryFullTextFunction.h"
#import "CBLFunctionExpression.h"

@implementation CBLQueryFullTextFunction

+ (CBLQueryExpression*) rank: (NSString*)indexName {
    CBLQueryExpression* indexNameExpr = [CBLQueryExpression string: indexName];
    return [[CBLFunctionExpression alloc] initWithFunction: @"RANK()"
                                                    params: @[indexNameExpr]];
}

@end
