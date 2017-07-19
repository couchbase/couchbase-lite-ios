//
//  CBLQuery.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLDatabase, CBLQueryRow, CBLDocument;
@class CBLQuerySelectResult, CBLQueryDataSource, CBLQueryJoin, CBLQueryOrdering, CBLQueryGroupBy;
@class CBLQueryLimit, CBLQueryExpression, CBLQueryParameters;
@class CBLQueryResultSet;
@class CBLLiveQuery;


NS_ASSUME_NONNULL_BEGIN


/** A database query.
    A CBLQuery instance can be constructed by calling one of the select methods. */
@interface CBLQuery : NSObject

/** A CBLQueryParameters object used for setting values to the query parameters defined 
    in the query. All parameters defined in the query must be given values 
    before running the query, or the query will fail. */
@property (nonatomic, readonly) CBLQueryParameters* parameters;

// SELECT > FROM

/** Create a query from the select and from component.
    @param select   The select component reresenting the SELECT clause of the query.
    @param from     The from component representing the FROM clause of the query.
    @return The CBLQuery instance. */
+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from;

/** Create a distinct query from the select and from component.
    @param select   The select component representing the SELECT clause of the query.
    @param from     The from component representing the FROM clause of the query.
    @return The CBLQuery instance. */
+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from;

// SELECT > FROM > WHERE

/** Create a query from the select, from, and where component.
    @param select   The select component representing the SELECT clause of the query.
    @param from     The from component representing the FROM clause of the query.
    @param where    The where component representing the WHERE clause of the query.
    @return The CBLQuery instance. */
+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                  where: (nullable CBLQueryExpression*)where;

/** Create a distinct query from the select, from, and where component. 
    @param select   The select component representing the SELECT clause of the query.
    @param from     The from component representing the FROM clause of the query.
    @param where    The where component representing the WHERE clause of the query.
    @return The CBLQuery instance. */
+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                          from: (CBLQueryDataSource*)from
                         where: (nullable CBLQueryExpression*)where;

// SELECT > FROM > WHERE > ORDER BY

/** Create a query Create a query from the select, from, where, and order by component.
    @param select    The select component representing the SELECT clause of the query.
    @param from      The from component representing the FROM clause of the query.
    @param where     The where component representing the WHERE clause of the query.
    @param orderings The ordering components representing the ORDER BY clause of the query.
    @return the CBLQuery instance. */
+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                  where: (nullable CBLQueryExpression*)where
                orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings;

/** Create a distinct query Create a query from the select, from, where, and order by component.
    @param select   The select component representing the SELECT clause of the query.
    @param from     The from component representing the FROM clause of the query.
    @param where    The where component representing the WHERE clause of the query.
    @param orderings The ordering components representing the ORDER BY clause of the query.
    @return The CBLQuery instance. */
+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                          from: (CBLQueryDataSource*)from
                         where: (nullable CBLQueryExpression*)where
                       orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings;

// SELECT > FROM > WHERE > GROUP BY

/** Create a query from the select, from, and where component.
 @param select   The select component representing the SELECT clause of the query.
 @param from     The from component representing the FROM clause of the query.
 @param where    The where component representing the WHERE clause of the query.
 @param groupBy  The group by expressions representing the GROUP BY clause of the query.
 @return The CBLQuery instance. */
+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                  where: (nullable CBLQueryExpression*)where
                groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy;

/** Create a distinct query from the select, from, and where component.
 @param select   The select component representing the SELECT clause of the query.
 @param from     The from component representing the FROM clause of the query.
 @param where    The where component representing the WHERE clause of the query.
 @param groupBy  The group by expressions representing the GROUP BY clause of the query.
 @return The CBLQuery instance. */
+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from
                          where: (nullable CBLQueryExpression*)where
                        groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy;

// SELECT > FROM > WHERE > GROUP BY

/** Create a query from the select, from, and where component.
    @param select   The select component representing the SELECT clause of the query.
    @param from     The from component representing the FROM clause of the query.
    @param where    The where component representing the WHERE clause of the query.
    @param groupBy  The group by expressions representing the GROUP BY clause of the query.
    @param having   The having component representing the HAVING clause of the query.
    @return The CBLQuery instance. */
+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                  where: (nullable CBLQueryExpression*)where
                groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
                 having: (nullable CBLQueryExpression*)having;

/** Create a distinct query from the select, from, and where component.
    @param select   The select component representing the SELECT clause of the query.
    @param from     The from component representing the FROM clause of the query.
    @param where    The where component representing the WHERE clause of the query.
    @param groupBy  The group by expressions representing the GROUP BY clause of the query.
    @param having   The having component representing the HAVING clause of the query.
    @return The CBLQuery instance. */
+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from
                          where: (nullable CBLQueryExpression*)where
                        groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
                         having: (nullable CBLQueryExpression*)having;

// SELECT > FROM > WHERE > GROUP BY > HAVING > ORDER BY

