//
//  CBLPredicateQuery.h
//  Couchbase Lite
//
//  Created by Jens Alfke on 11/30/16.
//  Copyright © 2016 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLDatabase, CBLQueryRow, CBLDocument;

NS_ASSUME_NONNULL_BEGIN


/** A compiled database query.
    You create a query by calling the CBLDatabase method createQueryWhere:. The query can be
    further configured by setting properties before running it. Some properties alter the
    behavior of the query enough to trigger recompilation; it's usually best to set these only
    once and then reuse the CBLQuery object. You can use NSPredicate / NSExpression variables
    to parameterize the query, making it flexible without needing recompilation. Then you just
    set the `parameters` property before running it. */
@interface CBLPredicateQuery : NSObject

/** The database being queried. */
@property (nonatomic, readonly) CBLDatabase* database;

/** Specifies a condition (predicate) that documents have to match; corresponds to the WHERE
    clause of a SQL or N1QL query.
    This can be an NSPredicate, or an NSString (interpreted as an NSPredicate format string),
    or nil to return all documents. Defaults to nil.
    If this property is changed, the query will be recompiled the next time it is run. */
@property (copy, nullable, nonatomic) id where;

/** An array of NSSortDescriptors or NSStrings, specifying properties or expressions that the
    result rows should be sorted by; corresponds to the ORDER BY clause of a SQL or N1QL query.
    These strings, or sort-descriptor names, can name key-paths or be NSExpresson format strings.
    If nil, no sorting occurs; this is faster but the order of rows is undefined.
    The default value sorts by document ID.
    If this property is changed, the query will be recompiled the next time it is run. */
@property (copy, nullable, nonatomic) NSArray* orderBy;

/** An array of NSExpressions (or expression format strings) describing values to include in each
    result row; corresponds to the SELECT clause of a SQL or N1QL query.
    If nil, only the document ID and sequence number will be available. Defaults to nil.
    If this property is changed, the query will be recompiled the next time it is run. */
@property (copy, nullable, nonatomic) NSArray* returning;

/** An array of NSExpressions (or expression format strings) describing how to group rows
    together: all documents having the same values for these expressions will be coalesced into a
    single row.
    If nil, no grouping is done. Defaults to nil. */
@property (copy, nullable, nonatomic) NSArray* groupBy;

/** Specifies a condition (predicate) that grouped rows have to match; corresponds to the HAVING
    clause of a SQL or N1QL query.
    This can be an NSPredicate, or an NSString (interpreted as an NSPredicate format string),
    or nil to not filter groups. Defaults to nil.
    If this property is changed, the query will be recompiled the next time it is run. */
@property (copy, nullable, nonatomic) id having;

/** If YES, duplicate result rows will be removed so that all rows are unique;
    corresponds to the DISTINCT keyword of a SQL or N1QL query.
    Defaults to NO. */
@property (nonatomic) BOOL distinct;

/** The number of result rows to skip; corresponds to the OFFSET property of a SQL or N1QL query.
    This can be useful for "paging" through a large query, but skipping many rows is slow.
    Defaults to 0. */
@property (nonatomic) NSUInteger offset;

/** The maximum number of rows to return; corresponds to the LIMIT property of a SQL or N1QL query.
    Defaults to NSUIntegerMax (i.e. unlimited.) */
@property (nonatomic) NSUInteger limit;

/** Values to substitute for placeholder parameters defined in the query. Defaults to nil.
    The dictionary's keys are parameter names, and values are the values to use.
    All parameters must be given values before running the query, or it will fail. */
@property (copy, nullable, nonatomic) NSDictionary<NSString*,id>* parameters;

/** Checks whether the query is valid, recompiling it if necessary, without running it. */
- (BOOL) check: (NSError**)error;

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
- (nullable NSEnumerator<CBLQueryRow*>*) run: (NSError**)error;

/** A convenience method equivalent to -run: except that its enumerator returns CBLDocuments
    directly, not CBLQueryRows. */
- (nullable NSEnumerator<CBLDocument*>*) allDocuments: (NSError**)error;

/** Not available. */
- (instancetype) init NS_UNAVAILABLE;

@end


NS_ASSUME_NONNULL_END
