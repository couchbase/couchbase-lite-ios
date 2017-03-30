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


- (instancetype) initWithNone: (id)none {
    return [super init];
}


#pragma mark - Property:


+ (CBLQueryExpression*) property: (NSString*)property {
    return [[CBLQueryTypeExpression alloc] initWithKeypath: property];
}


#pragma mark - Unary operators:


+ (CBLQueryExpression*) negated: (id)expression {
    return [[CBLQueryCompoundPredicate alloc] initWithType: NSNotPredicateType
                                             subpredicates: @[expression]];
}


+ (CBLQueryExpression*) not: (id)expression {
    return [self negated: expression];
}


- (CBLQueryExpression*) operatorExpressionWithType: (NSPredicateOperatorType)type
                                 againstExpression: (id)expression
{
    CBLQueryExpression* rhs = $castIf(CBLQueryExpression, expression);
    if (!rhs)
        rhs = [[CBLQueryTypeExpression alloc] initWithConstantValue: expression];
    return [[CBLQueryComparisonPredicate alloc] initWithLeftExpression: self
                                                       rightExpression: rhs
                                                                  type: type];
}


#pragma mark - Arithmetic Operators:


- (CBLQueryExpression*) concat: (id)expression {
    Assert(NO, @"Unsupported operation");
}


- (CBLQueryExpression*) multiply: (id)expression {
    return [[CBLQueryTypeExpression alloc] initWithFunction: @"multiply:by:"
                                                    operand: nil
                                                  arguments: @[self, expression]];
}


- (CBLQueryExpression*) divide: (id)expression {
    return [[CBLQueryTypeExpression alloc] initWithFunction: @"divide:by:"
                                                    operand: nil
                                                  arguments: @[self, expression]];
}


- (CBLQueryExpression*) modulo: (id)expression {
    return [[CBLQueryTypeExpression alloc] initWithFunction: @"modulus:by:"
                                                    operand: nil
                                                  arguments: @[self, expression]];
}


- (CBLQueryExpression*) add: (id)expression {
    return [[CBLQueryTypeExpression alloc] initWithFunction: @"add:to:"
                                                    operand: nil
                                                  arguments: @[self, expression]];
}


- (CBLQueryExpression*) subtract: (id)expression {
    return [[CBLQueryTypeExpression alloc] initWithFunction: @"from:subtract:"
                                                    operand: nil
                                                  arguments: @[self, expression]];
}


#pragma mark - Comparison operators:


- (CBLQueryExpression*) lessThan: (id)expression {
    return [self operatorExpressionWithType: NSLessThanPredicateOperatorType
                          againstExpression: expression];
}


- (CBLQueryExpression*) notLessThan: (id)expression {
    return [self operatorExpressionWithType: NSGreaterThanOrEqualToPredicateOperatorType
                          againstExpression: expression];
}


- (CBLQueryExpression*) lessThanOrEqualTo: (id)expression {
    return [self operatorExpressionWithType: NSLessThanOrEqualToPredicateOperatorType
                          againstExpression: expression];
}


- (CBLQueryExpression*) notLessThanOrEqualTo: (id)expression {
    return [self operatorExpressionWithType: NSGreaterThanPredicateOperatorType
                          againstExpression: expression];

}


- (CBLQueryExpression*) greaterThan: (id)expression {
    return [self operatorExpressionWithType: NSGreaterThanPredicateOperatorType
                          againstExpression: expression];
}


- (CBLQueryExpression*) notGreaterThan: (id)expression {
    return [self operatorExpressionWithType: NSLessThanOrEqualToPredicateOperatorType
                          againstExpression: expression];
}


- (CBLQueryExpression*) greaterThanOrEqualTo: (id)expression {
    return [self operatorExpressionWithType: NSGreaterThanOrEqualToPredicateOperatorType
                          againstExpression: expression];
}


- (CBLQueryExpression*) notGreaterThanOrEqualTo: (id)expression {
    return [self operatorExpressionWithType: NSLessThanPredicateOperatorType
                          againstExpression: expression];
}


- (CBLQueryExpression*) equalTo: (id)expression {
    return [self operatorExpressionWithType: NSEqualToPredicateOperatorType
                          againstExpression: expression];
}


- (CBLQueryExpression*) notEqualTo: (id)expression {
    return [self operatorExpressionWithType: NSNotEqualToPredicateOperatorType
                          againstExpression: expression];
}


#pragma mark - Bitwise operators:


- (CBLQueryExpression*) and: (id)expression {
    return [[CBLQueryCompoundPredicate alloc] initWithType: NSAndPredicateType
                                             subpredicates: @[self, expression]];
}


