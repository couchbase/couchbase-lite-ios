//
//  CBLQuery.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLDatabase, CBLQueryRow, CBLMutableDocument;
@class CBLQuerySelectResult, CBLQueryDataSource, CBLQueryJoin, CBLQueryOrdering, CBLQueryGroupBy;
@class CBLQueryLimit, CBLQueryExpression, CBLQueryParameters;
@class CBLQueryResultSet;
@class CBLQueryChange;
@protocol CBLListenerToken;


NS_ASSUME_NONNULL_BEGIN


/** 
 A database query.
 A CBLQuery instance can be constructed by calling one of the select methods.
 */
@interface CBLQuery : NSObject

/**
 A CBLQueryParameters object used for setting values to the query parameters defined
 in the query. All parameters defined in the query must be given values
 before running the query, or the query will fail.
 */
@property (nonatomic, nullable) CBLQueryParameters* parameters;

// SELECT > FROM

/** 
 Create a query from the select and from component.
 
 @param select The select component reresenting the SELECT clause of the query.
 @param from The from component representing the FROM clause of the query.
 @return The CBLQuery instance.
 */
+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from;

/** 
 Create a distinct query from the select and from component.
 
 @param select The select component representing the SELECT clause of the query.
 @param from The from component representing the FROM clause of the query.
 @return The CBLQuery instance.
 */
+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from;

// SELECT > FROM > WHERE

/** 
 Create a query from the select, from, and where component.
 
 @param select The select component representing the SELECT clause of the query.
 @param from The from component representing the FROM clause of the query.
 @param where The where component representing the WHERE clause of the query.
 @return The CBLQuery instance.
 */
+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                  where: (nullable CBLQueryExpression*)where;

/** 
 Create a distinct query from the select, from, and where component.
 
 @param select The select component representing the SELECT clause of the query.
 @param from The from component representing the FROM clause of the query.
 @param where The where component representing the WHERE clause of the query.
 @return The CBLQuery instance.
 */
+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
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
+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
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
+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
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
+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
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
+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
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
+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
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
+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
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
+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
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
+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
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
+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
                   from: (CBLQueryDataSource*)from
                   join: (nullable NSArray<CBLQueryJoin*>*)join;

/** 
 Create a distinct query from the select from, and join component.
 
 @param select The select component representing the SELECT clause of the query.
 @param from The from component representing the FROM clause of the query.
 @param join The join components representing the JOIN clause of the query.
 @return The CBLQuery instance.
 */
+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
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
+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
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
+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
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
+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
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
+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
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
+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
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
+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
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
+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
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
+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
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
+ (instancetype) select: (NSArray<CBLQuerySelectResult*>*)select
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
+ (instancetype) selectDistinct: (NSArray<CBLQuerySelectResult*>*)select
                           from: (CBLQueryDataSource*)from
                           join: (nullable NSArray<CBLQueryJoin*>*)join
                          where: (nullable CBLQueryExpression*)where
                        groupBy: (nullable NSArray<CBLQueryExpression*>*)groupBy
                         having: (nullable CBLQueryExpression*)having
                        orderBy: (nullable NSArray<CBLQueryOrdering*>*)orderings
                          limit: (nullable CBLQueryLimit*)limit;


/** 
 Returns a string describing the implementation of the compiled query.
 This is intended to be read by a developer for purposes of optimizing the query, especially
 to add database indexes. It's not machine-readable and its format may change.
 
 As currently implemented, the result is two or more lines separated by newline characters:
 * The first line is the SQLite SELECT statement.
 * The subsequent lines are the output of SQLite's "EXPLAIN QUERY PLAN" command applied to that
 statement; for help interpreting this, see https://www.sqlite.org/eqp.html . The most
 important thing to know is that if you see "SCAN TABLE", it means that SQLite is doing a
 slow linear scan of the documents instead of using an index.
 
 @param outError If an error occurs, it will be stored here if this parameter is non-NULL.
 @return A string describing the implementation of the compiled query.
 */
- (nullable NSString*) explain: (NSError**)outError;

/** 
 Executes the query. The returning an enumerator that returns result rows one at a time.
 You can run the query any number of times, and you can even have multiple enumerators active at
 once.
 The results come from a snapshot of the database taken at the moment -run: is called, so they
 will not reflect any changes made to the database afterwards.
 
 @param outError If an error occurs, it will be stored here if this parameter is non-NULL.
 @return An enumerator of the query result.
 */
- (nullable CBLQueryResultSet*) execute: (NSError**)outError;

/**
 Adds a query change listener. Changes will be posted on the main queue.
 
 @param listener The listener to post changes.
 @return An opaque listener token object for removing the listener.
 */
- (id<CBLListenerToken>) addChangeListener: (void (^)(CBLQueryChange*))listener;

/**
 Adds a query change listener with the dispatch queue on which changes
 will be posted. If the dispatch queue is not specified, the changes will be
 posted on the main queue.
 
 @param queue The dispatch queue.
 @param listener The listener to post changes.
 @return An opaque listener token object for removing the listener.
 */
- (id<CBLListenerToken>) addChangeListenerWithQueue: (nullable dispatch_queue_t)queue
                                           listener: (void (^)(CBLQueryChange*))listener;

/**
 Removes a change listener wih the given listener token.
 
 @param token The listener token.
 */
- (void) removeChangeListenerWithToken: (id<CBLListenerToken>)token;


/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end


NS_ASSUME_NONNULL_END
