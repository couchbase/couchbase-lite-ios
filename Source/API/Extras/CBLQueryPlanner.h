//
//  CBLQueryPlanner.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/4/14.
//
//

#import <Foundation/Foundation.h>
@class CBLView, CBLQuery;


/** A higher-level interface to views and queries that feels more like a traditional query language.
    Uses NSPredicate, NSExpression, NSSortDescriptor. Sets the CBLView's map block and configures
    CBLQueries. */
@interface CBLQueryPlanner : NSObject

/** Initializes a CBLQueryPlanner and configures its view's map block.
    @param view  The view to configure
    @param valueTemplate  The values you want in queries. The array items are either keypath
                strings or NSExpressions; in either case they're evaluated relative to the
                document being indexed.
    @param predicate  Specifies what you're looking for. Usually includes variables that will be
                filled in at query time, like key ranges. Components of the predicate may be
                evaluated during the map block, or as part of the query's index lookup, or as
                post-processing applied to the query results.
    @param sortDescriptors  The sort order you want the results in. If possible, the view's key
                will take these into account so the results are naturally sorted; otherwise the
                query results will be sorted afterwards.
    @param outError  If the planner doesn't know how to handle the input, this will be filled in
                with an NSError describing the problem.
    @return  The initialized CBLQueryPlanner, or nil on error. */
- (instancetype) initWithView: (CBLView*)view
                       select: (NSArray*)valueTemplate
               wherePredicate: (NSPredicate*)predicate
                      orderBy: (NSArray*)sortDescriptors
                        error: (NSError**)outError;

/** Initializes a CBLQueryPlanner and configures its view's map block.
    This is a convenience initializer that parses a predicate string for you;
    see the other initializer for details. */
- (instancetype) initWithView: (CBLView*)view
                       select: (NSArray*)valueTemplate
                        where: (NSString*)predicateStr
                      orderBy: (NSArray*)sortDescriptors
                        error: (NSError**)outError;

/** The view the query planner is using. */
@property (readonly, nonatomic) CBLView* view;

/** A human-readable string that explains in pseudocode what the query planner is doing.
    It shows what the map function does, and what the query's properties will be set to.    
    This is intended for troubleshooting and debugging purposes only. */
@property (readonly, nonatomic) NSString* explanation;

/** Creates a query, given a set of values for the variables.
    @param context  A dictionary mapping variable names to values. The names should not include
                        the dollar signs used in the predicate string; if a predicate referred to
                        $FOO, the dictionary key should be @"FOO".
    @return  The configured query, ready to run. */
- (CBLQuery*) createQueryWithContext: (NSDictionary*)context;

@end
