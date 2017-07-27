//
//  CBLQueryExpression.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryExpression.h"
#import "CBLQuery+Internal.h"

@implementation CBLQueryExpression


- (instancetype) initWithNone {
    return [super init];
}

- (id) asJSON {
    // Subclass needs to implement this method:
    return [NSNull null];
}


#pragma mark - Property:


+ (CBLQueryExpression*) property: (NSString*)property {
    return [self property: property from: nil];
}


+ (CBLQueryExpression*) property: (NSString*)property from:(NSString *)alias {
    return [[CBLPropertyExpression alloc] initWithKeyPath: property
                                               columnName: nil
                                                     from: alias];
}


#pragma mark - Meta:


+ (CBLQueryMeta*) meta {
    return [self metaFrom: nil];
}


+ (CBLQueryMeta*) metaFrom: (NSString*)alias {
    return [[CBLQueryMeta alloc] initWithFrom: alias];
}


#pragma mark - Parameter:


+ (CBLQueryExpression *) parameterNamed:(NSString *)name {
    return [[CBLParameterExpression alloc] initWithName:name];
}


#pragma mark - Unary operators:


+ (CBLQueryExpression*) negated: (id)expression {
    return [[CBLCompoundExpression alloc] initWithExpressions: @[expression]
                                                         type: CBLNotCompundExpType];
}


+ (CBLQueryExpression*) not: (id)expression {
    return [self negated: expression];
}


#pragma mark - Arithmetic Operators:


- (CBLQueryExpression*) concat: (id)expression {
    Assert(NO, @"Unsupported operation");
}


- (CBLQueryExpression*) multiply: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLMultiplyBinaryExpType];
}


- (CBLQueryExpression*) divide: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLDivideBinaryExpType];
}


- (CBLQueryExpression*) modulo: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLModulusBinaryExpType];
}


- (CBLQueryExpression*) add: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLAddBinaryExpType];
}


- (CBLQueryExpression*) subtract: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLSubtractBinaryExpType];
}


#pragma mark - Comparison operators:


- (CBLQueryExpression*) lessThan: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLLessThanBinaryExpType];
}


- (CBLQueryExpression*) notLessThan: (id)expression {
    return [self greaterThanOrEqualTo: expression];
}


- (CBLQueryExpression*) lessThanOrEqualTo: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLLessThanOrEqualToBinaryExpType];
}


- (CBLQueryExpression*) notLessThanOrEqualTo: (id)expression {
    return [self greaterThan: expression];
}


- (CBLQueryExpression*) greaterThan: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLGreaterThanBinaryExpType];
}


- (CBLQueryExpression*) notGreaterThan: (id)expression {
    return [self lessThanOrEqualTo: expression];
}


- (CBLQueryExpression*) greaterThanOrEqualTo: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLGreaterThanOrEqualToBinaryExpType];
}


- (CBLQueryExpression*) notGreaterThanOrEqualTo: (id)expression {
    return [self lessThan: expression];
}


- (CBLQueryExpression*) equalTo: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLEqualToBinaryExpType];
}


- (CBLQueryExpression*) notEqualTo: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLNotEqualToBinaryExpType];
}


#pragma mark - Bitwise operators:


- (CBLQueryExpression*) and: (id)expression {
    return [[CBLCompoundExpression alloc] initWithExpressions: @[self, expression]
                                                         type: CBLAndCompundExpType];
}


- (CBLQueryExpression*) or: (id)expression {
    return [[CBLCompoundExpression alloc] initWithExpressions: @[self, expression]
                                                         type: CBLOrCompundExpType];
}


#pragma mark - Like operators:


- (CBLQueryExpression*) like: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLLikeBinaryExpType];
}


- (CBLQueryExpression*) notLike: (id)expression {
    return [[self class] negated: [self like: expression]];
}


#pragma mark - Regex like operators:


- (CBLQueryExpression*) regex: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLRegexLikeBinaryExpType];
}


- (CBLQueryExpression*) notRegex: (id)expression {
    return [[self class] negated: [self regex: expression]];
}


#pragma mark - Fulltext search operators:


- (CBLQueryExpression*) match: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLMatchesBinaryExpType];
}


