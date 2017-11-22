//
//  CBLFunctionExpression.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 11/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLQueryExpression+Internal.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLFunctionExpression : CBLQueryExpression

- (instancetype) initWithFunction: (NSString*)function
                           params: (nullable NSArray*)params;

@end

NS_ASSUME_NONNULL_END
