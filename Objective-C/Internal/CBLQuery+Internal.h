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
#import "CBLQueryFunction.h"
#import "CBLQueryGroupBy.h"
#import "CBLQueryJoin.h"
#import "CBLQuerySelectResult.h"
#import "CBLQueryExpression.h"
#import "CBLQueryOrdering.h"
#import "CBLPredicateQuery+Internal.h"

NS_ASSUME_NONNULL_BEGIN


/////

@protocol CBLQueryJSONEncoding <NSObject>

/** Encode as a JSON object. */
- (id) asJSON;

@end

/////

@interface CBLQuery () <CBLQueryInternal, NSCopying>

@property (readonly, nonatomic) NSArray<CBLQuerySelectResult*>* select;

@property (readonly, nonatomic) CBLQueryDataSource* from;

@property (readonly, nullable, nonatomic) NSArray<CBLQueryJoin*>* join;

@property (readonly, nullable, nonatomic) CBLQueryExpression* where;

@property (readonly, nullable, nonatomic) NSArray<CBLQueryGroupBy*>* groupBy;

@property (readonly, nullable, nonatomic) CBLQueryExpression* having;

@property (readonly, nullable, nonatomic) NSArray<CBLQueryOrdering*>* orderings;

@property (readonly, nonatomic) BOOL distinct;

/** Initializer. */
- (instancetype) initWithSelect: (NSArray<CBLQuerySelectResult*>*)select
                       distinct: (BOOL)distinct
                           from: (CBLQueryDataSource*)from
                           join: (nullable NSArray<CBLQueryJoin*>*)join
                          where: (nullable CBLQueryExpression*)where
                        groupBy: (nullable NSArray<CBLQueryGroupBy*>*)groupBy
                         having: (nullable CBLQueryExpression*)having
                        orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings;

@end

/////

@interface CBLQueryDataSource () <CBLQueryJSONEncoding>

@property (nonatomic, readonly) id source;

@property (nonatomic, readonly, nullable) NSString* alias;

- (instancetype) initWithDataSource: (id)source as: (nullable NSString*)alias;

@end

/////

@interface CBLQuerySelectResult () <CBLQueryJSONEncoding>

- (instancetype) initWithExpression: (CBLQueryExpression*)expression;

@end

/////

@interface CBLQueryJoin () <CBLQueryJSONEncoding>

- (instancetype) initWithType: (NSString*)type
                   dataSource: (CBLQueryDataSource*)dataSource
                           on: (CBLQueryExpression*)expression;

@end

/////

@interface CBLQueryGroupBy () <CBLQueryJSONEncoding>

- (instancetype) initWithExpression: (CBLQueryExpression*)expression;

@end

/////

@interface CBLQueryOrdering () <CBLQueryJSONEncoding>

@property (readonly, nonatomic) CBLQueryExpression* expression;

- (instancetype) initWithExpression: (CBLQueryExpression*)expression;

@end

@interface CBLQuerySortOrder ()

@property (readonly, nonatomic) BOOL isAscending;

@end

/////

@interface CBLQueryExpression () <CBLQueryJSONEncoding>

/** This constructor is for hiding the public -init: */
- (instancetype) initWithNone: (nullable id)none;

@end

/////

@interface CBLAggregateExpression: CBLQueryExpression

@property(readonly, copy, nonatomic) NSArray* subexpressions;

- (instancetype)initWithExpressions: (NSArray*)subs;

@end

/////

typedef NS_ENUM(NSInteger, CBLBinaryExpType) {
    CBLAddBinaryExpType,
    CBLBetweenBinaryExpType,
    CBLDivideBinaryExpType,
    CBLEqualToBinaryExpType,
    CBLGreaterThanBinaryExpType,
    CBLGreaterThanOrEqualToBinaryExpType,
    CBLInBinaryExpType,
    CBLIsBinaryExpType,
    CBLIsNotBinaryExpType,
    CBLLessThanBinaryExpType,
    CBLLessThanOrEqualToBinaryExpType,
    CBLLikeBinaryExpType,
    CBLMatchesBinaryExpType,
    CBLModulusBinaryExpType,
    CBLMultiplyBinaryExpType,
    CBLNotEqualToBinaryExpType,
    CBLSubtractBinaryExpType,
    CBLRegexLikeBinaryExpType
};

@interface CBLBinaryExpression: CBLQueryExpression

@property(readonly, nonatomic) id lhs;
@property(readonly, nonatomic) id rhs;
@property(readonly, nonatomic) CBLBinaryExpType type;

- (instancetype) initWithLeftExpression: (id)lhs
                        rightExpression: (id)rhs
                                   type: (CBLBinaryExpType)type;

@end

/////

typedef NS_ENUM(NSInteger, CBLCompoundExpType) {
    CBLAndCompundExpType,
    CBLOrCompundExpType,
    CBLNotCompundExpType
};

@interface CBLCompoundExpression: CBLQueryExpression

@property(readonly, copy, nonatomic) NSArray* subexpressions;
@property(readonly, nonatomic) CBLCompoundExpType type;


- (instancetype)initWithExpressions: (NSArray*)subs type: (CBLCompoundExpType)type;

@end

/////

@interface CBLKeyPathExpression : CBLQueryExpression

@property(nonatomic, readonly, copy) NSString* keyPath;

@property(nonatomic, readonly, copy, nullable) NSString* from; // Data Source Alias

- (instancetype)initWithKeyPath: (NSString*)keyPath from: (nullable NSString*)from;

@end

typedef NS_ENUM(NSInteger, CBLUnaryExpType) {
    CBLMissingUnaryExpType,
    CBLNotMissingUnaryExpType,
    CBLNotNullUnaryExpType,
    CBLNullUnaryExpType
};

/////

@interface CBLUnaryExpression : CBLQueryExpression

@property(readonly, nonatomic) CBLUnaryExpType type;
@property(readonly, nonatomic) id operand;

- (instancetype)initWithExpression: (id)operand type: (CBLUnaryExpType)type;

@end

/////

@interface CBLQueryFunction () <CBLQueryJSONEncoding>

- (instancetype) initWithFunction: (NSString*)function parameter: (id)param;

@end

NS_ASSUME_NONNULL_END