- (CBLQueryExpression*) notMatch: (id)expression {
    return [[self class] negated: [self match: expression]];
}


#pragma mark - Null check operators:


- (CBLQueryExpression*) isNull {
    return [[CBLUnaryExpression alloc] initWithExpression: self type: CBLNullUnaryExpType];
}


- (CBLQueryExpression*) notNull {
    return [[CBLUnaryExpression alloc] initWithExpression: self type: CBLNotNullUnaryExpType];
}


#pragma mark - is operations:


- (CBLQueryExpression*) is: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLIsBinaryExpType];
}


- (CBLQueryExpression*) isNot: (id)expression {
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: expression
                                                          type: CBLIsNotBinaryExpType];
}


#pragma mark - Aggregate operations:


- (CBLQueryExpression*) between: (id)expression1 and: (id)expression2 {
    CBLQueryExpression* aggr =
        [[CBLAggregateExpression alloc] initWithExpressions: @[expression1, expression2]];
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: aggr
                                                          type: CBLBetweenBinaryExpType];
}


- (CBLQueryExpression*) notBetween: (id)exp1 and: (id)exp2 {
    return [[self class] negated: [self between: exp1 and: exp2]];
}


- (CBLQueryExpression*) in: (NSArray*)expressions {
    CBLQueryExpression* aggr =
    [[CBLAggregateExpression alloc] initWithExpressions: expressions];
    return [[CBLBinaryExpression alloc] initWithLeftExpression: self
                                               rightExpression: aggr
                                                          type: CBLInBinaryExpType];
}


- (CBLQueryExpression*) notIn: (NSArray*)expressions {
    return [[self class] negated: [self in: expressions]];
}


@end


/////


@implementation CBLAggregateExpression

@synthesize subexpressions=_subexpressions;

- (instancetype) initWithExpressions: (NSArray *)subs {
    self = [super initWithNone];
    if (self) {
        _subexpressions = [subs copy];
    }
    return self;
}

- (id) asJSON {
    NSMutableArray *json = [NSMutableArray array];
    for (id exp in _subexpressions) {
        if ([exp isKindOfClass:[CBLQueryExpression class]])
            [json addObject: [(CBLQueryExpression *)exp asJSON]];
        else
            [json addObject: exp];
    }
    return json;
}

@end


@implementation CBLBinaryExpression

@synthesize lhs=_lhs, rhs=_rhs, type=_type;

- (instancetype) initWithLeftExpression:(id)lhs
                        rightExpression:(id)rhs
                                   type:(CBLBinaryExpType)type {
    self = [super initWithNone];
    if (self) {
        _lhs = lhs;
        _rhs = rhs;
        _type = type;
    }
    return self;
}

- (id) asJSON {
    NSMutableArray *json = [NSMutableArray array];
    switch (_type) {
        case CBLAddBinaryExpType:
            [json addObject: @"+"];
            break;
        case CBLBetweenBinaryExpType:
            [json addObject: @"BETWEEN"];
            break;
        case CBLDivideBinaryExpType:
            [json addObject: @"/"];
            break;
        case CBLEqualToBinaryExpType:
            [json addObject: @"="];
            break;
        case CBLGreaterThanBinaryExpType:
            [json addObject: @">"];
            break;
        case CBLGreaterThanOrEqualToBinaryExpType:
            [json addObject: @">="];
            break;
        case CBLInBinaryExpType:
            [json addObject: @"IN"];
            break;
        case CBLIsBinaryExpType:
            [json addObject: @"IS"];
            break;
        case CBLIsNotBinaryExpType:
            [json addObject: @"IS NOT"];
            break;
        case CBLLessThanBinaryExpType:
            [json addObject: @"<"];
            break;
        case CBLLessThanOrEqualToBinaryExpType:
            [json addObject: @"<="];
            break;
        case CBLLikeBinaryExpType:
            [json addObject: @"LIKE"];
            break;
        case CBLMatchesBinaryExpType:
            [json addObject: @"MATCH"];
            break;
        case CBLModulusBinaryExpType:
            [json addObject: @"%"];
            break;
        case CBLMultiplyBinaryExpType:
            [json addObject: @"*"];
            break;
        case CBLNotEqualToBinaryExpType:
            [json addObject: @"!="];
            break;
        case CBLRegexLikeBinaryExpType:
            [json addObject: @"regexp_like()"];
            break;
        case CBLSubtractBinaryExpType:
            [json addObject: @"-"];
            break;
        default:
            break;
    }
    
    if ([_lhs isKindOfClass: [CBLQueryExpression class]])
        [json addObject: [(CBLQueryExpression*)_lhs asJSON]];
    else
        [json addObject: _lhs];
    
    if ([_rhs isKindOfClass: [CBLAggregateExpression class]])
        [json addObjectsFromArray: [(CBLAggregateExpression*)_rhs asJSON]];
    else if ([_rhs isKindOfClass: [CBLQueryExpression class]])
        [json addObject: [(CBLQueryExpression*)_rhs asJSON]];
    else
        [json addObject: _rhs];
    
    return json;
}

