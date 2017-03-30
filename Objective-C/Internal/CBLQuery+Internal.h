//
//  CBLQuery+Internal.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQuery.h"
#import "CBLInternal.h"
#import "CBLQueryDataSource.h"
#import "CBLQuerySelect.h"
#import "CBLQueryExpression.h"
#import "CBLQueryOrderBy.h"

NS_ASSUME_NONNULL_BEGIN


/////

@interface CBLQuery ()

@property (readonly, nonatomic) CBLQuerySelect* select;

@property (readonly, nonatomic) CBLQueryDataSource* from;

@property (readonly, nullable, nonatomic) CBLQueryExpression* where;

@property (readonly, nullable, nonatomic) CBLQueryOrderBy* orderBy;

@property (readonly, nonatomic) BOOL distinct;

/** Initializer. */
- (instancetype) initWithSelect: (CBLQuerySelect*)select
                       distinct: (BOOL)distinct
                           from: (CBLQueryDataSource*)from
                          where: (nullable CBLQueryExpression*)where
                        orderBy: (nullable CBLQueryOrderBy*)orderBy;

@end

/////

@interface CBLQueryDataSource ()

@property (readonly, nonatomic) id source;

- (instancetype) initWithDataSource: (id)source;

@end

/////

@interface CBLQueryDatabase ()

- (instancetype) initWithDatabase: (CBLDatabase*)database;

@end

/////

@interface CBLQuerySelect ()

@property (readonly, nullable, nonatomic) id select;

- (instancetype) initWithSelect: (nullable id)select;

@end

/////

@interface CBLQueryExpression ()

/** This constructor is currently for hiding the public -init: */
- (instancetype) initWithNone: (nullable id)none;

@end

/////

@protocol CBLNSPredicateCoding <NSObject>
- (NSPredicate*) asNSPredicate;
@end

@interface CBLQueryComparisonPredicate: CBLQueryExpression <CBLNSPredicateCoding>

@property(readonly, nonatomic) CBLQueryExpression* leftExpression;
@property(readonly, nonatomic) CBLQueryExpression* rightExpression;
@property(readonly, nonatomic) NSPredicateOperatorType predicateOperatorType;

- (instancetype) initWithLeftExpression: (CBLQueryExpression*)lhs
                        rightExpression: (CBLQueryExpression*)rhs
                                   type: (NSPredicateOperatorType)type;

@end

/////

@interface CBLQueryCompoundPredicate: CBLQueryExpression <CBLNSPredicateCoding>

@property(readonly, nonatomic) NSCompoundPredicateType compoundPredicateType;
@property(readonly, copy, nonatomic) NSArray* subpredicates;

- (instancetype)initWithType: (NSCompoundPredicateType)type subpredicates: (NSArray*)subs;

@end

/////

@protocol CBLNSExpressionCoding <NSObject>
- (NSExpression*) asNSExpression;
@end

@interface CBLQueryTypeExpression: CBLQueryExpression <CBLNSExpressionCoding>

@property(readonly, nonatomic) NSExpressionType expressionType;

// Constant Value Expression:
@property(nullable, readonly, nonatomic) id constantValue;

// Keypath Expression:
@property(nullable, readonly, copy, nonatomic) NSString* keyPath;

// Functional Expression:
@property(nullable, readonly, copy, nonatomic) NSString* function;
@property(nullable, readonly, copy, nonatomic) NSArray*arguments;
@property(nullable, readonly, nonatomic) CBLQueryExpression* operand;

// Aggregrate Expression:
@property(nullable, readonly, copy, nonatomic) NSArray*subexpressions;

- (instancetype) initWithConstantValue: (id)value;

- (instancetype) initWithKeypath: (NSString*)keyPath;

- (instancetype) initWithFunction: (NSString*)function
                          operand: (nullable CBLQueryExpression*)operand
                        arguments: (nullable NSArray*)arguments;

- (instancetype) initWithAggregateExpressions: (NSArray*)subexpressions;

@end

/////

@interface CBLQueryOrderBy ()

@property (readonly, nullable, copy, nonatomic) NSArray* orders;

- (instancetype) initWithOrders: (nullable NSArray*)orders;

- (NSArray*) asSortDescriptors;

@end

@interface CBLQuerySortOrder ()

@property (readonly, nonatomic) CBLQueryExpression* expression;
@property (readonly, nonatomic) BOOL isAscending;

- (instancetype) initWithExpression: (CBLQueryExpression*)expression;

@end


NS_ASSUME_NONNULL_END