- (CBLQueryExpression*) or: (id)expression {
    return [[CBLQueryCompoundPredicate alloc] initWithType: NSOrPredicateType
                                             subpredicates: @[self, expression]];
}


#pragma mark - Like operators:


- (CBLQueryExpression*) like: (id)expression {
    return [self operatorExpressionWithType: NSLikePredicateOperatorType
                          againstExpression: expression];
}


- (CBLQueryExpression*) notLike: (id)expression {
    return [[self class] negated: [self like: expression]];
}


#pragma mark - Regex like operators:


- (CBLQueryExpression*) regex: (id)expression {
    CBLQueryExpression *regexp = [[CBLQueryTypeExpression alloc] initWithFunction: @"REGEXP_LIKE"
                                                                          operand: self
                                                                        arguments: @[expression]];
    return [self operatorExpressionWithType: NSEqualToPredicateOperatorType
                          againstExpression: regexp];
}


- (CBLQueryExpression*) notRegex: (id)expression {
    return [[self class] negated: [self regex: expression]];
}


#pragma mark - Fulltext search operators:


- (CBLQueryExpression*) match: (id)expression {
    return [self operatorExpressionWithType: NSMatchesPredicateOperatorType
                          againstExpression: expression];
}


- (CBLQueryExpression*) notMatch: (id)expression {
    return [[self class] negated: [self match: expression]];
}


#pragma mark - Null check operators:


- (CBLQueryExpression*) isNull {
    return [self equalTo: nil];
}


- (CBLQueryExpression*) notNull {
    return [self notEqualTo: nil];
}


#pragma mark - is operations:


- (CBLQueryExpression*) is: (id)expression {
    return [self equalTo: expression];
}


- (CBLQueryExpression*) isNot: (id)expression {
    return [self notEqualTo: expression];
}


#pragma mark - Aggregate operations:


- (CBLQueryExpression*) between: (id)expression1 and: (id)expression2 {
    CBLQueryExpression* exp1 = $castIf(CBLQueryExpression, expression1);
    if (!exp1)
        exp1 = [[CBLQueryTypeExpression alloc] initWithConstantValue: expression1];
    CBLQueryExpression* exp2 = $castIf(CBLQueryExpression, expression1);
    if (!exp2)
        exp2 = [[CBLQueryTypeExpression alloc] initWithConstantValue: expression2];
    
    id rhs = [[CBLQueryTypeExpression alloc] initWithAggregateExpressions: @[exp1, exp2]];
    return [[CBLQueryComparisonPredicate alloc] initWithLeftExpression: self
                                                       rightExpression: rhs
                                                                  type: NSBetweenPredicateOperatorType];
}


- (CBLQueryExpression*) notBetween: (id)exp1 and: (id)exp2 {
    return [[self class] negated: [self between: exp1 and: exp2]];
}


- (CBLQueryExpression*) in: (NSArray*)expressions {
    CBLQueryTypeExpression* rhs = [[CBLQueryTypeExpression alloc] initWithAggregateExpressions: expressions];
    return [[CBLQueryComparisonPredicate alloc] initWithLeftExpression: self
                                                       rightExpression: rhs
                                                                  type: NSInPredicateOperatorType];
}


- (CBLQueryExpression*) notIn: (NSArray*)expressions {
    return [[self class] negated: [self in: expressions]];
}


@end


/////


@implementation CBLQueryComparisonPredicate

@synthesize leftExpression=_leftExpression, rightExpression=_rightExpression;
@synthesize predicateOperatorType=_predicateOperatorType;


- (instancetype) initWithLeftExpression: (CBLQueryExpression*)lhs
                        rightExpression: (CBLQueryExpression*)rhs
                                   type: (NSPredicateOperatorType)type
{
    self = [super initWithNone: nil];
    if (self) {
        _leftExpression = lhs;
        _rightExpression = rhs;
        _predicateOperatorType = type;
    }
    return self;
}


- (NSPredicate*) asNSPredicate {
    NSExpression* lhs;
    if ([self.leftExpression respondsToSelector:@selector(asNSExpression)])
        lhs = [self.leftExpression performSelector: @selector(asNSExpression)];
    Assert(lhs != nil, @"The LHS expression of the comparison expression is invalid.");
    
    NSExpression* rhs;
    if ([self.rightExpression respondsToSelector:@selector(asNSExpression)])
        rhs = [self.rightExpression performSelector: @selector(asNSExpression)];
    Assert(rhs != nil, @"The RHS expression of the comparsion expression is invalid.");
    
    return [NSComparisonPredicate predicateWithLeftExpression: lhs
                                              rightExpression: rhs
                                                     modifier: NSDirectPredicateModifier
                                                         type: self.predicateOperatorType
                                                      options: 0];
}


