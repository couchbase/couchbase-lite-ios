//
//  CBLQueryOrderBy.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLQuerySortOrder, CBLQueryExpression;

NS_ASSUME_NONNULL_BEGIN

/** A CBLQueryOrderBy represents a query ORDER BY clause by specifying properties or expressions
    that the result rows should be sorted by.
    A CBLQueryOrderBy can be construct as a single CBLQuerySortOrder instance with a propery name
    or an expression instance or as a chain of multiple CBLQueryOrderBy instances. */
@interface CBLQueryOrderBy : NSObject

/** Create a chain of multiple CBLQueryOrderBy instances for constructing an ORDER BY clause of 
    the query.
    @param orders   an array of CBLQueryOrderBy.
    @return a CBLQueryOrderBy instance. */
+ (CBLQueryOrderBy*) orderBy: (NSArray<CBLQueryOrderBy*>*)orders;

/** Create a sort order instance with a given property name.
    @param name a propert name in key path format.
    @return a sort order instance.
 */
+ (CBLQuerySortOrder*) property: (NSString*)name;

/** Create a sort order instance with a given expression. 
    @param expression   an expression instance.
    @return a sort order instance. */
+ (CBLQuerySortOrder*) expression: (CBLQueryExpression*)expression;

- (instancetype) init NS_UNAVAILABLE;

@end

/** CBLQuerySortOrder is a subclass of the CBLQueryOrderBy that allows to create an 
    ascending or a descending CBLQueryOrderBy instance. */
@interface CBLQuerySortOrder : CBLQueryOrderBy

/** Create an ascending CBLQueryOrderBy instance. 
    @return an ascending CBLQueryOrderBy instance. */
- (CBLQueryOrderBy*) ascending;

/** Create a descending CBLQueryOrderBy instance. 
    @return a descending CBLQueryOrderBy instance. */
- (CBLQueryOrderBy*) descending;

/** Not available. */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
