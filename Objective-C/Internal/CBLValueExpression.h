//
//  CBLValueExpression.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/12/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLQueryExpression.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLValueExpression : CBLQueryExpression

- (instancetype) initWithValue: (nullable id)value;

@end

NS_ASSUME_NONNULL_END
