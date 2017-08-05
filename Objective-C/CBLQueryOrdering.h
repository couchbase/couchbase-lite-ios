//
//  CBLQueryOrdering.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLQuerySortOrder, CBLQueryExpression;

NS_ASSUME_NONNULL_BEGIN

/** 
 A CBLQueryOrdering represents a single ordering component in the query ORDER BY clause. 
 */
@interface CBLQueryOrdering : NSObject

/** 
 Create a sort order instance with a given property name.
 
 @param name A propert name in key path format.
 @return A sort order instance.
 */
+ (CBLQuerySortOrder*) property: (NSString*)name;

/** 
 Create a sort order instance with a given expression.
 
 @param expression An expression instance.
 @return  A sort order instance.
 */
+ (CBLQuerySortOrder*) expression: (CBLQueryExpression*)expression;

- (instancetype) init NS_UNAVAILABLE;

@end

/** 
 CBLQuerySortOrder allows to specify the ordering direction which is an ascending or 
 a descending order
 */
@interface CBLQuerySortOrder : CBLQueryOrdering

/** 
 Create an ascending CBLQueryOrdering instance.
 
 @return An ascending CBLQueryOrdering instance.
 */
- (CBLQueryOrdering*) ascending;

/** 
 Create a descending CBLQueryOrdering instance.
 
 @return A descending CBLQueryOrdering instance.
 */
- (CBLQueryOrdering*) descending;

/** Not available. */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