@end

@implementation CBLCompoundExpression

@synthesize subexpressions=_subexpressions, type=_type;

- (instancetype) initWithExpressions: (NSArray*)subs type: (CBLCompoundExpType)type {
    self = [super initWithNone];
    if (self) {
        _subexpressions = [subs copy];
        _type = type;
    }
    return self;
}

- (id) asJSON {
    NSMutableArray* json = [NSMutableArray array];
    switch (self.type) {
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
    
    for (id exp in _subexpressions) {
        if ([exp isKindOfClass: [CBLQueryExpression class]])
            [json addObject: [(CBLQueryExpression *)exp asJSON]];
        else
            [json addObject: exp];
    }
    return json;
}

@end

@implementation CBLPropertyExpression

@synthesize keyPath=_keyPath, columnName=_columnName, from=_from;

- (instancetype) initWithKeyPath: (NSString*)keyPath
                      columnName: (nullable NSString*)columnName
                            from: (NSString*)from {
    self = [super initWithNone];
    if (self) {
        _keyPath = keyPath;
        _columnName = columnName;
        _from = from;
    }
    return self;
}

- (id) asJSON {
    NSMutableArray* json = [NSMutableArray array];
    if ([_keyPath hasPrefix: @"rank("]) {
        [json addObject: @"rank()"];
        [json addObject: @[@".",
                           [_keyPath substringWithRange:
                                NSMakeRange(5, _keyPath.length - 6)]]];
    } else {
        if (_from)
            [json addObject: [NSString stringWithFormat: @".%@.%@", _from, _keyPath]];
        else
            [json addObject: [NSString stringWithFormat: @".%@", _keyPath]];
    }
    return json;
}

- (NSString*) columnName {
    if (!_columnName)
        _columnName = [_keyPath componentsSeparatedByString: @"."].lastObject;
    return _columnName;
}

@end


@implementation CBLUnaryExpression

@synthesize operand=_operand, type=_type;

- (instancetype) initWithExpression: (id)operand type: (CBLUnaryExpType)type {
    self = [super initWithNone];
    if (self) {
        _operand = operand;
        _type = type;
    }
    return self;
}

- (id) asJSON {
    NSMutableArray* json = [NSMutableArray array];
    switch (_type) {
        case CBLMissingUnaryExpType:
            [json addObject: @"IS MISSING"];
            break;
        case CBLNotMissingUnaryExpType:
            [json addObject: @"IS NOT MISSING"];
            break;
        case CBLNotNullUnaryExpType:
            [json addObject: @"IS NOT NULL"];
            break;
        case CBLNullUnaryExpType:
            [json addObject: @"IS NULL"];
            break;
        default:
            break;
    }
    
    if ([_operand isKindOfClass: [CBLQueryExpression class]])
        [json addObject: [(CBLQueryExpression*)_operand asJSON]];
    else
        [json addObject: _operand];
    
    return json;
}

@end


@implementation CBLParameterExpression

@synthesize name=_name;

- (instancetype)initWithName: (id)name {
    self = [super initWithNone];
    if (self) {
        _name = name;
    }
    return self;
}

- (id) asJSON {
    return @[[NSString stringWithFormat: @"$%@", _name]];
}

@end
