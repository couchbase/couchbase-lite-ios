//
//  CBLQuerySelectResult.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/5/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQuerySelectResult.h"
#import "CBLQueryExpression+Internal.h"
#import "CBLPropertyExpression.h"

@implementation CBLQuerySelectResult {
    CBLQueryExpression* _expression;
    NSString* _alias;
}

+ (instancetype) property: (NSString*)property {
    return [[self alloc] initWithExpression: [CBLQueryExpression property: property]
                                         as: nil];
}


+ (instancetype) property: (NSString*)property as: (nullable NSString*)alias {
    return [[self alloc] initWithExpression: [CBLQueryExpression property: property]
                                         as: alias];
}


+ (instancetype) expression: (CBLQueryExpression*)expression {
    return [self expression: expression as: nil];
}


+ (instancetype) expression: (CBLQueryExpression*)expression as: (nullable NSString*)alias {
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
