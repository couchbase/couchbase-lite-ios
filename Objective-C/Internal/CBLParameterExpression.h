//
//  CBLParameterExpression.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/1/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLQueryExpression.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLParameterExpression : CBLQueryExpression

@property(nonatomic, readonly) id name;

- (instancetype) initWithName: (id)name;

@end

NS_ASSUME_NONNULL_END
