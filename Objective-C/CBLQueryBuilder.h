//
//  CBLQueryBuilder.h
//  CouchbaseLite
//
//  Copyright (c) 2018 Couchbase, Inc All rights reserved.
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

#import <Foundation/Foundation.h>
@class CBLQuery, CBLQuerySelectResult, CBLQueryDataSource, CBLQueryJoin;
@class CBLQueryOrdering, CBLQueryGroupBy, CBLQueryLimit;
@class CBLQueryExpression;

NS_ASSUME_NONNULL_BEGIN

@interface CBLQueryBuilder : NSObject

// SELECT > FROM

/**
 Create a query from the select and from component.
 
 @param select The select component reresenting the SELECT clause of the query.
 @param from The from component representing the FROM clause of the query.
 @return The CBLQuery instance.
 */
+ (CBLQuery*) select: (NSArray<CBLQuerySelectResult*>*)select
                from: (CBLQueryDataSource*)from;

/**
 Create a distinct query from the select and from component.
 
 @param select The select component representing the SELECT clause of the query.
 @param from The from component representing the FROM clause of the query.
 @return The CBLQuery instance.
 */
+ (CBLQuery*) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                        from: (CBLQueryDataSource*)from;

// SELECT > FROM > WHERE

/**
 Create a query from the select, from, and where component.
 
 @param select The select component representing the SELECT clause of the query.
 @param from The from component representing the FROM clause of the query.
 @param where The where component representing the WHERE clause of the query.
 @return The CBLQuery instance.
 */
+ (CBLQuery*) select: (NSArray<CBLQuerySelectResult*>*)select
                from: (CBLQueryDataSource*)from
               where: (nullable CBLQueryExpression*)where;

/**
 Create a distinct query from the select, from, and where component.
 
 @param select The select component representing the SELECT clause of the query.
 @param from The from component representing the FROM clause of the query.
 @param where The where component representing the WHERE clause of the query.
 @return The CBLQuery instance.
 */
+ (CBLQuery*) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                        from: (CBLQueryDataSource*)from
                       where: (nullable CBLQueryExpression*)where;

// SELECT > FROM > WHERE > ORDER BY

/**
 Create a query from the select, from, where, and order by component.
 
 @param select The select component representing the SELECT clause of the query.
 @param from The from component representing the FROM clause of the query.
 @param where The where component representing the WHERE clause of the query.
 @param orderings The ordering components representing the ORDER BY clause of the query.
 @return The CBLQuery instance.
 */
+ (CBLQuery*) select: (NSArray<CBLQuerySelectResult*>*)select
                from: (CBLQueryDataSource*)from
               where: (nullable CBLQueryExpression*)where
             orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings;

/**
 Create a distinct query from the select, from, where, and order by component.
 
 @param select The select component representing the SELECT clause of the query.
 @param from The from component representing the FROM clause of the query.
 @param where The where component representing the WHERE clause of the query.
 @param orderings The ordering components representing the ORDER BY clause of the query.
 @return The CBLQuery instance.
 */
+ (CBLQuery*) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                        from: (CBLQueryDataSource*)from
                       where: (nullable CBLQueryExpression*)where
                     orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings;

// SELECT > FROM > WHERE > GROUP BY

/**
 Create a query from the select, from, where, and group by component.
 
 @param select The select component representing the SELECT clause of the query.
 @param from The from component representing the FROM clause of the query.
 @param where The where component representing the WHERE clause of the query.
 @param groupBy The group by expressions representing the GROUP BY clause of the query.
 @return The CBLQuery instance.
 */
+ (CBLQuery*) select: (NSArray<CBLQuerySelectResult*>*)select
                from: (CBLQueryDataSource*)from
               where: (nullable CBLQueryExpression*)where
             groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy;

