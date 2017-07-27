//
//  CBLQuerySelectResult.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/5/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQuerySelectResult.h"
#import "CBLQuery+Internal.h"

@implementation CBLQuerySelectResult {
    CBLQueryExpression* _expression;
    NSString* _alias;
}


+ (instancetype) expression: (CBLQueryExpression*)expression {
    return [self expression: expression as: nil];
}


+ (instancetype) expression: (CBLQueryExpression*)expression as: (nullable NSString*)alias {
    return [[self alloc] initWithExpression: expression as: alias];
}


#pragma mark - Internal


- (instancetype) initWithExpression: (CBLQueryExpression*)expression as: (nullable NSString*)alias {
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