/** Create a query from the select, from, and where component.
    @param select    The select component representing the SELECT clause of the query.
    @param from      The from component representing the FROM clause of the query.
    @param where     The where component representing the WHERE clause of the query.
    @param groupBy   The group by expressions representing the GROUP BY clause of the query.
    @param having    The having component representing the HAVING clause of the query.
    @param orderings The ordering components representing the ORDER BY clause of the query.
    @param limit     The limit component representing the LIMIT clause of the query.
    @return The CBLQuery instance. */
+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                  where: (nullable CBLQueryExpression*)where
                groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
                 having: (nullable CBLQueryExpression*)having
                orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
                  limit: (nullable CBLQueryLimit*)limit;

/** Create a distinct query from the select, from, and where component.
    @param select    The select component representing the SELECT clause of the query.
    @param from      The from component representing the FROM clause of the query.
    @param where     The where component representing the WHERE clause of the query.
    @param groupBy   The group by expressions representing the GROUP BY clause of the query.
    @param having    The having component representing the HAVING clause of the query.
    @param orderings The ordering components representing the ORDER BY clause of the query.
    @param limit     The limit component representing the LIMIT clause of the query.
    @return The CBLQuery instance. */
+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from
                          where: (nullable CBLQueryExpression*)where
                        groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
                         having: (nullable CBLQueryExpression*)having
                        orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
                          limit: (nullable CBLQueryLimit*)limit;

// SELECT > FROM > JOIN

/** Create a query from the select and from component.
    @param select  The select component reresenting the SELECT clause of the query.
    @param from    The from component representing the FROM clause of the query.
    @param join    The join components representing the JOIN clause of the query.
    @return the CBLQuery instance. */
+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                   join: (nullable NSArray<CBLQueryJoin*>*)join;

/** Create a distinct query from the select and from component.
    @param select   The select component representing the SELECT clause of the query.
    @param from     The from component representing the FROM clause of the query.
    @param join     The join components representing the JOIN clause of the query.
    @return The CBLQuery instance. */
+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from
                           join: (nullable NSArray<CBLQueryJoin*>*)join;

// SELECT > FROM > JOIN > WHERE

/** Create a query from the select, from, and where component.
    @param select   The select component representing the SELECT clause of the query.
    @param from     The from component representing the FROM clause of the query.
    @param join     The join components representing the JOIN clause of the query.
    @param where    The where component representing the WHERE clause of the query.
    @return The CBLQuery instance. */
+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                   join: (nullable NSArray<CBLQueryJoin*>*)join
                  where: (nullable CBLQueryExpression*)where;

/** Create a distinct query from the select, from, and where component.
    @param select   The select component representing the SELECT clause of the query.
    @param from     The from component representing the FROM clause of the query.
    @param join     The join components representing the JOIN clause of the query.
    @param where    The where component representing the WHERE clause of the query.
    @return The CBLQuery instance. */
+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from
                           join: (nullable NSArray<CBLQueryJoin*>*)join
                          where: (nullable CBLQueryExpression*)where;

// SELECT > FROM > JOIN > WHERE > GROUP BY

/** Create a query from the select, from, and where component.
 @param select   The select component representing the SELECT clause of the query.
 @param from     The from component representing the FROM clause of the query.
 @param join     The join components representing the JOIN clause of the query.
 @param where    The where component representing the WHERE clause of the query.
 @param groupBy  The group by expressions representing the GROUP BY clause of the query.
 @return The CBLQuery instance. */
+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                   join: (nullable NSArray<CBLQueryJoin*>*)join
                  where: (nullable CBLQueryExpression*)where
                groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy;


/** Create a distinct query from the select, from, and where component.
 @param select   The select component representing the SELECT clause of the query.
 @param from     The from component representing the FROM clause of the query.
 @param join     The join components representing the JOIN clause of the query.
 @param where    The where component representing the WHERE clause of the query.
 @param groupBy  The group by expressions representing the GROUP BY clause of the query.
 @return The CBLQuery instance. */
+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from
                           join: (nullable NSArray<CBLQueryJoin*>*)join
                          where: (nullable CBLQueryExpression*)where
                        groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy;

// SELECT > FROM > JOIN > WHERE > GROUP BY > HAVING

/** Create a query from the select, from, and where component.
    @param select   The select component representing the SELECT clause of the query.
    @param from     The from component representing the FROM clause of the query.
    @param join     The join components representing the JOIN clause of the query.
    @param where    The where component representing the WHERE clause of the query.
    @param groupBy  The group by expressions representing the GROUP BY clause of the query.
    @param having   The having component representing the HAVING clause of the query.
    @return The CBLQuery instance. */
+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                   join: (nullable NSArray<CBLQueryJoin*>*)join
                  where: (nullable CBLQueryExpression*)where
                groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
                 having: (nullable CBLQueryExpression*)having;


/** Create a distinct query from the select, from, and where component.
    @param select   The select component representing the SELECT clause of the query.
    @param from     The from component representing the FROM clause of the query.
    @param join     The join components representing the JOIN clause of the query.
    @param where    The where component representing the WHERE clause of the query.
    @param groupBy  The group by expressions representing the GROUP BY clause of the query.
    @param having   The having component representing the HAVING clause of the query.
    @return The CBLQuery instance. */
