//
//  CBLQuery+Internal.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQuery.h"
#import "CBLDatabase+Internal.h"
#import "CBLQueryCollation.h"
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

@protocol CBLQueryJSONEncoding <NSObject>

/** Encode as a JSON object. */
- (id) asJSON;

@end


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


@interface CBLQueryDataSource () <CBLQueryJSONEncoding>

@property (nonatomic, readonly) id source;

@property (nonatomic, readonly, nullable) NSString* alias;

@property (nonatomic, readonly, nullable) NSString* columnName;

- (instancetype) initWithDataSource: (id)source as: (nullable NSString*)alias;

@end


@interface CBLQuerySelectResult () <CBLQueryJSONEncoding>

- (instancetype) initWithExpression: (CBLQueryExpression*)expression
                                 as: (nullable NSString*)alias;

@property (nonatomic, readonly, nullable) NSString* columnName;

@end


@interface CBLQueryJoin () <CBLQueryJSONEncoding>

- (instancetype) initWithType: (NSString*)type
                   dataSource: (CBLQueryDataSource*)dataSource
                           on: (CBLQueryExpression*)expression;

@end


@interface CBLQueryOrdering () <CBLQueryJSONEncoding>

@property (nonatomic, readonly) CBLQueryExpression* expression;

- (instancetype) initWithExpression: (CBLQueryExpression*)expression;

@end


@interface CBLQuerySortOrder ()

@property (nonatomic, readonly) BOOL isAscending;

@end


@interface CBLQueryExpression () <CBLQueryJSONEncoding>

/** This constructor is for hiding the public -init: */
- (instancetype) initWithNone;

- (id) jsonValue: (id)value;

@end


@interface CBLQueryFunction () <CBLQueryJSONEncoding>

- (instancetype) initWithFunction: (NSString*)function params: (nullable NSArray*)params;

@end


@interface CBLQueryParameters () <NSCopying>

- (instancetype) initWithParameters: (nullable NSDictionary*)params;

- (nullable NSData*) encodeAsJSON: (NSError**)outError;

@end


@interface CBLQueryMeta ()

- (instancetype) initWithFrom: (nullable NSString*)alias;

@end


@interface CBLQueryLimit () <CBLQueryJSONEncoding>

@property(nonatomic, readonly) id limit;

@property(nonatomic, readonly, nullable) id offset;

- (instancetype) initWithLimit: (id)limit offset: (nullable id)offset;

@end

@interface CBLQueryCollation () <CBLQueryJSONEncoding>

- (instancetype) initWithUnicode: (BOOL)unicode
                          locale: (nullable NSString*)locale
                      ignoreCase: (BOOL)ignoreCase
                   ignoreAccents: (BOOL)ignoreAccents;

@end


NS_ASSUME_NONNULL_END