- (NSString*) description {
    return [[self asNSPredicate] description];
}


@end


/////


@implementation CBLQueryCompoundPredicate

@synthesize compoundPredicateType=_compoundPredicateType, subpredicates=_subpredicates;


- (instancetype) initWithType: (NSCompoundPredicateType)type subpredicates: (NSArray*)subs {
    self = [super initWithNone: nil];
    if (self) {
        _compoundPredicateType = type;
        _subpredicates = [subs copy];
    }
    return self;
}


- (NSPredicate*) asNSPredicate {
    NSMutableArray* subs = [NSMutableArray array];
    for (id s in self.subpredicates) {
        Assert([s conformsToProtocol: @protocol(CBLNSPredicateCoding)]);
        [subs addObject: [s asNSPredicate]];
    }
    
    NSPredicate* p = nil;
    switch (self.compoundPredicateType) {
        case NSAndPredicateType:
            p = [NSCompoundPredicate andPredicateWithSubpredicates: subs];
            break;
        case NSOrPredicateType:
            p = [NSCompoundPredicate orPredicateWithSubpredicates: subs];
            break;
        default:
            Assert(subs.count > 0);
            p = [NSCompoundPredicate notPredicateWithSubpredicate: subs[0]];
            break;
    }
    return p;
}


- (NSString*) description {
    return [[self asNSPredicate] description];
}


@end


/////


@implementation CBLQueryTypeExpression

@synthesize expressionType=_expressionType;
@synthesize constantValue=_constantValue, keyPath=_keyPath;
@synthesize function=_function, operand=_operand, arguments=_arguments;
@synthesize subexpressions=_subexpressions;


- (instancetype) initWithType: (NSExpressionType)type {
    self = [super initWithNone: nil];
    if (self) {
        _expressionType = type;
    }
    return self;
}


- (instancetype) initWithConstantValue: (id)value {
    self = [self initWithType: NSConstantValueExpressionType];
    if (self) {
        _constantValue = value;
    }
    return self;
}


- (instancetype) initWithKeypath: (NSString*)keyPath {
    self = [self initWithType: NSKeyPathExpressionType];
    if (self) {
        _keyPath = [keyPath copy];
    }
    return self;
}


- (instancetype) initWithFunction: (NSString*)function
                          operand:(CBLQueryExpression *)operand
                        arguments:(NSArray *)arguments
{
    self = [self initWithType: NSFunctionExpressionType];
    if (self) {
        _function = [function copy];
        _operand = operand;
        _arguments = [arguments copy];
    }
    return self;
}


- (instancetype) initWithAggregateExpressions: (NSArray*)subexpressions {
    self = [self initWithType: NSAggregateExpressionType];
    if (self) {
        _subexpressions = [subexpressions copy];
    }
    return self;
}


- (NSExpression*) asNSExpression {
    NSExpression* exp = nil;
    switch (self.expressionType) {
        case NSConstantValueExpressionType:
            exp = [NSExpression expressionForConstantValue: self.constantValue];
            break;
        case NSKeyPathExpressionType:
            Assert(self.keyPath);
            exp = [NSExpression expressionForKeyPath: self.keyPath];
            break;
        case NSFunctionExpressionType: {
            NSArray* args = [self toNSExpressionArray: self.arguments];
            if (self.operand && [self.operand respondsToSelector:@selector(asNSExpression)]) {
                NSExpression* operandExp = [self.operand performSelector: @selector(asNSExpression)];
                exp = [NSExpression expressionForFunction: operandExp
                                             selectorName: self.function
                                                arguments: args];
            } else
                exp = [NSExpression expressionForFunction: self.function arguments: args];
            break;
        }
        case NSAggregateExpressionType: {
            NSArray* subs = [self toNSExpressionArray: self.subexpressions];
            exp = [NSExpression expressionForAggregate: subs];
            break;
        }
        default:
            Assert(false, @"Unsupported expression type: %d", self.expressionType);
            break;
    }
    return exp;
}


- (NSArray*) toNSExpressionArray: (NSArray*)expressions {
    NSMutableArray* array = [NSMutableArray array];
    for (id exp in expressions) {
        if ([exp respondsToSelector:@selector(asNSExpression)])
            [array addObject: [exp performSelector: @selector(asNSExpression)]];
        else
            [array addObject: [NSExpression expressionForConstantValue: exp]];
    }
    return array;
}


- (NSString*) description {
    return [[self asNSExpression] description];
}


@end
