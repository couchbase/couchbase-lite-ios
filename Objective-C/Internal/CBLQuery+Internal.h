//
//  CBLQuery+Internal.h
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLQuery.h"
#import "CBLDatabase+Internal.h"
#import "CBLQueryCollation.h"
#import "CBLQueryDataSource.h"
#import "CBLQueryFunction.h"
#import "CBLQueryJSONEncoding.h"
#import "CBLQueryJoin.h"
#import "CBLQueryLimit.h"
#import "CBLQueryMeta.h"
#import "CBLQueryParameters.h"
#import "CBLQuerySelectResult.h"
#import "CBLQueryExpression.h"
#import "CBLQueryOrdering.h"


NS_ASSUME_NONNULL_BEGIN

@interface CBLQuery () <NSCopying>

@property (nonatomic, readonly) CBLDatabase* database;

- (instancetype) initWithSelect: (NSArray<CBLQuerySelectResult*>*)select
                       distinct: (BOOL)distinct
                           from: (CBLQueryDataSource*)from
                           join: (nullable NSArray<CBLQueryJoin*>*)join
                          where: (nullable CBLQueryExpression*)where
                        groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
                         having: (nullable CBLQueryExpression*)having
                        orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
                          limit: (nullable CBLQueryLimit*)limit;

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
                           on: (nullable CBLQueryExpression*)expression;

@end


@interface CBLQueryOrdering () <CBLQueryJSONEncoding>

@property (nonatomic, readonly) CBLQueryExpression* expression;

- (instancetype) initWithExpression: (CBLQueryExpression*)expression;

@end


@interface CBLQuerySortOrder ()

@property (nonatomic, readonly) BOOL isAscending;

@end


@interface CBLQueryParameters ()

- (instancetype) initWithParameters: (nullable CBLQueryParameters*)parameters
                           readonly: (BOOL)readonly;

- (nullable NSData*) encode: (NSError**)outError;

@end


@interface CBLQueryLimit () <CBLQueryJSONEncoding>

@property(nonatomic, readonly) id limit;

@property(nonatomic, readonly, nullable) id offset;

- (instancetype) initWithLimit: (CBLQueryExpression*)limit
                        offset: (nullable CBLQueryExpression*)offset;

@end

@interface CBLQueryCollation () <CBLQueryJSONEncoding>

- (instancetype) initWithUnicode: (BOOL)unicode
                          locale: (nullable NSString*)locale
                      ignoreCase: (BOOL)ignoreCase
                   ignoreAccents: (BOOL)ignoreAccents;

@end


NS_ASSUME_NONNULL_END
