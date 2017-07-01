//
//  CBLQuerySelect.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLQueryExpression;

NS_ASSUME_NONNULL_BEGIN

/** A CBLQuerySelect represents the returning values in each query result row. */
@interface CBLQuerySelect : NSObject

/** Creates a CBLQuerySelect that represents all properties.
    @return A CBLQuerySelect for all properties. */
+ (CBLQuerySelect*) all;

/** Creates a CBLQuerySelect for the given expression.
    @param expression   The expression.
    @return A CBLQuerySelect for the given expression. */
+ (CBLQuerySelect*) expression: (CBLQueryExpression*)expression;

/** Creates a CBLQuerySelect that combines all of the given CBLQuerySelect objects .
    @param selects  The array of the CBLQuerySelect objects.
    @return A CBLQuerySelect combining all of the given CBLQuerySelect objects. */
+ (CBLQuerySelect*) select: (NSArray<CBLQuerySelect*>*)selects;

@end

NS_ASSUME_NONNULL_END
