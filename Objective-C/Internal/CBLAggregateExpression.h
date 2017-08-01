//
//  CBLAggregateExpression.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/1/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLQueryExpression.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLAggregateExpression: CBLQueryExpression

@property(nonatomic, readonly) NSArray* subexpressions;

- (instancetype)initWithExpressions: (NSArray*)subs;

@end

NS_ASSUME_NONNULL_END
