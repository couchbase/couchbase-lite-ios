//
//  CBLUnaryExpression.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/1/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLQueryExpression.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CBLUnaryExpType) {
    CBLUnaryTypeMissing,
    CBLUnaryTypeNotMissing,
    CBLUnaryTypeNull,
    CBLUnaryTypeNotNull
};

@interface CBLUnaryExpression : CBLQueryExpression

@property(nonatomic, readonly) CBLUnaryExpType type;
@property(nonatomic, readonly) id operand;

- (instancetype) initWithExpression: (id)operand type: (CBLUnaryExpType)type;

@end

NS_ASSUME_NONNULL_END
