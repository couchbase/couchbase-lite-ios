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
#import "CBLQueryJoin.h"
#import "CBLQuerySelect.h"
#import "CBLQueryExpression.h"
#import "CBLQueryOrderBy.h"
#import "CBLPredicateQuery+Internal.h"

NS_ASSUME_NONNULL_BEGIN


/////

@interface CBLQuery () <CBLQueryInternal, NSCopying>

@property (readonly, nonatomic) CBLQuerySelect* select;

@property (readonly, nonatomic) CBLQueryDataSource* from;

@property (readonly, nullable, nonatomic) NSArray<CBLQueryJoin*>* join;

@property (readonly, nullable, nonatomic) CBLQueryExpression* where;

@property (readonly, nullable, nonatomic) NSArray<CBLQueryOrderBy*>* orderBy;

@property (readonly, nonatomic) BOOL distinct;

/** Initializer. */
- (instancetype) initWithSelect: (CBLQuerySelect*)select
                       distinct: (BOOL)distinct
                           from: (CBLQueryDataSource*)from
                           join: (nullable NSArray<CBLQueryJoin*>*)join
                          where: (nullable CBLQueryExpression*)where
                        orderBy: (nullable NSArray<CBLQueryOrderBy*>*)orderBy;

@end

/////

@interface CBLQueryDataSource ()

@property (nonatomic, readonly) id source;

@property (nonatomic, readonly, nullable) NSString* alias;

- (instancetype) initWithDataSource: (id)source as: (nullable NSString*)alias;

- (id) asJSON;

@end

/////

@interface CBLQuerySelect ()

@property (readonly, nullable, nonatomic) id select;

- (instancetype) initWithSelect: (nullable id)select;

@end

/////

@interface CBLQueryJoin ()

- (instancetype) initWithType: (NSString*)type
                   dataSource: (CBLQueryDataSource*)dataSource
                           on: (CBLQueryExpression*)expression;

- (id) asJSON;

@end

/////

@interface CBLQueryExpression ()
/** This constructor is currently for hiding the public -init: */
- (instancetype) initWithNone: (nullable id)none;

- (id) asJSON;

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

@interface CBLUnaryExpression : CBLQueryExpression

@property(readonly, nonatomic) CBLUnaryExpType type;
@property(readonly, nonatomic) id operand;

- (instancetype)initWithExpression: (id)operand type: (CBLUnaryExpType)type;

@end

/////

@interface CBLQueryOrderBy ()

@property (readonly, nullable, copy, nonatomic) NSArray* orders;

- (instancetype) initWithOrders: (nullable NSArray*)orders;

- (id) asJSON;

@end

@interface CBLQuerySortOrder ()

@property (readonly, nonatomic) CBLQueryExpression* expression;
@property (readonly, nonatomic) BOOL isAscending;

- (instancetype) initWithExpression: (CBLQueryExpression*)expression;

@end

NS_ASSUME_NONNULL_END