+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from
                           join: (nullable NSArray<CBLQueryJoin*>*)join
                          where: (nullable CBLQueryExpression*)where
                        groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
                         having: (nullable CBLQueryExpression*)having;

// SELECT > FROM > JOIN > WHERE > ORDER BY

/** Create a query Create a query from the select, from, where, and order by component.
    @param select    The select component representing the SELECT clause of the query.
    @param from      The from component representing the FROM clause of the query.
    @param join      The join components representing the JOIN clause of the query.
    @param where     The where component representing the WHERE clause of the query.
    @param orderings The ordering components representing the ORDER BY clause of the query.
    @return the CBLQuery instance. */
+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                   join: (nullable NSArray<CBLQueryJoin*>*)join
                  where: (nullable CBLQueryExpression*)where
                orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings;

/** Create a distinct query Create a query from the select, from, where, and order by component.
    @param select    The select component representing the SELECT clause of the query.
    @param from      The from component representing the FROM clause of the query.
    @param join      The join components representing the JOIN clause of the query.
    @param where     The where component representing the WHERE clause of the query.
    @param orderings The ordering components representing the ORDER BY clause of the query.
    @return The CBLQuery instance. */
+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from
                           join: (nullable NSArray<CBLQueryJoin*>*)join
                          where: (nullable CBLQueryExpression*)where
                        orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings;

// SELECT > FROM > JOIN > WHERE > GROUP BY > HAVING > ORDER BY

/** Create a query Create a query from the select, from, where, and order by component.
    @param select    The select component representing the SELECT clause of the query.
    @param from      The from component representing the FROM clause of the query.
    @param join      The join components representing the JOIN clause of the query.
    @param where     The where component representing the WHERE clause of the query.
    @param groupBy   The group by expressions representing the GROUP BY clause of the query.
    @param having    The having component representing the HAVING clause of the query.
    @param orderings The orderings components representing the ORDER BY clause of the query.
    @param limit     The limit component representing the LIMIT clause of the query.
    @return the CBLQuery instance. */
+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                   join: (nullable NSArray<CBLQueryJoin*>*)join
                  where: (nullable CBLQueryExpression*)where
                groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
                 having: (nullable CBLQueryExpression*)having
                orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
                  limit: (nullable CBLQueryLimit*)limit;

/** Create a distinct query Create a query from the select, from, where, and order by component.
    @param select    The select component representing the SELECT clause of the query.
    @param from      The from component representing the FROM clause of the query.
    @param join      The join components representing the JOIN clause of the query.
    @param where     The where component representing the WHERE clause of the query.
    @param groupBy   The group by expressions representing the GROUP BY clause of the query.
    @param having    The having component representing the HAVING clause of the query.
    @param orderings The ordering components representing the ORDER BY clause of the query.
    @param limit     The limit component representing the LIMIT clause of the query.
    @return The CBLQuery instance. */
+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from
                           join: (nullable NSArray<CBLQueryJoin*>*)join
                          where: (nullable CBLQueryExpression*)where
                        groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
                         having: (nullable CBLQueryExpression*)having
                        orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
                          limit: (nullable CBLQueryLimit*)limit;


/** Checks whether the query is valid, recompiling it if necessary, without running it.
    @param outError If an error occurs, it will be stored here if this parameter is non-NULL.
    @return YES if the query is valid, or NO if the query is not valid. */
- (BOOL) check: (NSError**)outError;

/** Returns a string describing the implementation of the compiled query.
    This is intended to be read by a developer for purposes of optimizing the query, especially
    to add database indexes. It's not machine-readable and its format may change.
 
    As currently implemented, the result is two or more lines separated by newline characters:
    * The first line is the SQLite SELECT statement.
    * The subsequent lines are the output of SQLite's "EXPLAIN QUERY PLAN" command applied to that
    statement; for help interpreting this, see https://www.sqlite.org/eqp.html . The most
    important thing to know is that if you see "SCAN TABLE", it means that SQLite is doing a
    slow linear scan of the documents instead of using an index.
    @param outError If an error occurs, it will be stored here if this parameter is non-NULL.
    @return A string describing the implementation of the compiled query. */
- (nullable NSString*) explain: (NSError**)outError;


/** Runs the query. The returning an enumerator that returns result rows one at a time.
    You can run the query any number of times, and you can even have multiple enumerators active at 
    once.
    The results come from a snapshot of the database taken at the moment -run: is called, so they
    will not reflect any changes made to the database afterwards. 
    @param outError If an error occurs, it will be stored here if this parameter is non-NULL.
    @return An enumerator of the query result.
 */
- (nullable CBLQueryResultSet*) run: (NSError**)outError;

/** Returns a live query based on the current query.
    @return A live query object. */
- (CBLLiveQuery*) toLive;

- (instancetype) init NS_UNAVAILABLE;

@end


NS_ASSUME_NONNULL_END
