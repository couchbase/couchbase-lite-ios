//
//  CBLQueryBuilder.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/4/14.
//  Copyright (c) 2014-2015 Couchbase, Inc. All rights reserved.
//

#import "CBLBase.h"
@class CBLDatabase, CBLView, CBLQuery, CBLQueryEnumerator;

NS_ASSUME_NONNULL_BEGIN

/** A higher-level interface to views and queries that feels more like a traditional query language
    or like Core Data's NSFetchRequest.
 
    A CBLQueryBuilder is a template for creating families of queries. You should create an instance
    for a generalized query, leaving "$"-prefixed placeholder variables in your "where" predicate
    for any values that won't be known until the query needs to run. Then at query time, you give
    the builder values for the variables and it creates a query.

    (Note: CBLQueryBuilder is not cross-platform since its API is based on the Cocoa Foundation 
    classes NSPredicate, NSExpression and NSSortDescriptor. Other implementations of Couchbase Lite
    will have equivalent functionality based on their platforms' APIs and idioms.)
*/
@interface CBLQueryBuilder : NSObject

/** Initializes a CBLQueryBuilder.
    @param database The database to index and query.
    @param valueTemplate  The result values you want, expressed either as keypath strings or
                NSExpressions; in either case they're evaluated relative to the
                document being indexed.
    @param predicateStr  A predicate template string that specifies the condition(s) that a
                document's properties must match. Often includes "$"-prefixed variables that will
                be filled in at query time, like key ranges.
                (See Apple's predicate syntax documentation: http://goo.gl/8ty3xG )
    @param sortDescriptors  The sort order you want the results in. Items in the array can be
                NSSortDescriptors or NSStrings. A string will be interpreted as a sort descriptor
                with that keyPath; prefix it with "-" to indicate descending order.
                If the order of query rows is unimportant, pass nil.
    @param outError  If the builder doesn't know how to handle the input, this will be filled in
                with an NSError describing the problem.
    @return  The initialized CBLQueryBuilder, or nil on error. */
- (nullable instancetype) initWithDatabase: (nullable CBLDatabase*)database
                                    select: (nullable NSArray*)valueTemplate
                                     where: (NSString*)predicateStr
                                   orderBy: (nullable NSArray*)sortDescriptors
                                     error: (NSError**)outError;

/** Initializes a CBLQueryBuilder.
    This is an alternate initializer that takes an NSPredicate instead of a predicate template
    string; see the main initializer for details. */
- (nullable instancetype) initWithDatabase: (nullable CBLDatabase*)database
                                    select: (nullable NSArray*)valueTemplate
                            wherePredicate: (NSPredicate*)predicate
                                   orderBy: (nullable NSArray*)sortDescriptors
                                     error: (NSError**)outError;

/** Initializes a CBLQueryBuilder, using an explicitly chosen view.
    See the main initializer for details. */
- (nullable instancetype) initWithView: (CBLView*)view
                                select: (NSArray*)valueTemplate
                        wherePredicate: (NSPredicate*)predicate
                               orderBy: (nullable NSArray*)sortDescriptors
                                 error: (NSError**)outError;

- (instancetype) init NS_UNAVAILABLE;

/** The view the query builder is using. */
@property (readonly, nonatomic) CBLView* view;

/** A human-readable string that explains in pseudocode what the query builder is doing.
    It shows what the map function does, and what the query's properties will be set to.    
    This is intended for troubleshooting and debugging purposes only. */
@property (readonly, nonatomic) NSString* explanation;

/** Creates a query, given a set of values for the variables.
    @param context  A dictionary mapping variable names to values. The names should not include
                        the dollar signs used in the predicate string; if a predicate referred to
                        $FOO, the dictionary key should be @"FOO".
    @return  The configured query, ready to run. */
- (CBLQuery*) createQueryWithContext: (nullable CBLJSONDict*)context;

/** A convenience method that creates a query and runs it. See -createQueryWithContext:. */
- (nullable CBLQueryEnumerator*) runQueryWithContext: (nullable CBLJSONDict*)context
                                               error: (NSError**)outError;

@end


NS_ASSUME_NONNULL_END