/**
 Create a distinct query from the select, from, where and group by component.
 
 @param select The select component representing the SELECT clause of the query.
 @param from The from component representing the FROM clause of the query.
 @param where The where component representing the WHERE clause of the query.
 @param groupBy The group by expressions representing the GROUP BY clause of the query.
 @return The CBLQuery instance.
 */
+ (CBLQuery*) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                        from: (CBLQueryDataSource*)from
                       where: (nullable CBLQueryExpression*)where
                     groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy;

// SELECT > FROM > WHERE > GROUP BY > HAVING

/**
 Create a query from the select, from, where, groupby and having component.
 
 @param select The select component representing the SELECT clause of the query.
 @param from The from component representing the FROM clause of the query.
 @param where The where component representing the WHERE clause of the query.
 @param groupBy The group by expressions representing the GROUP BY clause of the query.
 @param having The having component representing the HAVING clause of the query.
 @return The CBLQuery instance.
 */
+ (CBLQuery*) select: (NSArray<CBLQuerySelectResult*>*)select
                from: (CBLQueryDataSource*)from
               where: (nullable CBLQueryExpression*)where
             groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
              having: (nullable CBLQueryExpression*)having;

/**
 Create a distinct query from the select, from, where, groupby and having component.
 
 @param select The select component representing the SELECT clause of the query.
 @param from The from component representing the FROM clause of the query.
 @param where The where component representing the WHERE clause of the query.
 @param groupBy The group by expressions representing the GROUP BY clause of the query.
 @param having The having component representing the HAVING clause of the query.
 @return The CBLQuery instance.
 */
+ (CBLQuery*) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                        from: (CBLQueryDataSource*)from
                       where: (nullable CBLQueryExpression*)where
                     groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
                      having: (nullable CBLQueryExpression*)having;

// SELECT > FROM > WHERE > GROUP BY > HAVING > ORDER BY > LIMIT

/**
 Create a query from the select, from, where, groupby, having, order by, and limit component.
 
 @param select The select component representing the SELECT clause of the query.
 @param from The from component representing the FROM clause of the query.
 @param where The where component representing the WHERE clause of the query.
 @param groupBy The group by expressions representing the GROUP BY clause of the query.
 @param having The having component representing the HAVING clause of the query.
 @param orderings The ordering components representing the ORDER BY clause of the query.
 @param limit The limit component representing the LIMIT clause of the query.
 @return The CBLQuery instance.
 */
+ (CBLQuery*) select: (NSArray<CBLQuerySelectResult*>*)select
                from: (CBLQueryDataSource*)from
               where: (nullable CBLQueryExpression*)where
             groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
              having: (nullable CBLQueryExpression*)having
             orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
               limit: (nullable CBLQueryLimit*)limit;

/**
 Create a distinct query from the select, from, where, groupby, having, order by,
 and limit component.
 
 @param select The select component representing the SELECT clause of the query.
 @param from The from component representing the FROM clause of the query.
 @param where The where component representing the WHERE clause of the query.
 @param groupBy The group by expressions representing the GROUP BY clause of the query.
 @param having The having component representing the HAVING clause of the query.
 @param orderings The ordering components representing the ORDER BY clause of the query.
 @param limit The limit component representing the LIMIT clause of the query.
 @return The CBLQuery instance.
 */
+ (CBLQuery*) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                        from: (CBLQueryDataSource*)from
                       where: (nullable CBLQueryExpression*)where
                     groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
                      having: (nullable CBLQueryExpression*)having
                     orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
                       limit: (nullable CBLQueryLimit*)limit;

// SELECT > FROM > JOIN

/**
 Create a query from the select, from, and join component.
 
 @param select The select component reresenting the SELECT clause of the query.
 @param from The from component representing the FROM clause of the query.
 @param join The join components representing the JOIN clause of the query.
 @return The CBLQuery instance.
 */
+ (CBLQuery*) select: (NSArray<CBLQuerySelectResult*>*)select
                from: (CBLQueryDataSource*)from
                join: (nullable NSArray<CBLQueryJoin*>*)join;

