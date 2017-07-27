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
#import "CBLQueryJoin.h"
#import "CBLQueryLimit.h"
#import "CBLQueryMeta.h"
#import "CBLQueryParameters.h"
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

@interface CBLQuery () <NSCopying>

@property (nonatomic, readonly) CBLDatabase* database;

@property (nonatomic, readonly) NSArray<CBLQuerySelectResult*>* select;

@property (nonatomic, readonly) CBLQueryDataSource* from;

@property (nonatomic, readonly, nullable) NSArray<CBLQueryJoin*>* join;

@property (nonatomic, readonly, nullable) CBLQueryExpression* where;

@property (nonatomic, readonly, nullable) NSArray<CBLQueryExpression*>* groupBy;

@property (nonatomic, readonly, nullable) CBLQueryExpression* having;

@property (nonatomic, readonly, nullable) NSArray<CBLQueryOrdering*>* orderings;

@property (nonatomic, readonly, nullable) CBLQueryLimit* limit;

@property (nonatomic, readonly) BOOL distinct;

@property (nonatomic) CBLQueryParameters* parameters;

/** Initializer. */
- (instancetype) initWithSelect: (NSArray<CBLQuerySelectResult*>*)select
                       distinct: (BOOL)distinct
                           from: (CBLQueryDataSource*)from
                           join: (nullable NSArray<CBLQueryJoin*>*)join
                          where: (nullable CBLQueryExpression*)where
                        groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
                         having: (nullable CBLQueryExpression*)having
                        orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
                          limit: (nullable CBLQueryLimit*)limit;

+ (NSData*) encodeExpressions: (NSArray*)expressions error: (NSError**)outError;

@end


/////

@interface CBLQueryDataSource () <CBLQueryJSONEncoding>

@property (nonatomic, readonly) id source;

@property (nonatomic, readonly, nullable) NSString* alias;

- (instancetype) initWithDataSource: (id)source as: (nullable NSString*)alias;

@end

/////

@interface CBLQuerySelectResult () <CBLQueryJSONEncoding>

- (instancetype) initWithExpression: (CBLQueryExpression*)expression as: (nullable NSString*)alias;

- (nullable NSString*) columnName;

@end

/////

@interface CBLQueryJoin () <CBLQueryJSONEncoding>

- (instancetype) initWithType: (NSString*)type
                   dataSource: (CBLQueryDataSource*)dataSource
                           on: (CBLQueryExpression*)expression;

@end

/////

@interface CBLQueryOrdering () <CBLQueryJSONEncoding>

@property (nonatomic, readonly) CBLQueryExpression* expression;

- (instancetype) initWithExpression: (CBLQueryExpression*)expression;

@end

@interface CBLQuerySortOrder ()

@property (nonatomic, readonly) BOOL isAscending;

@end

/////

@interface CBLQueryExpression () <CBLQueryJSONEncoding>

/** This constructor is for hiding the public -init: */
- (instancetype) initWithNone;

@end

/////

@interface CBLAggregateExpression: CBLQueryExpression

@property(nonatomic, readonly) NSArray* subexpressions;

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

@property(nonatomic, readonly) id lhs;
@property(nonatomic, readonly) id rhs;
@property(nonatomic, readonly) CBLBinaryExpType type;

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

@property(nonatomic, readonly) NSArray* subexpressions;
@property(nonatomic, readonly) CBLCompoundExpType type;


- (instancetype) initWithExpressions: (NSArray*)subs type: (CBLCompoundExpType)type;

@end

/////

@interface CBLPropertyExpression : CBLQueryExpression

@property(nonatomic, readonly) NSString* keyPath;

@property(nonatomic, readonly) NSString* columnName;

@property(nonatomic, readonly, nullable) NSString* from; // Data Source Alias

- (instancetype) initWithKeyPath: (NSString*)keyPath
                      columnName: (nullable NSString*)columnName
                            from: (nullable NSString*)from;

@end

typedef NS_ENUM(NSInteger, CBLUnaryExpType) {
    CBLMissingUnaryExpType,
    CBLNotMissingUnaryExpType,
    CBLNotNullUnaryExpType,
    CBLNullUnaryExpType
};

/////

@interface CBLUnaryExpression : CBLQueryExpression

@property(nonatomic, readonly) CBLUnaryExpType type;
@property(nonatomic, readonly) id operand;

- (instancetype) initWithExpression: (id)operand type: (CBLUnaryExpType)type;

@end

/////

@interface CBLParameterExpression : CBLQueryExpression

@property(nonatomic, readonly) id name;

- (instancetype) initWithName: (id)name;

@end

/////

@interface CBLQueryFunction () <CBLQueryJSONEncoding>

- (instancetype) initWithFunction: (NSString*)function parameter: (id)param;

@end

/////

@interface CBLQueryParameters () <NSCopying>

- (instancetype) initWithParameters: (nullable NSDictionary*)params;

- (nullable NSData*) encodeAsJSON: (NSError**)outError;

@end

/////

@interface CBLQueryMeta ()

- (instancetype) initWithFrom: (nullable NSString*)alias;

@end

/////

@interface CBLQueryLimit () <CBLQueryJSONEncoding>

@property(nonatomic, readonly) id limit;

@property(nonatomic, readonly, nullable) id offset;

- (instancetype) initWithLimit: (id)limit offset: (nullable id)offset;

@end


NS_ASSUME_NONNULL_END
