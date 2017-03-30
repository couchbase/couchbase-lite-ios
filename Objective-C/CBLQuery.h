//
//  CBLQuery.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLDatabase, CBLQueryRow, CBLDocument;
@class CBLQuerySelect, CBLQueryDataSource, CBLQueryExpression, CBLQueryOrderBy;


NS_ASSUME_NONNULL_BEGIN


/** A database query.
 A CBLQuery instance can be constructed by calling one of the select methods. */
@interface CBLQuery : NSObject

/** Create a query from the select and from component.
    @param select   the select component reresenting the SELECT clause of the query.
    @param from the from component representing the FROM clause of the query.
    @return the CBLQuery instance. */
+ (instancetype) select: (CBLQuerySelect*)select from: (CBLQueryDataSource*)from;

/** Create a distinct query from the select and from component.
    @param selectDistinct   the select component representing the SELECT clause of the query.
    @param from the from component representing the FROM clause of the query.
    @return the CBLQuery instance. */
+ (instancetype) selectDistinct: (CBLQuerySelect*)selectDistinct from: (CBLQueryDataSource*)from;

/** Create a query from the select, from, and where component.
    @param select   the select component representing the SELECT clause of the query.
    @param from the from component representing the FROM clause of the query.
    @param where    the where component representing the WHERE clause of the query.
    @return the CBLQuery instance. */
+ (instancetype) select: (CBLQuerySelect*)select
                   from: (CBLQueryDataSource*)from
                  where: (nullable CBLQueryExpression*)where;

/** Create a distinct query from the select, from, and where component. 
    @param selectDistinct the select component representing the SELECT clause of the query.
    @param from the from component representing the FROM clause of the query.
    @param where    the where component representing the WHERE clause of the query.
    @return the CBLQuery instance. */
+ (instancetype) selectDistinct: (CBLQuerySelect*)selectDistinct
                          from: (CBLQueryDataSource*)from
                         where: (nullable CBLQueryExpression*)where;

/** Create a query Create a query from the select, from, where, and order by component.
    @param select   the select component representing the SELECT clause of the query.
    @param from the from component representing the FROM clause of the query.
    @param where    the where component representing the WHERE clause of the query.
    @param orderBy  the order by component representing the ORDER BY clause of the query.
    @return the CBLQuery instance. */
+ (instancetype) select: (CBLQuerySelect*)select
                   from: (CBLQueryDataSource*)from
                  where: (nullable CBLQueryExpression*)where
                orderBy: (nullable CBLQueryOrderBy*)orderBy;

/** Create a distinct query Create a query from the select, from, where, and order by component.
    @param selectDistinct   the select component representing the SELECT clause of the query.
    @param from the from component representing the FROM clause of the query.
    @param where    the where component representing the WHERE clause of the query.
    @param orderBy  the order by component representing the ORDER BY clause of the query.
    @return the CBLQuery instance. */
+ (instancetype) selectDistinct: (CBLQuerySelect*)selectDistinct
                          from: (CBLQueryDataSource*)from
                         where: (nullable CBLQueryExpression*)where
                       orderBy: (nullable CBLQueryOrderBy*)orderBy;


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
    @return a string describing the implementation of the compiled query. */
- (nullable NSString*) explain: (NSError**)outError;


/** Runs the query. The returning an enumerator that returns result rows one at a time.
    You can run the query any number of times, and you can even have multiple enumerators active at 
    once.
    The results come from a snapshot of the database taken at the moment -run: is called, so they
    will not reflect any changes made to the database afterwards. 
    @param outError If an error occurs, it will be stored here if this parameter is non-NULL.
    @return an enumerator of the query result.
 */
- (nullable NSEnumerator<CBLQueryRow*>*) run: (NSError**)outError;

- (instancetype) init NS_UNAVAILABLE;

@end


NS_ASSUME_NONNULL_END
