//
//  CBLQueryJoin.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/29/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLQueryDataSource, CBLQueryExpression;

NS_ASSUME_NONNULL_BEGIN

@interface CBLQueryJoin : NSObject

/** Create a JOIN (same as INNER JOIN) component with the given data source and the on expression */
+ (instancetype) join: (CBLQueryDataSource*)dataSource on: (CBLQueryExpression*)expression;

/** Create a LEFT JOIN (same as LEFT OUTER JOIN) component with the given data source 
    and the on expression */
+ (instancetype) leftJoin: (CBLQueryDataSource*)dataSource on: (CBLQueryExpression*)expression;

/** Create a LEFT OUTER JOIN component with the given data source and the on expression */
+ (instancetype) leftOuterJoin: (CBLQueryDataSource*)dataSource on: (CBLQueryExpression*)expression;

/** Create an INNER JOIN component with the given data source and the on expression */
+ (instancetype) innerJoin: (CBLQueryDataSource*)dataSource on: (CBLQueryExpression*)expression;

/** Create a CROSS JOIN component with the given data source and the on expression */
+ (instancetype) crossJoin: (CBLQueryDataSource*)dataSource on: (CBLQueryExpression*)expression;

/** Not available. */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