/**
 Create a distinct query from the select from, and join component.
 
 @param select The select component representing the SELECT clause of the query.
 @param from The from component representing the FROM clause of the query.
 @param join The join components representing the JOIN clause of the query.
 @return The CBLQuery instance.
 */
+ (CBLQuery*) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                        from: (CBLQueryDataSource*)from
                        join: (nullable NSArray<CBLQueryJoin*>*)join;

// SELECT > FROM > JOIN > WHERE

/**
 Create a query from the select, from, join and where component.
 
 @param select The select component representing the SELECT clause of the query.
 @param from The from component representing the FROM clause of the query.
 @param join The join components representing the JOIN clause of the query.
 @param where The where component representing the WHERE clause of the query.
 @return The CBLQuery instance.
 */
+ (CBLQuery*) select: (NSArray<CBLQuerySelectResult*>*)select
                from: (CBLQueryDataSource*)from
                join: (nullable NSArray<CBLQueryJoin*>*)join
               where: (nullable CBLQueryExpression*)where;

/**
 Create a distinct query from the select, from, join and where component.
 
 @param select The select component representing the SELECT clause of the query.
 @param from The from component representing the FROM clause of the query.
 @param join The join components representing the JOIN clause of the query.
 @param where The where component representing the WHERE clause of the query.
 @return The CBLQuery instance.
 */
+ (CBLQuery*) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                        from: (CBLQueryDataSource*)from
                        join: (nullable NSArray<CBLQueryJoin*>*)join
                       where: (nullable CBLQueryExpression*)where;

// SELECT > FROM > JOIN > WHERE > GROUP BY

/**
 Create a query from the select, from, join, where, and group by component.
 
 @param select The select component representing the SELECT clause of the query.
 @param from The from component representing the FROM clause of the query.
 @param join The join components representing the JOIN clause of the query.
 @param where The where component representing the WHERE clause of the query.
 @param groupBy The group by expressions representing the GROUP BY clause of the query.
 @return The CBLQuery instance.
 */
+ (CBLQuery*) select: (NSArray<CBLQuerySelectResult*>*)select
                from: (CBLQueryDataSource*)from
                join: (nullable NSArray<CBLQueryJoin*>*)join
               where: (nullable CBLQueryExpression*)where
             groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy;


/**
 Create a distinct query from the select, from, join, where, and groupby component.
 
 @param select The select component representing the SELECT clause of the query.
 @param from The from component representing the FROM clause of the query.
 @param join The join components representing the JOIN clause of the query.
 @param where The where component representing the WHERE clause of the query.
 @param groupBy The group by expressions representing the GROUP BY clause of the query.
 @return The CBLQuery instance.
 */
+ (CBLQuery*) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                        from: (CBLQueryDataSource*)from
                        join: (nullable NSArray<CBLQueryJoin*>*)join
                       where: (nullable CBLQueryExpression*)where
                     groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy;

// SELECT > FROM > JOIN > WHERE > GROUP BY > HAVING

/**
 Create a query from the select, from, join, where, grop by, and having component.
 
 @param select The select component representing the SELECT clause of the query.
 @param from The from component representing the FROM clause of the query.
 @param join The join components representing the JOIN clause of the query.
 @param where The where component representing the WHERE clause of the query.
 @param groupBy The group by expressions representing the GROUP BY clause of the query.
 @param having The having component representing the HAVING clause of the query.
 @return The CBLQuery instance.
 */
+ (CBLQuery*) select: (NSArray<CBLQuerySelectResult*>*)select
                from: (CBLQueryDataSource*)from
                join: (nullable NSArray<CBLQueryJoin*>*)join
               where: (nullable CBLQueryExpression*)where
             groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
              having: (nullable CBLQueryExpression*)having;


