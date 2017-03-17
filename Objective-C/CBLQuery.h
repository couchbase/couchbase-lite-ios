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
 A CBLQuery instance can be constructed by calling one of the select class methods. */
@interface CBLQuery : NSObject

/** Create a query from SELECT and FROM component. */
+ (instancetype) select: (CBLQuerySelect*)select from: (CBLQueryDataSource*)from;

/** Create a DISTINCT query from SELECT and FROM component. */
+ (instancetype) selectDistict: (CBLQuerySelect*)selectDistict from: (CBLQueryDataSource*)from;

/** Create a query from SELECT, FROM, and WHERE component. */
+ (instancetype) select: (CBLQuerySelect*)select
                   from: (CBLQueryDataSource*)from
                  where: (nullable CBLQueryExpression*)where;

/** Create a DISTINCT query from SELECT, FROM, and WHERE component. */
+ (instancetype) selectDistict: (CBLQuerySelect*)selectDistict
                          from: (CBLQueryDataSource*)from
                         where: (nullable CBLQueryExpression*)where;

/** Create a query from SELECT, FROM, WHERE, and ORDERBY component. */
+ (instancetype) select: (CBLQuerySelect*)select
                   from: (CBLQueryDataSource*)from
                  where: (nullable CBLQueryExpression*)where
                orderBy: (nullable CBLQueryOrderBy*)orderBy;

/** Create a DISTINCT query from SELECT, FROM, WHERE, and ORDERBY component. */
+ (instancetype) selectDistict: (CBLQuerySelect*)selectDistict
                          from: (CBLQueryDataSource*)from
                         where: (nullable CBLQueryExpression*)where
                       orderBy: (nullable CBLQueryOrderBy*)orderBy;


/** Checks whether the query is valid, recompiling it if necessary, without running it. */
- (BOOL) check: (NSError**)outError;

/** Returns a string describing the implementation of the compiled query.
 This is intended to be read by a developer for purposes of optimizing the query, especially
 to add database indexes. It's not machine-readable and its format may change.
 
 As currently implemented, the result is two or more lines separated by newline characters:
 * The first line is the SQLite SELECT statement.
 * The subsequent lines are the output of SQLite's "EXPLAIN QUERY PLAN" command applied to that
 statement; for help interpreting this, see https://www.sqlite.org/eqp.html . The most
 important thing to know is that if you see "SCAN TABLE", it means that SQLite is doing a
 slow linear scan of the documents instead of using an index. */
- (nullable NSString*) explain: (NSError**)outError;


/** Runs the query, using the current settings (skip, limit, parameters), returning an enumerator
 that returns result rows one at a time.
 You can run the query any number of times, and you can even have multiple enumerators active at
 once.
 The results come from a snapshot of the database taken at the moment -run: is called, so they
 will not reflect any changes made to the database afterwards. */
- (nullable NSEnumerator<CBLQueryRow*>*) run: (NSError**)outError;

- (instancetype) init NS_UNAVAILABLE;

@end


NS_ASSUME_NONNULL_END