/**
 Create a distinct query from the select, from, join, where, gropu by and having component.
 
 @param select The select component representing the SELECT clause of the query.
 @param from The from component representing the FROM clause of the query.
 @param join The join components representing the JOIN clause of the query.
 @param where The where component representing the WHERE clause of the query.
 @param groupBy The group by expressions representing the GROUP BY clause of the query.
 @param having The having component representing the HAVING clause of the query.
 @return The CBLQuery instance.
 */
+ (CBLQuery*) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                        from: (CBLQueryDataSource*)from
                        join: (nullable NSArray<CBLQueryJoin*>*)join
                       where: (nullable CBLQueryExpression*)where
                     groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
                      having: (nullable CBLQueryExpression*)having;

// SELECT > FROM > JOIN > WHERE > ORDER BY

/**
 Create a query from the select, from, join, where and order by component.
 
 @param select The select component representing the SELECT clause of the query.
 @param from The from component representing the FROM clause of the query.
 @param join The join components representing the JOIN clause of the query.
 @param where The where component representing the WHERE clause of the query.
 @param orderings The ordering components representing the ORDER BY clause of the query.
 @return The CBLQuery instance.
 */
+ (CBLQuery*) select: (NSArray<CBLQuerySelectResult*>*)select
                from: (CBLQueryDataSource*)from
                join: (nullable NSArray<CBLQueryJoin*>*)join
               where: (nullable CBLQueryExpression*)where
             orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings;

/**
 Create a distinct query from the select, from, join, where, and order by component.
 
 @param select The select component representing the SELECT clause of the query.
 @param from The from component representing the FROM clause of the query.
 @param join The join components representing the JOIN clause of the query.
 @param where The where component representing the WHERE clause of the query.
 @param orderings The ordering components representing the ORDER BY clause of the query.
 @return The CBLQuery instance.
 */
+ (CBLQuery*) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                        from: (CBLQueryDataSource*)from
                        join: (nullable NSArray<CBLQueryJoin*>*)join
                       where: (nullable CBLQueryExpression*)where
                     orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings;

// SELECT > FROM > JOIN > WHERE > GROUP BY > HAVING > ORDER BY > LIMIT

/**
 Create a query from the select, from, join, where, group by, having, order by, and limit component.
 
 @param select The select component representing the SELECT clause of the query.
 @param from The from component representing the FROM clause of the query.
 @param join The join components representing the JOIN clause of the query.
 @param where The where component representing the WHERE clause of the query.
 @param groupBy The group by expressions representing the GROUP BY clause of the query.
 @param having The having component representing the HAVING clause of the query.
 @param orderings The orderings components representing the ORDER BY clause of the query.
 @param limit The limit component representing the LIMIT clause of the query.
 @return The CBLQuery instance.
 */
+ (CBLQuery*) select: (NSArray<CBLQuerySelectResult*>*)select
                from: (CBLQueryDataSource*)from
                join: (nullable NSArray<CBLQueryJoin*>*)join
               where: (nullable CBLQueryExpression*)where
             groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
              having: (nullable CBLQueryExpression*)having
             orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
               limit: (nullable CBLQueryLimit*)limit;

/**
 Create a distinct query from the select, from, join, where, group by, having, order by and
 limit component.
 
 @param select The select component representing the SELECT clause of the query.
 @param from The from component representing the FROM clause of the query.
 @param join The join components representing the JOIN clause of the query.
 @param where The where component representing the WHERE clause of the query.
 @param groupBy The group by expressions representing the GROUP BY clause of the query.
 @param having The having component representing the HAVING clause of the query.
 @param orderings The ordering components representing the ORDER BY clause of the query.
 @param limit The limit component representing the LIMIT clause of the query.
 @return The CBLQuery instance.
 */
+ (CBLQuery*) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                        from: (CBLQueryDataSource*)from
                        join: (nullable NSArray<CBLQueryJoin*>*)join
                       where: (nullable CBLQueryExpression*)where
                     groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
                      having: (nullable CBLQueryExpression*)having
                     orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
                       limit: (nullable CBLQueryLimit*)limit;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
